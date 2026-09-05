import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS App Sandbox")
class ProviderBootstrapTests(unittest.TestCase):
    def test_python_bootstrap_and_retry_inside_app_sandbox(self):
        desktop_root = Path(__file__).resolve().parents[2]
        python = next(
            (
                path
                for prefix in ["/opt/homebrew/bin", "/usr/local/bin"]
                for version in ["3.13", "3.12", "3.11", "3.10"]
                if os.access(path := f"{prefix}/python{version}", os.X_OK)
            ),
            None,
        )
        if python is None:
            if os.environ.get("CI"):
                self.fail("CI must provision a supported Homebrew Python for the sandbox regression")
            self.skipTest("Requires a supported Homebrew Python interpreter")

        # Use the production entitlements and environment, but a unique test
        # identity so this never touches Okra's models or application state.
        with tempfile.TemporaryDirectory(prefix="okra-bootstrap-test-") as directory:
            root = Path(directory)
            app = root / "BootstrapProbe.app"
            contents = app / "Contents"
            binary = contents / "MacOS" / "BootstrapProbe"
            binary.parent.mkdir(parents=True)
            bundle_id = f"com.okrapdf.bootstrap-test.{uuid.uuid4()}"
            (contents / "Info.plist").write_bytes(
                plistlib.dumps(
                    {
                        "CFBundleExecutable": binary.name,
                        "CFBundleIdentifier": bundle_id,
                        "CFBundlePackageType": "APPL",
                    }
                )
            )
            # swiftc requires top-level statements to be in main.swift when
            # compiling alongside the production environment implementation.
            source = root / "main.swift"
            source.write_bytes(
                (desktop_root / "scripts/tests/provider_bootstrap_probe.swift").read_bytes()
            )
            commands = [
                [
                    "/usr/bin/swiftc",
                    str(source),
                    str(desktop_root / "OkraPDF/LocalProcessing/LocalProcessEnvironment.swift"),
                    "-o", str(binary),
                ],
                [
                    "/usr/bin/codesign", "--force", "--sign", "-",
                    "--entitlements", str(desktop_root / "okraPDF.entitlements"),
                    str(app),
                ],
                [str(binary), python],
            ]
            for command in commands:
                result = subprocess.run(
                    command, capture_output=True, text=True, timeout=120
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Sandboxed Python bootstrap and retry passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
