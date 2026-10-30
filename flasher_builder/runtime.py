"""Launch the same build worker locally on Linux or through WSL on Windows."""
import sys
import subprocess
from pathlib import Path
from .backend import ROOT, BuildError, clean_source, is_url


class Runtime:
    def __init__(self, distro=''):
        self.windows = sys.platform == 'win32'
        self.prefix = ['wsl.exe'] + (['--distribution', distro] if distro else []) + ['--exec'] if self.windows else []

    def path(self, value):
        if not self.windows:
            return str(Path(value).expanduser().resolve())
        try:
            result = subprocess.run(self.prefix + ['wslpath', '-a', '-u', str(Path(value).resolve())],
                                    capture_output=True, text=True, encoding='utf-8', errors='replace',
                                    timeout=30, creationflags=subprocess.CREATE_NO_WINDOW)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise BuildError('WSL is unavailable. Install Ubuntu with: wsl --install -d Ubuntu') from e
        if result.returncode:
            raise BuildError('WSL path conversion failed. Start your WSL distribution and finish its setup.\n' + result.stderr.strip())
        return result.stdout.strip()

    def command(self, values, action, cancel):
        root = self.path(ROOT)
        cmd = self.prefix + ['python3', '-u', root + '/flasher_builder/backend.py', '--repo', root]
        if action == 'check':
            return cmd + ['--check']
        if action == 'bloat':
            return cmd + ['--download-bloat', '--bloat-dir', self.path(values['bloat_dir']),
                          '--cancel', self.path(cancel), '--device', values['device'],
                          '--kind', values['kind'], '--region', values['region']]
        cmd += ['--output', self.path(values['output']), '--cancel', self.path(cancel)]
        if action == 'test':
            return cmd + ['--self-test']
        if values.get('bloat_dir'):
            cmd += ['--bloat-dir', self.path(values['bloat_dir'])]
        for key in ('device', 'kind', 'region'):
            cmd += ['--' + key, values[key]]
        for key in ('ota', 'base'):
            source = clean_source(values[key])
            if source:
                cmd += ['--' + key, source if is_url(source) else self.path(source)]
        return cmd
