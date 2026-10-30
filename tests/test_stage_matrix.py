"""Stage every workflow combination using manifest-only, offline fixture assets."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from flasher_builder.backend import Catalog, ROOT


class StagingMatrixTests(unittest.TestCase):
    @unittest.skipUnless((ROOT / 'bloat/assets-manifest.json').is_file(), 'Release manifest not yet installed')
    def test_all_workflow_combinations_stage_from_release_cache(self):
        actual_manifest = json.loads((ROOT / 'bloat/assets-manifest.json').read_text())
        catalog = Catalog(ROOT)
        with tempfile.TemporaryDirectory(prefix='flasher-stage-matrix-') as temporary:
            root = Path(temporary); repo = root / 'repo'; repo.mkdir()
            cache = root / 'cache'; cache.mkdir()
            for name in ('scripts', 'build_scripts', 'build_tools_assets', 'flasher_scripts'):
                shutil.copytree(ROOT / name, repo / name, ignore=shutil.ignore_patterns('__pycache__'))
            for name in ('otaripper', 'lpmake'):
                (repo / name).mkdir(); (repo / name / name).write_bytes(b'fixture tool, not executed')
            (repo / 'Platform-Tools').mkdir()
            for path in (repo / 'flasher_scripts').rglob('*.sh'):
                path.write_bytes(path.read_bytes().replace(b'\r\n', b'\n'))
            raw = b'Fixture image bytes\0' * 512
            checksum = hashlib.sha256(raw).hexdigest()
            (cache / (checksum + '.img')).write_bytes(raw)
            manifest = dict(schema_version=1, repository='owner/private', tag='test-only',
                assets={checksum: dict(asset_id=1, asset_name='fixture.img', bytes=len(raw), sha256=checksum,
                                       raw_bytes=len(raw), raw_sha256=checksum, encoding='identity')},
                files={path: checksum for path in actual_manifest['files']})
            (repo / 'bloat').mkdir()
            (repo / 'bloat/assets-manifest.json').write_text(json.dumps(manifest))
            for (kind, device, region), builder in catalog.builders.items():
                with self.subTest(device=device, flasher=kind, region=region):
                    env = os.environ | dict(DEV=device, FTYPE=kind, REGION=region, BUILDER_SH=builder,
                        OUT_DIR=str(root / 'out'), GITHUB_WORKSPACE=str(repo), GITHUB_ENV=str(root / 'env'),
                        BLOAT_CACHE_DIR=str(cache))
                    result = subprocess.run(['bash', str(repo / 'scripts/stage_files.sh')], env=env, cwd=repo,
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    # Every case begins without pre-materialized device folders.
                    for path in (repo / 'bloat').iterdir():
                        if path.is_dir(): shutil.rmtree(path)


if __name__ == '__main__':
    unittest.main()
