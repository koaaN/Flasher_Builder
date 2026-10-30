"""Bloat download controls: folder choice, status changes and OTA-free action."""
import hashlib
import json
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication
from flasher_builder.gui import App, STYLE
from flasher_builder.runtime import Runtime


class BloatGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])
        cls.app.setStyle('Fusion'); cls.app.setStyleSheet(STYLE)

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.raw = b'Test image\0' * 512
        sha = hashlib.sha256(self.raw).hexdigest()
        self.manifest = dict(schema_version=1, repository='owner/private', tag='test',
            files={'bloat/13/GLO_BLOAT/my_preload.img': sha},
            assets={sha: dict(raw_sha256=sha, raw_bytes=len(self.raw), sha256=sha, bytes=len(self.raw), encoding='identity', asset_id=1, asset_name='test.img')})
        self.patch_manifest = patch('flasher_builder.gui.load_manifest', return_value=self.manifest)
        self.patch_manifest.start()
        self.window = App(); self.window.settings = self.root / 'settings.json'
        self.window.fields['device'].setCurrentText('Oneplus 13')
        self.window.fields['kind'].setCurrentText('SuperHybrid Flasher'); self.window.set_region('GLO')
        self.window.show()
        self.folder = self.root / 'chosen bloat'
        self.window.fields['bloat_dir'].setText(str(self.folder))
        self.wait_for(lambda: self.window.bloat_data is not None and self.window.bloat_active_token is None)

    def tearDown(self):
        self.window.timer.stop(); self.window.bloat_watch_timer.stop(); self.window.bloat_check_timer.stop()
        self.window.bloat_scan_token += 1
        self.window.close(); self.app.processEvents()
        self.patch_manifest.stop(); self.temporary.cleanup()

    def wait_for(self, condition, timeout=8):
        end = time.monotonic() + timeout
        while not condition() and time.monotonic() < end:
            QTest.qWait(20)
        self.assertTrue(condition(), self.window.bloat_status.text() + '\n' + self.window.log.toPlainText())

    def test_download_button_needs_no_ota_and_switches_to_already_downloaded(self):
        self.assertEqual(self.window.bloat_status.text(), 'Not downloaded')
        self.assertTrue(self.window.bloat_download.isEnabled())
        self.assertFalse(self.window.bloat_continue.isEnabled())
        self.assertFalse(self.window.ota_card.isEnabled())
        self.assertFalse(self.window.start_button.isEnabled())
        self.assertEqual(self.window.fields['ota'].text(), '')
        target = self.folder / '13/GLO_BLOAT/my_preload.img'
        code = ('from pathlib import Path; p=Path(' + repr(str(target)) + '); '
                'p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(' + repr(self.raw) + '); '
                'print("STEP 5/5 • Bloat files ready")')
        with patch.object(Runtime, 'command', return_value=[sys.executable, '-u', '-c', code]):
            self.window.bloat_download.click()
            self.assertTrue(self.window.busy)
            self.wait_for(lambda: not self.window.busy and bool(self.window.bloat_data and self.window.bloat_data.get('ready')))
        self.assertEqual(self.window.bloat_status.text(), 'Already downloaded')
        self.assertFalse(self.window.bloat_download.isEnabled())
        self.assertTrue(self.window.bloat_continue.isEnabled())
        self.assertTrue(self.window.ota_card.isEnabled())
        self.assertTrue(self.window.start_button.isEnabled())
        saved = json.loads(self.window.settings.read_text())
        self.assertEqual(Path(saved['bloat_dir']).resolve(), self.folder.resolve())
        target.unlink(); self.window.refresh_bloat_status()
        self.wait_for(lambda: self.window.bloat_data is not None and not self.window.bloat_data.get('ready') and self.window.bloat_active_token is None)
        self.assertTrue(self.window.bloat_download.isEnabled())
        self.assertFalse(self.window.bloat_continue.isEnabled())
        self.assertFalse(self.window.ota_card.isEnabled())
        self.assertFalse(self.window.start_button.isEnabled())

    def test_folder_picker_updates_status_and_saved_destination(self):
        folder = self.root / 'another folder'; target = folder / '13/GLO_BLOAT/my_preload.img'
        target.parent.mkdir(parents=True); target.write_bytes(self.raw)
        with patch('flasher_builder.gui.QFileDialog.getExistingDirectory', return_value=str(folder)):
            self.window.bloat_browse.click()
        self.wait_for(lambda: bool(self.window.bloat_data and self.window.bloat_data.get('ready')))
        self.assertEqual(self.window.bloat_status.text(), 'Already downloaded')
        self.assertEqual(json.loads(self.window.settings.read_text())['bloat_dir'], str(folder))
        self.window.set_region('EU')
        self.wait_for(lambda: self.window.bloat_data is not None and self.window.bloat_active_token is None)
        self.assertEqual(self.window.bloat_status.text(), 'No extra bloat needed')

    def test_build_cannot_bypass_missing_step_two_files(self):
        self.window.fields['ota'].setText('https://example.invalid/full.zip')
        with patch('flasher_builder.gui.QMessageBox.warning') as warning, patch.object(Runtime, 'command') as command:
            self.window.start('build')
        warning.assert_called_once()
        self.assertEqual(warning.call_args.args[1], 'Bloat files required')
        command.assert_not_called()
        self.assertFalse(self.window.busy)

    def test_region_change_locks_step_three_until_its_files_exist(self):
        sha = next(iter(self.manifest['assets']))
        self.manifest['files']['bloat/13/EU_BLOAT/my_preload.img'] = sha
        target = self.folder / '13/GLO_BLOAT/my_preload.img'
        target.parent.mkdir(parents=True); target.write_bytes(self.raw)
        self.window.refresh_bloat_status(force=True)
        self.wait_for(lambda: self.window.local_bloat_ready())
        self.assertTrue(self.window.ota_card.isEnabled())
        self.window.set_region('EU')
        self.assertFalse(self.window.ota_card.isEnabled())
        self.assertFalse(self.window.bloat_continue.isEnabled())
        self.wait_for(lambda: self.window.bloat_data is not None and self.window.bloat_active_token is None)
        self.assertFalse(self.window.start_button.isEnabled())

    def test_wsl_download_command_maps_destination_without_ota(self):
        with patch('flasher_builder.runtime.sys.platform', 'win32'):
            runtime = Runtime('Ubuntu')
        with patch.object(runtime, 'path', side_effect=lambda value: '/mapped/' + str(value)):
            cmd = runtime.command(self.window.values(), 'bloat', 'cancel file')
        self.assertIn('--download-bloat', cmd)
        self.assertEqual(cmd[cmd.index('--bloat-dir') + 1], '/mapped/' + str(self.folder))
        self.assertNotIn('--ota', cmd)


if __name__ == '__main__':
    unittest.main()
