#!/usr/bin/env python3
"""Fetch and verify only the selected build's bloat assets from a private release.

Uses the existing GitHub CLI login (or GH_TOKEN) in the build environment.
Cache entries are identified and verified by SHA-256. All destination images
are verified against their original size and SHA-256 before atomic replacement.
"""
from __future__ import annotations
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid

PROJECT_ROOT = Path(sys.executable).resolve().parent if getattr(sys, 'frozen', False) else Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))
from scripts.http_download import DownloadError, download_url, release_url, resolve_release_url

CANCEL_FILE = None


def check_cancel():
    if CANCEL_FILE is not None and CANCEL_FILE.exists():
        raise InterruptedError('Bloat download cancelled')


class AssetError(Exception):
    pass


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        while chunk := f.read(4 * 1024 ** 2):
            check_cancel()
            h.update(chunk)
    return h.hexdigest()


def matches(path, size, checksum):
    return path.is_file() and path.stat().st_size == size and sha256(path) == checksum


def load_manifest(path):
    data = json.loads(path.read_text(encoding='utf-8'))
    if data.get('schema_version') != 1:
        raise AssetError('Unsupported bloat manifest version')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', data.get('repository', '')):
        raise AssetError('Invalid release repository in bloat manifest')
    for key, asset in data['assets'].items():
        if not re.fullmatch(r'[a-f0-9]{64}', key) or key != asset.get('raw_sha256'):
            raise AssetError('Invalid raw asset checksum in manifest')
        if not re.fullmatch(r'[a-f0-9]{64}', asset.get('sha256', '')):
            raise AssetError('Invalid transport checksum in manifest')
        if asset.get('encoding') not in ('identity', 'gzip'):
            raise AssetError('Unsupported bloat asset encoding')
        for field in ('bytes', 'raw_bytes'):
            if not isinstance(asset.get(field), int) or asset[field] <= 0:
                raise AssetError('Invalid asset size or ID in manifest')
        parts = asset.get('parts')
        if parts is not None:
            if not isinstance(parts, list) or not 2 <= len(parts) <= 100:
                raise AssetError('Invalid multipart asset')
        else:
            parts = [asset]
        for part in parts:
            if not isinstance(part, dict) or not isinstance(part.get('asset_id'), int) or part['asset_id'] <= 0:
                raise AssetError('Invalid release asset ID')
            if not isinstance(part.get('bytes'), int) or not 0 < part['bytes'] < 2 * 1024**3:
                raise AssetError('Invalid release asset size')
            if not re.fullmatch(r'[a-f0-9]{64}', part.get('sha256', '')):
                raise AssetError('Invalid release asset checksum')
            if not re.fullmatch(r'[A-Za-z0-9_.-]+', part.get('asset_name', '')):
                raise AssetError('Invalid release asset name')
        if sum(part['bytes'] for part in parts) != asset['bytes']:
            raise AssetError('Multipart asset size mismatch')
    for filename, key in data['files'].items():
        parts = PurePosixPath(filename).parts
        if len(parts) < 4 or parts[0] != 'bloat' or '..' in parts or '\\' in filename or filename != PurePosixPath(filename).as_posix() or not filename.endswith('.img'):
            raise AssetError('Unsafe bloat destination in manifest: ' + filename)
        if key not in data['assets']:
            raise AssetError('Bloat path references a missing asset')
    return data


def bloat_folder(device, kind, region):
    if device == 'X9U': return 'EU_BLOAT'
    if device == 'Ace6' and kind == 'SuperHybrid Flasher' and region == 'IN': return 'OOS_BLOAT'
    return region + '_BLOAT'


def selected_paths(manifest, device, kind, region, static_odm=False):
    if not re.fullmatch(r'[A-Za-z0-9]+', device):
        raise AssetError('Invalid device ID')
    if not re.fullmatch(r'[A-Z]{2,3}', region):
        raise AssetError('Invalid region code')
    main = bloat_folder(device, kind, region)
    prefix = f'bloat/{device}/'
    extra = set()
    if region == 'CN' and device != 'X9U':
        extra.add(prefix + 'GLO_BLOAT/my_preload.img')
    if device == '13' and kind == 'SuperHybrid Flasher' and region != 'CN':
        extra |= {prefix + 'COS_FILES_HERE/' + name + '.img' for name in ('my_region', 'oplusstanvbk')}
    if device == '13T' and kind == 'Super Flasher' and region == 'IN':
        extra |= {prefix + 'FIXES/' + name + '.img' for name in ('my_region', 'oplusstanvbk', 'odm')}
    if device == 'GT7Pro' and kind == 'Super Flasher' and region == 'EU':
        extra |= {prefix + 'FIXES/' + name + '.img' for name in ('my_region', 'oplusstanvbk')}
    return [path for path in sorted(manifest['files']) if (path.startswith(prefix + main + '/') or path in extra)
            and (static_odm or not (device == 'Ace6T' and kind == 'Super Flasher' and region in ('IN', 'GLO') and path.endswith('/odm.img')))]


