import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS XPC and App Sandbox")
class ProviderInstallationTests(unittest.TestCase):
    def test_xpc_install_native_library_retry_and_cancel(self):
        desktop = Path(__file__).resolve().parents[2]
        python = next(
            (str(path) for prefix in ["/opt/homebrew/bin", "/usr/local/bin"]
             for version in ["3.13", "3.12", "3.11", "3.10"]
             if os.access(path := Path(prefix) / f"python{version}", os.X_OK)),
            None,
        )
        if python is None:
            if os.environ.get("CI"):
                self.fail("CI must provision a supported Homebrew Python for the XPC regression")
            self.skipTest("Requires a supported Homebrew Python interpreter")

        def run(command, **kwargs):
            result = subprocess.run(command, capture_output=True, text=True, timeout=60, **kwargs)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result.stdout

        with tempfile.TemporaryDirectory(prefix="okra-install-test-") as directory:
            root = Path(directory)
            app = root / "InstallationProbe.app"
            contents = app / "Contents"
            binary = contents / "MacOS/InstallationProbe"
            binary.parent.mkdir(parents=True)
            (contents / "Resources/ProviderScripts").mkdir(parents=True)
            (contents / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": binary.name,
                "CFBundleIdentifier": f"com.okrapdf.install-test.{uuid.uuid4()}",
                "CFBundlePackageType": "APPL",
            }))
            sources = [
                "scripts/tests/provider_installation_probe.swift",
                "OkraPDF/LocalProcessing/ProviderRuntimeInstaller.swift",
                "OkraPDF/LocalProcessing/ProviderRuntimeXPCProtocol.swift",
                "OkraPDF/LocalProcessing/LocalProviderPaths.swift",
                "OkraPDF/LocalProcessing/LocalCommandRunner.swift",
                "OkraPDF/LocalProcessing/LocalCommandProcessBox.swift",
                "OkraPDF/LocalProcessing/LocalProcessEnvironment.swift",
            ]
            run(["/usr/bin/swiftc", "-parse-as-library", "-o", str(binary)] +
                [str(desktop / source) for source in sources])
            run(["/bin/bash", str(desktop / "scripts/build-provider-installer.sh"), str(contents)])
            service = contents / "XPCServices/com.okrapdf.desktop.provider-installer.xpc"
            scripts = service / "Contents/Resources/ProviderScripts"
            library_source = root / "probe.c"
            library_source.write_text("int provider_probe(void) { return 42; }\n")
            library = scripts / "provider-probe.dylib"
            run(["/usr/bin/clang", "-dynamiclib", str(library_source), "-o", str(library)])
            run(["/usr/bin/codesign", "--force", "--sign", "-", str(library)])
            # Exercise real venv/pip bootstrap and a native library without
            # networking or multi-gigabyte model downloads in CI.
            (scripts / "install-unlimited-ocr.sh").write_text('''#!/bin/zsh
set -euo pipefail
"$2" -m venv --clear "$1/venv"
cp "${0:A:h}/provider-probe.dylib" "$1/venv/provider-probe.dylib"
''')
            (scripts / "install-dots-ocr.sh").write_text('''#!/bin/zsh
set -euo pipefail
(
  trap '' TERM
  while true; do
    print tick >> "$1/heartbeat"
    sleep 0.05
  done
) &
wait
''')
            run(["/usr/bin/codesign", "--force", "--options", "runtime", "--sign", "-", str(service)])
            run(["/usr/bin/codesign", "--force", "--sign", "-",
                 "--options", "runtime",
                 "--entitlements", str(desktop / "okraPDF.entitlements"), str(app)])
            output = run([str(binary), python])
            self.assertIn("XPC install, native library load, retry, and cancellation passed", output)


if __name__ == "__main__":
    unittest.main()
