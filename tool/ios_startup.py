"""Boot a fresh simulator, verify first launch and cold restart, retain QA screenshots."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import subprocess
import sys
import tarfile
from tempfile import TemporaryDirectory
import time


def sim(*args, timeout=90):
    return subprocess.check_output(['xcrun','simctl',*args],text=True,timeout=timeout).strip()


def confirm_screen(device, classes, image):
    # Cold hosted macOS workers can stall simctl and JVM startup independently.
    # Keep a finite total budget; a timeout never counts as screen verification.
    deadline=time.monotonic()+480
    while time.monotonic()<deadline:
        try:
            print('Capturing',image.name,flush=True)
            remaining=deadline-time.monotonic()
            if remaining<=0:break
            sim('io',device,'screenshot',str(image),timeout=min(120,remaining))
            remaining=deadline-time.monotonic()
            if remaining<=0:break
            print('Recognizing',image.name,flush=True)
            if subprocess.run(['java','-Djava.awt.headless=true','-cp',classes,'RoleScreen',image],timeout=min(90,remaining)).returncode==0:
                return
        except subprocess.TimeoutExpired as error:
            print(f'{image.name}: {error.cmd[0]} timed out after {error.timeout}s; retrying the same running app',flush=True)
        time.sleep(min(4,max(0,deadline-time.monotonic())))
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
    # Cold CoreSimulator discovery can take several minutes on a fresh CI host.
    print('Waiting for the installed simulator devices',flush=True)
    devices=json.loads(sim('list','devices','available','--json',timeout=300))['devices']
    phones=[(runtime,phone) for runtime,group in devices.items() if '.iOS-' in runtime
            for phone in group if phone.get('isAvailable') and phone['name']=='iPhone 16 Pro']
    if not phones:
        raise RuntimeError('No available iPhone 16 Pro for the reviewed role-screen fixture')
    # Prefer an installed iOS 18 runtime on this Intel CI host. Device signing
    # and the full release OS matrix are separate acceptance steps.
    runtime,phone=max(phones,key=lambda item:(item[0].split('.iOS-')[1].startswith('18-'),
                        tuple(map(int,item[0].split('.iOS-')[1].split('-')))))
    print('Testing',phone['name'],'on',runtime,flush=True)
    evidence=Path('ci-artifacts/ios-startup')
    evidence.mkdir(parents=True,exist_ok=False)
    with TemporaryDirectory() as tmp:
        subprocess.run(['javac','-d',tmp,'tool/RoleScreen.java'],check=True,timeout=120)
        device=sim('create','Momiq QA '+secrets.token_hex(5),phone['deviceTypeIdentifier'],runtime)
        if not re.fullmatch('[A-Fa-f0-9-]{36}',device):
            raise RuntimeError('Unexpected simulator identifier')
        try:
            sim('bootstatus',device,'-b',timeout=360)
            print('Simulator booted; installing the verified QA bundle',flush=True)
            started = time.monotonic()
            sim('install',device,str(bundle),timeout=360)
            print(f'QA bundle installed in {time.monotonic()-started:.1f}s',flush=True)
            for phase in ('first-launch','cold-restart'):
                if phase=='cold-restart':sim('terminate',device,'net.momiq.app')
                print('Launching',phase,flush=True)
                sim('launch',device,'net.momiq.app',timeout=360)
                confirm_screen(device,tmp,evidence/(phase+'.png'))
            report={'sourceSha':os.environ['MOMIQ_SOURCE_SHA'],'bundleId':'net.momiq.app',
                    'runtime':runtime,'deviceType':phone['deviceTypeIdentifier'],
                    'verified':['first-launch','cold-restart'],'screen':'role-selection'}
            (evidence/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
            print(json.dumps(report))
        finally:
            original=sys.exc_info()[1]
            try:
                sim('delete',device)
            except (subprocess.CalledProcessError,subprocess.TimeoutExpired) as cleanup_error:
                if original is None:
                    raise
                original.add_note(f'Simulator cleanup also failed: {cleanup_error}')


if __name__=='__main__':
    with TemporaryDirectory() as unpacked:
        verify(unpack(Path('ci-artifacts/ios-simulator'),Path(unpacked),os.environ['MOMIQ_SOURCE_SHA']))
