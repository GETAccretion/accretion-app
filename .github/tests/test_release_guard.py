import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/release_guard.py"


class ReleaseGuard(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.email", "fictional@example.invalid")
        self.git("config", "user.name", "Fixture")
        (self.root / "Feather.xcconfig").write_text(
            "FEATHER_PROJECT_VERSION=1.0.0\nPRODUCT=first\n"
        )
        (self.root / "app.swift").write_text("let value = 1\n")
        self.commit()
        self.base = self.git("rev-parse", "HEAD").strip()

    def git(self, *arguments):
        return subprocess.check_output(["git", *arguments], cwd=self.root, text=True)

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture")

    def compare(self):
        return subprocess.run(
            [os.sys.executable, str(SCRIPT), "compare", self.base, "HEAD"],
            cwd=self.root,
            capture_output=True,
            check=False,
        ).returncode

    def test_only_the_version_assignment_can_change(self):
        (self.root / "Feather.xcconfig").write_text(
            "FEATHER_PROJECT_VERSION=1.0.1\nPRODUCT=first\n"
        )
        (self.root / "app-repo.json").write_text("{}")
        self.commit()
        self.assertEqual(self.compare(), 0)

    def test_changed_build_setting_or_swift_source_requires_compile(self):
        for filename, content in [
            ("Feather.xcconfig", "FEATHER_PROJECT_VERSION=1.0.1\nPRODUCT=other\n"),
            ("app.swift", "let value = 2\n"),
        ]:
            with self.subTest(filename=filename):
                (self.root / filename).write_text(content)
                self.commit()
                self.assertNotEqual(self.compare(), 0)

    def test_bad_reference_and_duplicate_version_assignment_fail_closed(self):
        result = subprocess.run(
            [os.sys.executable, str(SCRIPT), "compare", "missing", "HEAD"],
            cwd=self.root,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        (self.root / "Feather.xcconfig").write_text(
            "FEATHER_PROJECT_VERSION=1.0.1\nFEATHER_PROJECT_VERSION=1.0.2\nPRODUCT=first\n"
        )
        self.commit()
        self.assertNotEqual(self.compare(), 0)

    def test_old_key_cache_is_a_miss_and_valid_cache_restores(self):
        spec = importlib.util.spec_from_file_location("release_guard", SCRIPT)
        guard = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(guard)
        binary = shutil.which("openssl") or "C:/Program Files/Git/usr/bin/openssl.exe"
        self.assertTrue(Path(binary).exists())
        source, encrypted, target = [
            self.root / name for name in ("source.ipa", "cache.enc", "restored.ipa")
        ]
        with zipfile.ZipFile(source, "w") as archive:
            archive.writestr("Payload/Fixture.app/Info.plist", "fictional")
        settings = {**os.environ, "UPLOAD_KEY": "fictional-original-key"}
        subprocess.run(
            [
                binary,
                "enc",
                "-aes-256-cbc",
                "-pbkdf2",
                "-iter",
                "200000",
                "-salt",
                "-pass",
                "env:UPLOAD_KEY",
                "-in",
                str(source),
                "-out",
                str(encrypted),
            ],
            env=settings,
            check=True,
            capture_output=True,
        )
        self.assertFalse(
            guard.restore_cache(encrypted, target, "fictional-rotated-key")
        )
        self.assertFalse(target.exists())
        self.assertTrue(
            guard.restore_cache(encrypted, target, "fictional-original-key")
        )
        self.assertEqual(target.read_bytes(), source.read_bytes())


if __name__ == "__main__":
    unittest.main()
