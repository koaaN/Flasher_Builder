"""Deletion stays within the selected image paths and preserves shared data."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from flasher_builder.bloat_storage import BloatStorageError, plan_deletion, delete_bloat


class BloatStorageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = (Path(self.tmp.name)/'bloat').resolve()
        self.sha = hashlib.sha256(b'fixture').hexdigest()
        self.asset = dict(raw_sha256=self.sha, sha256=self.sha, encoding='identity')
        self.manifest = dict(files={'bloat/13/GLO_BLOAT/my_preload.img': self.sha}, assets={self.sha: self.asset})

    def tearDown(self): self.tmp.cleanup()

    def write(self, relative):
        p=self.root/relative;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'fixture');return p

    def test_deletes_only_selected_images_and_unused_cache(self):
        image=self.write('13/GLO_BLOAT/my_preload.img')
        cache=self.write('.cache/'+self.sha+'.img')
        unrelated=self.write('13/GLO_BLOAT/user-file.img')
        other=self.write('NEO8/CN_BLOAT/my_company.img')
        plan=plan_deletion(self.manifest,self.root,'13','SuperHybrid Flasher','GLO')
        self.assertEqual(set(plan.files),(set([image])))
        self.assertEqual(plan.cache,(cache,));self.assertEqual(plan.bytes,14)
        delete_bloat(plan)
        self.assertFalse(image.exists());self.assertFalse(cache.exists())
        self.assertEqual(unrelated.read_bytes(),b'fixture');self.assertEqual(other.read_bytes(),b'fixture')

    def test_shared_cache_stays_until_other_local_selection_is_removed(self):
        self.manifest['files']['bloat/13/EU_BLOAT/my_preload.img']=self.sha
        image=self.write('13/GLO_BLOAT/my_preload.img')
        other=self.write('13/EU_BLOAT/my_preload.img');cache=self.write('.cache/'+self.sha+'.img')
        plan=plan_deletion(self.manifest,self.root,'13','SuperHybrid Flasher','GLO')
        self.assertEqual(plan.cache,())
        delete_bloat(plan)
        self.assertFalse(image.exists());self.assertTrue(cache.exists());self.assertTrue(other.exists())

    def test_cache_only_and_compressed_objects_can_be_removed(self):
        self.asset['encoding']='gzip';cache=self.write('.cache/'+self.sha+'.img.gz')
        plan=plan_deletion(self.manifest,self.root,'13','SuperHybrid Flasher','GLO')
        self.assertEqual(plan.files,());self.assertEqual(plan.cache,(cache,))
        delete_bloat(plan);self.assertFalse(cache.exists())

    def test_linked_paths_are_rejected_before_any_deletion(self):
        outside=Path(self.tmp.name)/'original';outside.mkdir();(outside/'my_preload.img').write_bytes(b'original')
        parent=self.root/'13';parent.mkdir(parents=True)
        try:(parent/'GLO_BLOAT').symlink_to(outside,target_is_directory=True)
        except OSError:self.skipTest('Symlink creation unavailable on this host')
        with self.assertRaises(BloatStorageError):plan_deletion(self.manifest,self.root,'13','SuperHybrid Flasher','GLO')
        self.assertEqual((outside/'my_preload.img').read_bytes(),b'original')

    def test_paths_are_revalidated_after_confirmation(self):
        image=self.write('13/GLO_BLOAT/my_preload.img')
        plan=plan_deletion(self.manifest,self.root,'13','SuperHybrid Flasher','GLO')
        outside=Path(self.tmp.name)/'original.img';outside.write_bytes(b'original')
        image.unlink()
        try:image.symlink_to(outside)
        except OSError:self.skipTest('Symlink creation unavailable on this host')
        with self.assertRaises(BloatStorageError):delete_bloat(plan)
        self.assertEqual(outside.read_bytes(),b'original')

    def test_changed_root_cannot_redirect_deletion(self):
        self.write('13/GLO_BLOAT/my_preload.img')
        plan=plan_deletion(self.manifest,self.root,'13','SuperHybrid Flasher','GLO')
        moved=self.root.with_name('original-bloat');self.root.rename(moved)
        outside=Path(self.tmp.name)/'external';p=outside/'13/GLO_BLOAT/my_preload.img'
        p.parent.mkdir(parents=True);p.write_bytes(b'original')
        try:self.root.symlink_to(outside,target_is_directory=True)
        except OSError:self.skipTest('Symlink creation unavailable on this host')
        with self.assertRaises(BloatStorageError):delete_bloat(plan)
        self.assertEqual(p.read_bytes(),b'original')
