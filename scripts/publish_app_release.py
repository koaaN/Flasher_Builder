#!/usr/bin/env python3
"""Publish both tested desktop packages together, with SHA-256 receipts."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def find_release(tag):
    # The by-tag REST endpoint excludes unpublished drafts.
    releases = json.loads(subprocess.check_output(['gh', 'api', 'repos/{owner}/{repo}/releases?per_page=100']))
    return next((release for release in releases if release['tag_name'] == tag), None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path)
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--tag', required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'v\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', args.tag):
        raise ValueError('Use a version tag such as v1.0.0')
    if not re.fullmatch(r'[a-f0-9]{40}', args.commit): raise ValueError('Expected an exact commit SHA')
    if args.prepare:
        release = find_release(args.tag)
        if release is not None:
            if not release.get('draft'): raise ValueError('This version is already published; use a new tag.')
            subprocess.run(['gh', 'api', '--method', 'PATCH', 'repos/{owner}/{repo}/releases/' + str(release['id']),
                            '-f', 'target_commitish=' + args.commit], check=True)
        else:
            subprocess.run(['gh', 'release', 'create', args.tag, '--target', args.commit, '--draft',
                            '--title', 'Flasher Builder ' + args.tag, '--notes', 'Native release builds and validation are in progress.'], check=True)
        return
    if args.directory is None: raise ValueError('Release directory missing')
    directory = args.directory.resolve()
    for platform, artifact in [('linux', 'FlasherBuilder-linux-x86_64.tar.gz'), ('windows', 'FlasherBuilder-windows-x86_64.zip')]:
        report = json.loads((directory / f'validation-{platform}.json').read_text())
        if not all(report.get(k) is True for k in ('native_worker', 'frozen_gui', 'pipeline_passed')) or report.get('wsl_required') is not False:
            raise ValueError('Native package verification failed: ' + platform)
        digest = hashlib.sha256((directory / artifact).read_bytes()).hexdigest()
        if report.get('sha256') != digest or report.get('artifact') != artifact:
            raise ValueError('Validation receipt does not match package: ' + platform)
    if not (directory / 'FlasherBuilder-source-linux-windows.zip').is_file():
        raise ValueError('Source archive missing')
    files = sorted(p for p in directory.iterdir() if p.is_file() and p.name != 'SHA256SUMS')
    checksums = directory / 'SHA256SUMS'
    checksums.write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in files), encoding='utf-8')
    files.append(checksums)
    notes = '''Native desktop release for x86-64 Linux and Windows.

- Windows runs natively, with no WSL, Bash, or separate Python installation.
- Both packages include the GUI, console worker, otaripper-lite 3.5.0, lpmake, and GitHub CLI.
- Bloat remains required step 2; OTA catalog selection, downloads, and local builds are included.
- Linux and Windows packages passed native runner tests and their extracted, frozen GUI pipeline self-tests. Validation receipts and SHA256SUMS are attached.

Extract the entire platform archive and run FlasherBuilder (Linux) or FlasherBuilder.exe (Windows). Keep the bundled folders and worker beside it. Windows 10/11 x64; Linux x86-64 with curl and Qt runtime libraries (see README).

For private bloat downloads, sign in with the bundled tools/github/gh auth login (gh.exe on Windows), or use an existing GitHub CLI login. No token is shipped in these packages. Existing verified local bloat works offline.

The source ZIP supports both systems. Third-party licenses, pinned tool checksums, and build instructions are included. Test fixtures are synthetic and must never be flashed.
'''
    release = find_release(args.tag)
    if release is None or not release.get('draft'): raise ValueError('Expected an unpublished draft release.')
    subprocess.run(['gh', 'release', 'upload', args.tag, '--clobber', str(checksums)], check=True)
    with tempfile.TemporaryDirectory() as tmp:
        payload = Path(tmp) / 'release.json'
        payload.write_text(json.dumps(dict(draft=False, make_latest='true', body=notes,
            name='Flasher Builder ' + args.tag, target_commitish=args.commit)), encoding='utf-8')
        subprocess.run(['gh', 'api', '--method', 'PATCH', 'repos/{owner}/{repo}/releases/' + str(release['id']),
                        '--input', str(payload)], check=True)


if __name__ == '__main__': main()
