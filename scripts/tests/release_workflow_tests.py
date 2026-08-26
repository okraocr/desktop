import unittest
from pathlib import Path


class ReleaseWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = (
            Path(__file__).resolve().parents[2]
            / ".github"
            / "workflows"
            / "notarized-release.yml"
        ).read_text(encoding="utf-8")

    def test_signed_appcast_is_pushed_to_a_dedicated_branch(self):
        self.assertIn(
            'APPCAST_BRANCH="automation/appcast-${TAG}-${BUILD_NUMBER}-${GITHUB_RUN_ID}"',
            self.workflow,
        )
        self.assertIn('git push origin "HEAD:refs/heads/${APPCAST_BRANCH}"', self.workflow)

    def test_release_job_never_pushes_directly_to_protected_main(self):
        self.assertNotIn("git push origin main", self.workflow)
        self.assertNotIn("git pull --rebase origin main", self.workflow)

    def test_final_dmg_uses_shared_packager_after_app_notarization(self):
        app_staple = 'xcrun stapler staple "build/Okra.app"'
        package_dmg = './scripts/package-dmg.sh "build/Okra.app" "${DMG}"'

        self.assertIn("--app-only", self.workflow)
        self.assertIn(app_staple, self.workflow)
        self.assertIn(package_dmg, self.workflow)
        self.assertLess(self.workflow.index(app_staple), self.workflow.index(package_dmg))
        self.assertNotIn("hdiutil create", self.workflow)

    def test_packaged_launch_uses_a_release_only_container_identity(self):
        self.assertIn("name: Checkout release controls", self.workflow)
        self.assertIn("ref: ${{ github.workflow_sha }}", self.workflow)
        self.assertIn("path: .release-control", self.workflow)
        self.assertIn(
            "bash .release-control/scripts/prepare-release-smoke-app.sh",
            self.workflow,
        )
        self.assertIn("com.okrapdf.desktop.release-validation", self.workflow)
        self.assertIn(
            'OKRA_DESKTOP_PACKAGED_APP_PATH="${SMOKE_APP}"',
            self.workflow,
        )
        self.assertIn(
            'OKRA_DESKTOP_RELEASE_SMOKE_APP_PATH="${OKRA_RELEASE_SMOKE_APP_PATH}"',
            self.workflow,
        )
        self.assertIn(
            'codesign --verify --strict --deep "build/Okra.app"',
            self.workflow,
        )
        self.assertIn(
            'spctl --assess --type execute --verbose=4 "build/Okra.app"',
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main()
