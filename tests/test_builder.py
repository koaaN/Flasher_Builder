import contextlib
import io
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import zipfile
from types import SimpleNamespace

from flasher_builder.backend import BuildError, Cancelled, Catalog, ROOT, Worker, build, clean_source, validate_ota, normalize_assets
from flasher_builder.runtime import Runtime
from flasher_builder.selftest import make_ota


class BuilderTests(unittest.TestCase):
    def test_cancelled_build_removes_only_its_own_job(self):
        for phase in ('prepare', 'extract', 'package'):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); output = root/'output'; output.mkdir()
                previous = output/'completed'; previous.mkdir()
                (previous/'package.zip').write_bytes(b'completed package')
                source = root/'original.zip'; source.write_bytes(b'original OTA')
                cancel = root/'cancel'
                args = SimpleNamespace(repo=str(ROOT), output=str(output), device='Oneplus 13',
                    kind='SuperHybrid Flasher', region='GLO', base='', ota=str(source),
                    bloat_dir=str(root/'bloat'), cancel=str(cancel), fixture=True)
                def stop(worker, destination):
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(b'incomplete build data')
                    cancel.touch(); worker.check()
                def prepare(worker, args, role, destination):
                    if phase == 'prepare': stop(worker, destination)
                    destination.write_bytes(b'copied OTA')
                    return '1.2.3.4', 32, {}
                def normalize(repo, assets, dev, template): assets.mkdir()
                def stage(worker, assets, destination, *args):
                    destination.mkdir(); return destination
                def images(worker, assets, result, *args):
                    if phase == 'extract': stop(worker, result/'partial.img')
                    boot = result/'OOS_FILES_HERE'; boot.mkdir()
                    (boot/'boot.img').write_bytes(b'boot'); (result/'super.img').write_bytes(b'super')
                    return result
                with patch('flasher_builder.backend.check_environment'), \
                     patch('flasher_builder.backend.require_local_bloat'), \
                     patch('flasher_builder.backend.prepare_ota', side_effect=prepare), \
                     patch('flasher_builder.backend.normalize_assets', side_effect=normalize), \
                     patch('flasher_builder.native_pipeline.stage', side_effect=stage), \
                     patch('flasher_builder.native_pipeline.build_images', side_effect=images), \
                     patch('flasher_builder.backend.package', side_effect=lambda worker, result, dest: stop(worker, dest)), \
                     contextlib.redirect_stdout(io.StringIO()) as log:
                    with self.assertRaises(Cancelled): build(args)
                self.assertEqual(list(output.iterdir()), [previous])
                self.assertEqual((previous/'package.zip').read_bytes(), b'completed package')
                self.assertEqual(source.read_bytes(), b'original OTA')
                self.assertIn('Cancelled build output removed.', log.getvalue())

    def test_every_workflow_combination_has_assets(self):
        catalog = Catalog()
        self.assertEqual(len(catalog.builders), 61)
        for (kind, dev, region), builder in catalog.builders.items():
            device = next(k for k, v in catalog.devices.items() if v == dev)
            with self.subTest(device=device, kind=kind, region=region):
                catalog.selection(device, kind, region)
                self.assertTrue((ROOT / 'build_scripts' / builder).is_file())
                if 'Super' in kind:
                    self.assertGreater(catalog.sizes[dev], 0)
        with self.assertRaises(BuildError):
            catalog.selection('Oneplus 13', 'SuperHybrid Flasher', 'INVALID')

    def test_ota_validation_rejects_incremental_and_placeholder(self):
        with tempfile.TemporaryDirectory() as folder:
            ota = Path(folder) / 'test.zip'
            with zipfile.ZipFile(ota, 'w') as z:
                z.writestr('PLACEHOLDER.txt', 'not firmware')
            with self.assertRaises(BuildError):
                validate_ota(ota)
            make_ota(ota, {'boot': b'\0' * 4096})
            self.assertEqual(validate_ota(ota)[0], '1.2.3.4')
            with zipfile.ZipFile(ota) as z:
                payload = z.read('payload.bin')
            with zipfile.ZipFile(ota, 'w') as z:
                z.writestr('payload.bin', payload)
                z.writestr('META-INF/com/android/metadata', 'pre-build=old\nversion_name=1.2.3.4\n')
            with self.assertRaisesRegex(BuildError, 'incremental'):
                validate_ota(ota)

    def test_url_cleanup_and_literal_argument_passing(self):
        self.assertEqual(clean_source('  "https://host/ota?a=1\\u0026b=2"  '), 'https://host/ota?a=1&b=2')
        malicious = 'https://host/ota?x=$(touch /tmp/should-never-exist)&a=1'
        values = dict(output='/tmp/build dir', device='Oneplus 13', kind='SuperHybrid Flasher', region='GLO', ota=malicious, base='')
        command = Runtime().command(values, 'build', '/tmp/cancel marker')
        self.assertEqual(command[command.index('--ota') + 1], malicious)
        self.assertEqual(command[command.index('--output') + 1], str(Path(values['output']).resolve()))

    def test_windows_native_command_preserves_paths_and_url(self):
        with patch('flasher_builder.runtime.sys.platform', 'win32'):
            runtime = Runtime('Ubuntu Test')
        self.assertEqual(runtime.prefix, [])
        values = dict(output='Output Folder', device='Oneplus Ace 6', kind='SuperHybrid Flasher', region='IN', ota='https://host/ota?a=1&b=2', base='base OTA.zip')
        with patch.object(runtime, 'path', side_effect=lambda p: '/mapped/' + str(p)):
            command = runtime.command(values, 'build', 'cancel file')
        self.assertEqual(command[command.index('--base') + 1], '/mapped/base OTA.zip')
        self.assertEqual(command[command.index('--ota') + 1], values['ota'])
        self.assertNotIn('wsl.exe', command)
        self.assertEqual(command[:2], [sys.executable, '-u'])
        self.assertTrue(command[2].endswith('flasher-worker.py'))

    def test_release_jobs_copy_manifest_without_other_region_images(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); repo = root / 'repo'; repo.mkdir()
            for name in ('build_scripts', 'scripts', 'otaripper', 'lpmake', 'build_tools_assets', 'Platform-Tools'):
                (repo / name).mkdir()
            template = repo / 'flasher_scripts/13/oos/super'; template.mkdir(parents=True)
            (template / 'template.txt').write_text('template')
            (repo / 'bloat/13/CN_BLOAT').mkdir(parents=True)
            (repo / 'bloat/13/CN_BLOAT/unneeded.img').write_bytes(b'unneeded region image')
            (repo / 'bloat/assets-manifest.json').write_text('{}')
            target = root / 'job'
            normalize_assets(repo, target, '13', template)
            self.assertTrue((target / 'bloat/assets-manifest.json').is_file())
            self.assertFalse((target / 'bloat/13').exists())
            self.assertTrue((target / 'flasher_scripts/13/oos/super/template.txt').is_file())

    def test_child_failure_surfaces(self):
        with self.assertRaisesRegex(BuildError, 'exit 7'):
            Worker().run([sys.executable, '-c', 'raise SystemExit(7)'])

    @unittest.skipUnless(os.name == 'posix', 'POSIX process-group check')
    def test_cancellation_stops_process_group(self):
        with tempfile.TemporaryDirectory() as folder:
            marker = Path(folder) / 'cancel'
            pidfile = Path(folder) / 'pid'
            code = 'import os,time; from pathlib import Path; Path(' + repr(str(pidfile)) + ').write_text(str(os.getpid())); time.sleep(30)'
            trigger = threading.Timer(.5, marker.touch)
            trigger.start()
            start = time.monotonic()
            try:
                with self.assertRaises(Cancelled):
                    Worker(marker).run([sys.executable, '-c', code])
                self.assertLess(time.monotonic() - start, 5)
                pid = int(pidfile.read_text())
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
            finally:
                trigger.cancel()

    @unittest.skipUnless(os.name == 'posix', 'Legacy Actions Bash helper')
    def test_failed_asset_download_aborts_staging(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            text = (ROOT / 'scripts/stage_files.sh').read_text()
            # Exercise the actual helper with curl failing; no network required.
            helper = text[:text.index('# -----------------------------\n#      Device Configuration')]
            assets = root / 'assets'; assets.mkdir()
            (assets / 'my_preload').write_text('https://invalid.test/asset')
            command = helper + '\ncurl() { return 22; }\ncopy_bloat_from_folder "$1" assets "$2"\necho UNREACHABLE\n'
            result = subprocess.run(['bash', '-c', command, 'test', str(root), str(root / 'dest')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 22, result.stdout + result.stderr)
            self.assertNotIn('UNREACHABLE', result.stdout)


if __name__ == '__main__':
    unittest.main()
