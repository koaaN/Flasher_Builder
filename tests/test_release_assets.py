"""Verify private-release asset selection, caching and image integrity."""
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('materialize_bloat', Path(__file__).resolve().parents[1] / 'scripts/materialize_bloat.py')
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)


def fixture(raw, encoding='identity'):
    transport = gzip.compress(raw, mtime=0) if encoding == 'gzip' else raw
    checksum = hashlib.sha256(raw).hexdigest()
    obj = dict(asset_id=123, asset_name='test.img' + ('.gz' if encoding == 'gzip' else ''),
               raw_bytes=len(raw), raw_sha256=checksum, bytes=len(transport),
               sha256=hashlib.sha256(transport).hexdigest(), encoding=encoding)
    manifest = dict(schema_version=1, repository='owner/private-repo', tag='bloat-assets-v1',
                    assets={checksum: obj}, files={'bloat/13/CN_BLOAT/my_preload.img': checksum})
    return manifest, obj, transport


class ReleaseAssetTests(unittest.TestCase):
    def test_verified_gzip_cache_materializes_original_image(self):
        raw = b'Original image bytes\0' * 4096
        manifest, obj, transport = fixture(raw, 'gzip')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); cache = root / 'cache'; cache.mkdir()
            (cache / (obj['sha256'] + '.img.gz')).write_bytes(transport)
            with patch.object(assets.subprocess, 'run', side_effect=AssertionError('Unexpected download')):
                paths = assets.materialize(root, cache, manifest, '13', 'SuperHybrid Flasher', 'CN')
            self.assertEqual((root / paths[0]).read_bytes(), raw)
            self.assertEqual(len(paths), 1)

    def test_bad_cache_is_redownloaded_and_shared_object_fetched_once(self):
        raw = b'\0' * 4096
        manifest, obj, transport = fixture(raw)
        manifest['files']['bloat/13/CN_BLOAT/my_company.img'] = obj['raw_sha256']
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); cache = root / 'cache'; cache.mkdir()
            (cache / (obj['sha256'] + '.img')).write_bytes(b'bad cache')
            def download(command, stdout, **kwargs):
                self.assertIn('repos/owner/private-repo/releases/assets/123', command)
                stdout.write(transport)
                return SimpleNamespace(returncode=0, stderr=b'')
            with patch.object(assets.shutil, 'which', return_value='/usr/bin/gh'), patch.object(assets.subprocess, 'run', side_effect=download) as run:
                paths = assets.materialize(root, cache, manifest, '13', 'SuperHybrid Flasher', 'CN')
            self.assertEqual(run.call_count, 1)
            self.assertEqual(len(paths), 2)
            for path in paths: self.assertEqual((root / path).read_bytes(), raw)

    def test_transport_integrity_failure_does_not_replace_existing_image(self):
        raw = b'\0' * 4096
        manifest, obj, _ = fixture(raw)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); target = root / next(iter(manifest['files'])); target.parent.mkdir(parents=True)
            target.write_bytes(b'existing custom image')
            def download(command, stdout, **kwargs):
                stdout.write(b'not the requested image')
                return SimpleNamespace(returncode=0, stderr=b'')
            with patch.object(assets.shutil, 'which', return_value='/usr/bin/gh'), patch.object(assets.subprocess, 'run', side_effect=download):
                with self.assertRaisesRegex(assets.AssetError, 'SHA-256 mismatch'):
                    assets.materialize(root, root / 'cache', manifest, '13', 'SuperHybrid Flasher', 'CN')
            self.assertEqual(target.read_bytes(), b'existing custom image')
            self.assertFalse(list((root / 'cache').glob('*.part-*')))

    def test_download_status_detects_missing_complete_and_corrupt_images(self):
        raw = b'A' * 4096
        manifest, obj, _ = fixture(raw)
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp); verified = {}
            status = assets.inspect_downloads(manifest, folder, '13', 'SuperHybrid Flasher', 'CN', verified)
            self.assertFalse(status['ready'])
            target = folder / '13/CN_BLOAT/my_preload.img'; target.parent.mkdir(parents=True)
            target.write_bytes(raw)
            self.assertTrue(assets.inspect_downloads(manifest, folder, '13', 'SuperHybrid Flasher', 'CN', verified)['ready'])
            target.write_bytes(b'B' * len(raw))
            self.assertFalse(assets.inspect_downloads(manifest, folder, '13', 'SuperHybrid Flasher', 'CN', verified)['ready'])
            target.unlink()
            self.assertEqual(assets.inspect_downloads(manifest, folder, '13', 'SuperHybrid Flasher', 'CN', verified)['downloaded'], 0)

    def test_chosen_folder_is_reused_by_build_staging_without_download(self):
        raw = b'C' * 4096
        manifest, obj, transport = fixture(raw)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); folder = root / 'chosen'; cache = root / 'cache'; cache.mkdir()
            (cache / (obj['sha256'] + '.img')).write_bytes(transport)
            assets.materialize(root, cache, manifest, '13', 'SuperHybrid Flasher', 'CN', destination=folder)
            chosen = folder / '13/CN_BLOAT/my_preload.img'
            self.assertEqual(chosen.read_bytes(), raw)
            with patch.object(assets.subprocess, 'run', side_effect=AssertionError('Unexpected download')):
                assets.materialize(root / 'job', root / 'empty-cache', manifest, '13', 'SuperHybrid Flasher', 'CN', source=folder)
            self.assertEqual((root / 'job/bloat/13/CN_BLOAT/my_preload.img').read_bytes(), raw)

    def test_manifest_rejects_path_traversal(self):
        manifest, obj, _ = fixture(b'\0' * 4096)
        manifest['files'] = {'bloat/13/../../escape.img': obj['raw_sha256']}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'manifest.json'; path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(assets.AssetError, 'Unsafe bloat destination'):
                assets.load_manifest(path)

    def test_selection_includes_conversion_fixes_without_other_regions(self):
        manifest = {'files': {p: 'hash' for p in (
            'bloat/Ace6/OOS_BLOAT/system_dlkm_oki.img', 'bloat/Ace6/IN_BLOAT/wrong.img',
            'bloat/13T/FIXES/odm.img', 'bloat/13T/IN_BLOAT/my_company.img',
            'bloat/13T/CN_BLOAT/my_preload.img', 'bloat/13T/GLO_BLOAT/my_preload.img',
            'bloat/13T/GLO_BLOAT/system_dlkm_oki.img')}}
        self.assertEqual(assets.selected_paths(manifest, 'Ace6', 'SuperHybrid Flasher', 'IN'), ['bloat/Ace6/OOS_BLOAT/system_dlkm_oki.img'])
        self.assertEqual(assets.selected_paths(manifest, '13T', 'Super Flasher', 'IN'), ['bloat/13T/FIXES/odm.img', 'bloat/13T/IN_BLOAT/my_company.img'])
        self.assertEqual(assets.selected_paths(manifest, '13T', 'Super Flasher', 'CN'), ['bloat/13T/CN_BLOAT/my_preload.img', 'bloat/13T/GLO_BLOAT/my_preload.img'])


if __name__ == '__main__':
    unittest.main()
