import os
import subprocess
import tempfile
import unittest
from pathlib import Path


class DMGPackagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.desktop_root = Path(__file__).resolve().parents[2]
        cls.packager = cls.desktop_root / "scripts" / "package-dmg.sh"
        cls.layout = cls.desktop_root / "scripts" / "configure-dmg-layout.applescript"

    def test_packager_stages_app_and_applications_shortcut(self):
        with tempfile.TemporaryDirectory(prefix="okra-dmg-stage-") as temporary_directory:
            temporary_root = Path(temporary_directory)
            app_path = temporary_root / "Okra.app"
            (app_path / "Contents").mkdir(parents=True)
            staging_path = temporary_root / "staging"

            subprocess.run(
                [
                    "/bin/bash",
                    "-c",
                    'source "$1"; stage_dmg_contents "$2" "$3"',
                    "bash",
                    str(self.packager),
                    str(app_path),
                    str(staging_path),
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            self.assertTrue((staging_path / "Okra.app" / "Contents").is_dir())
            applications_link = staging_path / "Applications"
            self.assertTrue(applications_link.is_symlink())
            self.assertEqual(os.readlink(applications_link), "/Applications")

    def test_packager_and_layout_scripts_parse(self):
        subprocess.run(
            ["/bin/bash", "-n", str(self.packager)],
            check=True,
            capture_output=True,
            text=True,
        )
        with tempfile.TemporaryDirectory(prefix="okra-dmg-layout-") as temporary_directory:
            subprocess.run(
                [
                    "/usr/bin/osacompile",
                    "-o",
                    str(Path(temporary_directory) / "layout.scpt"),
                    str(self.layout),
                ],
                check=True,
                capture_output=True,
                text=True,
            )

    def test_packager_creates_install_ready_disk_image(self):
        with tempfile.TemporaryDirectory(prefix="okra-dmg-package-") as temporary_directory:
            temporary_root = Path(temporary_directory)
            app_path = temporary_root / "Okra.app"
            (app_path / "Contents").mkdir(parents=True)
            dmg_path = temporary_root / "Okra-test.dmg"
            mount_path = temporary_root / "mount"

            subprocess.run(
                [str(self.packager), str(app_path), str(dmg_path)],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                ["/usr/bin/hdiutil", "verify", str(dmg_path)],
                check=True,
                capture_output=True,
                text=True,
            )

            mount_path.mkdir()
            subprocess.run(
                [
                    "/usr/bin/hdiutil",
                    "attach",
                    str(dmg_path),
                    "-nobrowse",
                    "-readonly",
                    "-mountpoint",
                    str(mount_path),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            try:
                self.assertTrue((mount_path / "Okra.app").is_dir())
                applications_link = mount_path / "Applications"
                self.assertTrue(applications_link.is_symlink())
                self.assertEqual(os.readlink(applications_link), "/Applications")
                self.assertGreater((mount_path / ".DS_Store").stat().st_size, 0)
                self.assertFalse((mount_path / "staging").exists())
            finally:
                subprocess.run(
                    ["/usr/bin/hdiutil", "detach", "-force", str(mount_path)],
                    check=True,
                    capture_output=True,
                    text=True,
                )

    def test_local_and_release_builds_use_shared_packager(self):
        build_script = (self.desktop_root / "scripts" / "build-dmg.sh").read_text(
            encoding="utf-8"
        )
        release_workflow = (
            self.desktop_root / ".github" / "workflows" / "notarized-release.yml"
        ).read_text(encoding="utf-8")

        expected_call = './scripts/package-dmg.sh "build/Okra.app" "${DMG}"'
        self.assertIn(expected_call, build_script)
        self.assertIn(expected_call, release_workflow)
        self.assertIn("--app-only", release_workflow)
        self.assertNotIn('-srcfolder "build/Okra.app"', release_workflow)


if __name__ == "__main__":
    unittest.main()
