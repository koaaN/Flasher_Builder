"""Public release checks, with optional GitHub authentication for private forks."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

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
    try:
        request = Request(f'https://api.github.com/repos/{REPOSITORY}/releases?per_page=100',
            headers={'User-Agent': 'FlasherBuilder', 'Accept': 'application/vnd.github+json'})
        with urlopen(request, timeout=20) as response:
            raw = response.read(8 * 1024**2 + 1)
        if len(raw) > 8 * 1024**2:
            raise UpdateError('GitHub returned an oversized release list.')
    except HTTPError as error:
        if error.code not in (401, 403, 404):
            raise UpdateError('Update check unavailable. Try checking again later.') from None
        # Private forks and authenticated rate limits can use an existing login.
        bundled = Path(root) / 'tools/github' / ('gh.exe' if platform == 'win32' else 'gh')
        gh = str(bundled) if bundled.is_file() else shutil.which('gh')
        if not gh:
            raise UpdateError('Update check unavailable. Check your connection or try again later.') from None
        options = {'creationflags': subprocess.CREATE_NO_WINDOW} if sys.platform == 'win32' else {}
        try:
            result = subprocess.run([gh, 'api', f'repos/{REPOSITORY}/releases?per_page=100'],
                stdin=subprocess.DEVNULL, capture_output=True, text=True, encoding='utf-8',
                errors='replace', timeout=20, **options)
        except subprocess.TimeoutExpired as e:
            raise UpdateError('Update check timed out. Check your connection and try again.') from e
        except OSError as e:
            raise UpdateError('Could not check for updates. Try again later.') from e
        if result.returncode:
            raise UpdateError('Could not check for updates. Check your connection or try again later.')
        raw = result.stdout
    except (URLError, OSError, TimeoutError) as error:
        raise UpdateError('Could not check for updates. Check your connection and try again.') from error
    try:
        data = json.loads(raw)
    except (ValueError, UnicodeError) as error:
        raise UpdateError('GitHub returned an invalid release list. Try checking again.') from error
    return select_update(data, current, platform)
