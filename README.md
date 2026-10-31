# Flasher Builder

A local desktop GUI for this repository's firmware build workflow. Select the device, flasher type and region, choose a **full OTA ZIP** or paste its download URL, and click **Build package**. The GUI supports the same 62 combinations as `.github/workflows/build_tools.yml` and filters the choices as you select a device.

Open **Documentation** in the sidebar to read this guide inside the app, with formatted headings, code blocks, section navigation and text search. Bundled documentation works offline; web links open in your browser.

## Linux and Windows releases

Download the matching package from the repository's [Releases](https://github.com/koaaN/Flasher_Builder/releases):

- **Windows 10/11 x64:** extract `FlasherBuilder-windows-x86_64.zip` and run `FlasherBuilder.exe`.
- **Linux x86-64:** extract `FlasherBuilder-linux-x86_64.tar.gz` and run `./FlasherBuilder`.

Extract the whole archive and keep the worker and project folders beside the GUI.
Both packages include Python, Qt, native otaripper **3.5.0** with remote streaming, lpmake, aria2c **1.37.0** and GitHub
CLI (optional for private forks). Windows does not need WSL, Git Bash, or a separate Python installation.
Linux requires curl and Qt runtime libraries; on Ubuntu/Debian:

```sh
sudo apt install curl libegl1 libopengl0 libxkbcommon0
```

Public releases, bloat downloads and update checks work without a GitHub login.
Downloads use bundled **aria2c `-x8 -s8`** (up to eight connections per file), with
**curl fallback** if aria2c is unavailable or a transfer fails. Files still download
one at a time. Servers determine whether parallel range requests improve speed.
Sizes and checksums are verified before files are accepted. Cancelling removes
partial data and aria2 control files without starting a fallback transfer.
Windows uses its built-in curl; Linux users should keep curl installed as a fallback.

For a private fork, an existing GitHub CLI login can resolve authenticated release
links. No account token is shipped or saved in application preferences.

Click **Check setup**, then **Run pipeline self-test** to verify the native tools.
Test packages contain synthetic data and must never be flashed.

## Running from source

Install Python 3.10 or newer and run these commands from the project folder:

```sh
python -m pip install -r requirements.txt
python scripts/fetch_tools.py --platform all
python flasher-builder.py
```

On Windows, `py -3` can replace `python`. On Linux, use `python3`. The source
launchers `start-linux.sh` and `start-windows.bat` are also provided. Paths and
URLs are passed as argument arrays, without shell interpolation.

## Building a package

- Choose a supported device, flasher type and region. CN means ColorOS; other regions use OxygenOS templates.
- Complete **step 2 — Bloat files**: choose a folder containing the required images or click **Download bloat**. The app verifies their sizes and SHA-256 hashes. You can select or download an OTA before this step is complete. **Build package** stays disabled until the required bloat, OTA selections, output folder and any required ODM match are ready.
- In **step 3**, use **Version catalog**, choose a full OTA ZIP, or enter an HTTP(S) URL. Placeholder and incremental OTA files are rejected.
- Choose the output folder. **ZIP build** is checked by default; uncheck it to keep the finished flasher folder and skip compression. This choice is remembered between launches. Recovery installation requires a ZIP.
- Click **Build package**. The app opens **Build output** for progress and logs; **Back to setup** returns to the form. The log reports download, staging, extraction, packing and optional compression. **Cancel** stops the active native tools and their child processes.
- **Open output** opens the latest result folder. Each job has a unique name and contains either the final ZIP with `.zip.sha256`, or the finished flasher folder, plus `build.json` and `build.log`. Build history also opens folder builds directly. Temporary work files are removed after a successful build. Cancelled builds remove their entire job folder after stopping the native tools, including partial packages and temporary images. Existing completed packages, original OTA files and downloaded bloat are preserved. Failed jobs retain partial work for inspection; those job folders can be deleted when no longer needed.

