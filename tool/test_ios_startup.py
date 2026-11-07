import hashlib
import json
from pathlib import Path
import os
import plistlib
import subprocess
import tarfile
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from ios_startup import unpack, verify


class ArtifactStartupTests(unittest.TestCase):
    def test_booted_device_install_error_survives_cleanup_timeout(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier':'net.momiq.app','CFBundleSupportedPlatforms':['iPhoneSimulator']}))
            def simulate(command, *args, **kwargs):
                if command == 'list':
                    return json.dumps({'devices':{'com.apple.CoreSimulator.SimRuntime.iOS-18-6':[
                        {'name':'iPhone 16 Pro','isAvailable':True,'deviceTypeIdentifier':'TEST'}]}})
                if command == 'create':return 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                if command == 'bootstatus':return ''
                if command == 'install':raise RuntimeError('TEST install failure')
                if command == 'delete':raise subprocess.TimeoutExpired('simctl delete',90)
                self.fail(command)
            previous = Path.cwd()
            try:
                os.chdir(root)
                with patch('ios_startup.sim',side_effect=simulate), patch('ios_startup.subprocess.run') as host:
                    with self.assertRaisesRegex(RuntimeError,'TEST install failure') as error:
                        verify(root)
                    self.assertTrue(any('cleanup' in note for note in error.exception.__notes__))
                    self.assertEqual([call.args[0][0] for call in host.call_args_list],['javac'])
            finally:
                os.chdir(previous)

    def test_only_the_package_from_the_expected_revision_is_unpacked(self):
        with TemporaryDirectory() as tmp:
            root=Path(tmp);archive=root/'momiq-ios-simulator-debug.tar.gz'
            app=root/'Runner.app';app.mkdir();(app/'Info.plist').write_bytes(b'TEST')
            with tarfile.open(archive,'w:gz') as output:output.add(app,arcname=app.name)
            manifest={'sourceSha':'a'*40,'artifact':archive.name,'platform':'ios-simulator','releaseReady':False,
                      'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
            path=root/'manifest.json';path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):unpack(root,root/'foreign','b'*40)
            restored=unpack(root,root/'good','a'*40)
            self.assertEqual((restored/'Info.plist').read_bytes(),b'TEST')
            path.write_text(json.dumps({**manifest,'sha256':'0'*64}))
            with self.assertRaises(ValueError):unpack(root,root/'corrupt','a'*40)
            self.assertFalse((root/'corrupt').exists())
