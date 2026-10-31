"""Boot a fresh simulator, verify first launch and cold restart, retain QA screenshots."""
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import subprocess
from tempfile import TemporaryDirectory
import time


def sim(*args, timeout=90):
    return subprocess.check_output(['xcrun','simctl',*args],text=True,timeout=timeout).strip()


def confirm_screen(device, checker, image):
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        sim('io',device,'screenshot',str(image))
        if subprocess.run([checker,image],timeout=35).returncode==0:
            return
        time.sleep(4)
    raise RuntimeError('Role selection was not visible within two minutes')


def main():
    bundle=Path('build/ios/iphonesimulator/Runner.app').resolve(strict=True)
    with (bundle/'Info.plist').open('rb') as stream:
        info=plistlib.load(stream)
    if info['CFBundleIdentifier']!='net.momiq.app' or info['CFBundleSupportedPlatforms']!=['iPhoneSimulator']:
        raise ValueError('Expected the unsigned QA simulator bundle')
    devices=json.loads(sim('list','devices','available','--json'))['devices']
    phones=[(runtime,phone) for runtime,group in devices.items() if '.iOS-' in runtime
            for phone in group if phone.get('isAvailable') and phone['name'].startswith('iPhone')]
    if not phones:
        raise RuntimeError('No available iPhone simulator runtime')
    runtime,phone=max(phones,key=lambda entry:tuple(map(int,entry[0].split('.iOS-')[1].split('-'))))
    evidence=Path('ci-artifacts/ios-startup')
    evidence.mkdir(parents=True,exist_ok=False)
    with TemporaryDirectory() as tmp:
        checker=Path(tmp)/'role-screen'
        subprocess.run(['xcrun','swiftc','tool/ios_role_screen.swift','-o',checker],check=True,timeout=120)
        device=sim('create','Momiq QA '+secrets.token_hex(5),phone['deviceTypeIdentifier'],runtime)
        if not re.fullmatch('[A-Fa-f0-9-]{36}',device):
            raise RuntimeError('Unexpected simulator identifier')
        try:
            sim('bootstatus',device,'-b',timeout=360)
            sim('install',device,str(bundle))
            for phase in ('first-launch','cold-restart'):
                if phase=='cold-restart':sim('terminate',device,'net.momiq.app')
                sim('launch',device,'net.momiq.app')
                confirm_screen(device,checker,evidence/(phase+'.png'))
            report={'sourceSha':os.environ['MOMIQ_SOURCE_SHA'],'bundleId':'net.momiq.app',
                    'runtime':runtime,'deviceType':phone['deviceTypeIdentifier'],
                    'verified':['first-launch','cold-restart'],'screen':'role-selection'}
            (evidence/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
            print(json.dumps(report))
        finally:
            sim('delete',device)


if __name__=='__main__':
    main()
