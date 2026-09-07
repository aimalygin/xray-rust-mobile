from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


COMMON = Path(__file__).resolve().parents[1] / "_common.sh"


class AppleArtifactSourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.checkout = Path(self.temporary.name)
        self.git("init", "--quiet")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release-test@example.invalid")
        (self.checkout / "release").mkdir()
        (self.checkout / "Package.swift").write_text("unprepared package\n")
        (self.checkout / "release/artifacts.env").write_text("unprepared lock\n")
        (self.checkout / "source.swift").write_text("reviewed source\n")
        self.commit()
        self.source = self.git("rev-parse", "HEAD")
        self.tree = self.git("rev-parse", "HEAD^{tree}")

    def git(self, *args: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(self.checkout), *args], text=True
        ).strip()

    def commit(self) -> None:
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "fixture")

    def generate(self) -> None:
        (self.checkout / "Package.swift").write_text("package with checksum\n")
        (self.checkout / "release/artifacts.env").write_text("artifact provenance\n")

    def verify(self, mode: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "bash", "-c",
                'source "$1"; verify_apple_artifact_source "$2" "$3" "$4" "$5"',
                "verify-artifact-source", str(COMMON), str(self.checkout),
                self.source, self.tree, mode,
            ],
            capture_output=True, text=True, check=False,
        )

    def accepted(self, mode: str) -> None:
        result = self.verify(mode)
        self.assertEqual(result.returncode, 0, result.stderr)

    def rejected(self, mode: str, message: str) -> None:
        result = self.verify(mode)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)

    def test_generated_uncommitted_and_staged_locks_are_accepted(self) -> None:
        self.generate()
        self.accepted("generated")
        self.git("add", "Package.swift", "release/artifacts.env")
        self.accepted("generated")

    def test_committed_locks_are_accepted_only_by_strict_mode(self) -> None:
        self.generate()
        self.commit()
        self.accepted("strict")
        self.rejected("generated", "exact artifact source checkout")

    def test_generated_locks_do_not_satisfy_release_validation(self) -> None:
        self.generate()
        self.rejected("strict", "clean Git worktree")

    def test_generated_locks_reject_changed_build_input(self) -> None:
        self.generate()
        (self.checkout / "source.swift").write_text("changed source\n")
        self.rejected("generated", "outside the two lock files")

    def test_generated_locks_reject_untracked_build_input(self) -> None:
        self.generate()
        (self.checkout / "new.swift").write_text("untracked source\n")
        self.rejected("generated", "untracked build inputs")

    def test_generated_locks_reject_staged_input_hidden_by_worktree(self) -> None:
        self.generate()
        source = self.checkout / "source.swift"
        source.write_text("different staged source\n")
        self.git("add", "source.swift")
        source.write_text("reviewed source\n")
        self.rejected("generated", "staged build inputs")

    def test_missing_lock_change_is_rejected(self) -> None:
        (self.checkout / "Package.swift").write_text("only one lock\n")
        self.rejected("generated", "outside the two lock files")
        self.commit()
        self.rejected("strict", "outside the two lock files")

    def test_committed_source_change_is_rejected(self) -> None:
        self.generate()
        (self.checkout / "source.swift").write_text("different source\n")
        self.commit()
        self.rejected("strict", "outside the two lock files")

    def test_release_rejects_uncommitted_lock_tampering(self) -> None:
        self.generate()
        self.commit()
        (self.checkout / "release/artifacts.env").write_text("different artifact\n")
        self.rejected("strict", "clean Git worktree")

    def test_release_rejects_untracked_build_input(self) -> None:
        self.generate()
        self.commit()
        (self.checkout / "new.swift").write_text("untracked source\n")
        self.rejected("strict", "clean Git worktree")

    def test_wrong_tree_is_rejected(self) -> None:
        self.generate()
        self.tree = "0" * 40
        self.rejected("generated", "source commit/tree")

    def test_nonancestor_source_is_rejected(self) -> None:
        self.generate()
        self.commit()
        self.source = self.git("rev-parse", "HEAD")
        self.tree = self.git("rev-parse", "HEAD^{tree}")
        self.git("checkout", "--quiet", "HEAD~1")
        self.rejected("strict", "not an ancestor")


if __name__ == "__main__":
    unittest.main()
