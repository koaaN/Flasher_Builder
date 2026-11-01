"""OTA catalog caching, exact selection, link sessions and download integrity."""
from argparse import Namespace
import hashlib
import html
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from flasher_builder import backend, ota_catalog as catalog
from flasher_builder.backend import BuildError, Cancelled, Worker
from flasher_builder.selftest import make_ota


def release(**changes):
    return dict(id='stable-id', device='OP 13', region='GLO', model='CPH2653',
                version='CPH2653_16.0.10.600(EX01)', source_url='https://ota.example/downloadCheck?token=test',
                is_latest=True, **changes)


class OtaCatalogTests(unittest.TestCase):
    def test_all_workflow_devices_are_mapped_and_conversion_uses_two_distinct_targets(self):
        workflow = backend.Catalog()
        self.assertEqual(set(workflow.devices), set(catalog.DEVICE_NAMES))
        self.assertEqual(catalog.targets('Oneplus Ace 6', 'SuperHybrid Flasher', 'IN'),
                         dict(ota=('OP 15R', 'IN'), base=('OP ACE 6', 'CN')))
        self.assertEqual(catalog.targets('Oneplus Pad 2 Pro', 'SuperHybrid Flasher', 'CN')['ota'], ('OP PAD2 PRO', 'CN'))

    def test_cache_avoids_repeated_requests_and_revalidates_etag(self):
        data = dict(api_version='1', releases=[release()])
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(catalog, 'request', return_value=(json.dumps(data).encode(), {'ETag': 'abc'})) as request:
                self.assertEqual(catalog.load_catalog(tmp), data)
                self.assertEqual(catalog.load_catalog(tmp), data)
                request.assert_called_once()
            with patch.object(catalog, 'request', return_value=(None, {})) as request:
                self.assertEqual(catalog.load_catalog(tmp, force=True), data)
                self.assertEqual(request.call_args.kwargs['headers'], {'If-None-Match': 'abc'})
            with patch.object(catalog, 'request', side_effect=catalog.CatalogError('offline')):
                self.assertTrue(catalog.load_catalog(tmp, force=True)['_stale'])
            # The cached copy never persists the transient offline flag.
            self.assertNotIn('_stale', json.loads((Path(tmp) / 'catalog.json').read_text())['data'])

    def test_exact_device_region_and_natural_version_order(self):
        e = release()
        data = dict(api_version='1', releases=[dict(e, version='9', id='9', is_latest=False),
            dict(e, version='10', id='10', is_latest=False), dict(e, region='CN', id='CN')])
        self.assertEqual([e['id'] for e in catalog.releases_for(data, 'OP 13', 'GLO')], ['10', '9'])
        with patch.object(catalog, 'load_catalog', return_value=data):
            with self.assertRaises(catalog.CatalogError): catalog.find_release('/tmp', 'CN', 'OP 13', 'GLO')

    def test_resolver_matches_version_in_page_instead_of_assuming_catalog_index(self):
        entry = release()
        devices = {'OP 13': {'GLO': ['newer', entry['version'], 'older']}}
        page = '<select id="device" data-devices="' + html.escape(json.dumps(devices), quote=True) + '"></select>'
        result = '<div id="resultBox" data-url="" data-ota-key="opaque" data-csrf="csrf"></div>'
        calls = []
        def request(opener, url, data=None, **kw):
            calls.append((opener, url, data))
            if data is None: return page.encode(), {}
            if data.get('k'): return json.dumps(dict(ok=True, url='https://cdn.example/ota.zip?Expires=9999999999&Signature=abc')).encode(), {}
            return result.encode(), {}
        with patch.object(catalog, 'request', side_effect=request):
            self.assertIn('cdn.example', catalog.resolve_link(entry))
        self.assertEqual(calls[1][2]['version_index'], 1)
        self.assertEqual(calls[2][2], dict(k='opaque', csrf='csrf'))
        self.assertIs(calls[0][0], calls[2][0])

    def test_direct_zip_needs_no_resolution_and_expired_links_are_rejected(self):
        with patch.object(catalog, 'request') as request:
            entry = dict(release(), source_url='https://cdn.example/ota.zip')
            self.assertEqual(catalog.resolve_link(entry), entry['source_url'])
            request.assert_not_called()
        self.assertFalse(catalog.usable_link('https://cdn.example/ota.zip?Expires=123'))
        self.assertFalse(catalog.usable_link('https://ota.example/downloadCheck?k=x'))
        self.assertFalse(catalog.usable_link('file:///tmp/ota.zip'))

    def test_download_verifies_size_md5_and_atomic_result(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'fixture.zip'; make_ota(source, {'boot': b'boot' * 1024})
            entry = release(size=source.stat().st_size, md5=hashlib.md5(source.read_bytes()).hexdigest(),
                            sha256=hashlib.sha256(source.read_bytes()).hexdigest())
            args = Namespace(repo=str(backend.ROOT), device='Oneplus 13', kind='SuperHybrid Flasher', region='GLO',
                ota='', base='', ota_catalog_id='stable-id', base_catalog_id='', cancel=None,
                download_role='ota', download_path=str(root / 'saved.zip'), bloat_dir=str(root / 'bloat'))
            with patch.object(catalog, 'find_release', return_value=entry), patch.object(catalog, 'resolve_link', return_value=str(source)), \
                    patch.object(backend, 'require_local_bloat'):
                backend.download_ota(args)
                self.assertEqual((root / 'saved.zip').read_bytes(), source.read_bytes())
                args.download_path = str(root / 'bad.zip')
                entry['md5'] = '0' * 32
                with self.assertRaisesRegex(BuildError, 'checksum'): backend.download_ota(args)
                self.assertFalse((root / 'bad.zip').exists())
                self.assertFalse(list(root.glob('.ota-download-*')))
                entry['md5'] = hashlib.md5(source.read_bytes()).hexdigest()
                entry['sha256'] = '0' * 64
                with self.assertRaisesRegex(BuildError, 'checksum'): backend.download_ota(args)
                self.assertFalse((root / 'bad.zip').exists())
                entry['size'] += 1
                with self.assertRaisesRegex(BuildError, 'size'): backend.download_ota(args)
                self.assertFalse((root / 'bad.zip').exists())

    def test_cancelled_download_cleans_temp_and_preserves_existing_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp) / 'saved.zip'
            args = Namespace(repo=str(backend.ROOT), device='Oneplus 13', kind='SuperHybrid Flasher', region='GLO',
                ota='', base='', ota_catalog_id='stable-id', cancel=None, download_role='ota', download_path=str(destination))
            with patch.object(backend, 'require_local_bloat'), patch.object(backend, 'prepare_ota', side_effect=Cancelled('stopped')):
                with self.assertRaises(Cancelled): backend.download_ota(args)
                self.assertEqual(list(Path(tmp).iterdir()), [])
                destination.write_bytes(b'keep')
                with self.assertRaisesRegex(BuildError, 'already exists'): backend.download_ota(args)
                self.assertEqual(destination.read_bytes(), b'keep')

    def test_cancel_during_link_resolution_returns_without_waiting_for_http_timeout(self):
        import threading
        import time
        with tempfile.TemporaryDirectory() as tmp:
            cancel = Path(tmp) / 'cancel'
            started = threading.Event(); release = threading.Event()
            def resolve():
                started.set(); release.wait(3)
                return 'late link'
            timer = threading.Timer(.1, cancel.touch); timer.start()
            begin = time.monotonic()
            try:
                with self.assertRaises(Cancelled): Worker(cancel).metadata(resolve)
                self.assertTrue(started.is_set())
                self.assertLess(time.monotonic() - begin, 1)
            finally:
                release.set(); timer.join()


if __name__ == '__main__':
    unittest.main()
