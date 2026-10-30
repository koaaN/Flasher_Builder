#!/usr/bin/env python3
"""Download extensionless bloat link stubs sequentially and report Git eligibility.

Identical URLs share one download. Original stubs and image files are untouched.
Rerun to reuse completed downloads and retry failed or interrupted transfers.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import time
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parent.parent
MIB = 1024 ** 2
GIB = 1024 ** 3
LIMIT = 100 * MIB
RESERVE = 2 * GIB


def links(root):
    groups = {}
    for path in sorted((root / 'bloat').rglob('*')):
        if path.is_file() and not path.suffix:
            url = path.read_text(encoding='utf-8').strip().strip('\"\'').replace('\\u0026', '&')
            if urlsplit(url).scheme in ('https', 'http'):
                groups.setdefault(url, []).append(path.relative_to(root).as_posix())
    return groups


def image_format(path, content_type=''):
    with path.open('rb') as f:
        head = f.read(4096)
    sample = head.lstrip().lower()
    if 'text/' in content_type.lower() or any(sample.startswith(p) for p in (b'<!doctype', b'<html', b'<?xml', b'{"error', b'{"message')):
        raise ValueError('Server returned a text/error document instead of a binary image')
    if len(head) < 512:
        raise ValueError('Response is too small to be a firmware image')
    return 'android-sparse' if head[:4] == b'\x3a\xff\x26\xed' else 'raw-binary'


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as f:
        while chunk := f.read(4 * MIB):
            digest.update(chunk)
    return digest.hexdigest()


def head_size(url, header_file):
    result = subprocess.run(['curl', '--silent', '--show-error', '--location', '--head', '--connect-timeout', '20',
                             '--max-time', '45', '--proto', '=https,http', '--proto-redir', '=https,http',
                             '--dump-header', str(header_file), '--output', '/dev/null', url], capture_output=True, text=True)
    headers = {}
    if header_file.exists():
        for line in header_file.read_text(errors='replace').splitlines():
            if line.startswith('HTTP/'):
                headers = {'http_status': line.split()[1]}
            elif ':' in line:
                key, value = line.split(':', 1)
                headers[key.lower()] = value.strip()
    length = headers.get('content-length', '')
    return int(length) if length.isdecimal() and headers.get('http_status') == '200' else None


def save_reports(output, records, total, source_count):
    summary = dict(unique_urls=total, source_link_files=source_count,
                   processed=len(records), downloaded=sum(r['status'] == 'downloaded' for r in records),
                   unique_direct_git=sum(r.get('direct_git', False) for r in records),
                   unique_over_limit=sum(r['status'] == 'downloaded' and not r['direct_git'] for r in records),
                   failed=sum(r['status'] == 'failed' for r in records),
                   skipped_disk_space=sum(r['status'] == 'skipped_disk_space' for r in records),
                   downloaded_bytes=sum(r.get('bytes', 0) for r in records if r['status'] == 'downloaded'),
                   expanded_folder_bytes=sum(r.get('bytes', 0) * len(r['source_files']) for r in records if r['status'] == 'downloaded'),
                   direct_git_folder_bytes=sum(r.get('bytes', 0) * len(r['source_files']) for r in records if r.get('direct_git')))
    report = dict(summary=summary, files=records)
    temporary = output / 'report.json.tmp'
    temporary.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    temporary.replace(output / 'report.json')
    with (output / 'files.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['source_stub', 'target_image', 'status', 'bytes', 'MiB', 'direct_git_100_MiB', 'sha256', 'download', 'error'])
        for r in records:
            for stub in r['source_files']:
                writer.writerow([stub, stub + '.img', r['status'], r.get('bytes', ''),
                                 round(r.get('bytes', 0) / MIB, 3) if 'bytes' in r else '',
                                 r.get('direct_git', ''), r.get('sha256', ''), r.get('download', ''), r.get('error', '')])
    text = [f"Processed {len(records)}/{total} unique URLs covering {source_count} link files.",
            f"Downloaded: {summary['downloaded']}; direct Git: {summary['unique_direct_git']}; over 100 MiB: {summary['unique_over_limit']}; failed: {summary['failed']}; disk skips: {summary['skipped_disk_space']}.",
            f"Unique download storage: {summary['downloaded_bytes'] / GIB:.3f} GiB.",
            f"Full expanded bloat replacements (including duplicate paths): {summary['expanded_folder_bytes'] / GIB:.3f} GiB.",
            '', 'STATUS       SIZE MiB  DIRECT GIT  SOURCE FILE(S)']
    for r in records:
        text.append(f"{r['status']:12} {r.get('bytes', 0) / MIB:8.2f}  {str(r.get('direct_git', '')):10}  " + ', '.join(r['source_files']))
        if r.get('error'):
            text.append('  ' + r['error'])
    (output / 'report.txt').write_text('\n'.join(text) + '\n', encoding='utf-8')
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, default=ROOT / 'bloat-audit')
    args = parser.parse_args()
    output = args.output.resolve()
    for sub in ('downloads', 'headers', 'logs'):
        (output / sub).mkdir(parents=True, exist_ok=True)
    groups = links(args.root.resolve())
    count = sum(map(len, groups.values()))
    records = []
    old = {}
    if (output / 'report.json').exists():
        old = {r['url']: r for r in json.loads((output / 'report.json').read_text())['files']}
    print(f'{count} link stubs; {len(groups)} unique URLs. Download concurrency: 1.', flush=True)
    for number, (url, stubs) in enumerate(groups.items(), 1):
        remote = parse_qs(urlsplit(url).query).get('file', [urlsplit(url).path])[0]
        filename = re.sub(r'[^\w.()-]', '_', PurePosixPath(remote).name) or 'image.img'
        key = hashlib.sha256(url.encode()).hexdigest()[:16]
        final = output / 'downloads' / (key + '-' + filename)
        partial = final.with_suffix(final.suffix + '.part')
        record = dict(url=url, source_files=stubs, remote_file=remote,
                      download=str(final.relative_to(output)), status='failed')
        print(f'[{number:02d}/{len(groups)}] {remote} ({len(stubs)} local path(s))', flush=True)
        try:
            previous = old.get(url, {})
            if final.is_file() and previous.get('sha256'):
                if sha256(final) == previous['sha256']:
                    record.update(status='downloaded', bytes=final.stat().st_size,
                                  direct_git=final.stat().st_size <= LIMIT, sha256=previous['sha256'],
                                  format=image_format(final), reused=True)
                    records.append(record)
                    save_reports(output, records, len(groups), count)
                    print(f'  Reused verified file: {record["bytes"] / MIB:.2f} MiB', flush=True)
                    continue
            expected = head_size(url, output / 'headers' / (key + '.head'))
            free = shutil.disk_usage(output).free
            if free < RESERVE or (expected and expected > free - RESERVE):
                record.update(status='skipped_disk_space', error=f'Need {expected or "unknown"} bytes; {free} free, reserving 2 GiB')
                if expected is not None:
                    record['head_bytes'] = expected
                print('  Skipped: insufficient free disk space.', flush=True)
            else:
                if expected is not None:
                    print(f'  Server reports {expected / MIB:.2f} MiB.', flush=True)
                command = ['curl', '--silent', '--show-error', '--location', '--fail', '--retry', '2', '--retry-delay', '3',
                           '--connect-timeout', '20', '--max-time', '1800', '--speed-limit', '65536', '--speed-time', '120',
                           '--proto', '=https,http', '--proto-redir', '=https,http', '--max-filesize', str(free - RESERVE),
                           '--dump-header', str(output / 'headers' / (key + '.get')),
                           '--output', str(partial), '--write-out', '%{http_code}\n%{content_type}\n', url]
                if partial.exists() and partial.stat().st_size:
                    command[1:1] = ['--continue-at', '-']
                with (output / 'logs' / (key + '.log')).open('w') as errorlog:
                    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=errorlog, text=True)
                    started = time.monotonic()
                    announced = started
                    try:
                        while process.poll() is None:
                            now = time.monotonic()
                            if shutil.disk_usage(output).free < RESERVE:
                                process.terminate()
                                raise OSError('Stopped download to preserve 2 GiB free disk space')
                            if now - announced >= 20:
                                size = partial.stat().st_size if partial.exists() else 0
                                print(f'  {size / MIB:.1f} MiB downloaded, {int(now - started)} s elapsed…', flush=True)
                                announced = now
                            time.sleep(.25)
                        metadata = process.communicate()[0].splitlines()
                    finally:
                        if process.poll() is None:
                            process.terminate()
                            try:
                                process.wait(timeout=5)
                            except subprocess.TimeoutExpired:
                                process.kill(); process.wait()
                    if process.returncode:
                        error = (output / 'logs' / (key + '.log')).read_text().strip()
                        raise OSError(f'curl exit {process.returncode}: {error}')
                content_type = metadata[1] if len(metadata) > 1 else ''
                fmt = image_format(partial, content_type)
                size = partial.stat().st_size
                if expected is not None and size != expected:
                    raise ValueError(f'Size mismatch: received {size}, server reported {expected}')
                digest = sha256(partial)
                partial.replace(final)
                record.update(status='downloaded', bytes=size, sha256=digest, format=fmt, direct_git=size <= LIMIT)
                print(f'  OK: {size / MIB:.2f} MiB — ' + ('fits normal Git' if record['direct_git'] else 'OVER normal Git 100 MiB limit'), flush=True)
        except (OSError, ValueError) as e:
            record['error'] = str(e)
            print('  FAILED: ' + str(e), flush=True)
        records.append(record)
        save_reports(output, records, len(groups), count)
    print(json.dumps(save_reports(output, records, len(groups), count), indent=2), flush=True)


if __name__ == '__main__':
    main()
