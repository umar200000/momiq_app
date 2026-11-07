"""Collect resolved Pub package notices without guessing license approval.

Input must follow flutter pub get --enforce-lockfile and flutter pub deps --json.
SDK, engine, native libraries, providers and application assets remain separate.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


def document(path, root):
    if not path.resolve().is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError('Missing or escaped package document')
    if path.stat().st_size > 5 * 1024 * 1024:
        raise ValueError('Package document exceeds evidence limit')
    raw = path.read_bytes()
    text = raw.decode('utf-8-sig')
    if not text.strip():
        raise ValueError('Empty package document')
    return raw, text


def scalar(text, key):
    match = re.findall(r'^'+key+r':\s*([^\r\n]+)', text, re.M)
    if len(match) != 1:
        raise ValueError('Missing unique package identity')
    return match[0].strip().split(' #', 1)[0].strip().strip('\"\'')


def collect(inventory, config_path, lock):
    config_path = Path(config_path).resolve()
    config = json.loads(config_path.read_text(encoding='utf-8-sig'))
    resolved = config['packages']
    roots = {entry['name']: entry['rootUri'] for entry in resolved}
    packages = inventory['packages']
    if config.get('configVersion') != 2 or len(roots) != len(resolved) or len({p['name'] for p in packages}) != len(packages):
        raise ValueError('Ambiguous resolved packages')
    if set(roots) != {p['name'] for p in packages}:
        raise ValueError('Resolved package sets differ')
    result, excluded, notices = [], [], []
    for package in sorted(packages, key=lambda p: p['name']):
        name, version, source = package['name'], package['version'], package['source']
        if not re.fullmatch(r'[a-z_][a-z0-9_]*', name) or not isinstance(version, str) or not version:
            raise ValueError('Invalid package identity')
        if source in ('root', 'sdk'):
            excluded.append({'name': name, 'source': source})
            continue
        if source != 'hosted':
            raise ValueError('Non-hosted packages require separate evidence')
        uri = urlparse(urljoin(config_path.as_uri(), roots[name]))
        if uri.scheme != 'file' or uri.netloc not in ('', 'localhost') or uri.query or uri.fragment:
            raise ValueError('Expected local resolved package directory')
        root = Path(url2pathname(uri.path)).resolve()
        _, pubspec = document(root/'pubspec.yaml', root)
        if scalar(pubspec, 'name') != name or scalar(pubspec, 'version') != version:
            raise ValueError('Resolved package version differs from installed source')
        files = []
        for path in sorted(root.iterdir()):
            if not re.match(r'^(LICEN[CS]E|COPYING|NOTICE)(?:[._-].*)?$', path.name, re.I):
                continue
            if path.is_file():
                files.append(path)
            elif path.is_dir():
                if not path.resolve().is_relative_to(root):
                    raise ValueError('License directory escapes package')
                files.extend(sorted(p for p in path.rglob('*') if p.is_file()))
        if not files or len(files) > 100:
            raise ValueError('Missing or excessive license documents: '+name)
        evidence = []
        for path in files:
            raw, text = document(path, root)
            relative = path.relative_to(root).as_posix()
            evidence.append({'path': relative, 'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)})
            notices.append(f'===== {name} {version} / {relative} =====\n{text}\n')
        result.append({'name': name, 'version': version, 'kind': package['kind'], 'licenseFiles': evidence})
    if not result:
        raise ValueError('No hosted dependency evidence')
    return {'schemaVersion': 1, 'scope': 'resolved hosted Pub package license documents',
            'legalApproval': False, 'lockSha256': hashlib.sha256(Path(lock).read_bytes()).hexdigest(),
            'packages': result, 'excludedPackages': excluded,
            'separateReview': ['Flutter/Dart SDK and engine', 'Android/iOS native dependencies',
                               'provider SDK terms', 'application images/fonts and other assets']}, '\n'.join(notices)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inventory', type=Path)
    parser.add_argument('--config', type=Path, default=Path('.dart_tool/package_config.json'))
    parser.add_argument('--lock', type=Path, default=Path('pubspec.lock'))
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    report, notices = collect(json.loads(args.inventory.read_text(encoding='utf-8-sig')), args.config, args.lock)
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output/'inventory.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    (args.output/'NOTICES.txt').write_text(notices, encoding='utf-8')
    print('Collected', len(report['packages']), 'hosted package notices;', len(report['excludedPackages']), 'SDK/root packages excluded; no legal approval.')


if __name__ == '__main__':
    main()
