"""Setup fits without scrolling; task output is shown only after work starts."""
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from PySide6.QtCore import QPoint, QRect
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication, QLineEdit, QPushButton, QScrollArea, QWidget
from flasher_builder.gui import App, ComboBox, STYLE
from flasher_builder.runtime import Runtime
from flasher_builder.ota_catalog import targets


class WorkspaceLayoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])
        cls.app.setStyle('Fusion'); cls.app.setStyleSheet(STYLE)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.manifest = patch('flasher_builder.gui.load_manifest', return_value={'files': {}, 'assets': {}})
        self.manifest.start()
        self.window = App(); self.window.settings = self.root/'settings.json'
        self.window.fields['bloat_dir'].setText(str(self.root/'bloat'))
        self.window.fields['output'].setText(str(self.root/'output'))
        self.window.resize(1120, 720); self.window.show()
        self.wait_for(self.window.local_bloat_ready)

    def tearDown(self):
        self.window.timer.stop(); self.window.bloat_watch_timer.stop(); self.window.bloat_check_timer.stop()
        self.window.bloat_scan_token += 1; self.window.ota_fetch_token += 1; self.window.ota_link_token += 1
        self.window.close(); self.app.processEvents()
        self.manifest.stop(); self.tmp.cleanup()

    def wait_for(self, predicate):
        end = time.monotonic()+8
        while not predicate() and time.monotonic()<end: QTest.qWait(20)
        self.assertTrue(predicate(), self.window.log.toPlainText())

    def assert_setup_fits(self):
        self.app.processEvents()
        setup = self.window.pages.widget(0)
        minimum = setup.minimumSizeHint()
        self.assertLessEqual(minimum.width(), setup.width())
        self.assertLessEqual(minimum.height(), setup.height())
        self.assertFalse(setup.findChildren(QScrollArea))
        for control in setup.findChildren(QWidget):
            if isinstance(control, (QLineEdit, QPushButton, ComboBox)) and control.isVisibleTo(setup):
                rect = QRect(control.mapTo(setup, QPoint()), control.size())
                self.assertTrue(setup.rect().contains(rect), control.accessibleName() or control.objectName())

    def test_all_supported_setup_modes_fit_without_output_or_scrollbars(self):
        self.assertTrue(self.window.nav[3].isHidden())
        self.assertFalse(self.window.log.isVisible())
        entries = {}
        for device in self.window.catalog.devices:
            for region in ('GLO', 'EU', 'IN', 'NA', 'CN'):
                for name, code in targets(device, 'SuperHybrid Flasher', region).values():
                    entries[name+code] = dict(id=name+code, device=name, region=code,
                        version='CPH2653_16.0.10.600(EX01)', model='CPH2653', size=8325705068,
                        security_patch='2026-09-01', is_latest=True, source_url='https://example.invalid/full.zip')
        self.window.ota_data = {'releases': list(entries.values())}
        for kind, dev, region in self.window.catalog.builders:
            device = next(k for k,v in self.window.catalog.devices.items() if v == dev)
            self.window.fields['device'].setCurrentText(device)
            self.window.fields['kind'].setCurrentText(kind); self.window.set_region(region)
            for mode in (False, True, 'catalog'):
                with self.subTest(device=device, kind=kind, region=region, mode=mode):
                    self.window.source_mode(mode)
                    self.assert_setup_fits()
        self.assertFalse(self.window.output_available)
        self.assertFalse(self.window.log.isVisible())

    def test_output_opens_for_a_task_and_can_be_revisited_without_shrinking_setup(self):
        code = 'import time; print("STEP 1/5 • Native test",flush=True); time.sleep(.2); print("finished")'
        with patch.object(Runtime, 'command', return_value=[sys.executable, '-u', '-c', code]):
            self.window.start('test')
            self.assertEqual(self.window.pages.currentIndex(), 3)
            self.assertTrue(self.window.log.isVisible())
            self.assertTrue(self.window.cancel_button.isEnabled())
            self.wait_for(lambda: not self.window.busy)
        self.assertIn('finished', self.window.log.toPlainText())
        self.assertFalse(self.window.cancel_button.isEnabled())
        self.window.navigate(0)
        self.assertFalse(self.window.log.isVisible())
        self.assert_setup_fits()
        self.window.view_output_button.click()
        self.assertEqual(self.window.pages.currentIndex(), 3)
        self.assertIn('finished', self.window.log.toPlainText())

    def test_cancel_is_available_in_output_view(self):
        def command(values, action, cancel):
            code = ('from pathlib import Path; import time; marker=Path('+repr(str(cancel))+'); '
                    'exec("while not marker.exists(): time.sleep(.02)"); raise SystemExit(130)')
            return [sys.executable, '-u', '-c', code]
        with patch.object(Runtime, 'command', side_effect=command):
            self.window.start('test')
            self.window.cancel_button.click()
            self.wait_for(lambda: not self.window.busy)
        self.assertIn('cancelled', self.window.status.text().lower())
        self.assertEqual(self.window.pages.currentIndex(), 3)


if __name__ == '__main__': unittest.main()
