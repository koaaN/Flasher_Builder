#!/usr/bin/env python3
"""Package the source launchers and optionally a native GUI executable."""
import argparse
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DIRECTORIES = ('.github', 'flasher_builder', 'build_scripts', 'scripts', 'build_tools_assets',
               'Platform-Tools', 'bloat', 'flasher_scripts', 'lpmake', 'otaripper', 'tests', 'tools')
FILES = ('requirements.txt', 'README.md', 'THIRD-PARTY-NOTICES.md', 'flasher-builder.py', 'flasher-worker.py', 'start-linux.sh', 'start-windows.bat')


def copy_project(destination):
    destination.mkdir(parents=True)
    for name in DIRECTORIES:
        if name == 'bloat' and (ROOT / 'bloat/assets-manifest.json').is_file():
            (destination / 'bloat').mkdir()
            shutil.copy2(ROOT / 'bloat/assets-manifest.json', destination / 'bloat/assets-manifest.json')
        else:
            shutil.copytree(ROOT / name, destination / name,
                            ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    for name in FILES:
        shutil.copy2(ROOT / name, destination / name)


def make_zip(source, destination):
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED, compresslevel=3) as z:
        for path in sorted(source.rglob('*')):
            if path.is_file():
                z.write(path, path.relative_to(source.parent))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', action='store_true')
    args = parser.parse_args()
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='flasher-package-') as temporary:
        temp = Path(temporary)
        project = temp / 'FlasherBuilder'
        copy_project(project)
        source_zip = dist / 'FlasherBuilder-source-linux-windows.zip'
        make_zip(project, source_zip)
        print(f'Created {source_zip}', flush=True)
        if args.native:
            suffix = '.exe' if sys.platform == 'win32' else ''
            for name in ('otaripper', 'lpmake'):
                other = project / name / (name if suffix else name + '.exe')
                other.unlink(missing_ok=True)
            (project / 'tools/github' / ('gh' if suffix else 'gh.exe')).unlink(missing_ok=True)
            for name, entry, windowed in [('FlasherBuilderWorker', 'flasher-worker.py', False), ('FlasherBuilder', 'flasher-builder.py', True)]:
                subprocess.run([sys.executable, '-m', 'PyInstaller', '--noconfirm', '--clean', '--onefile',
                            '--windowed' if windowed else '--console', '--exclude-module', 'PyQt6', '--exclude-module', 'PyQt5', '--exclude-module', 'PySide2', '--name', name, '--distpath', str(project),
                            '--workpath', str(temp / 'work'), '--specpath', str(temp),
                            str(ROOT / entry)], cwd=ROOT, check=True)
            if sys.platform == 'win32':
                destination = dist / 'FlasherBuilder-windows-x86_64.zip'
                make_zip(project, destination)
            else:
                destination = dist / f'FlasherBuilder-linux-{platform.machine()}.tar.gz'
                with tarfile.open(destination, 'w:gz', compresslevel=3) as archive:
                    archive.add(project, arcname='FlasherBuilder')
            print(f'Created {destination}', flush=True)


if __name__ == '__main__':
    main()
