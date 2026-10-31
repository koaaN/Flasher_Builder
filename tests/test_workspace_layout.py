"""Setup fits without scrolling; task output is shown only after work starts."""
import os
import json
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from PySide6.QtCore import QPoint, QRect, Qt, QUrl
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication, QLineEdit, QPushButton, QScrollArea, QWidget
from flasher_builder.gui import App, CheckBox, ComboBox, ROOT, STYLE
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
        if minimum.width() > setup.width():
            for card in (self.window.configure_card, self.window.bloat_card, self.window.ota_card):
                print('LAYOUT CARD', card.minimumSizeHint().toTuple(), flush=True)
                for control in card.findChildren(QWidget):
                    if control.isVisibleTo(card):
                        print(type(control).__name__, getattr(control, 'text', lambda: '')()[:50],
                              'min', control.minimumSize().toTuple(),
                              'hints', control.minimumSizeHint().toTuple(), control.sizeHint().toTuple(),
                              'font', control.font().toString(), flush=True)
        self.assertLessEqual(minimum.width(), setup.width(),
            f'configuration={self.window.configure_card.minimumSizeHint().toTuple()}, '
            f'bloat={self.window.bloat_card.minimumSizeHint().toTuple()}, '
            f'OTA={self.window.ota_card.minimumSizeHint().toTuple()}')
        self.assertLessEqual(minimum.height(), setup.height())
        self.assertFalse(setup.findChildren(QScrollArea))
        for control in setup.findChildren(QWidget):
            if isinstance(control, (QLineEdit, QPushButton, CheckBox, ComboBox)) and control.isVisibleTo(setup):
                rect = QRect(control.mapTo(setup, QPoint()), control.size())
                self.assertTrue(setup.rect().contains(rect), control.accessibleName() or control.objectName())

    def test_all_supported_setup_modes_fit_without_output_or_scrollbars(self):
        self.assertTrue(self.window.nav[3].isHidden())
        self.assertFalse(self.window.log.isVisible())
        entries = {}
        for kind, dev, region in self.window.catalog.builders:
            device = next(k for k,v in self.window.catalog.devices.items() if v == dev)
            for name, code in targets(device, kind, region).values():
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

    def test_zip_option_remembers_choice_and_opens_finished_folder(self):
        self.window.zip_build.setChecked(True)
        QTest.mouseClick(self.window.zip_build, Qt.MouseButton.LeftButton)
        self.assertFalse(self.window.values()['zip_output'])
        self.assertFalse(json.loads(self.window.settings.read_text())['zip_output'])
        self.window.zip_build.setChecked(True)
        self.window.saved = json.loads(self.window.settings.read_text()) | {'zip_output': False}
        self.window.restore()
        self.assertFalse(self.window.zip_build.isChecked())
        output = self.root / 'output'; job = output / 'completed'
        folder = job / 'Finished flasher'; folder.mkdir(parents=True)
        (job / 'build.json').write_text(json.dumps(dict(device='Test device', flasher_type='Super Flasher',
            region='CN', version='1.0', created='2026-10-31T12:00:00', artifact=folder.name, output_format='folder')))
        self.window.load_history()
        item = self.window.history.topLevelItem(0)
        self.assertIn('Folder', item.text(0))
        self.assertEqual(Path(item.data(0, Qt.ItemDataRole.UserRole)), folder)
        self.window.current_output = output
        self.window.events.put(('output-root', str(output)))
        self.window.events.put(('line', '@@RESULT ' + json.dumps(dict(job=str(job), folder=str(folder), format='folder'))))
        self.window.poll()
        self.assertEqual(self.window.last_folder, folder)
        self.window.view_output_button.show()
        self.assert_setup_fits()

    def test_update_notification_and_manual_retry_do_not_reveal_build_output(self):
        result = dict(version='v9.0.0', url='https://github.com/koaaN/Flasher_Builder/releases/tag/v9.0.0')
        with patch('flasher_builder.gui.updates.check_for_updates', return_value=result), \
             patch('flasher_builder.gui.QDesktopServices.openUrl') as open_url:
            self.window.check_updates()
            self.wait_for(lambda: not self.window.update_checking)
            self.assertFalse(self.window.update_notice.isHidden())
            self.assertIn('v9.0.0', self.window.update_status.text())
            self.window.update_notice.click()
            self.assertEqual(open_url.call_args.args[0].toString(), result['url'])
        self.assertFalse(self.window.output_available)
        self.assertTrue(self.window.nav[3].isHidden())
        self.window.navigate(2)
        self.app.processEvents()
        environment = self.window.pages.widget(2)
        self.assertLessEqual(environment.minimumSizeHint().height(), environment.height())
        with patch('flasher_builder.gui.updates.check_for_updates', return_value=None):
            self.window.update_check_button.click()
            self.wait_for(lambda: not self.window.update_checking)
        self.assertIn('up to date', self.window.update_status.text())

    def test_documentation_opens_inside_app_and_preserves_setup(self):
        self.window.fields['ota'].setText('https://example.invalid/full.zip')
        before = self.window.values()
        with patch('flasher_builder.gui.QDesktopServices.openUrl') as open_url:
            self.window.documentation_button.click()
            self.assertEqual(self.window.pages.currentIndex(), 4)
            self.assertTrue(self.window.documentation_button.isChecked())
            self.assertTrue(self.window.documentation_view.isReadOnly())
            text = self.window.documentation_view.toPlainText()
            self.assertIn('Building a package', text)
            self.assertNotIn('## Building a package', text)
            self.assertGreater(self.window.documentation_topics.count(), 4)
            open_url.assert_not_called()
        self.app.processEvents()
        page = self.window.pages.currentWidget()
        self.assertLessEqual(page.minimumSizeHint().width(), page.width())
        self.assertLessEqual(page.minimumSizeHint().height(), page.height())
        self.assertFalse(self.window.output_available)
        self.window.nav[0].click()
        self.assertEqual(self.window.pages.currentIndex(), 0)
        self.assertEqual(self.window.values(), before)

    def test_documentation_section_navigation_and_search_wrap(self):
        self.window.documentation_button.click()
        topics = self.window.documentation_topics
        topics.setCurrentIndex(topics.findText('Building a package'))
        self.assertEqual(self.window.documentation_view.textCursor().block().text(), 'Building a package')
        self.window.documentation_search.setText('bloat')
        cursor = self.window.documentation_view.textCursor()
        self.assertEqual(cursor.selectedText().lower(), 'bloat')
        first = cursor.selectionStart()
        self.window.documentation_next.click()
        self.assertGreater(self.window.documentation_view.textCursor().selectionStart(), first)
        self.window.documentation_search.setText('no-such-documentation-text-9382')
        self.assertIn('No matching text', self.window.documentation_search.toolTip())
        self.window.documentation_search.clear()
        self.assertFalse(self.window.documentation_next.isEnabled())

    def test_local_documentation_links_stay_in_app_and_web_links_open_browser(self):
        self.window.documentation_button.click()
        with patch('flasher_builder.gui.QDesktopServices.openUrl') as open_url:
            self.window.documentation_view.anchorClicked.emit(QUrl('THIRD-PARTY-NOTICES.md'))
            self.assertEqual(self.window.documentation_path, ROOT / 'THIRD-PARTY-NOTICES.md')
            self.assertIn('Bundled native dependencies', self.window.documentation_view.toPlainText())
            open_url.assert_not_called()
            self.window.open_documentation_link(QUrl.fromLocalFile(str(self.root / 'outside.md')))
            self.assertEqual(self.window.documentation_path, ROOT / 'THIRD-PARTY-NOTICES.md')
            self.window.documentation_view.anchorClicked.emit(QUrl('https://github.com/koaaN/Flasher_Builder/releases'))
            open_url.assert_called_once()
            self.assertEqual(open_url.call_args.args[0].scheme(), 'https')
        self.window.documentation_button.click()
        self.assertEqual(self.window.documentation_path, ROOT / 'README.md')

    def test_missing_documentation_is_reported_inside_viewer(self):
        self.window.open_documentation()
        self.window.load_documentation(self.root / 'missing.md')
        self.assertIn('Documentation unavailable', self.window.documentation_view.toPlainText())
        self.assertEqual(self.window.pages.currentIndex(), 4)


if __name__ == '__main__': unittest.main()
