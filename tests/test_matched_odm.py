"""Exact patch matching and selective remote extraction failure boundaries."""
from argparse import Namespace
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from flasher_builder import backend, ota_catalog as catalog
from flasher_builder.backend import BuildError, Cancelled, ROOT, Worker
from flasher_builder.remote_zip import ota_metadata, RangeError
from flasher_builder.selftest import make_ota, serve_ranges
from scripts.materialize_bloat import selected_paths


def entry(device='OP 15R', region='IN', model='CPH2767', version='16.0.10.500', **changes):
    return dict(dict(id=device+region+version, device=device, region=region, model=model,
                     version=model+'_'+version, security_patch='2026-08-01',
                     source_url='https://example.invalid/full.zip'), **changes)


def metadata(release):
    return dict(version_name=release['version'], **{'post-security-patch-level': release['security_patch']})


class MatchedOdmTests(unittest.TestCase):
    def setUp(self):
        self.target = entry()
        self.donor = entry('OP ACE 6T', 'CN', 'PLR110')
        self.data = dict(api_version='1', releases=[self.target, self.donor,
            entry('OP ACE 6T', 'CN', 'PLR110', '17.0.0.101', security_patch='2026-09-01', is_latest=True)])

    def test_both_regions_use_15r_and_match_old_patch_instead_of_latest(self):
        for region in ('IN', 'GLO'):
            self.assertEqual(catalog.targets('Oneplus Ace 6T', 'Super Flasher', region), {'ota': ('OP 15R', region)})
        self.assertEqual(catalog.targets('Oneplus Ace 6T', 'Super Flasher', 'CN'), {'ota': ('OP ACE 6T', 'CN')})
        self.assertEqual(catalog.matching_odm(self.data, self.target), self.donor)
        newer = dict(self.donor, id='newer-same-patch', version='PLR110_16.0.10.501', build_timestamp='2026-08-20T00:00:00')
        self.data['releases'].append(newer)
        self.assertEqual(catalog.matching_odm(self.data, self.target), newer)

    def test_missing_invalid_and_different_patch_dates_never_fall_back(self):
        for value in (None, '', '2026-08', '2026-02-30', '2026-08-05', '2026-10-01'):
            with self.subTest(value=value), self.assertRaises(catalog.CatalogError):
                catalog.matching_odm(self.data, dict(self.target, security_patch=value))

    def test_local_zip_identification_requires_exact_model_version_and_region(self):
        self.assertEqual(catalog.release_from_metadata(self.data, 'OP 15R', 'IN', metadata(self.target)), self.target)
        for device, region, fields in [('OP 15R', 'GLO', metadata(self.target)),
                                       ('OP 15R', 'IN', metadata(self.donor)),
                                       ('OP 15R', 'IN', {'version_name': '16.0.10.500'})]:
            with self.assertRaises(catalog.CatalogError): catalog.release_from_metadata(self.data, device, region, fields)

    def test_bloat_selection_excludes_static_odm_for_in_and_glo(self):
        manifest = json.loads((ROOT/'bloat/assets-manifest.json').read_text())
        for region in ('IN', 'GLO'):
            selected = selected_paths(manifest, 'Ace6T', 'Super Flasher', region)
            self.assertTrue(selected)
            self.assertFalse(any(p.endswith('/odm.img') for p in selected))
            self.assertIn(f'bloat/Ace6T/{region}_BLOAT/odm.img', selected_paths(manifest, 'Ace6T', 'Super Flasher', region, static_odm=True))

    def test_no_matching_donor_stops_before_full_target_download(self):
        with tempfile.TemporaryDirectory() as tmp:
            args = Namespace(repo=str(ROOT), output=tmp, device='Oneplus Ace 6T', kind='Super Flasher',
                             region='IN', ota='', ota_catalog_id='target', base='', cancel=None, fixture=True)
            with patch.object(backend, 'check_environment'), patch.object(backend, 'require_local_bloat'), \
                 patch.object(catalog, 'load_catalog', return_value={'releases': []}), \
                 patch.object(backend, 'selected_release', return_value=self.target), \
                 patch.object(Worker, 'source') as source, contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(catalog.CatalogError, 'No Ace 6T'): backend.build(args)
                source.assert_not_called()

    def test_donor_and_target_metadata_must_agree_before_image_transfer(self):
        args = Namespace(repo=str(ROOT), region='IN')
        with tempfile.TemporaryDirectory() as tmp, patch.object(catalog, 'resolve_link', return_value=self.donor['source_url']), \
             patch.object(backend, 'ota_metadata', return_value=metadata(dict(self.donor, security_patch='2026-09-01'))), \
             patch('flasher_builder.native_pipeline.extract') as extract:
            with self.assertRaisesRegex(BuildError, 'donor OTA security patch'):
                backend.prepare_matched_odm(Worker(), args, metadata(self.target), Path(tmp), (self.data, self.target))
            extract.assert_not_called()
            with self.assertRaisesRegex(BuildError, 'target OTA security patch'):
                backend.prepare_matched_odm(Worker(), args, metadata(dict(self.target, security_patch='2026-07-01')),
                                           Path(tmp), (self.data, self.target))
            extract.assert_not_called()

    def test_range_metadata_reads_no_payload_and_rejects_ignored_ranges(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); path = root/'ota.zip'
            make_ota(path, {'odm': b'O'*4096, 'unrelated': b'U'*(4*1024**2)},
                     'ota-type=AB\npost-security-patch-level=2026-08-01\nversion_name=PLR110_16.0.10.500\n')
            with serve_ranges(root) as (address, requests):
                self.assertEqual(ota_metadata(address+'/ota.zip')['post-security-patch-level'], '2026-08-01')
                self.assertLess(sum(end-start+1 for _,start,end in requests), 128*1024)
                self.assertFalse(any(start <= 2*1024**2 <= end for _,start,end in requests))
            class NoRanges(io.BytesIO):
                status = 200
                headers = {}
            with patch('flasher_builder.remote_zip.urlopen', return_value=NoRanges(b'whole OTA')):
                with self.assertRaisesRegex(RangeError, 'does not support HTTP ranges'):
                    ota_metadata('https://example.invalid/ota.zip')

    def test_corrupt_remote_odm_fails_strict_payload_verification(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); path = root/'donor.zip'
            make_ota(path, {'odm': b'O'*4096}, 'ota-type=AB\nversion_name=PLR110_16.0.10.500\npost-security-patch-level=2026-08-01\n')
            with zipfile.ZipFile(path) as archive:
                info = archive.getinfo('payload.bin')
                offset = info.header_offset + 30 + len(info.filename.encode()) + len(info.extra) + info.file_size - 10
            damaged = bytearray(path.read_bytes()); damaged[offset] ^= 1; path.write_bytes(damaged)
            download = root/'download'; download.mkdir()
            with serve_ranges(root) as (address, requests), patch.object(catalog, 'resolve_link', return_value=address+'/donor.zip'):
                with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(BuildError):
                    backend.prepare_matched_odm(Worker(), Namespace(repo=str(ROOT), region='IN'), metadata(self.target),
                                               download, (self.data, self.target))
            self.assertFalse(list(download.rglob('odm.img')))

    def test_cancel_during_odm_transfer_cleans_build_job_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); previous = root/'completed'; previous.mkdir(); (previous/'keep').write_text('keep')
            args = Namespace(repo=str(ROOT), output=tmp, device='Oneplus Ace 6T', kind='Super Flasher',
                             region='GLO', ota='', base='', cancel=None, fixture=True)
            with patch.object(backend, 'check_environment'), patch.object(backend, 'require_local_bloat'), \
                 patch.object(backend, 'plan_matched_odm', return_value=(self.data, self.target)), \
                 patch.object(backend, 'prepare_ota', return_value=('16.0.10.500', 4096, metadata(self.target))), \
                 patch.object(backend, 'prepare_matched_odm', side_effect=Cancelled('cancelled')), \
                 contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(Cancelled): backend.build(args)
            self.assertEqual(list(root.iterdir()), [previous])


if __name__ == '__main__': unittest.main()
