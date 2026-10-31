import hashlib
import json
from pathlib import Path
import tarfile
from tempfile import TemporaryDirectory
import unittest

from ios_startup import unpack


class ArtifactStartupTests(unittest.TestCase):
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
