import shlex
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
TAG_REF = "refs/tags/${{ env.RELEASE_TAG }}"
MANUAL_ONLY = "${{ github.event_name == 'workflow_dispatch' }}"
TOOLS_DIRECTORY = ".release-build-tools"
TOOLS_FILES = ["scripts/build_apk.ps1", "scripts/common.ps1"]


class ReleaseWorkflowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # BaseLoader preserves GitHub's `on` key and expression strings.
        cls.workflow = yaml.load(
            (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8"),
            Loader=yaml.BaseLoader,
        )
        cls.jobs = cls.workflow["jobs"]

    def step(self, job, name):
        matches = [step for step in self.jobs[job]["steps"] if step.get("name") == name]
        self.assertEqual(len(matches), 1, name)
        return matches[0]

    def test_release_triggers_do_not_add_a_mutable_tools_ref_input(self):
        self.assertEqual(set(self.workflow["on"]), {"push", "workflow_dispatch"})
        self.assertEqual(self.workflow["on"]["push"]["tags"], ["v*", "!v*-beta*"])
        self.assertEqual(set(self.workflow["on"]["workflow_dispatch"]["inputs"]), {"tag_name"})
        self.assertEqual(
            self.workflow["env"]["RELEASE_TAG"],
            "${{ github.event.inputs.tag_name || github.ref_name }}",
        )
        self.assertEqual(self.workflow["concurrency"]["cancel-in-progress"], "false")

    def test_android_retains_three_abis_and_tag_based_build_command(self):
        job = self.jobs["build-android"]
        self.assertEqual(job["runs-on"], "ubuntu-latest")
        self.assertEqual(job["strategy"]["fail-fast"], "false")
        self.assertEqual(job["strategy"]["matrix"]["include"], [
            {"target-platform": "android-arm", "abi": "armeabi-v7a"},
            {"target-platform": "android-arm64", "abi": "arm64-v8a"},
            {"target-platform": "android-x64", "abi": "x86_64"},
        ])
        build = self.step("build-android", "Build APK")
        self.assertEqual(build["shell"], "pwsh")
        self.assertEqual(
            build["run"],
            "scripts/build_apk.ps1 -TargetPlatform ${{ matrix.target-platform }} -Abi ${{ matrix.abi }}",
        )

    def test_every_application_and_release_checkout_stays_on_the_tag(self):
        self.assertEqual(set(self.jobs), {"release-target", "build-android", "build-windows", "build-ios", "release", "sync-ci-release"})
        self.assertEqual(self.jobs["build-ios"]["with"]["source_ref"], "${{ needs.release-target.outputs.source_sha }}")
        target = self.jobs["release-target"]
        self.assertEqual(target["outputs"]["source_sha"], "${{ steps.capabilities.outputs.source_sha }}")
        self.assertIn('"$(git rev-parse HEAD)"', target["steps"][1]["run"])
        auxiliary = []
        for name, job in self.jobs.items():
            if name == "build-ios":
                continue
            checkouts = [step for step in job["steps"] if step.get("uses", "").startswith("actions/checkout@")]
            primary = [step for step in checkouts if not step.get("with", {}).get("path")]
            with self.subTest(job=name):
                self.assertEqual(len(primary), 1)
                self.assertEqual(primary[0]["with"]["ref"], TAG_REF)
                self.assertNotIn("if", primary[0])
                self.assertIs(job["steps"][0], primary[0])
            auxiliary.extend((name, step) for step in checkouts if step not in primary)
        self.assertEqual(len(auxiliary), 1)
        self.assertEqual(auxiliary[0][0], "build-android")
        self.assertEqual(auxiliary[0][1], self.step("build-android", "Checkout workflow build tools for manual recovery"))

    def test_auxiliary_checkout_is_manual_and_uses_immutable_workflow_sha(self):
        checkout = self.step("build-android", "Checkout workflow build tools for manual recovery")
        self.assertEqual(checkout["if"], MANUAL_ONLY)
        self.assertEqual(checkout["with"], {
            "ref": "${{ github.workflow_sha }}",
            "path": TOOLS_DIRECTORY,
            "persist-credentials": "false",
            "sparse-checkout": "\n".join(TOOLS_FILES) + "\n",
            "sparse-checkout-cone-mode": "false",
        })

    def test_manual_overlay_copies_only_the_two_build_scripts_before_build(self):
        overlay = self.step("build-android", "Apply manual recovery build tools")
        self.assertEqual(overlay["if"], MANUAL_ONLY)
        self.assertEqual(overlay["shell"], "bash")
        commands = [shlex.split(line) for line in overlay["run"].splitlines() if line.strip()]
        self.assertEqual(commands, [
            ["set", "-euo", "pipefail"],
            *[["cp", "--", f"{TOOLS_DIRECTORY}/{path}", path] for path in TOOLS_FILES],
        ])
        steps = self.jobs["build-android"]["steps"]
        checkout = self.step("build-android", "Checkout workflow build tools for manual recovery")
        build = self.step("build-android", "Build APK")
        self.assertLess(steps.index(checkout), steps.index(overlay))
        self.assertLess(steps.index(overlay), steps.index(build))

    def test_summary_records_actual_source_and_tools_commits_for_both_events(self):
        summary = self.step("build-android", "Record Android build sources")
        self.assertNotIn("if", summary)
        self.assertEqual(summary["shell"], "bash")
        script = summary["run"]
        for fragment in (
            'source_sha="$(git rev-parse HEAD)"',
            'tools_sha="$source_sha"',
            'if [[ "$GITHUB_EVENT_NAME" == \'workflow_dispatch\' ]]; then',
            'tools_sha="$(git -C .release-build-tools rev-parse HEAD)"',
            "Release tag snapshot (no overlay)",
            "Manual recovery: workflow commit; only scripts/build_apk.ps1 and scripts/common.ps1 overlaid",
            '"$RELEASE_TAG"', '"$source_sha"', '"$tools_sha"',
            '>> "$GITHUB_STEP_SUMMARY"',
        ):
            self.assertIn(fragment, script)
        steps = self.jobs["build-android"]["steps"]
        self.assertLess(steps.index(self.step("build-android", "Apply manual recovery build tools")), steps.index(summary))
        self.assertLess(steps.index(summary), steps.index(self.step("build-android", "Build APK")))

    def test_release_requires_ios_success_except_for_historical_dispatch(self):
        target = self.jobs["release-target"]
        self.assertEqual(target["outputs"]["build_ios"], "${{ steps.capabilities.outputs.build_ios }}")
        capability = target["steps"][1]["run"]
        self.assertIn("[ -f .github/workflows/build-ios-package.yml ]", capability)
        self.assertIn('elif [ "$GITHUB_EVENT_NAME" = workflow_dispatch ]; then', capability)
        self.assertIn("exit 1", capability)
        ios = self.jobs["build-ios"]
        ios_required = "${{ needs.release-target.outputs.build_ios == 'true' }}"
        self.assertEqual(ios["uses"], "./.github/workflows/build-ios-package.yml")
        self.assertEqual(ios["permissions"], {"contents": "read"})
        self.assertEqual(ios["needs"], "release-target")
        self.assertEqual(ios["if"], ios_required)

        release = self.jobs["release"]
        self.assertEqual(release["needs"], ["release-target", "build-android", "build-windows", "build-ios"])
        for condition in (
            "!cancelled()", "needs.release-target.result == 'success'",
            "needs.build-android.result == 'success'", "needs.build-windows.result == 'success'",
            "needs.release-target.outputs.build_ios == 'false' && needs.build-ios.result == 'skipped'",
            "needs.release-target.outputs.build_ios == 'true' && needs.build-ios.result == 'success'",
        ):
            self.assertIn(condition, release["if"])
        ios_steps = (
            "Require passing iOS tests and sealed artifact ID", "Download sealed iOS IPA and checksum",
            "Verify the iOS IPA before adding it to the release",
        )
        for name, job in self.jobs.items():
            with self.subTest(job=name):
                self.assertNotIn("continue-on-error", job)
                for step in job.get("steps", []):
                    self.assertNotIn("continue-on-error", step)
                    if name in {"release", "sync-ci-release"}:
                        self.assertEqual(step.get("if"), ios_required if step.get("name") in ios_steps else None)
        test_gate = self.step("release", ios_steps[0])
        self.assertEqual(test_gate["env"]["FLUTTER_TESTS"], "${{ needs.build-ios.outputs.flutter_tests }}")
        self.assertEqual(test_gate["env"]["SIMULATOR_TEST"], "${{ needs.build-ios.outputs.simulator_test }}")
        self.assertIn('test "$FLUTTER_TESTS" = success && test "$SIMULATOR_TEST" = success', test_gate["run"])
        download = self.step("release", ios_steps[1])["with"]
        self.assertEqual(download, {
            "artifact-ids": "${{ needs.build-ios.outputs.artifact_id }}",
            "path": "ios-artifact/", "merge-multiple": "true",
        })
        self.assertIn("scripts/package_ios.py verify-release --artifact-dir ios-artifact/ --pubspec pubspec.yaml",
                      self.step("release", ios_steps[2])["run"])
        self.assertIn("mv -- ios-artifact/*.ipa artifacts/", self.step("release", ios_steps[2])["run"])
        indices = [release["steps"].index(self.step("release", name)) for name in (
            *ios_steps, "Create or reuse GitHub Release", "Generate and upload release.json",
        )]
        self.assertEqual(indices, sorted(indices))
        self.assertEqual(release["steps"][0]["with"]["sparse-checkout"].splitlines(), [
            "docs/CHANGELOG.md", "pubspec.yaml", "scripts/generate_release_manifest.py",
            "scripts/package_ios.py", "test/scripts/generate_release_manifest_test.py",
        ])
        self.assertEqual(self.jobs["sync-ci-release"]["needs"], "release")
        self.assertEqual(self.jobs["sync-ci-release"]["steps"][0]["with"]["sparse-checkout"].splitlines(), [
            "docs/CHANGELOG.md", "scripts/sync_release_to_ci.sh",
        ])
        self.assertEqual(self.step("build-windows", "Build installer")["run"], "scripts/build_windows.ps1")

    def test_beta_builds_ios_from_same_commit_independently_of_android(self):
        workflow = yaml.load(
            (ROOT / ".github/workflows/build-ci.yml").read_text(encoding="utf-8"), Loader=yaml.BaseLoader,
        )
        self.assertEqual(workflow["on"]["push"]["tags"], ["v*-beta*"])
        self.assertIn("workflow_dispatch", workflow["on"])
        ios = workflow["jobs"]["build-ios"]
        self.assertEqual(ios["uses"], "./.github/workflows/build-ios.yml")
        self.assertEqual(ios["with"], {"source_ref": "${{ github.sha }}", "note": "${{ inputs.note || '' }}"})
        self.assertEqual(ios["permissions"], {"contents": "write"})
        for job in (ios, workflow["jobs"]["build-android"]):
            self.assertNotIn("needs", job)
            self.assertNotIn("if", job)
            self.assertNotIn("continue-on-error", job)


if __name__ == "__main__":
    unittest.main()
