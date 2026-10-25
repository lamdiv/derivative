"""Engine identity guards: a same-version custom framework must not reuse old bytes."""
import importlib.util
import plistlib
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('native_build', Path(__file__).resolve().parents[1] / 'scripts/build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)

class EngineIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.cef = Path(self.temporary.name)
        (self.cef / 'include').mkdir()
        self.header = self.cef / 'include/cef_version.h'
        self.header.write_text(f'#define CEF_VERSION "{build.LOCK["version"]}"\n')
        self.binary = self.cef / 'Release/Chromium Embedded Framework.framework/Chromium Embedded Framework'
        self.binary.parent.mkdir(parents=True)
        self.binary.write_bytes(b'official-engine-fixture')

    def test_same_version_different_framework_changes_identity(self):
        official = build.validate_cef(self.cef)
        self.binary.write_bytes(b'codec-enabled-engine-fixture')
        self.assertNotEqual(official, build.validate_cef(self.cef))

    def test_incompatible_version_is_rejected(self):
        self.header.write_text('#define CEF_VERSION "older-version"\n')
        with self.assertRaisesRegex(SystemExit, 'must match'): build.validate_cef(self.cef)

    def test_incomplete_distribution_is_rejected(self):
        self.binary.unlink()
        with self.assertRaisesRegex(SystemExit, 'missing its Release framework'): build.validate_cef(self.cef)

class AppBundlePrivacyTests(unittest.TestCase):
    def test_browser_and_helpers_declare_bluetooth_purpose(self):
        with tempfile.TemporaryDirectory() as directory:
            for name, extra in [('Derivative', {'NSPrincipalClass': 'DerivativeApplication'}), ('Derivative Helper', {'LSUIElement': True})]:
                with self.subTest(executable=name):
                    path = Path(directory) / 'Info.plist'
                    build.write_app_info(path, 'app.derivative.test', name, extra)
                    info = plistlib.loads(path.read_bytes())
                    self.assertTrue(info.get('NSBluetoothAlwaysUsageDescription', '').strip(), 'WebAuthn Bluetooth access must not terminate the app with a TCC privacy violation')
                    self.assertEqual(info['CFBundleExecutable'], name)
                    for key, value in extra.items(): self.assertEqual(info[key], value)

if __name__ == '__main__':
    unittest.main()
