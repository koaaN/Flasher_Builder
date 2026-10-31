#!/usr/bin/env python3
"""Exercise the shipped worker and GUI from an extracted release archive."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    logs = []
    with tempfile.TemporaryDirectory(prefix='flasher-release-') as temporary:
        root = Path(temporary)
        if args.archive.suffix == '.zip':
            with zipfile.ZipFile(args.archive) as archive: archive.extractall(root)
        else:
            with tarfile.open(args.archive) as archive: archive.extractall(root)
        project = root / 'FlasherBuilder'
        exe = '.exe' if sys.platform == 'win32' else ''
        worker = project / ('FlasherBuilderWorker' + exe)
        app = project / ('FlasherBuilder' + exe)
        environment = os.environ | {'QT_QPA_PLATFORM': 'offscreen', 'PYTHONUTF8': '1'}
        environment.pop('PYTHONPATH', None); environment.pop('PYTHONHOME', None)
        if sys.platform == 'win32':
            # Prove the frozen app works without runner Python, Git Bash, or WSL on PATH.
            windows = Path(os.environ['SystemRoot'])
            environment['PATH'] = str(windows / 'System32') + os.pathsep + str(windows)
        for command in ([str(worker), '--check'],
                        [str(app), '--smoke-test', '--test-output', str(root / 'smoke')]):
            result = subprocess.run(command, cwd=project, env=environment,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
            logs.append(result.stdout.decode('utf-8', errors='replace'))
            if result.returncode:
                raise RuntimeError('Packaged program failed:\n' + logs[-1])
        smoke = json.loads((root / 'smoke/qt-smoke-test.json').read_text())
        if not smoke['passed'] or not smoke['frozen']: raise RuntimeError('Frozen GUI smoke test failed.')
        logs.append((root / 'smoke/qt-smoke-test.log').read_text(encoding='utf-8'))
        report = dict(platform=sys.platform, artifact=args.archive.name,
                      sha256=hashlib.sha256(args.archive.read_bytes()).hexdigest(),
                      native_worker=True, frozen_gui=True, pipeline_passed=True,
                      wsl_required=False, otaripper_version='3.5.0', app_version=smoke['app_version'])
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
        args.report.with_suffix('.log').write_text('\n'.join(logs), encoding='utf-8')
        print(json.dumps(report), flush=True)


if __name__ == '__main__': main()
