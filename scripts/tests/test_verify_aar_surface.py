from __future__ import annotations

import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "verify-aar-surface.py"
SPEC = importlib.util.spec_from_file_location("verify_aar_surface", SCRIPT)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


MANIFEST = b'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.xrayrust.mobile">
<uses-sdk android:minSdkVersion="24" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
</manifest>'''


class VerifyAarSurfaceTests(unittest.TestCase):
    def make_aar(self, mutate=None) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / "test.aar"
        entries = {name: b"x" for name in VALIDATOR.EXPECTED_FILES}
        entries["AndroidManifest.xml"] = MANIFEST
        if mutate:
            mutate(entries)
        with zipfile.ZipFile(path, "w") as archive:
            for name, data in entries.items():
                archive.writestr(name, data)
        return path

    def test_exact_surface_is_accepted(self):
        VALIDATOR.validate(str(self.make_aar()))

    def test_extra_file_is_rejected(self):
        path = self.make_aar(lambda entries: entries.__setitem__("assets/payload", b"x"))
        with self.assertRaisesRegex(ValueError, "unexpected"):
            VALIDATOR.validate(str(path))

    def test_manifest_component_is_rejected(self):
        def mutate(entries):
            entries["AndroidManifest.xml"] = MANIFEST.replace(
                b"</manifest>", b"<application><service /></application></manifest>"
            )

        with self.assertRaisesRegex(ValueError, "unexpected manifest element"):
            VALIDATOR.validate(str(self.make_aar(mutate)))

    def test_manifest_root_attribute_is_rejected(self):
        def mutate(entries):
            entries["AndroidManifest.xml"] = MANIFEST.replace(
                b'package="org.xrayrust.mobile"',
                b'package="org.xrayrust.mobile" android:sharedUserId="hostile"',
            )

        with self.assertRaisesRegex(ValueError, "manifest attributes differ"):
            VALIDATOR.validate(str(self.make_aar(mutate)))

    def test_manifest_sdk_attribute_is_rejected(self):
        def mutate(entries):
            entries["AndroidManifest.xml"] = MANIFEST.replace(
                b'android:minSdkVersion="24"',
                b'android:minSdkVersion="24" android:maxSdkVersion="25"',
            )

        with self.assertRaisesRegex(ValueError, "uses-sdk attributes differ"):
            VALIDATOR.validate(str(self.make_aar(mutate)))

    def test_traversal_entry_is_rejected(self):
        path = self.make_aar(lambda entries: entries.__setitem__("../payload", b"x"))
        with self.assertRaisesRegex(ValueError, "unsafe ZIP entry"):
            VALIDATOR.validate(str(path))


if __name__ == "__main__":
    unittest.main()
