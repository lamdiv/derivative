"""Distribution guards that must hold before Apple credentials are used."""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release_signing', Path(__file__).resolve().parents[1] / 'scripts/release_signing.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class DistributionTests(unittest.TestCase):
    def test_development_and_adhoc_identities_are_rejected(self):
        identities = '  1) ' + 'A' * 40 + ' "Apple Development: Someone (ABCDEFGHIJ)"\n'
        with patch.object(signing.subprocess, 'check_output', return_value=identities):
            with self.assertRaisesRegex(RuntimeError, 'Developer ID Application'):
                signing.identity_team('A' * 40)

    def test_developer_id_can_be_selected_by_fingerprint(self):
        identities = '  1) ' + 'A' * 40 + ' "Developer ID Application: Someone (ABCDEFGHIJ)"\n'
        with patch.object(signing.subprocess, 'check_output', return_value=identities):
            self.assertEqual(signing.identity_team('A' * 40), 'ABCDEFGHIJ')

    def test_timeout_resumes_original_submission(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / 'app.zip'
            artifact.write_bytes(b'the exact signed app bytes')
            receipts = Path(directory) / 'receipts'
            calls = []
            def command(*args, **kwargs):
                calls.append(args)
                payload = {'id': 'original-id', 'status': 'In Progress'}
                return subprocess.CompletedProcess(args, 0, json.dumps(payload), '')
            with patch.object(signing, 'run', side_effect=command), patch.object(signing.subprocess, 'run'):
                for _ in range(2):
                    with self.assertRaisesRegex(RuntimeError, 'In Progress'):
                        signing.notarize(artifact, 'test-profile', receipts)
            self.assertEqual(sum('submit' in args for args in calls), 1)
            self.assertEqual(sum('info' in args for args in calls), 2)

    def test_jit_is_limited_to_renderer_and_gpu(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Derivative.app'
            frameworks = app / 'Contents/Frameworks'
            framework = frameworks / 'Chromium Embedded Framework.framework'
            framework.mkdir(parents=True)
            (framework / 'Chromium Embedded Framework').write_bytes(bytes.fromhex('cffaedfe'))
            for bundle, name in [(app, 'Derivative')] + [(frameworks / f'Derivative Helper{role}.app', f'Derivative Helper{role}') for role in signing.HELPER_ROLES]:
                executable = bundle / 'Contents/MacOS' / name
                executable.parent.mkdir(parents=True)
                executable.write_bytes(bytes.fromhex('cffaedfe'))
                (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': name}))
            plan = signing.signing_plan(app)
            self.assertEqual([path.name for path, kind in plan if kind == 'jit'],
                             ['Derivative Helper (GPU).app', 'Derivative Helper (Renderer).app'])
            self.assertEqual(plan[-1], (app.resolve(), 'app'))
            self.assertFalse(any('disable-library-validation' in key or 'get-task-allow' in key
                                 for values in signing.ENTITLEMENTS.values() for key in values))
            (app / 'Contents/Resources').mkdir()
            (app / 'Contents/Resources/unexpected-tool').write_bytes(bytes.fromhex('cffaedfe'))
            with self.assertRaisesRegex(RuntimeError, 'missing from signing inventory'):
                signing.signing_plan(app)

    def test_rejection_fetches_log_and_cannot_be_treated_as_success(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / 'app.zip'
            artifact.write_bytes(b'signed bytes')
            calls = []
            def command(*args, **kwargs):
                calls.append(args)
                payload = {'id': 'rejected-id', 'status': 'Invalid'}
                return subprocess.CompletedProcess(args, 0, json.dumps(payload), '')
            with patch.object(signing, 'run', side_effect=command), patch.object(signing.subprocess, 'run'):
                with self.assertRaisesRegex(RuntimeError, 'Invalid'):
                    signing.notarize(artifact, 'test-profile', Path(directory) / 'receipts')
            self.assertEqual(sum('log' in args for args in calls), 1)


if __name__ == '__main__':
    unittest.main()
