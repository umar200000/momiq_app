"""Audit resolved public Pub package versions against OSV; never upload app code.

Input: flutter pub deps --json, generated after pub get --enforce-lockfile.
Reference: https://google.github.io/osv.dev/post-v1-querybatch/
SDK/root packages require separate Flutter/native review.
"""
import argparse
import json
import hashlib
import re
from datetime import datetime, timezone
from pathlib import Path
import sys
import urllib.request


def post(queries):
    request=urllib.request.Request('https://api.osv.dev/v1/querybatch',
        data=json.dumps({'queries':queries}).encode(),headers={'Content-Type':'application/json'},method='POST')
    with urllib.request.urlopen(request,timeout=30) as response:
        return json.load(response)


def audit(dependencies, send=post):
    packages=dependencies['packages']
    if not isinstance(packages,list):raise ValueError('Missing resolved dependency inventory')
    public=[];excluded=[]
    for package in packages:
        if package['source']=='hosted':
            if not package.get('name') or not package.get('version'):raise ValueError('Unresolved Pub package')
            public.append(package)
        elif package['source'] in ('sdk','root'):
            excluded.append({'name':package['name'],'source':package['source']})
        else:raise ValueError('Non-hosted dependency requires a separate advisory review')
    if not public:raise ValueError('No public Pub dependencies were audited')
    output=[]
    for start in range(0,len(public),100):
        batch=public[start:start+100]
        entries=[{'name':p['name'],'version':p['version'],'vulnerabilities':[]} for p in batch]
        pending=[(i,{'package':{'name':p['name'],'ecosystem':'Pub'},'version':p['version']}) for i,p in enumerate(batch)]
        for _ in range(20):
            if not pending:break
            response=send([query for _,query in pending])
            results=response.get('results')
            if not isinstance(results,list) or len(results)!=len(pending):raise ValueError('Incomplete OSV response; audit did not complete')
            again=[]
            for (index,query),result in zip(pending,results):
                if not isinstance(result,dict) or set(result)-{'vulns','next_page_token'}:raise ValueError('Unexpected OSV result')
                for item in result.get('vulns',[]):
                    identity=item['id']
                    if not isinstance(identity,str) or not identity:raise ValueError('Invalid advisory identity')
                    entries[index]['vulnerabilities'].append(identity)
                token=result.get('next_page_token')
                if token:
                    if not isinstance(token,str):raise ValueError('Invalid advisory cursor')
                    again.append((index,dict(query,page_token=token)))
            pending=again
        if pending:raise ValueError('OSV pagination unfinished; audit did not complete')
        for entry in entries:entry['vulnerabilities']=sorted(set(entry['vulnerabilities']))
        output.extend(entries)
    return {'service':'https://api.osv.dev/v1/querybatch','ecosystem':'Pub','packages':output,'excluded':excluded}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inventory',type=Path);parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--lock',type=Path,default=Path('pubspec.lock'))
    args=parser.parse_args()
    # PowerShell output can include a UTF-8 BOM.
    inventory=json.loads(args.inventory.read_text(encoding='utf-8-sig'))
    lock=args.lock.read_bytes()
    urls=re.findall(r'^\s+url:\s*[\"\']?(https?://[^\"\'\s]+)[\"\']?\s*$',lock.decode('utf-8'),re.MULTILINE)
    hosted=sum(p['source']=='hosted' for p in inventory['packages'])
    if len(urls)!=hosted or set(urls)!={'https://pub.dev'}:
        raise ValueError('Only verified public pub.dev dependencies may be sent to OSV')
    report=audit(inventory)
    report.update(checkedAt=datetime.now(timezone.utc).isoformat(),lockSha256=hashlib.sha256(lock).hexdigest())
    args.output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    vulnerable=[p for p in report['packages'] if p['vulnerabilities']]
    print('Audited',len(report['packages']),'Pub packages; excluded SDK/root:',len(report['excluded']))
    for item in vulnerable:print(item['name'],item['version'],','.join(item['vulnerabilities']))
    if not vulnerable:print('No known Pub advisories returned; native/SDK and unknown vulnerabilities are not covered.')
    return 1 if vulnerable else 0


if __name__=='__main__':
    try:sys.exit(main())
    except Exception as error:
        print('Dependency audit failed:',type(error).__name__,str(error),file=sys.stderr)
        sys.exit(2)
