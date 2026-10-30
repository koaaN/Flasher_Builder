# Bundled native dependencies

The private application packages include these tools; their licenses remain in
force. No GitHub credentials are included in a package.

- **otaripper-lite 3.5.0**, by syedinsaf and contributors, Apache-2.0.
  https://github.com/syedinsaf/otaripper/releases/tag/v3.5.0
  Linux uses the static musl x86-64 build; Windows uses the MSVC x86-64 build.
  This application downloads the OTA itself, then uses the local extractor.
  License: `otaripper/LICENSE`.
- **lpmake**, Android Open Source Project, Apache-2.0.
  The existing Linux executable is retained. Windows uses Rprop's native AOSP
  Android 15 build at commit `5e92a5d504de33414318ced8bad5507440bb8c30`.
  https://github.com/Rprop/aosp15_partition_tools/tree/5e92a5d504de33414318ced8bad5507440bb8c30
  Its Windows executable is x86 and runs on supported x86-64 Windows systems.
  It uses Windows' Universal C Runtime. The upstream build patches are included
  beside the binary. License: `lpmake/LICENSE`.
- **GitHub CLI 2.103.3**, GitHub and contributors, MIT.
  https://github.com/cli/cli/releases/tag/v2.103.3
  License: `tools/github/LICENSE`. Its platform binaries are fetched during
  release builds and bundled for private bloat downloads; they are not Git blobs.
- **PySide6 / Qt 6**, Qt Company and contributors, LGPL-3.0/GPL/commercial options.
  https://doc.qt.io/qtforpython-6/licenses.html
  The packaged app uses the open-source PySide6 distribution. Qt libraries are
  distributed as dynamically loaded libraries by PyInstaller. The source app and
  packaging instructions allow rebuilding with a replacement compatible PySide6.
- **PyInstaller**, PyInstaller Development Team, GPL-2.0-or-later with the
  bootloader exception. https://pyinstaller.org/en/stable/license.html
- **avbtool and Android platform tools** retain their existing upstream licenses.
  avbtool is from AOSP, Apache-2.0; platform-tool license notices are bundled in
  `Platform-Tools` where provided by the original project.

`tools/dependencies.json` pins archive and executable SHA-256 hashes and download
origins. `scripts/fetch_tools.py` verifies every newly downloaded dependency.
