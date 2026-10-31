"""NEO8 selection, exact bloat inputs and generated flashers without hardware."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from flasher_builder.backend import Catalog, ROOT
from flasher_builder.native_pipeline import SUPER_PARTS
from flasher_builder.ota_catalog import targets
from scripts.materialize_bloat import load_manifest, selected_paths


class Neo8Tests(unittest.TestCase):
    def test_cn_only_super_configuration_and_supplied_images(self):
        catalog = Catalog()
        self.assertEqual(catalog.types('Realme NEO8'), ['Super Flasher'])
        self.assertEqual(catalog.regions('Realme NEO8', 'Super Flasher'), ['CN'])
        self.assertEqual(catalog.sizes['NEO8'], 18790481920)
        dev, builder, template = catalog.selection('Realme NEO8', 'Super Flasher', 'CN')
        self.assertEqual((dev, builder), ('NEO8', 'BUILD_SUPER.sh'))
        self.assertTrue((template/'Super_Flasher_COS.bat').is_file())
        self.assertTrue((template/'Super_Flasher_COS.sh').is_file())
        self.assertEqual(targets('Realme NEO8', 'Super Flasher', 'CN'), {'ota': ('Realme NEO 8', 'CN')})
        manifest = load_manifest(ROOT/'bloat/assets-manifest.json')
        paths = selected_paths(manifest, dev, 'Super Flasher', 'CN')
        self.assertEqual({Path(p).name for p in paths}, {'my_preload.img', 'my_company.img', 'system_dlkm_oki.img'})
        for name, sha in {
            'my_preload': '183688e20dbb34486259f3d3cf9d3e860cb3bc40cb8c5b1d028b17dc9e2476d2',
            'system_dlkm_oki': 'df5ebddcdbb85a8a7470bc1d5436ad37e446c72b0475361754833735e1022b2d',
            'my_company': '59603377dca738fda1d8c733b3d87712817e54d8ab9390846387b3bfb86c5730',
        }.items():
            self.assertEqual(manifest['files'][f'bloat/NEO8/CN_BLOAT/{name}.img'], sha)

    def run_flasher(self, root, fail=False, incomplete=False):
        _, _, template = Catalog().selection('Realme NEO8', 'Super Flasher', 'CN')
        package = root/'package with spaces'; shutil.copytree(template, package)
        images = package/'COS_FILES_HERE'; images.mkdir()
        for name in (*SUPER_PARTS, 'boot', 'init_boot', 'xbl'):
            (images/(name+'.img')).write_bytes(b'test fixture only')
        if not incomplete: (package/'super.img').write_bytes(b'test super only')
        binary = root/'bin'; binary.mkdir(); log = root/'fastboot.log'
        env = os.environ | {'PATH': str(binary)+os.pathsep+os.environ.get('PATH',''),
                            'FLASH_LOG': str(log), 'FAIL_FLASH': '1' if fail else '0'}
        if os.name == 'nt':
            (binary/'fastboot.cmd').write_text('@echo off\n' +
                'echo %*>>"%FLASH_LOG%"\n' +
                'if "%FAIL_FLASH%"=="1" if "%~1"=="flash" if "%~2"=="boot_b" exit /b 7\nexit /b 0\n')
            command = ['cmd', '/c', str(package/'Super_Flasher_COS.bat')]
        else:
            mock = binary/'fastboot'; mock.write_text('#!/bin/sh\n' +
                'printf "%s\\n" "$*" >> "$FLASH_LOG"\n' +
                'if [ "$FAIL_FLASH" = 1 ] && [ "$1" = flash ] && [ "$2" = boot_b ]; then exit 7; fi\n')
            mock.chmod(0o755); command = ['bash', str(package/'Super_Flasher_COS.sh')]
        result = subprocess.run(command, cwd=package, env=env, input='\n\nN\n',
            capture_output=True, text=True, timeout=15)
        return result, log.read_text() if log.exists() else ''

    def test_host_flasher_uses_super_once_and_does_not_overwrite_bloat(self):
        with tempfile.TemporaryDirectory() as tmp:
            result, log = self.run_flasher(Path(tmp))
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(log.count('flash super super.img'), 1)
        self.assertIn('flash boot_a ', log); self.assertIn('flash boot_b ', log)
        self.assertIn('flash --slot=all', log)
        for name in SUPER_PARTS:
            self.assertNotIn(f'{name}.img', log)
        self.assertNotIn('delete-logical-partition', log)
        self.assertNotIn('OOS_FILES_HERE', log)

    def test_host_flasher_stops_on_error_and_rejects_incomplete_packages(self):
        for fail, incomplete in ((True, False), (False, True)):
            with self.subTest(fail=fail, incomplete=incomplete), tempfile.TemporaryDirectory() as tmp:
                result, log = self.run_flasher(Path(tmp), fail, incomplete)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('flash super', log)
                self.assertNotIn('reboot', log)
