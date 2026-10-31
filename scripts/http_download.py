"""Cancellable HTTP downloads: bundled aria2 first, curl fallback."""
from pathlib import Path
import hashlib
import os
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit, urlunsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

ROOT = Path(sys.executable).resolve().parent if getattr(sys, 'frozen', False) else Path(__file__).resolve().parent.parent


class DownloadError(Exception):
    pass


def executable(name, root=ROOT):
    suffix = '.exe' if sys.platform == 'win32' else ''
    directory = 'aria2' if name == 'aria2c' else 'github'
    bundled = Path(root) / 'tools' / directory / (name + suffix)
    return str(bundled) if name in ('aria2c', 'gh') and bundled.is_file() else shutil.which(name)


def redact_output(text):
    def hide(match):
        try:
            value = urlsplit(match.group())
            host = value.hostname or ''
            return urlunsplit((value.scheme, host, value.path, '[redacted]' if value.query else '', ''))
        except ValueError:
            return '[download URL]'
    return re.sub(r'https?://[^\s<>"\]]+', hide, text)


def checked_call(function, check):
    """Cancel promptly even while a bounded metadata HTTP request is pending."""
    result = queue.Queue()
    def task():
        try: result.put((True, function()))
        except Exception as e: result.put((False, e))
    check(); threading.Thread(target=task, daemon=True).start()
    while True:
        check()
        try: ok, value = result.get(timeout=.15)
        except queue.Empty: continue
        check()
        if ok: return value
        raise value


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def release_url(repository, tag, name):
    return f'https://github.com/{repository}/releases/download/{quote(tag, safe="")}/{quote(name, safe="")}'


def resolve_release_url(url, repository, asset_id, root=ROOT, check=lambda: None):
    """Public downloads need no login. Private forks use GH only to obtain a URL.

    The GitHub token is sent only to api.github.com; aria2/curl never receive it.
    """
    def resolve():
        opener = build_opener(NoRedirect())
        try:
            with opener.open(Request(url, headers={'User-Agent': 'FlasherBuilder'}), timeout=20):
                return url
        except HTTPError as error:
            code = error.code; error.close()
            if code != 404: return url  # aria2/curl handle redirects and retries.
        except (URLError, OSError):
            return url
        gh = executable('gh', root)
        if not gh: return url
        options = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
        try:
            token = subprocess.run([gh, 'auth', 'token', '--hostname', 'github.com'],
                stdin=subprocess.DEVNULL, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=10,
                env=os.environ | {'GH_PROMPT_DISABLED': '1'}, **options)
        except (OSError, subprocess.TimeoutExpired): return url
        if token.returncode or not token.stdout.strip(): return url
        credential = token.stdout.strip()
        if any(ord(c) < 33 or ord(c) > 126 for c in credential): return url
        request = Request(f'https://api.github.com/repos/{repository}/releases/assets/{asset_id}',
            headers={'User-Agent': 'FlasherBuilder', 'Accept': 'application/octet-stream',
                     'Authorization': 'Bearer ' + credential})
        try:
            with opener.open(request, timeout=20):
                raise DownloadError('The release service did not provide a download redirect.')
        except HTTPError as error:
            location = error.headers.get('Location', '')
            code = error.code; error.close()
            if code in (301, 302, 303, 307, 308) and urlsplit(location).scheme == 'https':
                return location
            raise DownloadError('Release asset unavailable. Check repository access and try again.') from None
        except (URLError, OSError):
            raise DownloadError('Could not resolve the release download. Check your connection.') from None
    return checked_call(resolve, check)


