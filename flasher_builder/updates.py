"""Authenticated, read-only release checks for the private app repository."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

from . import __version__

REPOSITORY = 'koaaN/Flasher_Builder'
ASSETS = {'linux': 'FlasherBuilder-linux-x86_64.tar.gz', 'win32': 'FlasherBuilder-windows-x86_64.zip'}


class UpdateError(Exception):
    pass


def version_key(tag):
    match = re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)', str(tag))
    return tuple(map(int, match.groups())) if match else None


def select_update(releases, current=__version__, platform=None):
    platform = platform or sys.platform
    current_key = version_key(current)
    if current_key is None or platform not in ASSETS:
        raise UpdateError('This app version or platform cannot be checked for updates.')
    if not isinstance(releases, list):
        raise UpdateError('GitHub returned an invalid release list. Try checking again.')
    candidates = []
    for release in releases:
        if not isinstance(release, dict) or release.get('draft') or release.get('prerelease'):
            continue
        key = version_key(release.get('tag_name', ''))
        assets = release.get('assets', [])
        if not isinstance(assets, list):
            continue
        names = {a.get('name') for a in assets if isinstance(a, dict) and a.get('state') == 'uploaded'}
        if key and key > current_key and {ASSETS[platform], 'SHA256SUMS'} <= names:
            candidates.append((key, release['tag_name']))
    if not candidates:
        return None
    _, tag = max(candidates)
    return dict(version=tag, url=f'https://github.com/{REPOSITORY}/releases/tag/{tag}', asset=ASSETS[platform])


def check_for_updates(root, current=__version__, platform=None):
    platform = platform or sys.platform
    bundled = Path(root) / 'tools/github' / ('gh.exe' if platform == 'win32' else 'gh')
    gh = str(bundled) if bundled.is_file() else shutil.which('gh')
    if not gh:
        raise UpdateError('GitHub CLI is missing. Keep the bundled tools folder beside the app.')
    options = {'creationflags': subprocess.CREATE_NO_WINDOW} if sys.platform == 'win32' else {}
    try:
        result = subprocess.run([gh, 'api', f'repos/{REPOSITORY}/releases?per_page=100'],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, encoding='utf-8',
            errors='replace', timeout=20, **options)
    except subprocess.TimeoutExpired as e:
        raise UpdateError('Update check timed out. Check your connection and try again.') from e
    except OSError as e:
        raise UpdateError('Could not start GitHub CLI to check for updates.') from e
    if result.returncode:
        raise UpdateError('Could not check for updates. Check your connection and sign in with GitHub CLI for this private repository.')
    try:
        data = json.loads(result.stdout)
    except ValueError as e:
        raise UpdateError('GitHub returned an invalid release list. Try checking again.') from e
    return select_update(data, current, platform)
