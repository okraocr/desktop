import re
import unittest
from pathlib import Path


class ProviderDependencyLockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.desktop_root = Path(__file__).resolve().parents[2]
        cls.provider_scripts = cls.desktop_root / "OkraPDF" / "ProviderScripts"

    def test_provider_installers_require_hash_locked_dependencies(self):
        expected_locks = {
            "install-dots-ocr.sh": "requirements-mlx.lock",
            "install-chandra-ocr.sh": "requirements-mlx.lock",
            "install-unlimited-ocr.sh": "requirements-mlx.lock",
            "install-presidio.sh": "requirements-presidio.lock",
        }

        for script_name, lock_name in expected_locks.items():
            with self.subTest(script=script_name):
                script = (self.provider_scripts / script_name).read_text(encoding="utf-8")
                self.assertIn(lock_name, script)
                self.assertIn("--require-hashes", script)
                self.assertIn("--only-binary=:all:", script)
                self.assertNotRegex(script, r"pip install[^\n]*==")
                self.assertNotIn("command -v python", script)
                self.assertIn('python_bin="${2:-}"', script)
                self.assertIn("trusted_python_candidates", script)

    def test_every_locked_requirement_has_at_least_one_sha256_hash(self):
        for lock_name in ["requirements-mlx.lock", "requirements-presidio.lock"]:
            with self.subTest(lock=lock_name):
                lock = (self.provider_scripts / lock_name).read_text(encoding="utf-8")
                requirement_blocks = re.split(r"\n(?=[a-zA-Z0-9])", lock)
                packages = [block for block in requirement_blocks if "==" in block or " @ " in block]

                self.assertGreater(len(packages), 1)
                for package in packages:
                    self.assertRegex(package, r"--hash=sha256:[0-9a-f]{64}")


if __name__ == "__main__":
    unittest.main()
