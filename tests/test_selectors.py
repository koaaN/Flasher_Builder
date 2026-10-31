"""Exercise the custom selector's popup and keyboard selection contract."""
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
import unittest
from PySide6.QtCore import Qt
from PySide6.QtTest import QSignalSpy, QTest
from PySide6.QtGui import QFont, QFontMetrics
from PySide6.QtWidgets import QApplication, QVBoxLayout, QWidget, QStyle, QStyleOptionButton
from flasher_builder.gui import ComboBox, STYLE, button


class SelectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])
        cls.app.setStyle('Fusion')
        cls.app.setStyleSheet(STYLE)

    def setUp(self):
        self.window = QWidget()
        layout = QVBoxLayout(self.window)
        self.combo = ComboBox()
        self.combo.addItems(['OnePlus 13', 'OnePlus 13R', 'OnePlus Ace 6'])
        layout.addWidget(self.combo)
        self.window.resize(400, 120)
        self.window.show()
        self.app.processEvents()

    def tearDown(self):
        self.combo.hidePopup()
        self.window.close()
        self.app.processEvents()

    def test_mouse_commits_selection_once(self):
        spy = QSignalSpy(self.combo.activated)
        QTest.mouseClick(self.combo, Qt.MouseButton.LeftButton)
        self.app.processEvents()
        self.assertTrue(self.combo.menu.isVisible())
        view = self.combo.menu.view
        index = self.combo.model().index(1, 0)
        QTest.mouseClick(view.viewport(), Qt.MouseButton.LeftButton, pos=view.visualRect(index).center())
        self.assertEqual(self.combo.currentText(), 'OnePlus 13R')
        self.assertEqual(spy.count(), 1)
        self.assertFalse(self.combo.menu.isVisible())

    def test_region_labels_fit_selected_bold_text_without_resizing(self):
        for text in ('Global', 'EU', 'IN', 'NA', 'CN'):
            control = button(text, name='region'); control.setCheckable(True)
            self.window.layout().addWidget(control)
            self.app.processEvents()
            size = control.sizeHint()
            for selected in (False, True):
                control.setChecked(selected); self.app.processEvents()
                control.resize(size)
                option = QStyleOptionButton(); control.initStyleOption(option)
                contents = control.style().subElementRect(QStyle.SubElement.SE_PushButtonContents, option, control)
                font = QFont(control.font()); font.setWeight(QFont.Weight.Bold)
                self.assertGreaterEqual(contents.width(), QFontMetrics(font).horizontalAdvance(text) + 2, text)
                self.assertEqual(size, control.sizeHint(), text)

    def test_keyboard_navigation_and_escape(self):
        self.combo.setFocus()
        QTest.keyClick(self.combo, Qt.Key.Key_Down, Qt.KeyboardModifier.AltModifier)
        self.app.processEvents()
        self.assertTrue(self.combo.menu.isVisible())
        QTest.keyClick(self.combo.menu.view, Qt.Key.Key_Down)
        QTest.keyClick(self.combo.menu.view, Qt.Key.Key_Return)
        self.assertEqual(self.combo.currentIndex(), 1)
        self.combo.showPopup()
        QTest.keyClick(self.combo.menu.view, Qt.Key.Key_Down)
        QTest.keyClick(self.combo.menu.view, Qt.Key.Key_Escape)
        self.assertEqual(self.combo.currentIndex(), 1)
        self.assertFalse(self.combo.menu.isVisible())

    def test_popup_fits_options_and_tracks_replaced_model(self):
        self.combo.clear()
        self.combo.addItems(['Super Flasher', 'Regional Flasher'])
        self.combo.showPopup()
        self.app.processEvents()
        view = self.combo.menu.view
        self.assertEqual(view.verticalScrollBar().maximum(), 0)
        self.assertEqual(self.combo.menu.width() - 20, self.combo.width())
        self.combo.accept_option(view.model().index(1, 0))
        self.assertEqual(self.combo.currentText(), 'Regional Flasher')


if __name__ == '__main__':
    unittest.main()