def download_asset(repository, asset, cache, tag='bloat-assets-v1'):
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / (asset['sha256'] + ('.img.gz' if asset['encoding'] == 'gzip' else '.img'))
    if matches(path, asset['bytes'], asset['sha256']):
        print('  Using verified cached asset: ' + asset['asset_name'], flush=True)
        return path
    largest_part = max((part['bytes'] for part in asset.get('parts', [])), default=0)
    required = asset['bytes'] + max(asset['raw_bytes'], largest_part) + 512 * 1024 ** 2
    if shutil.disk_usage(cache).free < required:
        raise AssetError('Not enough disk space for the bloat asset cache')
    partial = path.with_name(path.name + '.part-' + uuid.uuid4().hex)
    chunk_path = partial.with_name(partial.name + '.chunk')
    print('  Downloading release asset: ' + asset['asset_name'], flush=True)
    try:
        try:
            if asset.get('parts'):
                with partial.open('wb') as combined:
                    for number, part in enumerate(asset['parts'], 1):
                        check_cancel()
                        print(f'  Part {number}/{len(asset["parts"])}: {part["asset_name"]}', flush=True)
                        download_url(release_url(repository, tag, part['asset_name']), chunk_path,
                            root=PROJECT_ROOT, check=check_cancel, checksum=part['sha256'], expected_bytes=part['bytes'],
                            resolve=lambda address, part=part: resolve_release_url(address, repository, part['asset_id'], PROJECT_ROOT, check_cancel))
                        with chunk_path.open('rb') as src:
                            while chunk := src.read(4 * 1024**2):
                                check_cancel(); combined.write(chunk)
                        chunk_path.unlink()
            else:
                url = release_url(repository, tag, asset['asset_name'])
                download_url(url, partial, root=PROJECT_ROOT, check=check_cancel, checksum=asset['sha256'], expected_bytes=asset['bytes'],
                    resolve=lambda address: resolve_release_url(address, repository, asset['asset_id'], PROJECT_ROOT, check_cancel))
        except DownloadError as e:
            raise AssetError(str(e)) from e
        if not matches(partial, asset['bytes'], asset['sha256']):
            raise AssetError('Release asset size/SHA-256 mismatch: ' + asset['asset_name'])
        partial.replace(path)
        return path
    finally:
        partial.unlink(missing_ok=True)
        chunk_path.unlink(missing_ok=True)


def materialize(root, cache, manifest, device, kind, region, destination=None, source=None, local_only=False, static_odm=False):
    paths = selected_paths(manifest, device, kind, region, static_odm)
    print(f'Bloat release: {manifest["repository"]} / {manifest["tag"]} • {len(paths)} selected image path(s)', flush=True)
    objects = {}
    for relative in paths:
        check_cancel()
        asset = manifest['assets'][manifest['files'][relative]]
        bloat_root = (destination or (root / 'bloat')).resolve()
        target = (bloat_root / PurePosixPath(relative).relative_to('bloat')).resolve()
        if not target.is_relative_to(bloat_root):
            raise AssetError('Bloat destination escapes the workspace')
        if matches(target, asset['raw_bytes'], asset['raw_sha256']):
            print('  Using verified local image: ' + relative, flush=True)
            continue
        local = None
        if source:
            candidate = (source / PurePosixPath(relative).relative_to('bloat')).resolve()
            if candidate.is_relative_to(source.resolve()) and matches(candidate, asset['raw_bytes'], asset['raw_sha256']):
                local = candidate
                print('  Reusing downloaded image: ' + relative, flush=True)
        if local is None and local_only:
            raise AssetError('Required bloat image is not available locally: ' + relative + '. Complete step 2 before building.')
        key = asset['sha256']
        if local is None and key not in objects:
            objects[key] = download_asset(manifest['repository'], asset, cache, manifest['tag'])
        target.parent.mkdir(parents=True, exist_ok=True)
        partial = target.with_name(target.name + '.part-' + uuid.uuid4().hex)
        h = hashlib.sha256()
        size = 0
        try:
            opener = gzip.open if local is None and asset['encoding'] == 'gzip' else open
            with opener(local or objects[key], 'rb') as src, partial.open('wb') as dst:
                while chunk := src.read(4 * 1024 ** 2):
                    check_cancel()
                    size += len(chunk)
                    if size > asset['raw_bytes']:
                        raise AssetError('Decompressed bloat image exceeds its declared size')
                    h.update(chunk)
                    dst.write(chunk)
            if size != asset['raw_bytes'] or h.hexdigest() != asset['raw_sha256']:
                raise AssetError('Original image size/SHA-256 mismatch: ' + relative)
            partial.replace(target)
            print('  Verified and staged: ' + relative, flush=True)
        finally:
            partial.unlink(missing_ok=True)
    return paths



