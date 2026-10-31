"""Package already-built local QA binaries with exact source and content identity.

Never signs, installs, runs, deploys or promotes an application.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tarfile
import zipfile


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def apk_badging(apk):
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    candidates = []
    if sdk:
        for path in (Path(sdk)/'build-tools').glob('*/aapt' + ('.exe' if os.name == 'nt' else '')):
            if re.fullmatch(r'\d+(?:\.\d+)*', path.parent.name):
                candidates.append((tuple(map(int, path.parent.name.split('.'))), path))
    if not candidates:
        raise ValueError('Set ANDROID_HOME to the SDK containing stable Android build tools')
    return subprocess.check_output([str(max(candidates)[1]), 'dump', 'badging', str(apk)],
                                   encoding='utf-8', timeout=60)


def package(root, platform, checkout_sha, source_sha):
    root = Path(root).resolve()
    if platform not in ('android', 'ios-simulator'):
        raise ValueError('Only local QA builds may be packaged')
    for value in (checkout_sha, source_sha):
        if not re.fullmatch('[a-f0-9]{40}', value):
            raise ValueError('Exact checkout and source commit required')
    version = re.search(r'^version:\s*(\S+)\s*$', (root/'pubspec.yaml').read_text(encoding='utf-8'), re.M)
    if not version:
        raise ValueError('Missing declared application version')
    name, separator, number = version[1].rpartition('+')
    if not name or not separator or not re.fullmatch('[1-9][0-9]*', number):
        raise ValueError('Expected an application version and a positive build number')
    if json.loads((root/'config/local.json').read_text(encoding='utf-8')).get('MOMIQ_ENV') != 'local':
        raise ValueError('Expected local QA configuration')
    source = root/('build/app/outputs/flutter-apk/app-debug.apk' if platform == 'android' else 'build/ios/iphonesimulator/Runner.app')
    if not source.resolve().is_relative_to(root/'build'):
        raise ValueError('Build source escapes workspace build directory')
    if platform == 'android':
        with zipfile.ZipFile(source) as archive:
            if not {'AndroidManifest.xml', 'lib/arm64-v8a/libflutter.so'}.issubset(archive.namelist()):
                raise ValueError('Expected ARM64 Android APK')
        badging = apk_badging(source)
        package_line = next((line for line in badging.splitlines() if line.startswith('package: ')), '')
        fields = dict(re.findall(r"\b(\w+)='([^']*)'", package_line))
        minimum = re.search(r"^sdkVersion:'(\d+)'$", badging, re.M)
        target = re.search(r"^targetSdkVersion:'(\d+)'$", badging, re.M)
        if (fields.get('name') != 'net.momiq.app' or fields.get('versionName') != name
                or fields.get('versionCode') != number or not minimum or not target
                or not 26 <= int(minimum[1]) <= int(target[1])):
            raise ValueError('Android binary identity, version or SDK is incompatible')
        binary_identity = {'applicationId': fields['name'], 'versionName': name, 'versionCode': int(number),
                           'minSdk': int(minimum[1]), 'targetSdk': int(target[1])}
    else:
        with (source/'Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        if info.get('CFBundleIdentifier') != 'net.momiq.app' or info.get('CFBundleSupportedPlatforms') != ['iPhoneSimulator']:
            raise ValueError('Expected Momiq simulator bundle')
        minimum = info.get('MinimumOSVersion')
        if (info.get('CFBundleShortVersionString') != name or info.get('CFBundleVersion') != number
                or not isinstance(minimum, str) or not re.fullmatch(r'\d+(?:\.\d+){0,2}', minimum)):
            raise ValueError('iOS binary version or minimum OS is incompatible')
        binary_identity = {'bundleId': info['CFBundleIdentifier'], 'versionName': name, 'buildNumber': number,
                           'minimumOs': minimum}
        executable = source/str(info.get('CFBundleExecutable', ''))
        if not executable.is_file() or not executable.resolve().is_relative_to(source.resolve()):
            raise ValueError('Missing simulator executable')
        if any(path.is_symlink() and not path.resolve().is_relative_to(source.resolve()) for path in source.rglob('*')):
            raise ValueError('Bundle link escapes application')
    output = root/'ci-artifacts'/platform
    if not output.resolve().is_relative_to(root) or output.exists():
        raise ValueError('Refusing to replace existing artifact evidence')
    output.mkdir(parents=True)
    artifact = output/('momiq-android-arm64-debug.apk' if platform == 'android' else 'momiq-ios-simulator-debug.tar.gz')
    if platform == 'android':
        shutil.copyfile(source, artifact)
    else:
        # tar preserves executable modes and internal framework links.
        with tarfile.open(artifact, 'w:gz', dereference=False) as archive:
            archive.add(source, arcname='Runner.app')
    manifest = {
        'schemaVersion': 1, 'platform': platform, 'mode': 'debug', 'environment': 'local',
        'releaseReady': False, 'signing': 'android-debug-key' if platform == 'android' else 'unsigned-simulator',
        'checkoutSha': checkout_sha, 'sourceSha': source_sha, 'declaredVersion': version[1],
        'binaryIdentity': binary_identity,
        'pubspecLockSha256': digest(root/'pubspec.lock'),
        'artifact': artifact.name, 'bytes': artifact.stat().st_size, 'sha256': digest(artifact),
    }
    (output/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=('android', 'ios-simulator'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    checkout = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    source = os.environ.get('MOMIQ_SOURCE_SHA', checkout)
    manifest = package(root, args.platform, checkout, source)
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
