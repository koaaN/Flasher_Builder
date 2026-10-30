# Flasher Builder

A local desktop GUI for this repository's firmware build workflow. Select the device, flasher type and region, choose a **full OTA ZIP** or paste its download URL, and click **Build package**. The GUI supports the same 61 combinations as `.github/workflows/build_tools.yml` and filters the choices as you select a device.

## Linux

Use an x86-64 Linux PC. For the source version, install Python 3.10 or newer and install the Qt 6 interface dependency. Ubuntu/Debian setup:

```sh
sudo apt install python3 python3-pip curl rsync coreutils findutils gawk gh
python3 -m pip install -r requirements.txt
gh auth login
./start-linux.sh
```

If downloaded file permissions have been removed, run `bash start-linux.sh`. The native Linux distribution also contains a `FlasherBuilder` executable; it includes Python and Qt 6. Keep it beside the bundled project folders. Build tools such as curl and rsync are still required.

## Windows

The GUI runs natively on Windows. The bundled `otaripper` and `lpmake` binaries run in **x86-64 WSL Linux**. Git Bash alone cannot execute these Linux binaries.

1. Install Python 3.10 or newer from [python.org](https://www.python.org/downloads/windows/), and run `py -3 -m pip install -r requirements.txt` from the project folder.
2. Install WSL Ubuntu from an Administrator PowerShell:

   ```powershell
   wsl --install -d Ubuntu
   ```

3. Restart if requested, open Ubuntu and finish creating its user. Inside Ubuntu run:

   ```sh
   sudo apt update
   sudo apt install python3 curl rsync coreutils findutils gawk gh
   gh auth login
   ```

4. Extract the whole project to a writable folder, then double-click `start-windows.bat`.
5. Click **Check setup**. Leave the WSL distribution field blank for your default distribution, or enter its name from `wsl --list --quiet`.

Paths are converted through `wslpath`; local paths and URLs are passed as arguments without shell interpolation. Choose a Windows-visible output folder with enough space. See Microsoft's [WSL installation guide](https://learn.microsoft.com/en-us/windows/wsl/install) and [command reference](https://learn.microsoft.com/en-us/windows/wsl/basic-commands).

A native Windows executable can also be built on Windows using the packaging command below. It removes the GUI's Windows Python requirement; Python inside WSL remains necessary.

## Building a package

- Choose a supported device, flasher type and region. CN means ColorOS; other regions use OxygenOS templates.
- Complete **step 2 — Bloat files**: choose a folder containing the required images or click **Download bloat**. The app verifies their sizes and SHA-256 hashes. **Continue to OTA**, step 3, and **Build package** stay locked until the selected build's files are verified locally.
- In **step 3**, choose a full OTA ZIP or enter an HTTP(S) URL. Placeholder and incremental OTA files are rejected.
- **Ace 6 / SuperHybrid / IN** additionally requires the Ace 6 ColorOS **BASE** OTA. Its primary OTA must be the OnePlus 15R India OxygenOS **TARGET** OTA.
- Choose the output folder and click **Build package**. The log reports download, staging, extraction, packing and compression. **Cancel** stops the worker's current subprocess group, including through WSL.
- **Open output** opens the latest result folder. Each job has a unique name and contains the final ZIP, `.zip.sha256`, `build.json`, and `build.log`. Temporary work files are removed after a successful build. Failed or cancelled jobs retain partial work for inspection; those job folders can be deleted when no longer needed.

Budget roughly **40–80 GB free** for full firmware builds, depending on device, OTA compression and the number of inputs. The worker checks available space before extraction, but actual requirements vary. The GUI logs the OTA's declared device identifier; choose firmware appropriate for the selected device. A successful package build does not establish compatibility with a physical phone.

This application builds local ZIPs. SFTP uploads and Telegram announcements remain in the original GitHub Actions workflow. No runner registration is needed. Private release downloads use the GitHub CLI login in the Linux build environment; run `gh auth login` on Linux or inside WSL on Windows. No token is saved in the application settings.

## Bloat assets

All bloat images are versioned together in the private `bloat-assets-v1` release.
`bloat/assets-manifest.json` maps each device/region image path to a release
attachment and pins its size and SHA-256. Identical images share one attachment.

The **Bloat files** panel follows the selected device, region and flasher type.
Use its folder button to choose where to keep the images, then click
**Download bloat**. No OTA is needed for this download. The panel reports
**Already downloaded** when all selected images have the correct sizes and
SHA-256 checksums, or shows how many files are missing. Use the refresh button
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
staged. The build worker requires local images and does not silently fetch
missing bloat after step 2. The Ace 6T ODM attachment is
losslessly gzip-compressed to fit GitHub's 2 GiB release-asset limit; the builder
restores the original `.img` automatically.

The repository remains private. GitHub CLI authentication must have read access
to `koaaN/Flasher_Builder`. Set `BLOAT_CACHE_DIR` in the Linux build environment to use a different
cache location. The cache can be removed when no build is running; the next
build downloads the required assets again. Cached assets can be reused offline.
This asset release uses release attachments, not Git LFS or expiring Actions
artifacts.

## Testing

**Check setup** verifies required commands and assets. **Run self-test** generates a tiny Android OTA with valid payload operations and runs the **real bundled** otaripper, lpmake and avbtool through all three builder scripts. It tests SuperHybrid, Super, RegionalHybrid CN and GLO, and the Ace 6 base/target conversion, then checks extracted bytes, sparse-image headers, archive CRCs and SHA-256. Test artifacts begin with `TEST-DO-NOT-FLASH`; they contain synthetic bytes and must never be flashed.

Command-line checks:

```sh
python3 -m unittest discover -s tests -v
QT_QPA_PLATFORM=offscreen python3 flasher-builder.py --smoke-test --test-output /tmp/flasher-qt-test
python3 flasher_builder/backend.py --check
python3 flasher_builder/backend.py --self-test --output /tmp/flasher-builder-test
```

A normal command-line build is also supported:

```sh
python3 flasher_builder/backend.py --download-bloat --device 'Oneplus 13' \
  --kind 'SuperHybrid Flasher' --region GLO --bloat-dir /path/to/bloat
python3 flasher_builder/backend.py --device 'Oneplus 13' \
  --kind 'SuperHybrid Flasher' --region GLO --bloat-dir /path/to/bloat \
  --ota /path/to/FULL-OTA.zip --output /path/to/builds
```

The original scripts now extract to explicit directories, normalize script line endings in per-job copies, stop when an asset download fails, and reject super images missing core partitions. Local builds never execute the workflow's runner-workspace cleanup step.

## Distribution builds

The UI uses PySide6 (Qt 6). The build worker uses Python's standard library. Build history, environment checks, resizable logs and package summaries are built into the desktop interface. Create a portable source ZIP with:

```sh
python3 scripts/package_app.py
```

To also create a native executable distribution, run on the target OS:

```sh
python3 -m pip install -r requirements.txt pyinstaller
python3 scripts/package_app.py --native
```

On Windows, use `py -3` instead of `python3`. Native packages include project assets and the worker sources; do not distribute the executable by itself. Windows executables must be built on Windows. The Linux executable's glibc requirements depend on its build host.
