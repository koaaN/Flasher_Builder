"""Separate NA feeds, direct reconstructed links and complete payload checks."""
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from flasher_builder import ota_catalog
from flasher_builder.backend import BuildError, validate_ota
from flasher_builder.payload import verify_full_payload
from flasher_builder.selftest import blob, make_ota, number


def entry(device='OP 13', **changes):
    return dict(dict(id=device,device=device,region='NA',version='16.0.10.600',
        package_type='reconstructed_full',source_url='https://roms.danielspringer.at/download.php?file=Files%2FBloat%2FNA%2Ffirmware.zip&download=true'),**changes)


class NaSupportTests(unittest.TestCase):
    def test_na_cache_is_independent_and_keeps_its_own_etag_and_offline_copy(self):
        general={'api_version':'1','releases':[entry(region='GLO')]}
        na={'api_version':'1','releases':[entry(),entry('OP 15')]}
        def request(opener,url,headers):
            self.assertNotIn('If-None-Match',headers)
            return json.dumps(na if url==ota_catalog.NA_API else general).encode(),{'ETag':url}
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(ota_catalog,'request',side_effect=request) as call:
                self.assertEqual(ota_catalog.load_catalog(tmp),general)
                self.assertEqual(ota_catalog.load_catalog(tmp,na=True),na)
                self.assertEqual(ota_catalog.load_catalog(tmp,na=True),na)
                self.assertEqual(call.call_count,2)
            with patch.object(ota_catalog,'request',return_value=(None,{})) as call:
                self.assertEqual(ota_catalog.load_catalog(tmp,force=True,na=True),na)
                self.assertEqual(call.call_args.args[1],ota_catalog.NA_API)
                self.assertEqual(call.call_args.kwargs['headers'],{'If-None-Match':ota_catalog.NA_API})
            with patch.object(ota_catalog,'request',side_effect=ota_catalog.CatalogError('offline')):
                cached=ota_catalog.load_catalog(tmp,force=True,na=True)
                self.assertTrue(cached['_stale'])
                self.assertEqual(cached['releases'],na['releases'])

    def test_exact_na_device_selection_uses_na_feed_and_direct_download_without_session(self):
        for device in ('OP 13','OP 15'):
            release=entry(device)
            with patch.object(ota_catalog,'load_catalog',return_value={'releases':[entry(),entry('OP 15')]}) as load:
                selected=ota_catalog.find_release('/tmp',device,device,'NA')
                self.assertEqual(selected['device'],device)
                self.assertTrue(load.call_args.kwargs['na'])
            with patch.object(ota_catalog,'request') as request:
                self.assertEqual(ota_catalog.resolve_link(release),release['source_url'])
                request.assert_not_called()
        self.assertTrue(ota_catalog.uses_na_api('Oneplus 13','NA'))
        self.assertTrue(ota_catalog.uses_na_api('Oneplus 15','NA'))
        self.assertFalse(ota_catalog.uses_na_api('Oneplus 15','EU'))
        self.assertFalse(ota_catalog.uses_na_api('Oneplus 13R','NA'))

    def test_reconstructed_full_zip_with_old_delta_metadata_is_accepted_locally(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'full.zip'
            make_ota(path,{'boot':b'B'*4096},'ota-type=AB\npre-build=old\npre-build-incremental=123\nversion_name=16.0.10.600\n')
            self.assertEqual(validate_ota(path)[0],'16.0.10.600')
            with zipfile.ZipFile(path) as z,z.open('payload.bin') as stream:
                self.assertEqual(verify_full_payload(stream,z.getinfo('payload.bin').file_size),1)

    def test_true_source_dependent_delta_operations_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'delta.zip'
            for operation in (2,3,4,5,9,10,11,12,13):
                with self.subTest(operation=operation):
                    make_ota(path,{'boot':b'B'*4096},'pre-build=old\nversion_name=1.2.3.4\n',operation_type=operation)
                    with self.assertRaisesRegex(BuildError,'incremental'):validate_ota(path)

    def test_replace_only_payload_with_missing_or_overlapping_blocks_is_rejected(self):
        for extents in ((1,), (0,0), ()):
            operation=number(1,0)+number(2,0)+number(3,4096)
            for start in extents:operation+=blob(6,number(1,start)+number(2,1))
            partition=blob(1,b'boot')+blob(7,number(1,8192))+blob(8,operation)
            manifest=number(3,4096)+blob(13,partition)
            payload=b'CrAU'+struct.pack('>QQI',2,len(manifest),0)+manifest+b'B'*4096
            with self.subTest(extents=extents),self.assertRaisesRegex(ValueError,'complete partition'):
                verify_full_payload(io.BytesIO(payload),len(payload))

    def test_invalid_or_oversized_manifests_are_rejected_before_reading_data(self):
        for payload in (b'CrAU',b'CrAU'+struct.pack('>QQI',2,20*1024**2,0),
                        b'CrAU'+struct.pack('>QQI',2,1,0)+b'\x80'):
            with self.subTest(payload=payload),self.assertRaises(ValueError):
                verify_full_payload(io.BytesIO(payload),len(payload))


if __name__=='__main__':unittest.main()
