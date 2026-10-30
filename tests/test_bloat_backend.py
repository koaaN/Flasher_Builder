"""Check cancellation of a bloat-only download without contacting GitHub."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from flasher_builder.backend import ROOT


class BloatBackendTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'linux', 'Linux/WSL build worker')
    def test_cancelled_download_removes_partial_cache_and_keeps_no_image(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); repo = root / 'repo'
            (repo / '.github/workflows').mkdir(parents=True)
            shutil.copy2(ROOT / '.github/workflows/build_tools.yml', repo / '.github/workflows/build_tools.yml')
            (repo / 'flasher_scripts/13/oos/super/META-INF').mkdir(parents=True)
            (repo / 'scripts').mkdir(); shutil.copy2(ROOT / 'scripts/materialize_bloat.py', repo / 'scripts/materialize_bloat.py')
            raw = b'\0' * 4096; sha = hashlib.sha256(raw).hexdigest()
            manifest = dict(schema_version=1, repository='owner/private', tag='test',
                assets={sha: dict(asset_id=1, asset_name='test.img', bytes=len(raw), sha256=sha,
                                  raw_bytes=len(raw), raw_sha256=sha, encoding='identity')},
                files={'bloat/13/GLO_BLOAT/my_preload.img': sha})
            (repo / 'bloat').mkdir(); (repo / 'bloat/assets-manifest.json').write_text(json.dumps(manifest))
            bin_dir = root / 'bin'; bin_dir.mkdir()
            fake = bin_dir / 'gh'
            fake.write_text('#!/usr/bin/python3\nimport sys,time\nsys.stdout.buffer.write(b"x"*1024)\nsys.stdout.buffer.flush()\ntime.sleep(30)\n')
            fake.chmod(0o755)
            destination = root / 'chosen bloat'; cancel = root / 'cancel'
            env = os.environ | {'PATH': str(bin_dir) + os.pathsep + os.environ['PATH']}
            env.pop('BLOAT_CACHE_DIR', None)
            process = subprocess.Popen([sys.executable, str(ROOT / 'flasher_builder/backend.py'), '--repo', str(repo),
                '--download-bloat', '--bloat-dir', str(destination), '--cancel', str(cancel)],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
            try:
                end = time.monotonic() + 8
                while time.monotonic() < end:
                    if list((destination / '.cache').glob('*.part-*')): break
                    if process.poll() is not None: break
                    time.sleep(.02)
                self.assertTrue(list((destination / '.cache').glob('*.part-*')))
                cancel.touch()
                output = process.communicate(timeout=8)[0]
                self.assertEqual(process.returncode, 130, output)
                self.assertFalse(list((destination / '.cache').glob('*.part-*')))
                self.assertFalse((destination / '13/GLO_BLOAT/my_preload.img').exists())
            finally:
                if process.poll() is None: process.kill(); process.communicate()


if __name__ == '__main__':
    unittest.main()
