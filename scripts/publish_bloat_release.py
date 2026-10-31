#!/usr/bin/env python3
"""Publish audited bloat assets sequentially to one GitHub release.

Uploads are resumable at asset granularity. Every object is checked against the
SHA-256 digest reported by GitHub before oversized temporary copies are removed.
Original files in bloat/ are never removed by this script.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
GIB = 1024 ** 3
MIB = 1024 ** 2


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        while chunk := f.read(4 * MIB):
            h.update(chunk)
    return h.hexdigest()


def gh(*args):
    p = subprocess.run(['gh', *map(str, args)], capture_output=True, text=True,
                       env=os.environ | {'GH_PROMPT_DISABLED': '1'})
    if p.returncode:
        raise RuntimeError(p.stderr.strip() or p.stdout.strip())
    return p.stdout


def api(endpoint):
    return json.loads(gh('api', endpoint))


def save(path, value):
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    tmp.replace(path)


def make_plan(root, audit):
    report = json.loads((audit / 'report.json').read_text())
    compressed = json.loads((audit / 'oversized-compression.json').read_text())
    objects, paths = {}, {}
    for path in sorted((root / 'bloat').rglob('*.img')):
        sha = digest(path)
        key = path.relative_to(root).as_posix()
        objects.setdefault(sha, dict(raw_sha256=sha, raw_bytes=path.stat().st_size,
                                    paths=[], candidates=[], urls=[]))
        objects[sha]['paths'].append(key)
        objects[sha]['candidates'].append(str(path))
        paths[key] = sha
    for r in report['files']:
        sha = r['sha256']
        objects.setdefault(sha, dict(raw_sha256=sha, raw_bytes=r['bytes'], paths=[], candidates=[], urls=[]))
        item = objects[sha]
        item['candidates'].append(str(audit / r['download']))
        item['urls'].append(r['url'])
        for stub in r['source_files']:
            target = stub + '.img'
            if target in paths and paths[target] != sha:
                raise RuntimeError('Conflicting image contents for ' + target)
            if target not in item['paths']:
                item['paths'].append(target)
            paths[target] = sha
    for sha, item in objects.items():
        item['encoding'] = 'identity'
        item['sha256'], item['bytes'] = sha, item['raw_bytes']
        if sha == compressed['source_sha256']:
            item.update(encoding='gzip', sha256=compressed['compressed_sha256'], bytes=compressed['compressed_bytes'])
            item['candidates'] = [str(audit / compressed['compressed_download'])]
        if item['bytes'] >= 2 * GIB:
            raise RuntimeError('Asset exceeds the 2 GiB release limit: ' + item['paths'][0])
        canonical = min(item['paths'])
        stem = re.sub(r'[^A-Za-z0-9_.-]', '-', canonical.removeprefix('bloat/').removesuffix('.img'))
        item['asset_name'] = f'bloat-{stem}-{sha[:12]}.img' + ('.gz' if item['encoding'] == 'gzip' else '')
    return dict(objects=objects, paths=paths)


def metadata(repo, release_id):
    output = gh('api', f'repos/{repo}/releases/{release_id}/assets?per_page=100', '--paginate')
    decoder = json.JSONDecoder()
    result = {}
    while output.strip():
        page, end = decoder.raw_decode(output.lstrip())
        result.update({item['name']: item for item in page})
        output = output.lstrip()[end:]
    return result


def verify_remote(asset, size, sha):
    return (asset.get('state') == 'uploaded' and asset.get('size') == size
            and asset.get('digest') == 'sha256:' + sha)


def upload(repo, tag, path, logs):
    for attempt in range(1, 4):
        log = logs / (path.name + '.upload.log')
        with log.open('w') as f:
            process = subprocess.Popen(['gh', 'release', 'upload', tag, str(path), '--repo', repo],
                                       stdout=f, stderr=subprocess.STDOUT,
                                       env=os.environ | {'GH_PROMPT_DISABLED': '1'})
            start = last = time.monotonic()
            while process.poll() is None:
                if time.monotonic() - last >= 20:
                    print(f'  Upload in progress: {int(time.monotonic() - start)} s elapsed', flush=True)
                    last = time.monotonic()
                time.sleep(.5)
            if not process.returncode:
                return
        error = log.read_text().strip()
        if attempt == 3 or 'already exists' in error:
            raise RuntimeError(error)
        print(f'  Upload attempt {attempt} failed; retrying: {error}', flush=True)
        time.sleep(3)


def obtain(item, audit):
    for candidate in item['candidates']:
        path = Path(candidate)
        if path.is_file() and path.stat().st_size == item['bytes'] and digest(path) == item['sha256']:
            return path
    if item['encoding'] != 'identity' or not item['urls']:
        raise RuntimeError('No verified local source available: ' + item['asset_name'])
    target = audit / 'downloads' / ('restored-' + item['raw_sha256'][:16] + '.img')
    partial = target.with_suffix('.img.part')
    if target.is_file() and target.stat().st_size == item['bytes'] and digest(target) == item['sha256']:
        item['candidates'].append(str(target))
        return target
    if shutil.disk_usage(audit).free < item['raw_bytes'] + GIB:
        raise RuntimeError('Insufficient disk space to restore ' + item['asset_name'])
    print('  Restoring previously measured source download…', flush=True)
    command = ['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '3',
               '--connect-timeout', '20', '--speed-time', '120', '--speed-limit', '65536',
               '--proto', '=https,http', '--proto-redir', '=https,http', '--output', str(partial), item['urls'][0]]
    subprocess.run(command, check=True)
    if partial.stat().st_size != item['bytes'] or digest(partial) != item['sha256']:
        raise RuntimeError('Restored source no longer matches its audited SHA-256: ' + item['asset_name'])
    partial.replace(target)
    item['candidates'].append(str(target))
    return target


def clear_temporary(item, audit, upload_file):
    upload_file.unlink(missing_ok=True)
    if item['raw_bytes'] <= 100 * MIB:
        return
    report = json.loads((audit / 'report.json').read_text())
    candidates = list(item['candidates'])
    for r in report['files']:
        if r['sha256'] == item['raw_sha256']:
            candidates.append(str(audit / r['download']))
    for value in set(candidates):
        path = Path(value).resolve()
        if path.is_relative_to((audit / 'downloads').resolve()) and path.is_file():
            path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default='koaaN/Flasher_Builder')
    parser.add_argument('--tag', default='bloat-assets-v1')
    args = parser.parse_args()
    root = ROOT.resolve()
    audit = root / 'bloat-audit'
    state_path = audit / 'release-upload-state.json'
    stage = audit / 'release-upload'
    stage.mkdir(exist_ok=True)
    logs = audit / 'logs'
    repository = api('repos/' + args.repo)
    if repository['full_name'].lower() != args.repo.lower():
        raise RuntimeError('Repository identity mismatch')
    plan_path = audit / 'release-plan.json'
    if plan_path.exists():
        plan = json.loads(plan_path.read_text())
    else:
        plan = make_plan(root, audit)
        save(plan_path, plan)
    release = json.loads(gh('release', 'view', args.tag, '--repo', args.repo, '--json', 'apiUrl,isDraft,tagName'))
    release_id = int(release['apiUrl'].rstrip('/').rsplit('/', 1)[1])
    state = json.loads(state_path.read_text()) if state_path.exists() else {'release_id': release_id, 'uploaded': {}}
    if state['release_id'] != release_id:
        raise RuntimeError('Release ID changed since the upload started')
    remote = metadata(args.repo, release_id)
    objects = list(plan['objects'].values())
    # Free the largest verified temporary copies first, then restore missing ones.
    objects.sort(key=lambda item: (not any(Path(p).is_file() for p in item['candidates']), -item['raw_bytes']))
    for number, item in enumerate(objects, 1):
        name = item['asset_name']
        print(f'[{number:02d}/{len(objects)}] {name} • {item["bytes"] / MIB:.2f} MiB', flush=True)
        if name not in remote:
            source = obtain(item, audit)
            staged = stage / name
            if not staged.exists():
                os.link(source, staged)
            upload(args.repo, args.tag, staged, logs)
            remote = metadata(args.repo, release_id)
        asset = remote.get(name)
        if not asset or not verify_remote(asset, item['bytes'], item['sha256']):
            raise RuntimeError('GitHub size/SHA-256 verification failed for ' + name)
        state['uploaded'][item['raw_sha256']] = dict(asset_id=asset['id'], asset_name=name,
            bytes=item['bytes'], sha256=item['sha256'], raw_bytes=item['raw_bytes'],
            raw_sha256=item['raw_sha256'], encoding=item['encoding'])
        save(state_path, state)
        print(f'  Verified GitHub SHA-256; {len(state["uploaded"])}/{len(objects)} assets complete.', flush=True)
        clear_temporary(item, audit, stage / name)
    manifest = dict(schema_version=1, repository=args.repo, tag=args.tag, release_id=release_id,
                    assets=state['uploaded'], files=plan['paths'])
    manifest_path = audit / 'assets-manifest.json'
    save(manifest_path, manifest)
    checksums = [f'{v["sha256"]}  {v["asset_name"]}' for v in state['uploaded'].values()]
    checksums.append(digest(manifest_path) + '  assets-manifest.json')
    checksum_path = audit / 'SHA256SUMS'
    checksum_path.write_text('\n'.join(sorted(checksums)) + '\n')
    for path in (manifest_path, checksum_path):
        if path.name not in remote:
            upload(args.repo, args.tag, path, logs)
            remote = metadata(args.repo, release_id)
        if not verify_remote(remote[path.name], path.stat().st_size, digest(path)):
            raise RuntimeError('Manifest/checksum verification failed')
    state['complete'] = True
    state['asset_count'] = len(remote)
    state['mapped_paths'] = len(manifest['files'])
    save(state_path, state)
    print(f'COMPLETE: {len(objects)} image assets, {len(manifest["files"])} image paths; manifest and checksums verified.', flush=True)


if __name__ == '__main__':
    main()
