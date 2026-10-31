"""Exercise real aria2/curl, HTTP ranges, fallback, cancellation and redirects."""
import contextlib
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from scripts import http_download as download

DATA = bytes(range(256)) * (32 * 1024**2 // 256)
SHA = hashlib.sha256(DATA).hexdigest()


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.dest = Path(self.tmp.name)/'folder with spaces'/'file.part'
        self.ranges = []; self.headers = []; self.agents = []; self.active = 0; self.maximum = 0; self.lock = threading.Lock()
        test = self
        class Handler(BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'
            def log_message(self, *args): pass
            def do_GET(self):
                if self.path.startswith('/missing'):
                    self.send_error(404); return
                start, end = 0, len(DATA)-1
                value = None if getattr(self.server,'ignore_ranges',False) else self.headers.get('Range')
                if value:
                    a,b=value.removeprefix('bytes=').split('-');start=int(a);end=int(b) if b else end
                with test.lock:
                    test.active += 1; test.maximum = max(test.maximum,test.active)
                    test.ranges.append(value);test.headers.append(self.headers.get('X-Test'))
                    test.agents.append(self.headers.get_all('User-Agent'))
                try:
                    self.send_response(206 if value else 200)
                    self.send_header('Content-Length',str(end-start+1))
                    if not getattr(self.server,'ignore_ranges',False):self.send_header('Accept-Ranges','bytes')
                    if value:self.send_header('Content-Range',f'bytes {start}-{end}/{len(DATA)}')
                    self.end_headers()
                    for offset in range(start,end+1,65536):
                        self.wfile.write(DATA[offset:min(offset+65536,end+1)]);time.sleep(.002)
                except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError): pass
                finally:
                    with test.lock:test.active -= 1
        self.server = ThreadingHTTPServer(('127.0.0.1',0),Handler)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.url=f'http://127.0.0.1:{self.server.server_port}/file?signature=TEMPORARY'
        self.output=io.StringIO();self.capture=contextlib.redirect_stdout(self.output);self.capture.__enter__()

    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join()
        self.capture.__exit__(None,None,None);self.tmp.cleanup()

    def test_bundled_aria2_uses_multiple_connections_and_keeps_headers(self):
        self.assertIsNotNone(download.executable('aria2c'))
        engine=download.download_url(self.url,self.dest,headers=['X-Test: preserved','User-Agent: Dalvik/test'],checksum=SHA,expected_bytes=len(DATA))
        self.assertEqual(engine,'aria2c');self.assertEqual(hashlib.sha256(self.dest.read_bytes()).hexdigest(),SHA)
        self.assertGreater(self.maximum,1);self.assertGreater(sum(r is not None for r in self.ranges),1)
        self.assertEqual(set(self.headers),{'preserved'})
        self.assertTrue(all(agent==['Dalvik/test'] for agent in self.agents))
        self.assertFalse(Path(str(self.dest)+'.aria2').exists())
        self.assertNotIn('signature=TEMPORARY',self.output.getvalue())

    def test_aria_failure_cleans_its_partial_data_before_real_curl_fallback(self):
        original=download.run_download_command;calls=[]
        def run(command,check):
            calls.append(command)
            if 'aria2c' in Path(command[0]).name:
                self.dest.write_bytes(b'incomplete')
                Path(str(self.dest)+'.aria2').write_bytes(b'control')
                raise download.DownloadError('Simulated aria failure')
            self.assertFalse(self.dest.exists());self.assertFalse(Path(str(self.dest)+'.aria2').exists())
            return original(command,check)
        with patch.object(download,'run_download_command',side_effect=run):
            engine=download.download_url(self.url,self.dest,headers=['X-Test: preserved'],checksum=SHA)
        self.assertEqual(engine,'curl');self.assertEqual(hashlib.sha256(self.dest.read_bytes()).hexdigest(),SHA)
        self.assertIn('-x8',calls[0]);self.assertIn('-s8',calls[0]);self.assertEqual(set(self.headers),{'preserved'})

    def test_cancellation_removes_data_and_control_file_without_falling_back(self):
        event=threading.Event();timer=threading.Timer(.15,event.set);timer.start()
        def check():
            if event.is_set():raise InterruptedError('Cancelled')
        try:
            with self.assertRaises(InterruptedError):download.download_url(self.url,self.dest,check=check)
        finally:timer.cancel()
        self.assertFalse(self.dest.exists());self.assertFalse(Path(str(self.dest)+'.aria2').exists())
        self.assertNotIn('trying curl',self.output.getvalue())

    def test_checksum_mismatch_rejects_both_downloads(self):
        with self.assertRaisesRegex(download.DownloadError,'SHA-256 mismatch'):
            download.download_url(self.url,self.dest,checksum='0'*64)
        self.assertFalse(self.dest.exists());self.assertIn('trying curl',self.output.getvalue())

    def test_missing_aria2_uses_curl(self):
        original=download.executable
        with patch.object(download,'executable',side_effect=lambda name,root:None if name=='aria2c' else original(name,root)):
            self.assertEqual(download.download_url(self.url,self.dest,checksum=SHA),'curl')

    def test_server_without_range_support_still_downloads_correctly(self):
        self.server.ignore_ranges=True
        download.download_url(self.url,self.dest,checksum=SHA)
        self.assertEqual(hashlib.sha256(self.dest.read_bytes()).hexdigest(),SHA)

    def test_worker_retries_invalid_aria_ota_using_curl(self):
        from flasher_builder.backend import Worker
        from flasher_builder.selftest import make_ota
        ota=Path(self.tmp.name)/'fixture.zip';make_ota(ota,{'boot':b'B'*4096})
        data=ota.read_bytes();target=Path(self.tmp.name)/'downloaded.zip'
        original=download.run_download_command
        def run(command,check):
            if 'aria2c' in Path(command[0]).name:
                Path(str(target)+'.part').write_bytes(b'not an OTA');return
            return original(command,check)
        with patch.dict(globals(),DATA=data),patch.object(download,'run_download_command',side_effect=run):
            self.assertEqual(Worker().source(self.url,target)[0],'1.2.3.4')
        self.assertEqual(target.read_bytes(),data)


class ReleaseRedirectTests(unittest.TestCase):
    def test_public_release_needs_no_credentials(self):
        opener=SimpleNamespace(open=lambda request,timeout:(_ for _ in ()).throw(HTTPError(request.full_url,302,'redirect',{'Location':'https://cdn.example/image'},None)))
        with patch.object(download,'build_opener',return_value=opener),patch.object(download.subprocess,'run',side_effect=AssertionError('Unexpected authentication')):
            url=download.release_url('owner/repo','tag','image name.img')
            self.assertEqual(download.resolve_release_url(url,'owner/repo',1),url)

    def test_private_token_is_used_only_for_api_and_not_the_download_url(self):
        requests=[]
        def open(request,timeout):
            requests.append(request)
            code=302 if len(requests)==2 else 404
            raise HTTPError(request.full_url,code,'redirect',{'Location':'https://release-assets.githubusercontent.com/file?signature=SIGNED'},None)
        with patch.object(download,'build_opener',return_value=SimpleNamespace(open=open)), \
             patch.object(download,'executable',return_value='gh'), \
             patch.object(download.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout='LONG_LIVED_TOKEN')):
            url=download.resolve_release_url('https://github.com/owner/repo/releases/download/tag/file','owner/repo',123)
        self.assertEqual(requests[1].get_header('Authorization'),'Bearer LONG_LIVED_TOKEN')
        self.assertTrue(requests[1].full_url.startswith('https://api.github.com/'))
        self.assertIsNone(requests[0].get_header('Authorization'))
        self.assertNotIn('LONG_LIVED_TOKEN',url)

    def test_logs_redact_url_queries_and_userinfo(self):
        log=download.redact_output('error https://user:password@example.com/file?token=SECRET')
        self.assertNotIn('password',log);self.assertNotIn('SECRET',log)
