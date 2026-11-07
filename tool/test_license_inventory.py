import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from license_inventory import collect


class PubLicenseTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.package = self.root/'cached package'
        self.package.mkdir()
        (self.package/'pubspec.yaml').write_text('name: example\nversion: "1.2.3"\n', encoding='utf-8')
        (self.package/'LICENSE').write_text('Copyright TEST\nLicense TEST\n', encoding='utf-8')
        self.lock = self.root/'pubspec.lock'
        self.lock.write_text('TEST LOCK', encoding='utf-8')
        self.config = self.root/'package_config.json'
        self.entries = [{'name': 'example', 'rootUri': self.package.as_uri()}]
        self.inventory = {'packages': [{'name': 'example', 'version': '1.2.3', 'source': 'hosted', 'kind': 'direct'}]}

    def collect(self):
        self.config.write_text(json.dumps({'configVersion': 2, 'packages': self.entries}), encoding='utf-8')
        return collect(self.inventory, self.config, self.lock)

    def test_exact_version_notices_hash_and_explicit_sdk_exclusion(self):
        self.entries.append({'name': 'flutter', 'rootUri': 'not-read'})
        self.inventory['packages'].append({'name': 'flutter', 'version': '0.0.0', 'source': 'sdk', 'kind': 'direct'})
        report, notices = self.collect()
        self.assertFalse(report['legalApproval'])
        self.assertEqual(report['excludedPackages'], [{'name': 'flutter', 'source': 'sdk'}])
        file = report['packages'][0]['licenseFiles'][0]
        self.assertEqual(file['sha256'], hashlib.sha256((self.package/'LICENSE').read_bytes()).hexdigest())
        self.assertIn((self.package/'LICENSE').read_bytes().decode('utf-8'), notices)
        self.assertNotIn(str(self.root), str(report)+notices)

    def test_missing_or_empty_license_and_version_mismatch_fail(self):
        (self.package/'LICENSE').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing'):
            self.collect()
        (self.package/'LICENSE').write_text(' ', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'Empty'):
            self.collect()
        self.inventory['packages'][0]['version'] = '9.9.9'
        with self.assertRaisesRegex(ValueError, 'differs'):
            self.collect()

    def test_remote_paths_and_non_hosted_sources_fail_without_network(self):
        self.entries[0]['rootUri'] = 'https://example.invalid/private'
        with self.assertRaisesRegex(ValueError, 'local'):
            self.collect()
        self.inventory['packages'][0]['source'] = 'git'
        with self.assertRaisesRegex(ValueError, 'Non-hosted'):
            self.collect()

    def test_duplicate_and_incomplete_resolved_inventory_fail(self):
        self.entries.append(dict(self.entries[0]))
        with self.assertRaisesRegex(ValueError, 'Ambiguous'):
            self.collect()
        self.entries.clear()
        with self.assertRaisesRegex(ValueError, 'sets differ'):
            self.collect()


if __name__ == '__main__':
    unittest.main()
