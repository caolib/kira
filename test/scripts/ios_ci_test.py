import importlib.util
import os
import plistlib
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import yaml


SUPPORT_SPEC = importlib.util.spec_from_file_location("ios_test_support", Path(__file__).with_name("ios_test_support.py"))
support = importlib.util.module_from_spec(SUPPORT_SPEC)
SUPPORT_SPEC.loader.exec_module(support)
ci = support.load_script("ios_ci.py", "ios_ci")
simulator = support.load_script("ios_simulator.py", "ios_simulator")


class IosCiTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def create_config(self):
        files = {".flutter-version": "3.44.2\n", "integration_test/ios_startup_test.dart": "test entry\n",
                 "pubspec.yaml": "dev_dependencies:\n  integration_test:\n    sdk: flutter\nflutter:\n  config:\n    enable-swift-package-manager: false\n",
                 "ios/Podfile": "platform :ios, '14.0'\nflutter_install_all_ios_pods\n",
                 "ios/Runner.xcodeproj/project.pbxproj": "IPHONEOS_DEPLOYMENT_TARGET = 14.0;\n"
                 "PRODUCT_BUNDLE_IDENTIFIER = io.github.caolib.kira;\n"
                 "PRODUCT_BUNDLE_IDENTIFIER = io.github.caolib.kira.RunnerTests;\n"
                 "PrivacyInfo.xcprivacy\nDebug.xcconfig\nRelease.xcconfig\nProfile.xcconfig\n",
                 "ios/Runner/Base.lproj/Main.storyboard": "<document/>\n",
                 "ios/Runner/Base.lproj/LaunchScreen.storyboard": "<document/>\n"}
        for configuration in ("Debug", "Release", "Profile"):
            files[f"ios/Flutter/{configuration}.xcconfig"] = (
                f'#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.{configuration.lower()}.xcconfig"\n'
                '#include "Generated.xcconfig"\n')
        for name, content in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        (self.root / "ios/Runner/Info.plist").write_bytes(plistlib.dumps({
            "UIApplicationSceneManifest": {}, "BGTaskSchedulerPermittedIdentifiers": ["com.pravera.flutter_foreground_task.refresh"],
            "UIBackgroundModes": ["fetch"], "NSPhotoLibraryAddUsageDescription": "save", "NSLocalNetworkUsageDescription": "proxy"}))
        (self.root / "ios/Runner/PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps({
            "NSPrivacyTracking": False, "NSPrivacyAccessedAPITypes": [
                {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                 "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}]}))

    def test_configuration_contracts_and_private_prefs_reason(self):
        self.create_config()
        ci.check_config(self.root)
        privacy = self.root / "ios/Runner/PrivacyInfo.xcprivacy"
        content = plistlib.loads(privacy.read_bytes())
        content["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"] = ["different-reviewed-reason"]
        del content["NSPrivacyTracking"]  # Apple allows this optional key to be absent.
        privacy.write_bytes(plistlib.dumps(content))
        ci.check_config(self.root)  # CI validates resources; does not invent reason-code semantics.

    def test_configuration_requires_pin_pods_profile_and_startup(self):
        for path, content, message in ((".flutter-version", "3.41.0", "Flutter 3.44.2"),
                                       ("ios/Podfile", "platform :ios, '13.0'", "iOS 14.0"),
                                       ("ios/Flutter/Profile.xcconfig", '#include "Generated.xcconfig"', "Profile")):
            with self.subTest(path=path):
                self.create_config()
                (self.root / path).write_text(content, encoding="utf-8")
                with self.assertRaisesRegex(ValueError, message):
                    ci.check_config(self.root)
        self.create_config()
        (self.root / "integration_test/ios_startup_test.dart").unlink()
        with self.assertRaisesRegex(ValueError, "startup integration test"):
            ci.check_config(self.root)

    def test_logged_command_redacts_secret_and_encoded_define(self):
        secret = "sensitive-example-value"
        environment = dict(os.environ, COPY_AUTH_KEY=secret)
        variants = ci.secret_variants(environment)
        code = "import os,base64; k=os.environ['COPY_AUTH_KEY']; print(k); print(base64.b64encode(('COPY_AUTH_KEY='+k).encode()).decode())"
        log = self.root / "command.log"
        result = ci.run_logged([sys.executable, "-I", "-c", code], log, 5, environment)
        self.assertEqual(result, 0)
        content = log.read_text(encoding="utf-8")
        self.assertIn("***", content)
        for value in variants:
            self.assertNotIn(value, content)

    def test_logged_command_preserves_failure_and_bounds_timeout(self):
        log = self.root / "command.log"
        self.assertEqual(ci.run_logged([sys.executable, "-I", "-c", "import sys; print('failed'); sys.exit(7)"], log, 5), 7)
        start = time.monotonic()
        self.assertEqual(ci.run_logged([sys.executable, "-I", "-c", "import time; time.sleep(30)"], log, 0.3), 124)
        self.assertLess(time.monotonic() - start, 10)
        self.assertIn("timed out", log.read_text(encoding="utf-8"))

    def environment(self, skip=False):
        return {"GITHUB_REPOSITORY": "test/repo", "GITHUB_SHA": "0" * 40, "GITHUB_RUN_ID": "123",
                "GITHUB_RUN_ATTEMPT": "2", "SKIP_TESTS": str(skip).lower(), "VERIFY_ANALYSIS": "success",
                "VERIFY_SCRIPTS": "success", "FLUTTER_TESTS": "skipped" if skip else "success",
                "SIMULATOR_TEST": "skipped" if skip else "success", "NOTE": "$(touch unexpected); `uname`\n'quoted'\n中文说明"}

    def test_notes_keep_note_as_text_and_distinguish_skips(self):
        for skip in (False, True):
            with self.subTest(skip=skip):
                environment = self.environment(skip)
                notes = ci.release_notes("1.7.7+656", "Flutter 3.44.2\nXcode 26.3\nCocoaPods 1.16.2",
                                         "Native lock generated; OrderedSet (6.0.3)", environment)
                self.assertIn(environment["NOTE"], notes)
                self.assertIn("https://github.com/test/repo/actions/runs/123", notes)
                self.assertIn("未签名", notes)
                self.assertIn("不能直接安装", notes)
                self.assertIn("重签", notes)
                if skip:
                    self.assertIn("未执行，不代表通过", notes)
                    self.assertNotIn("全量 Flutter 测试：通过", notes)
                else:
                    self.assertIn("全量 Flutter 测试：通过", notes)

    def test_failed_gates_never_generate_pass_notes(self):
        for key in ("VERIFY_ANALYSIS", "VERIFY_SCRIPTS", "FLUTTER_TESTS", "SIMULATOR_TEST"):
            with self.subTest(key=key):
                environment = self.environment()
                environment[key] = "failure"
                with self.assertRaises(ValueError):
                    ci.release_notes("1.7.7+656", "Flutter 3.44.2 Xcode 26.3", "lock", environment)
        environment = self.environment(True)
        environment["FLUTTER_TESTS"] = "success"
        with self.assertRaisesRegex(ValueError, "test status"):
            ci.release_notes("1.7.7+656", "Flutter 3.44.2 Xcode 26.3", "lock", environment)

    def test_native_lock_first_generation_records_ordered_set_without_guessing(self):
        lock = self.root / "Podfile.lock"
        lock.write_text("PODS:\n  - OrderedSet (6.0.3)\n  - SomePlugin (1.0.0)\n", encoding="utf-8")
        output = self.root / "native-lock.txt"
        lines = ci.native_lock_report(lock, False, output)
        self.assertIn("not yet locked in source control", lines[0])
        self.assertIn("OrderedSet (6.0.3)", output.read_text(encoding="utf-8"))
        self.assertIn("deployment install enforced", ci.native_lock_report(lock, True, output)[0])
        initial = self.root / "Podfile.initial.lock"
        initial.write_bytes(lock.read_bytes())
        lock.write_text("PODS:\n  - OrderedSet (7.0.0)\n", encoding="utf-8")
        report = ci.native_lock_report(lock, False, output, initial)
        self.assertIn("YES; compare retained snapshots", report[-2])
        self.assertIn("OrderedSet (6.0.3) -> OrderedSet (7.0.0)", report[-1])


class IosSimulatorTest(unittest.TestCase):
    def listing(self):
        ids = ["com.apple.CoreSimulator.SimRuntime.iOS-18-5", "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
               "com.apple.CoreSimulator.SimRuntime.iOS-27-0"]
        result = {"runtimes": [], "devices": {}}
        for index, (identifier, version) in enumerate(zip(ids, ("18.5", "26.2", "27.0"))):
            result["runtimes"].append({"identifier": identifier, "version": version, "name": "iOS " + version,
                                       "isAvailable": True})
            result["devices"][identifier] = [{"name": "iPhone Dynamic", "udid": f"0000000{index}-0000-0000-0000-000000000000",
                                                "isAvailable": True, "state": "Shutdown"}]
        return result

    def test_dynamic_selection_prefers_installed_ios26_iphone(self):
        listing = self.listing()
        selected = simulator.select_simulator(listing)
        self.assertEqual(selected["version"], "26.2")
        listing["devices"][selected["runtime"]].insert(0, {"name": "iPad", "udid": "unsafe", "isAvailable": True})
        self.assertEqual(simulator.select_simulator(listing)["udid"], selected["udid"])

    def test_unavailable_or_missing_runtime_fails_not_a_false_pass(self):
        listing = self.listing()
        for runtime in listing["runtimes"]:
            runtime["isAvailable"] = False
        with self.assertRaisesRegex(ValueError, "No available installed"):
            simulator.select_simulator(listing)
        listing = self.listing()
        for devices in listing["devices"].values():
            devices[0]["udid"] = "shell;injection"
        with self.assertRaises(ValueError):
            simulator.select_simulator(listing)

    def test_smoke_uses_bounded_bootstatus_and_flutter_integration_test(self):
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            pubspec.write_bytes(b"name: kira\nversion: 1.7.8-beta.2+657\n")
            with patch.object(simulator, "list_simulators", return_value=self.listing()), \
                    patch.object(simulator.ci, "run_logged", return_value=0) as run:
                self.assertEqual(simulator.smoke(directory, 240, 1800, pubspec), 0)
            commands = [call.args[0] for call in run.call_args_list]
            self.assertEqual(commands[0][:3], ["xcrun", "simctl", "boot"])
            self.assertEqual(commands[1][:3], ["xcrun", "simctl", "bootstatus"])
            self.assertEqual(run.call_args_list[1].args[2], 240)
            self.assertEqual(commands[2][:4], ["flutter", "test", "--no-pub", "integration_test/ios_startup_test.dart"])
            self.assertIn("expanded", commands[2])
            self.assertFalse(any(word.startswith(("--build-name", "--build-number")) for word in commands[2]))
            self.assertEqual(pubspec.read_bytes(), b"name: kira\nversion: 1.7.8-beta.2+657\n")
            self.assertNotIn("launch", [word for command in commands for word in command])

    def test_prerelease_normalizes_only_runtime_version_and_restores_after_success_or_failure(self):
        originals = (b'name: kira\nversion: "1.7.8-beta.2+657" # original comment\nother: preserved\n',
                     b"name: kira\r\nversion: 1.7.8-beta.2+657\r\nother: preserved\r\n")
        for original in originals:
            for status in (0, 7, 124):
                with self.subTest(original=original, status=status), tempfile.TemporaryDirectory() as directory:
                    pubspec = Path(directory) / "pubspec.yaml"
                    pubspec.write_bytes(original)

                    def test_command(command, log, timeout):
                        normalized = pubspec.read_bytes()
                        self.assertIn(b"version: 1.7.8+657", normalized)
                        self.assertNotIn(b"beta.2", normalized)
                        self.assertIn(b"other: preserved", normalized)
                        self.assertEqual(simulator.package.version_parts(simulator.package.pubspec_version(pubspec)),
                                         ("1.7.8", "657"))
                        self.assertEqual(command, ["flutter", "test", "--no-pub"])
                        return status

                    with patch.object(simulator.ci, "run_logged", side_effect=test_command):
                        self.assertEqual(simulator.run_versioned_flutter_test(["flutter", "test", "--no-pub"],
                                                                            Path(directory) / "test.log", 10, pubspec), status)
                    self.assertEqual(pubspec.read_bytes(), original)

    def test_prerelease_restores_original_bytes_when_test_process_start_throws(self):
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            original = b"name: kira\nversion: 1.7.8-beta.2+657\n"
            pubspec.write_bytes(original)

            def start_fails(*args):
                self.assertIn(b"version: 1.7.8+657", pubspec.read_bytes())
                raise OSError("test process failed to start")

            with patch.object(simulator.ci, "run_logged", side_effect=start_fails):
                with self.assertRaisesRegex(OSError, "failed to start"):
                    simulator.run_versioned_flutter_test(["flutter", "test"], Path(directory) / "test.log", 10, pubspec)
            self.assertEqual(pubspec.read_bytes(), original)

    def test_pubspec_restore_write_failure_propagates_and_blocks_success(self):
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            pubspec.write_bytes(b"name: kira\nversion: 1.7.8-beta.2+657\n")
            write_bytes = Path.write_bytes
            calls = 0

            def fail_restore(path, content):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("restoration write failed")
                return write_bytes(path, content)

            with patch.object(simulator.Path, "write_bytes", new=fail_restore), \
                    patch.object(simulator.ci, "run_logged", return_value=0):
                with self.assertRaisesRegex(OSError, "restoration write failed"):
                    simulator.run_versioned_flutter_test(["flutter", "test"], Path(directory) / "test.log", 10, pubspec)

    def test_diagnostics_snapshot_simulator_results_before_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            result = home / "Library/Developer/Xcode/DerivedData/Runner-test/Logs/Test/Startup.xcresult"
            result.mkdir(parents=True)
            (result / "Data").write_text("simulator-result", encoding="utf-8")
            output = root / "diagnostics"
            output.mkdir()
            (output / "selected-simulator.json").write_text('{"udid":"selected-id"}', encoding="utf-8")
            with patch.object(simulator.Path, "home", return_value=home), \
                    patch.object(simulator.ci, "run_logged", return_value=0) as run:
                simulator.diagnostics(output)
            self.assertEqual(run.call_args_list[1].args[0][3], "selected-id")
            self.assertTrue(any((output / "simulator-xcresult").rglob("Data")))
            report = (output / "simulator-diagnostics.json").read_text(encoding="utf-8")
            self.assertIn("Not retained", report)

    def test_boot_failure_or_flutter_failure_propagates(self):
        for statuses, expected_calls in (([124], 1), ([0, 124], 2), ([0, 0, 7], 3)):
            with self.subTest(statuses=statuses), tempfile.TemporaryDirectory() as directory:
                pubspec = Path(directory) / "pubspec.yaml"
                pubspec.write_bytes(b"name: kira\nversion: 1.7.8-beta.2+657\n")
                with patch.object(simulator, "list_simulators", return_value=self.listing()), \
                        patch.object(simulator.ci, "run_logged", side_effect=statuses) as run:
                    self.assertEqual(simulator.smoke(directory, 240, 1800, pubspec), statuses[-1])
                self.assertEqual(run.call_count, expected_calls)


class IosWorkflowTest(unittest.TestCase):
    def setUp(self):
        # BaseLoader deliberately keeps "on" as a string rather than YAML 1.1's boolean.
        self.workflow = yaml.load((support.ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
        self.jobs = self.workflow["jobs"]

    def step(self, job, identifier):
        return next(step for step in self.jobs[job]["steps"] if step.get("id") == identifier)

    def test_dispatch_only_defaults_fixed_concurrency_and_permissions(self):
        self.assertEqual(set(self.workflow["on"]), {"workflow_dispatch"})
        inputs = self.workflow["on"]["workflow_dispatch"]["inputs"]
        self.assertEqual(set(inputs), {"note", "skip_tests"})
        self.assertEqual(inputs["note"]["type"], "string")
        self.assertEqual(inputs["skip_tests"]["type"], "boolean")
        self.assertEqual(inputs["skip_tests"]["default"], "false")
        self.assertEqual(self.workflow["concurrency"], {"group": "ios-build", "cancel-in-progress": "false"})
        self.assertEqual(self.workflow["permissions"], {"contents": "read"})
        self.assertEqual(self.jobs["publish"]["permissions"], {"contents": "write"})
        self.assertNotIn("permissions", self.jobs["verify"])
        self.assertNotIn("permissions", self.jobs["build-ios"])

    def test_three_jobs_fail_closed_and_tests_only_step_skipped(self):
        self.assertEqual(set(self.jobs), {"verify", "build-ios", "publish"})
        self.assertEqual(self.jobs["build-ios"]["needs"], "verify")
        self.assertEqual(self.jobs["publish"]["needs"], ["verify", "build-ios"])
        self.assertIn("needs.verify.result == 'success'", self.jobs["publish"]["if"])
        self.assertIn("needs.build-ios.result == 'success'", self.jobs["publish"]["if"])
        self.assertNotIn("always", self.jobs["publish"]["if"])
        self.assertNotIn("if", self.jobs["verify"])
        self.assertEqual(self.step("verify", "tests")["if"], "${{ !inputs.skip_tests }}")
        self.assertIn("--concurrency 4", self.step("verify", "tests")["run"])
        self.assertNotIn("skip_tests", self.step("verify", "analyze").get("if", ""))
        self.assertNotIn("if", self.step("verify", "contracts"))
        self.assertEqual(self.step("build-ios", "smoke")["if"], "${{ !inputs.skip_tests }}")
        for identifier in ("archive", "package"):
            self.assertNotIn("skip_tests", self.step("build-ios", identifier).get("if", ""))
            self.assertNotIn("continue-on-error", self.step("build-ios", identifier))

    def test_pinned_tools_locked_pubdeps_and_production_target(self):
        self.assertEqual(self.jobs["build-ios"]["runs-on"], "macos-15")
        self.assertEqual(self.jobs["build-ios"]["env"]["DEVELOPER_DIR"], "/Applications/Xcode_26.3.app/Contents/Developer")
        for job in ("verify", "build-ios"):
            self.assertTrue(any(step.get("uses") == "./.github/actions/setup-flutter" for step in self.jobs[job]["steps"]))
        action = (support.ROOT / ".github/actions/setup-flutter/action.yml").read_text(encoding="utf-8")
        self.assertIn("flutter pub get --enforce-lockfile", action)
        self.assertIn("git diff --exit-code -- pubspec.lock", action)
        archive = self.step("build-ios", "archive")
        self.assertIn("flutter build ipa --release --no-codesign --target lib/main.dart --no-pub", archive["run"])
        self.assertEqual(archive["env"]["COPY_AUTH_KEY"], "${{ secrets.COPY_AUTH_KEY }}")
        self.assertNotIn("${{ secrets.COPY_AUTH_KEY }}", archive["run"])
        lock = self.step("build-ios", "lock")["run"]
        self.assertIn("pod install --deployment --project-directory=ios", lock)
        self.assertIn("pod install --project-directory=ios", lock)
        self.assertIn("git diff --exit-code -- ios/Podfile.lock", lock)

    def test_prerelease_bundle_parameters_and_pubspec_restoration_contract(self):
        resolver = self.step("build-ios", "bundle-version")
        self.assertIn("scripts/package_ios.py build-version --field name", resolver["run"])
        self.assertIn("scripts/package_ios.py build-version --field number", resolver["run"])
        prepare = next(step for step in self.jobs["build-ios"]["steps"]
                       if step.get("name") == "Prepare Flutter iOS configuration and engine")
        archive = self.step("build-ios", "archive")
        for step in (prepare, archive):
            self.assertEqual(step["env"]["BUILD_NAME"], "${{ steps.bundle-version.outputs.name }}")
            self.assertEqual(step["env"]["BUILD_NUMBER"], "${{ steps.bundle-version.outputs.number }}")
            self.assertIn('"--build-name=$BUILD_NAME" "--build-number=$BUILD_NUMBER"', step["run"])
        restore = next(step for step in self.jobs["build-ios"]["steps"]
                       if step.get("name") == "Require exact source version restoration after simulator smoke")
        self.assertIn("always()", restore["if"])
        self.assertIn("git diff --exit-code -- pubspec.yaml pubspec.lock", restore["run"])
        self.assertIn("git diff --exit-code -- pubspec.yaml pubspec.lock", archive["run"])

    def test_diagnostic_snapshot_precedes_sensitive_release_build(self):
        steps = self.jobs["build-ios"]["steps"]
        diagnostic_index = next(index for index, step in enumerate(steps)
                                if step.get("run") == "python3 -I scripts/ios_simulator.py diagnostics")
        archive_index = steps.index(self.step("build-ios", "archive"))
        self.assertLess(diagnostic_index, archive_index)
        uploads = [step for step in steps if step.get("uses", "").startswith("actions/upload-artifact")]
        for step in uploads:
            self.assertNotIn("build/ios/**", step["with"]["path"])
            self.assertNotIn("DerivedData", step["with"]["path"])

    def test_root_commands_diagnostics_only_always_and_no_bare_app_transfer(self):
        self.assertEqual(self.workflow["defaults"]["run"]["working-directory"], ".")
        for job in self.jobs.values():
            for step in job["steps"]:
                if "run" in step:
                    self.assertNotIn("cd ios", step["run"])
                    if "| tee" in step["run"]:
                        self.assertIn("pipefail", step["run"])
                if step.get("uses", "").startswith("actions/upload-artifact"):
                    self.assertNotIn(".app", step["with"]["path"])
                    if "diagnostic" in step["with"]["name"] or "provenance" in step["with"]["name"] or "verify" in step["with"]["name"]:
                        self.assertIn("always()", step["if"])
        self.assertNotIn("release.json", (support.ROOT / "scripts/publish_ios_release.sh").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