def inspect_downloads(manifest, destination, device, kind, region, verified=None, cancelled=None):
    """Inspect the chosen image folder without downloading or blocking the GUI.

    Successful hashes may be reused while size/mtime/ctime/inode are unchanged.
    Build staging still verifies the actual image checksum independently.
    """
    paths = selected_paths(manifest, device, kind, region)
    verified = verified if verified is not None else {}
    count = 0
    total_bytes = 0
    for relative in paths:
        if cancelled and cancelled():
            return None
        asset = manifest['assets'][manifest['files'][relative]]
        total_bytes += asset['raw_bytes']
        path = destination / PurePosixPath(relative).relative_to('bloat')
        try:
            stat = path.stat()
        except FileNotFoundError:
            continue
        fingerprint = (stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns, stat.st_ino)
        key = (str(path.resolve()), asset['raw_sha256'])
        if not path.is_file() or stat.st_size != asset['raw_bytes']:
            verified.pop(key, None)
            continue
        # Some filesystems have coarse timestamp resolution. A same-size edit
        # within the current timestamp tick must not reuse a previous hash.
        stable_age = time.time_ns() - max(stat.st_mtime_ns, stat.st_ctime_ns)
        if verified.get(key) != fingerprint or stable_age < 2_000_000_000:
            h = hashlib.sha256()
            with path.open('rb') as image:
                while chunk := image.read(4 * 1024 ** 2):
                    if cancelled and cancelled():
                        return None
                    h.update(chunk)
            if h.hexdigest() != asset['raw_sha256']:
                verified.pop(key, None)
                continue
            after = path.stat()
            if (after.st_size, after.st_mtime_ns, after.st_ctime_ns, after.st_ino) != fingerprint:
                continue
            verified[key] = fingerprint
        count += 1
    return dict(total=len(paths), downloaded=count, bytes=total_bytes,
                ready=bool(paths) and count == len(paths))


def main():
    global CANCEL_FILE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--destination', type=Path)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--local-only', action='store_true')
    parser.add_argument('--static-odm', action='store_true', help='Retain the legacy GitHub Actions ODM asset.')
    parser.add_argument('--cancel', type=Path)
    parser.add_argument('--device', required=True)
    parser.add_argument('--kind', required=True, choices=['Super Flasher', 'SuperHybrid Flasher', 'Regional Flasher', 'RegionalHybrid Flasher'])
    parser.add_argument('--region', required=True)
    args = parser.parse_args()
    CANCEL_FILE = args.cancel
    try:
        root = args.root.resolve()
        manifest = load_manifest(root / 'bloat/assets-manifest.json')
        if args.check_only:
            folder = (args.source or args.destination or (root / 'bloat')).resolve()
            status = inspect_downloads(manifest, folder, args.device, args.kind, args.region,
                                       cancelled=lambda: check_cancel() or False)
            if status['total'] and not status['ready']:
                raise AssetError(f'Local bloat files required: {status["downloaded"]}/{status["total"]} verified. Complete step 2 before building.')
            print(f'Local bloat files verified: {status["total"]}', flush=True)
            return 0
        materialize(root, args.cache.resolve(), manifest, args.device, args.kind, args.region,
                    args.destination.resolve() if args.destination else None,
                    args.source.resolve() if args.source else None, local_only=args.local_only, static_odm=args.static_odm)
        return 0
    except (AssetError, OSError, ValueError, KeyError, gzip.BadGzipFile) as e:
        print('ERROR: ' + str(e), file=sys.stderr, flush=True)
        return 1


if __name__ == '__main__':
    def interrupted(signum, frame):
        raise InterruptedError('Bloat download cancelled')
    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main())
