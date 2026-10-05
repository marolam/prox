import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1]


class GrowthRollbackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.git("init")
        self.git("config", "user.email", "rollback-test@example.invalid")
        self.git("config", "user.name", "Rollback test")
        self.git("config", "core.autocrlf", "false")
        (self.workspace / ".gitignore").write_text(".env*\nandroid/*.jks\nartifacts/\n")
        (self.workspace / "keep.txt").write_bytes(b"original\r\n")
        (self.workspace / "deleted.txt").write_bytes(b"deleted by user")
        self.git("add", ".")
        self.git("commit", "-m", "baseline")
        (self.workspace / "keep.txt").write_bytes(b"staged\r\n")
        self.git("add", "keep.txt")
        (self.workspace / "keep.txt").write_bytes(b"unstaged\r\n")
        (self.workspace / "deleted.txt").unlink()
        (self.workspace / "untracked.txt").write_bytes(b"untracked")
        (self.workspace / ".env.local").write_bytes(b"PRIVATE_INPUT=fixture\n")
        (self.workspace / "android").mkdir()
        (self.workspace / "android" / "fixture.jks").write_bytes(b"signing-fixture")
        self.backup, self.mirror = self.root / "backup", self.root / "mirror"
        result = self.command("create_growth_rollback.py", self.backup, "--workspace", self.workspace, "--mirror", self.mirror)
        self.assertEqual(result.returncode, 0, result.stderr)

    def git(self, *args, cwd=None):
        return subprocess.run(["git", "-C", str(cwd or self.workspace), *args], capture_output=True, check=True).stdout

    def command(self, script, *args):
        return subprocess.run([sys.executable, str(SCRIPTS / script), *(str(arg) for arg in args)], capture_output=True, text=True)

    def test_full_dirty_source_and_index_restore(self):
        restored = self.root / "restored"
        result = self.command("restore_growth_rollback.py", self.mirror, "--destination", restored)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((restored / "keep.txt").read_bytes(), b"unstaged\r\n")
        self.assertEqual((restored / "untracked.txt").read_bytes(), b"untracked")
        self.assertEqual((restored / ".env.local").read_bytes(), b"PRIVATE_INPUT=fixture\n")
        self.assertEqual((restored / "android" / "fixture.jks").read_bytes(), b"signing-fixture")
        self.assertFalse((restored / "deleted.txt").exists())
        self.assertEqual(self.git("diff", "--cached", "--binary", cwd=restored), self.git("diff", "--cached", "--binary"))
        self.assertEqual(self.git("diff", "--binary", cwd=restored), self.git("diff", "--binary"))

    def test_existing_destination_and_workspace_are_never_overwritten(self):
        for destination in (self.workspace, self.root / "existing"):
            destination.mkdir(exist_ok=True)
            sentinel = destination / "sentinel.txt"
            sentinel.write_bytes(b"preserve me")
            result = self.command("restore_growth_rollback.py", self.backup, "--destination", destination)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sentinel.read_bytes(), b"preserve me")

    def test_corrupt_component_fails_before_restore(self):
        (self.backup / "workspace.zip").write_bytes(b"damaged archive")
        restored = self.root / "restored"
        result = self.command("restore_growth_rollback.py", self.backup, "--destination", restored)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(restored.exists())

    def test_traversal_archive_rejected_even_with_matching_archive_digest(self):
        archive_path = self.backup / "workspace.zip"
        with zipfile.ZipFile(archive_path, "a") as archive:
            archive.writestr("../escape.txt", b"unsafe")
        manifest_path = self.backup / "manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["workspace.zipSha256"] = hashlib.sha256(archive_path.read_bytes()).hexdigest()
        manifest_path.write_text(json.dumps(manifest))
        result = self.command("restore_growth_rollback.py", self.backup)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "escape.txt").exists())


if __name__ == "__main__":
    unittest.main()
