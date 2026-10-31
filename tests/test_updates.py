"""Only complete, newer stable app releases notify; offline checks stay usable."""
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from contextlib import contextmanager
from flasher_builder.updates import ASSETS, UpdateError, check_for_updates, select_update


def release(tag, **kwargs):
    return dict(tag_name=tag, draft=False, prerelease=False,
        assets=[dict(name=n, state='uploaded') for n in (*ASSETS.values(), 'SHA256SUMS')], **kwargs)


class UpdateTests(unittest.TestCase):
    def test_public_repository_checks_updates_without_login(self):
        from unittest.mock import MagicMock
        response = MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps([release('v1.1.0')]).encode()
        with patch('flasher_builder.updates.urlopen', return_value=response), \
             patch('flasher_builder.updates.subprocess.run', side_effect=AssertionError('Login should not be needed')):
            self.assertEqual(check_for_updates('/no-gh', '1.0.4', 'linux')['version'], 'v1.1.0')

    def test_numeric_versions_and_platform_assets_ignore_other_releases(self):
        drafts = release('v4.0.0'); drafts['draft'] = True
        preview = release('v3.0.0'); preview['prerelease'] = True
        linux_only = release('v2.0.0'); linux_only['assets'] = [a for a in linux_only['assets'] if a['name'] != ASSETS['win32']]
        entries = [release('bloat-assets-v1'), drafts, preview, linux_only, release('v1.9.9'), release('v1.10.0')]
        result = select_update(entries, '1.9.0', 'win32')
        self.assertEqual(result['version'], 'v1.10.0')
        self.assertEqual(result['asset'], ASSETS['win32'])
        self.assertEqual(result['url'], 'https://github.com/koaaN/Flasher_Builder/releases/tag/v1.10.0')
        self.assertEqual(select_update(entries, '1.9.0', 'linux')['version'], 'v2.0.0')

    def test_no_downgrades_or_incomplete_release_notifications(self):
        self.assertIsNone(select_update([release('v1.0.2'), release('v1.0.1')], '1.0.2', 'linux'))
        incomplete = release('v2.0.0'); incomplete['assets'] = []
        self.assertIsNone(select_update([incomplete], '1.0.2', 'linux'))
        with self.assertRaises(UpdateError): select_update({}, '1.0.2', 'linux')

    def test_authenticated_cli_uses_explicit_private_repository_and_bounded_wait(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); cli = root/'tools/github/gh'; cli.parent.mkdir(parents=True); cli.touch()
            response = SimpleNamespace(returncode=0, stdout=json.dumps([release('v1.1.0')]))
            with patch('flasher_builder.updates.urlopen', side_effect=HTTPError('https://api.github.com',404,'private',{},None)), \
                 patch('flasher_builder.updates.subprocess.run', return_value=response) as run:
                self.assertEqual(check_for_updates(root, '1.0.2', 'linux')['version'], 'v1.1.0')
            command = run.call_args.args[0]
            self.assertEqual(command[0], str(cli))
            self.assertIn('repos/koaaN/Flasher_Builder/releases?per_page=100', command)
            self.assertEqual(run.call_args.kwargs['timeout'], 20)
            self.assertEqual(run.call_args.kwargs['stdin'], subprocess.DEVNULL)

    def test_auth_offline_timeout_and_bad_json_are_readable_without_leaking_stderr(self):
        cases = [SimpleNamespace(returncode=1, stdout='', stderr='secret diagnostic'),
                 SimpleNamespace(returncode=0, stdout='invalid JSON'),
                 subprocess.TimeoutExpired('gh', 20)]
        with patch('flasher_builder.updates.shutil.which', return_value='gh'), \
             patch('flasher_builder.updates.urlopen', side_effect=HTTPError('https://api.github.com',404,'private',{},None)):
            for response in cases:
                with self.subTest(response=response):
                    kwargs = {'side_effect': response} if isinstance(response, Exception) else {'return_value': response}
                    with patch('flasher_builder.updates.subprocess.run', **kwargs), self.assertRaises(UpdateError) as error:
                        check_for_updates('/not-a-project')
                    self.assertNotIn('secret', str(error.exception))