Budget roughly **40–80 GB free** for full firmware builds, depending on device, OTA compression and the number of inputs. The worker checks available space before extraction, but actual requirements vary. The GUI logs the OTA's declared device identifier; choose firmware appropriate for the selected device. A successful package build does not establish compatibility with a physical phone.

This application builds local ZIPs or flasher folders. SFTP uploads and Telegram announcements remain in the original GitHub Actions workflow. No runner registration or GitHub login is needed for public downloads.

### OTA version catalog

Open **Version catalog** in step 3 to fetch versions from [Daniel Springer's OTA catalog](https://roms.danielspringer.at/index.php?view=ota).
The picker matches the selected device and region, shows the latest release first,
and displays the model, size and security patch when available. **Fetch versions**
uses the site's [public catalog API](https://roms.danielspringer.at/api/ota.php?format=html&help=1),
with a shared 15-minute cache and ETag revalidation. An offline cached list is clearly marked.
Selections with no matching catalog releases can still use a local ZIP or a manual URL.
Conversion builds use explicit target/base mappings and show both selectors when needed.

Where a conversion requires a patch-matched ODM, the catalog shows the selected
donor version. The app finds a full donor OTA with the **exact same security patch
date**, including for older target versions, checks the actual OTA metadata, and
streams **only `odm.img`** plus the small ZIP/payload metadata needed to locate it.
The full donor OTA is never downloaded. The image must pass its payload SHA-256
checks before packing; the donor version, patch, image size and SHA-256 are recorded
in `build.json`. Missing patch data, no exact match, or a server without range
support stops the build. A fixed bloat ODM or a different patch is never substituted.
Local-file and direct-URL targets are identified from their embedded OTA metadata.

Select a version and click **Build package** to download it and build in one operation.
Alternatively, **Download OTA** saves and verifies the full ZIP without building;
the current session then shows **Already downloaded** and reuses that local ZIP for
builds. On later launches, choose that saved ZIP in **Local file**. Downloads happen
one at a time, including separate target and base packages when required. Bloat is required for building, and can be downloaded before or after selecting the OTA.

**Copy download link** resolves a fresh link onto the clipboard. Some links expire;
the worker resolves them again immediately before transfer rather than reusing an
old copied link. Temporary resolved links are not saved in settings, the cache or
build logs. Catalog downloads check the listed size and MD5 when provided, as well
as the existing full-OTA ZIP checks. Cancelled or failed standalone downloads remove
their partial files and leave existing files intact.

## Bloat assets

All bloat images are versioned together in the public `bloat-assets-v1` release.
`bloat/assets-manifest.json` maps each device/region image path to a release
attachment and pins its size and SHA-256. Identical images share one attachment.

The **Bloat files** panel follows the selected device, region and flasher type.
Use its folder button to choose where to keep the images, then click
**Download bloat**. No OTA is needed for this download. The panel reports
**Already downloaded** when all selected images have the correct sizes and
SHA-256 checksums, or shows how many files are missing. Use **Recheck** (the refresh icon spins while verifying)
to recheck files manually; status also updates when the selection or folder
changes. The chosen folder is remembered between sessions.

Images are stored as `<chosen folder>/<device>/<region folder>/*.img`.
Downloads happen one at a time. Completed images are reused, and a cancelled
download can be retried without downloading those images again. A hidden
`.cache` folder contains verified transport objects used for repairs and
compressed images. Builds reuse the images from the chosen folder automatically. The worker rechecks them before any OTA transfer and requires local images during staging; it never silently downloads missing bloat as part of a GUI build.

Step 2 fetches only the images needed by the selected device, region and
flasher type. Downloads are verified and kept in the chosen folder's `.cache`
for reuse. Images are verified again before the build starts and as they are
staged. The native build worker requires local images and does not silently fetch
missing bloat after step 2. Oversized release attachments are losslessly gzip-compressed;
the builder restores the original `.img` automatically.

The repository and bloat release are public. Set `BLOAT_CACHE_DIR` in the build environment to use a different
cache location. The cache can be removed when no build is running; the next
build downloads the required assets again. Cached assets can be reused offline.
This asset release uses release attachments, not Git LFS or expiring Actions
artifacts.

## Testing

**Check setup** verifies required commands and assets. **Run self-test** generates tiny Android OTAs with valid payload operations and runs the **real bundled** otaripper, lpmake and avbtool through all three builder scripts. It checks extracted bytes, sparse-image headers, archive CRCs, SHA-256, folder output, and patch-matched ODM extraction from a local HTTP range server. The range test checks that unrelated payload data is never transferred. Test artifacts begin with `TEST-DO-NOT-FLASH`; they contain synthetic bytes and must never be flashed.

Command-line checks:

```sh
python3 -m unittest discover -s tests -v
QT_QPA_PLATFORM=offscreen python3 flasher-builder.py --smoke-test --test-output /tmp/flasher-qt-test
python3 flasher_builder/backend.py --check
python3 flasher_builder/backend.py --self-test --output /tmp/flasher-builder-test
```

A normal command-line build is also supported:

```sh
python3 flasher_builder/backend.py --download-bloat --device 'DEVICE_NAME' \
  --kind 'FLASHER_TYPE' --region REGION --bloat-dir /path/to/bloat
python3 flasher_builder/backend.py --device 'DEVICE_NAME' \
  --kind 'FLASHER_TYPE' --region REGION --bloat-dir /path/to/bloat \
  --ota /path/to/FULL-OTA.zip --output /path/to/builds
```

The GitHub Actions scripts extract to explicit directories, normalize script line endings in per-job copies, stop when an asset download fails, and reject super images missing core partitions. Local builds never execute the workflow's runner-workspace cleanup step.

Add `--no-zip` to the command-line build to keep the finished flasher folder instead of creating an archive.

## Distribution builds

The setup form fits without scrolling, including supported target/base OTA selectors. Build output stays hidden until a task starts and uses its own view, so logs never shrink the setup form. Successful bloat and OTA downloads return to setup automatically; **View output** reopens their logs.

The app checks for newer stable app releases in the background on startup. When an update is available, an **Update v…** button appears in the sidebar and opens the release download page. **Environment → Check for updates** checks again manually and displays your installed version. Public update checks work without a login; connection problems appear in Environment and do not block builds. Checks ignore bloat releases, drafts, prereleases and releases missing your platform's package. Extract the new package to update; automatic installation is not performed.

The UI uses PySide6 (Qt 6). The build worker uses Python's standard library. Build history, environment checks, task logs and package summaries are built into the desktop interface. Create a portable source ZIP with:

```sh
python3 scripts/fetch_tools.py --platform all
python3 scripts/package_app.py
```

To also create a native executable distribution, run on the target OS:

```sh
python3 -m pip install -r requirements.txt pyinstaller
python3 scripts/fetch_tools.py --platform all
python3 scripts/package_app.py --native
```

On Windows, use `py -3` instead of `python3`. Native packages include project assets and a separate bundled console worker; do not distribute the executable by itself. Windows executables must be built on Windows. The Linux executable's glibc requirements depend on its build host.


The **Native desktop releases** GitHub Actions workflow builds on Ubuntu 22.04
and Windows Server 2022, runs regression tests, exercises real native tools, then
runs the extracted GUI's frozen pipeline self-test. It publishes both platform
archives, a source ZIP, validation receipts and SHA256SUMS only after both jobs
pass. Dispatch it with a new version such as `v1.0.0`.

The desktop pipeline stages files, selects partitions and constructs lpmake
arguments in Python. The original shell scripts remain for the separate firmware
GitHub Actions workflow. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for
tool origins, versions and licenses.


**Delete bloat** removes the image files required by the current selection and their unused download-cache copies from the selected bloat folder. A confirmation lists the device, region, folder and exact image paths. Other files remain in place; cache objects shared with another locally stored image are preserved. Deleting required files disables building until **Download bloat** restores them; OTA selection stays available. Delete/recheck controls are disabled during builds and downloads.
