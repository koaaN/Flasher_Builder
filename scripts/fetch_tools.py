#!/usr/bin/env python3
"""Fetch pinned native dependencies; verify archive and executable SHA-256."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
from urllib.request import urlopen, Request
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def fetch(platforms):
    dependencies = json.loads((ROOT / 'tools/dependencies.json').read_text())
    for entry in dependencies:
        if entry['platform'] not in platforms and entry['platform'] != 'all': continue
        path = ROOT / entry['path']
        if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']: continue
        print('Fetching verified ' + entry['path'], flush=True)
        with urlopen(Request(entry['url'], headers={'User-Agent': 'FlasherBuilder-release'}), timeout=120) as response:
            data = response.read(100 * 1024**2 + 1)
        if hashlib.sha256(data).hexdigest() != entry['archive_sha256']:
            raise ValueError('Download checksum mismatch: ' + entry['path'])
        if entry.get('member'):
            if entry['url'].endswith('.zip'):
                with zipfile.ZipFile(io.BytesIO(data)) as archive: binary = archive.read(entry['member'])
            else:
                with tarfile.open(fileobj=io.BytesIO(data)) as archive: binary = archive.extractfile(entry['member']).read()
        else: binary = data
        if hashlib.sha256(binary).hexdigest() != entry['sha256']:
            raise ValueError('Executable checksum mismatch: ' + entry['path'])
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(path.name + '.part')
        temporary.write_bytes(binary); temporary.chmod(0o755); temporary.replace(path)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['linux', 'windows', 'all'], default='all')
    args = parser.parse_args()
    fetch(['linux', 'windows'] if args.platform == 'all' else [args.platform])
