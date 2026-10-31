"""Boot a fresh simulator, verify first launch and cold restart, retain QA screenshots."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import subprocess
import tarfile
from tempfile import TemporaryDirectory
import time


def sim(*args, timeout=90):
    return subprocess.check_output(['xcrun','simctl',*args],text=True,timeout=timeout).strip()


def confirm_screen(device, checker, image):
    deadline=time.monotonic()+240
    while time.monotonic()<deadline:
        try:
            sim('io',device,'screenshot',str(image),timeout=75)
            if subprocess.run([checker,image],timeout=45).returncode==0:
                return
        except subprocess.TimeoutExpired:
            print('Simulator capture or recognition timed out; retrying the same running app',flush=True)
        time.sleep(4)
    raise RuntimeError('Could not verify the rendered role selection screen')

def unpack(package,output,revision):
    manifest=json.loads((package/'manifest.json').read_text())
    archive=package/'momiq-ios-simulator-debug.tar.gz'
    if (manifest['sourceSha']!=revision or manifest['artifact']!=archive.name or
            manifest['platform']!='ios-simulator' or manifest['releaseReady'] is not False or
            manifest['bytes']!=archive.stat().st_size):
        raise ValueError('Unexpected QA artifact manifest')
    with archive.open('rb') as stream:
        if hashlib.file_digest(stream,'sha256').hexdigest()!=manifest['sha256']:
            raise ValueError('QA binary digest mismatch')
    with tarfile.open(archive) as bundle:
        bundle.extractall(output,filter='data')
    return output/'Runner.app'

def verify(bundle):
    with (bundle/'Info.plist').open('rb') as stream:
        info=plistlib.load(stream)
    if info['CFBundleIdentifier']!='net.momiq.app' or info['CFBundleSupportedPlatforms']!=['iPhoneSimulator']:
        raise ValueError('Expected the unsigned QA simulator bundle')
    devices=json.loads(sim('list','devices','available','--json'))['devices']
    phones=[(runtime,phone) for runtime,group in devices.items() if '.iOS-' in runtime
            for phone in group if phone.get('isAvailable') and phone['name'].startswith('iPhone')]
    if not phones:
        raise RuntimeError('No available iPhone simulator runtime')
    # Prefer an installed iOS 18 runtime on this Intel CI host. Device signing
    # and the full release OS matrix are separate acceptance steps.
    runtime,phone=max(phones,key=lambda item:(item[0].split('.iOS-')[1].startswith('18-'),
                        tuple(map(int,item[0].split('.iOS-')[1].split('-')))))
    print('Testing',phone['name'],'on',runtime,flush=True)
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
            subprocess.run(['open','-g','-a','Simulator','--args','-CurrentDeviceUDID',device],check=True,timeout=40)
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
    with TemporaryDirectory() as unpacked:
        verify(unpack(Path('ci-artifacts/ios-simulator'),Path(unpacked),os.environ['MOMIQ_SOURCE_SHA']))
