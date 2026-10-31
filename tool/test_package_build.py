import hashlib
import json
from pathlib import Path
import plistlib
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from package_build import package


class PackageTests(unittest.TestCase):
    badging = "package: name='net.momiq.app' versionCode='4' versionName='1.2.3'\nsdkVersion:'26'\ntargetSdkVersion:'36'\n"
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        (self.root/'pubspec.yaml').write_text('version: 1.2.3+4\n')
        (self.root/'pubspec.lock').write_text('TEST locked dependencies')
        (self.root/'config').mkdir()
        (self.root/'config/local.json').write_text('{"MOMIQ_ENV":"local"}')

    def android(self):
        path = self.root/'build/app/outputs/flutter-apk/app-debug.apk'
        path.parent.mkdir(parents=True)
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('AndroidManifest.xml', 'TEST manifest')
            archive.writestr('lib/arm64-v8a/libflutter.so', 'TEST engine')
        return path

    @patch('package_build.apk_badging', return_value=badging)
    def test_android_identity_hash_and_existing_evidence(self, _badging):
        binary = self.android()
        result = package(self.root, 'android', 'a'*40, 'b'*40)
        self.assertEqual(result['sha256'], hashlib.sha256(binary.read_bytes()).hexdigest())
        self.assertEqual(result['checkoutSha'], 'a'*40)
        self.assertEqual(result['sourceSha'], 'b'*40)
        self.assertEqual(result['binaryIdentity']['minSdk'], 26)
        self.assertFalse(result['releaseReady'])
        output = self.root/'ci-artifacts/android/manifest.json'
        before = output.read_bytes()
        with self.assertRaisesRegex(ValueError, 'existing artifact'):
            package(self.root, 'android', 'a'*40, 'c'*40)
        self.assertEqual(output.read_bytes(), before)

    def test_android_binary_must_match_the_declared_identity(self):
        self.android()
        for previous, changed in [('net.momiq.app', 'com.example.demo'), ("'4'", "'5'"),
                                  ("'1.2.3'", "'1.2.2'"), ("'26'", "'21'")]:
            with self.subTest(changed=changed), patch('package_build.apk_badging',
                    return_value=self.badging.replace(previous, changed)):
                with self.assertRaisesRegex(ValueError, 'Android binary'):
                    package(self.root, 'android', 'a'*40, 'b'*40)
                self.assertFalse((self.root/'ci-artifacts').exists())

    def test_unsigned_simulator_archive_keeps_source_permissions(self):
        app = self.root/'build/ios/iphonesimulator/Runner.app'
        app.mkdir(parents=True)
        (app/'Runner').write_bytes(b'TEST executable')
        (app/'Runner').chmod(0o755)
        with (app/'Info.plist').open('wb') as stream:
            info = {'CFBundleIdentifier':'net.momiq.app', 'CFBundleSupportedPlatforms':['iPhoneSimulator'],
                    'CFBundleExecutable':'Runner', 'CFBundleShortVersionString':'1.2.3',
                    'CFBundleVersion':'4', 'MinimumOSVersion':'15.0'}
            plistlib.dump(dict(info, CFBundleVersion='5'), stream)
        with self.assertRaisesRegex(ValueError, 'iOS binary'):
            package(self.root, 'ios-simulator', 'a'*40, 'b'*40)
        with (app/'Info.plist').open('wb') as stream:
            plistlib.dump(info, stream)
        result = package(self.root, 'ios-simulator', 'a'*40, 'b'*40)
        self.assertEqual(result['binaryIdentity']['minimumOs'], '15.0')
        self.assertEqual(result['signing'], 'unsigned-simulator')
        with tarfile.open(self.root/'ci-artifacts/ios-simulator'/result['artifact']) as archive:
            self.assertEqual(archive.extractfile('Runner.app/Runner').read(), b'TEST executable')
            self.assertEqual(archive.getmember('Runner.app/Runner').mode & 0o777, (app/'Runner').stat().st_mode & 0o777)

    def test_wrong_build_or_environment_produces_no_publishable_directory(self):
        self.android()
        for change in ('commit', 'environment', 'platform'):
            with self.subTest(change=change):
                (self.root/'config/local.json').write_text(json.dumps({'MOMIQ_ENV':'production' if change=='environment' else 'local'}))
                with self.assertRaises(ValueError):
                    package(self.root, 'release' if change=='platform' else 'android', 'wrong' if change=='commit' else 'a'*40, 'b'*40)
                self.assertFalse((self.root/'ci-artifacts').exists())
        (self.root/'config/local.json').write_text('{"MOMIQ_ENV":"local"}')
        with zipfile.ZipFile(self.root/'build/app/outputs/flutter-apk/app-debug.apk','w') as archive:
            archive.writestr('TEST', 'not an APK')
        with self.assertRaisesRegex(ValueError, 'ARM64'):
            package(self.root, 'android', 'a'*40, 'b'*40)
        self.assertFalse((self.root/'ci-artifacts').exists())
