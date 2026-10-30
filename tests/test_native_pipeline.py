"""Portable staging parity, sparse sizes and native process/worker checks."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from flasher_builder.backend import ROOT, BuildError, Cancelled, Catalog, Worker
from flasher_builder.host import tool, worker_command
from flasher_builder.native_pipeline import stage, image_size, pack_super


class NativePipelineTests(unittest.TestCase):
    def test_pinned_tools_and_native_extractor_version(self):
        for entry in json.loads((ROOT/'tools/dependencies.json').read_text()):
            path = ROOT/entry['path']
            if path.is_file(): self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), entry['sha256'])
        result = subprocess.run([str(tool(ROOT, 'otaripper')), '--version'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('3.5.0', result.stdout)

    def test_frozen_worker_is_native_on_both_systems(self):
        for platform, name in [('win32', 'FlasherBuilderWorker.exe'), ('linux', 'FlasherBuilderWorker')]:
            with patch('flasher_builder.host.sys.platform', platform), patch('flasher_builder.host.sys.frozen', True, create=True):
                command = worker_command(ROOT)
            self.assertEqual(command, [str(ROOT / name)])
            self.assertNotIn('wsl.exe', command)

    def test_all_61_selections_stage_same_images_as_actions(self):
        workflow = Catalog()
        original = json.loads((ROOT / 'bloat/assets-manifest.json').read_text())
        raw = b'Native staging image\0' * 256
        sha = hashlib.sha256(raw).hexdigest()
        manifest = dict(schema_version=1, repository='owner/private', tag='fixture',
            files={p: sha for p in original['files']}, assets={sha: dict(asset_id=1,
                asset_name='fixture.img', bytes=len(raw), sha256=sha, raw_bytes=len(raw), raw_sha256=sha, encoding='identity')})
        with tempfile.TemporaryDirectory(prefix='native-stage-') as tmp:
            root = Path(tmp); assets = root / 'assets'; assets.mkdir()
            for name in ('flasher_scripts', 'scripts', 'build_scripts', 'build_tools_assets', 'lpmake', 'otaripper'):
                shutil.copytree(ROOT / name, assets / name, ignore=shutil.ignore_patterns('__pycache__'))
            (assets / 'Platform-Tools').mkdir(); (assets / 'bloat').mkdir()
            (assets / 'bloat/assets-manifest.json').write_text(json.dumps(manifest))
            source = root / 'local'
            for relative in manifest['files']:
                path = source / Path(relative).relative_to('bloat'); path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
            for index, ((kind, dev, region), builder) in enumerate(workflow.builders.items()):
                with self.subTest(device=dev, kind=kind, region=region):
                    output = stage(Worker(), assets, root / 'native', dev, kind, region, source)
                    images = {p.relative_to(output).as_posix(): p.read_bytes() for p in output.rglob('*.img')}
                    self.assertTrue(images)
                    self.assertTrue(all(data == raw for data in images.values()))
                    if os.name == 'posix':
                        env = os.environ | dict(DEV=dev, FTYPE=kind, REGION=region, BUILDER_SH=builder,
                            OUT_DIR=str(root/'actions'), GITHUB_WORKSPACE=str(assets), GITHUB_ENV=str(root/'env'),
                            BLOAT_SOURCE_DIR=str(source), BLOAT_REQUIRE_LOCAL='1', BLOAT_CACHE_DIR=str(root/'cache'))
                        result = subprocess.run(['bash', str(assets/'scripts/stage_files.sh')], env=env, capture_output=True, text=True)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        legacy = root / 'actions' / output.name
                        expected = {p.relative_to(legacy).as_posix(): p.read_bytes() for p in legacy.rglob('*.img')}
                        self.assertEqual(images, expected)
                        shutil.rmtree(root/'actions')
                    shutil.rmtree(root/'native')

    def test_lpmake_handles_images_and_super_larger_than_4_gib(self):
        with tempfile.TemporaryDirectory(prefix='native-large-sparse-') as tmp:
            directory = Path(tmp)
            blocks = 5 * 1024**3 // 4096
            # 5 GiB logical image; only one actual 4 KiB block is stored.
            header = struct.pack('<IHHHHIIII', 0xed26ff3a, 1, 0, 28, 12, 4096, blocks, 2, 0)
            skip = struct.pack('<HHII', 0xcac3, 0, blocks-1, 12)
            data = struct.pack('<HHII', 0xcac1, 0, 1, 12+4096) + b'S' * 4096
            (directory/'system.img').write_bytes(header + skip + data)
            for name in ('vendor', 'product'): (directory/(name+'.img')).write_bytes(b'V'*4096)
            self.assertEqual(image_size(directory/'system.img'), 5*1024**3)
            pack_super(Worker(), ROOT, directory, 16*1024**3)
            self.assertEqual(image_size(directory/'super.img'), 16*1024**3)
            self.assertLess((directory/'super.img').stat().st_size, 4*1024**2)

    @unittest.skipUnless(os.name == 'nt', 'Windows process cancellation')
    def test_windows_cancellation_stops_native_child(self):
        with tempfile.TemporaryDirectory() as tmp:
            cancel = Path(tmp)/'cancel'
            timer = threading.Timer(.4, cancel.touch); timer.start()
            start = time.monotonic()
            try:
                with self.assertRaises(Cancelled):
                    Worker(cancel).run([sys.executable, '-c', 'import time; time.sleep(30)'])
                self.assertLess(time.monotonic()-start, 5)
            finally: timer.join()


if __name__ == '__main__': unittest.main()