def run_download_command(command, check):
    check()
    options = {'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {'start_new_session': True}
    try:
        proc = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', bufsize=1, **options)
    except OSError as e:
        raise DownloadError('Could not start ' + Path(command[0]).name) from e
    lines = queue.Queue()
    def reader():
        try:
            for line in proc.stdout: lines.put(line)
        finally: lines.put(None)
    thread = threading.Thread(target=reader, daemon=True); thread.start()
    try:
        ended = False
        while not ended or proc.poll() is None:
            check()
            try:
                line = lines.get(timeout=.15)
                if line is None: ended = True
                else: print(redact_output(line), end='', flush=True)
            except queue.Empty: pass
        check()
        if proc.wait():
            raise DownloadError(f'{Path(command[0]).name} failed (exit {proc.returncode}).')
    finally:
        if proc.poll() is None:
            if os.name == 'nt': proc.terminate()
            else: os.killpg(proc.pid, signal.SIGTERM)
            try: proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                if os.name == 'nt': proc.kill()
                else: os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
        proc.stdout.close(); thread.join(timeout=1)


def download_url(url, destination, *, root=ROOT, headers=(), check=lambda: None, resolve=None, checksum=None, expected_bytes=None, verify=None):
    """Write a fresh temporary file; cancellation never triggers the fallback."""
    destination = Path(destination).resolve()
    if destination.exists(): raise DownloadError('Download temporary file already exists.')
    if urlsplit(url).scheme not in ('https', 'http') or any(c in url for c in '\r\n'):
        raise DownloadError('Only HTTP and HTTPS downloads are supported.')
    if any('\r' in h or '\n' in h for h in headers): raise DownloadError('Invalid download header.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    aria = executable('aria2c', root); curl = executable('curl', root)
    engines = [('aria2c', aria), ('curl', curl)]
    errors = []
    complete = False
    try:
        for name, binary in engines:
            check()
            if not binary: continue
            try:
                address = resolve(url) if resolve else url
                if urlsplit(address).scheme not in ('http', 'https') or any(c in address for c in '\r\n'):
                    raise DownloadError('The download service returned an invalid URL.')
                if name == 'aria2c':
                    print('Downloading with aria2c · up to 8 connections', flush=True)
                    command = [binary, '--no-conf=true', '-x8', '-s8', '-j1', '--min-split-size=1M',
                        '--file-allocation=none', '--auto-file-renaming=false', '--allow-overwrite=true',
                        '--content-disposition=false', '--no-netrc=true', '--follow-torrent=false',
                        '--follow-metalink=false', '--max-tries=3', '--retry-wait=2', '--connect-timeout=20',
                        '--timeout=120', '--lowest-speed-limit=1024', '--summary-interval=2',
                        '--console-log-level=warn', '--download-result=hide', '--enable-color=false',
                        '--dir=' + str(destination.parent), '--out=' + destination.name]
                    for header in headers: command += ['--header=' + header]
                else:
                    print('Downloading with curl' + (' · aria2c fallback' if errors else ''), flush=True)
                    command = [binary, '--disable', '--location', '--fail', '--retry', '3', '--retry-delay', '2',
                        '--connect-timeout', '20', '--speed-limit', '1024', '--speed-time', '120',
                        '--proto', '=https,http', '--proto-redir', '=https,http', '--output', str(destination)]
                    for header in headers: command += ['--header', header]
                run_download_command(command + [address], check)
                if not destination.is_file(): raise DownloadError('The downloader did not create its output file.')
                if expected_bytes is not None and destination.stat().st_size != expected_bytes:
                    raise DownloadError('Downloaded file size mismatch.')
                if checksum:
                    digest = hashlib.sha256()
                    with destination.open('rb') as source:
                        while block := source.read(4 * 1024**2):
                            check(); digest.update(block)
                    if digest.hexdigest() != checksum:
                        raise DownloadError('Downloaded file SHA-256 mismatch.')
                if verify and not verify(destination):
                    raise DownloadError('Downloaded content failed validation.')
                complete = True
                return name
            except DownloadError as error:
                errors.append(str(error)); destination.unlink(missing_ok=True)
                Path(str(destination) + '.aria2').unlink(missing_ok=True)
                if name == 'aria2c': print('aria2c could not finish; trying curl…', flush=True)
        raise DownloadError('Download failed. ' + (' '.join(errors) if errors else 'Neither aria2c nor curl is available.'))
    finally:
        Path(str(destination) + '.aria2').unlink(missing_ok=True)
        if not complete: destination.unlink(missing_ok=True)
