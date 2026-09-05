from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


MOBILE_ROOT = Path(__file__).resolve().parents[2]
COMMON = MOBILE_ROOT / "scripts" / "_common.sh"
CORE_SOURCE = MOBILE_ROOT.parent / "xray-rust"


class CoreCheckoutPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.checkout = Path(self.temporary.name) / "core"
        subprocess.run(
            ["git", "clone", "--quiet", "--shared", str(CORE_SOURCE), str(self.checkout)],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(self.checkout), "checkout", "--quiet", "v0.5.0"],
            check=True,
        )

    def verify(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; verify_core_checkout "$2"',
                "verify-core-checkout",
                str(COMMON),
                str(self.checkout),
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    def test_clean_pinned_checkout_is_accepted(self) -> None:
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_untracked_core_input_is_rejected(self) -> None:
        (self.checkout / "untracked-build-input.rs").write_text("untrusted\n")
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tracked or untracked changes", result.stderr)


if __name__ == "__main__":
    unittest.main()
