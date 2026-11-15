# Run from the repository root: python -I -m unittest discover -s test/scripts -p '*ios*_test.py'
import copy
import importlib.util
import plistlib
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path
from unittest.mock import patch


SUPPORT_SPEC = importlib.util.spec_from_file_location("ios_test_support", Path(__file__).with_name("ios_test_support.py"))
support = importlib.util.module_from_spec(SUPPORT_SPEC)
SUPPORT_SPEC.loader.exec_module(support)
package = support.load_script("package_ios.py", "package_ios")


class PackageIosTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.version = "1.7.7+656"
        self.ipa = self.directory / f"kira-{self.version}-ios-unsigned.ipa"
        self.entries = support.fixture_entries(self.version)

    def write(self, entries=None, extra_entries=()):
        return support.write_ipa(self.ipa, self.entries if entries is None else entries, extra_entries=extra_entries)

    def expect_invalid(self, message):
        with self.assertRaisesRegex(ValueError, message):
            package.validate_release(self.directory)

    def test_device_release_and_hash_report(self):
        self.write()
        report = package.validate_release(self.directory, self.version)
        self.assertEqual(report["signing"], "unsigned")
        self.assertEqual(report["architecture"], "device arm64")
        self.assertEqual(report["macho_binaries"], 4)
        self.assertEqual(report["bundle_id"], "io.github.caolib.kira")
        self.assertEqual(len(report["sha256"]), 64)

    def test_complete_prerelease_pubspec_version_is_kept_in_filename(self):
        self.version = "1.7.8-beta.2+657"
        self.ipa = self.directory / f"kira-{self.version}-ios-unsigned.ipa"
        support.write_ipa(self.ipa, version=self.version)
        self.assertEqual(package.validate_release(self.directory)["version"], self.version)
        pubspec = self.directory / "pubspec.yaml"
        pubspec.write_text(f"name: kira\nversion: '{self.version}' # full version\n", encoding="utf-8")
        self.assertEqual(package.pubspec_version(pubspec), self.version)

    def test_numeric_bundle_version_cli_matches_prerelease_package_expectations(self):
        version = "1.7.8-beta.2+657"
        pubspec = self.directory / "pubspec.yaml"
        original = f"name: kira\nversion: '{version}' # retain full version\n".encode()
        pubspec.write_bytes(original)
        expected_name, expected_number = package.version_parts(version)
        self.assertEqual((expected_name, expected_number), ("1.7.8", "657"))
        resolved = {}
        for field, expected in (("name", expected_name), ("number", expected_number)):
            result = subprocess.run([sys.executable, "-I", str(support.ROOT / "scripts/package_ios.py"),
                                     "build-version", "--pubspec", str(pubspec), "--field", field],
                                    cwd=support.ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), expected)
            resolved[field] = result.stdout.strip()
        self.assertEqual(pubspec.read_bytes(), original)
        entries = support.fixture_entries(version)
        support.update_info(entries, CFBundleShortVersionString=resolved["name"], CFBundleVersion=resolved["number"])
        ipa = self.directory / f"kira-{version}-ios-unsigned.ipa"
        support.write_ipa(ipa, entries, version=version)
        self.assertEqual(package.validate_release(self.directory, version)["version"], version)

    def test_arm64_simulator_is_rejected_by_platform_not_cpu(self):
        for name in ("Runner", "Frameworks/Flutter.framework/Flutter", "Frameworks/App.framework/App",
                     "Frameworks/ExamplePlugin.framework/ExamplePlugin"):
            with self.subTest(name=name):
                entries = copy.deepcopy(self.entries)
                mode, _ = entries[name]
                entries[name] = mode, support.macho(platform=7, filetype=2 if name == "Runner" else 6)
                self.write(entries)
                self.expect_invalid("LC_BUILD_VERSION device iOS")

    def test_other_architecture_and_missing_build_version_are_rejected(self):
        for content, reason in ((support.macho(cpu=0x01000007), "device arm64"),
                                (struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 0, 0, 0, 0), "LC_BUILD_VERSION")):
            with self.subTest(reason=reason):
                self.entries["Runner"] = stat.S_IFREG | 0o755, content
                self.write()
                self.expect_invalid(reason)

    def test_fat_binary_checks_every_slice(self):
        self.entries["Runner"] = stat.S_IFREG | 0o755, support.fat_macho([support.macho(), support.macho(platform=7)])
        self.write()
        self.expect_invalid("device iOS")
        self.entries["Runner"] = stat.S_IFREG | 0o755, support.fat_macho([support.macho(), support.macho()])
        self.write()
        self.assertEqual(package.validate_release(self.directory)["signing"], "unsigned")

    def test_malformed_macho_and_newer_os_fail(self):
        malformed = bytearray(support.macho())
        struct.pack_into("<I", malformed, 36, 0xFFFF)
        for content, message in ((bytes(malformed), "command size"), (support.macho(minimum=0x000F0000), "newer than")):
            with self.subTest(message=message):
                self.entries["Runner"] = stat.S_IFREG | 0o755, content
                self.write()
                self.expect_invalid(message)

    def test_identity_version_minimum_and_device_platform(self):
        cases = [("CFBundleIdentifier", "com.example.kira", "bundle identifier"),
                 ("CFBundleShortVersionString", "9.9.9", "version differs"),
                 ("CFBundleVersion", "1", "build number differs"),
                 ("MinimumOSVersion", "13.0", "must be 14.0"),
                 ("MinimumOSVersion", "15.0", "must be 14.0"),
                 ("CFBundleSupportedPlatforms", ["iPhoneSimulator"], "device bundle"),
                 ("CFBundleExecutable", "../../outside", "executable name")]
        for key, value, message in cases:
            with self.subTest(key=key):
                entries = copy.deepcopy(self.entries)
                support.update_info(entries, **{key: value})
                self.write(entries)
                self.expect_invalid(message)

    def test_executable_modes_and_apple_signed_main_are_rejected(self):
        for name in ("Runner", "Frameworks/Flutter.framework/Flutter"):
            with self.subTest(name=name):
                entries = copy.deepcopy(self.entries)
                entries[name] = stat.S_IFREG | 0o644, entries[name][1]
                self.write(entries)
                self.expect_invalid("permission was lost")
        entries = copy.deepcopy(self.entries)
        entries["Runner"] = stat.S_IFREG | 0o755, support.signed_macho(adhoc=False, cms=True)
        self.write(entries)
        self.expect_invalid("CMS/Apple identity signature")
        entries = copy.deepcopy(self.entries)
        entries["embedded.mobileprovision"] = stat.S_IFREG | 0o644, b"signing profile"
        self.write(entries)
        self.expect_invalid("signing material")

    def test_confirmed_adhoc_main_is_allowed_but_identity_and_unknown_signatures_fail(self):
        self.entries["Runner"] = stat.S_IFREG | 0o755, support.signed_macho()
        self.write()
        report = package.validate_release(self.directory)
        self.assertEqual(report["signing"], "unsigned")
        self.assertIn("ad-hoc only", report["main_signature"])
        self.entries["Runner"] = stat.S_IFREG | 0o755, support.signed_macho(version=0x20400)
        self.write()
        self.assertIn("ad-hoc only", package.validate_release(self.directory)["main_signature"])
        for content, message in ((support.signed_macho(adhoc=False), "identity signature"),
                                 (support.signed_macho(cms=True), "CMS/Apple identity"),
                                 (support.signed_macho(version=0x20400, team=True), "must not declare an Apple team"),
                                 (support.signed_macho(malformed=True), "malformed embedded signature"),
                                 (support.macho(signed=True), "LC_CODE_SIGNATURE bounds")):
            with self.subTest(message=message):
                self.entries["Runner"] = stat.S_IFREG | 0o755, content
                self.write()
                self.expect_invalid(message)

    def test_adhoc_page_hash_corruption_and_unknown_slot_fail_closed(self):
        data = bytearray(support.signed_macho())
        data[-1] ^= 1
        self.entries["Runner"] = stat.S_IFREG | 0o755, bytes(data)
        self.write()
        self.expect_invalid("CodeDirectory page hash")
        data = bytearray(support.signed_macho())
        signature_offset = struct.unpack_from("<I", data, 64)[0]
        struct.pack_into(">I", data, signature_offset + 12, 0x10002)
        self.entries["Runner"] = stat.S_IFREG | 0o755, bytes(data)
        self.write()
        self.expect_invalid("Unknown embedded signature slot")
        data = bytearray(support.signed_macho())
        signature_offset = struct.unpack_from("<I", data, 64)[0]
        directory_offset = struct.unpack_from(">I", data, signature_offset + 16)[0]
        struct.pack_into(">I", data, signature_offset + directory_offset + 8, 0x20700)
        self.entries["Runner"] = stat.S_IFREG | 0o755, bytes(data)
        self.write()
        self.expect_invalid("Unknown/truncated CodeDirectory version")

    def test_missing_aot_resources_and_debug_assets(self):
        for name in ("Frameworks/App.framework/App", "Frameworks/Flutter.framework/Flutter",
                     "Frameworks/App.framework/flutter_assets/AssetManifest.bin", "Assets.car",
                     "AppIcon-160x60@2x.png", "Base.lproj/Main.storyboardc", "PrivacyInfo.xcprivacy"):
            with self.subTest(name=name):
                entries = copy.deepcopy(self.entries)
                del entries[name]
                self.write(entries)
                with self.assertRaises(ValueError):
                    package.validate_release(self.directory)
        entries = copy.deepcopy(self.entries)
        entries["Frameworks/App.framework/flutter_assets/kernel_blob.bin"] = stat.S_IFREG | 0o644, b"JIT"
        self.write(entries)
        self.expect_invalid("Debug/JIT")

    def test_missing_alternate_icon_and_invalid_privacy_plist(self):
        info = plistlib.loads(self.entries["Info.plist"][1])
        del info["CFBundleIcons"]["CFBundleAlternateIcons"]
        self.entries["Info.plist"] = stat.S_IFREG | 0o644, plistlib.dumps(info)
        self.write()
        self.expect_invalid("alternate icon")
        self.entries = support.fixture_entries()
        self.entries["PrivacyInfo.xcprivacy"] = stat.S_IFREG | 0o644, b"not a plist"
        self.write()
        self.expect_invalid("Invalid bundle plist")

    def test_missing_extra_and_bad_checksums_fail(self):
        self.expect_invalid("exactly one IPA, found 0")
        self.write()
        other = self.directory / "kira-1.7.8+657-ios-unsigned.ipa"
        support.write_ipa(other, version="1.7.8+657")
        self.expect_invalid("exactly one IPA, found 2")
        other.unlink()
        other.with_name(other.name + ".sha256").unlink()
        checksum = self.ipa.with_name(self.ipa.name + ".sha256")
        checksum.unlink()
        self.expect_invalid("matching SHA-256")
        checksum.write_text("0" * 64 + "  " + self.ipa.name + "\n", encoding="utf-8")
        self.expect_invalid("SHA-256 mismatch")
        checksum.write_text("0" * 64 + "  ../../other.ipa\n", encoding="utf-8")
        self.expect_invalid("Invalid SHA-256 file")

    def test_file_version_and_corrupt_zip_are_rejected(self):
        self.write()
        with self.assertRaisesRegex(ValueError, "filename differs"):
            package.validate_release(self.directory, "1.7.8+657")
        self.ipa.write_bytes(b"not a zip")
        support.checksum(self.ipa)
        self.expect_invalid("Invalid IPA")

    def test_symlinks_and_inventory_are_preserved(self):
        self.write()
        with zipfile.ZipFile(self.ipa) as archive:
            bundle = package.ZipBundle(archive)
            self.assertEqual(bundle.read("Frameworks/ExamplePlugin.framework/Info.link"),
                             self.entries["Frameworks/ExamplePlugin.framework/Info.plist"][1])
            inventory = bundle.inventory()
        package.inspect_ipa(self.ipa, self.version, inventory)
        inventory["Runner"] = "different"
        with self.assertRaisesRegex(ValueError, "permissions differ"):
            package.inspect_ipa(self.ipa, self.version, inventory)

    def test_versioned_framework_directory_symlinks_are_preserved(self):
        root = "Frameworks/ExamplePlugin.framework/"
        self.entries.pop(root + "Info.link")
        executable = self.entries.pop(root + "ExamplePlugin")
        self.entries[root + "Versions"] = stat.S_IFDIR | 0o755, b""
        self.entries[root + "Versions/A"] = stat.S_IFDIR | 0o755, b""
        self.entries[root + "Versions/A/ExamplePlugin"] = executable
        self.entries[root + "Versions/Current"] = stat.S_IFLNK | 0o777, b"A"
        self.entries[root + "ExamplePlugin"] = stat.S_IFLNK | 0o777, b"Versions/Current/ExamplePlugin"
        self.write()
        self.assertEqual(package.validate_release(self.directory)["signing"], "unsigned")
        with zipfile.ZipFile(self.ipa) as archive:
            bundle = package.ZipBundle(archive)
            self.assertEqual(bundle.read(root + "ExamplePlugin"), executable[1])

    def test_unfamiliar_nested_framework_macho_also_checks_platform(self):
        self.entries["Frameworks/Plugin.framework/NestedBinary"] = stat.S_IFREG | 0o755, support.macho(platform=7, filetype=6)
        self.write()
        self.expect_invalid("device iOS")

    def test_escaping_and_cyclic_symlinks_fail(self):
        for target, reason in ((b"../../../outside", "escapes"), (b"/absolute", "Unsafe IPA symlink"),
                               (b"Info.link", "Cyclic"), (b"missing", "Missing IPA symlink target")):
            with self.subTest(target=target):
                entries = copy.deepcopy(self.entries)
                entries["Frameworks/ExamplePlugin.framework/Info.link"] = stat.S_IFLNK | 0o777, target
                self.write(entries)
                self.expect_invalid(reason)

    def test_unsafe_paths_duplicate_entries_and_missing_unix_metadata(self):
        for name in ("Payload/Runner.app/../../bad", "/absolute", "Payload/Other.app/Runner", "Payload/Runner.app/Runner"):
            with self.subTest(name=name), warnings.catch_warnings():
                warnings.filterwarnings("ignore", message="Duplicate name:", category=UserWarning)
                self.write(extra_entries=[(name, stat.S_IFREG | 0o644, b"unexpected")])
                with self.assertRaises(ValueError):
                    package.validate_release(self.directory)
        entries = copy.deepcopy(self.entries)
        entries["Runner"] = 0, entries["Runner"][1]
        self.write(entries)
        self.expect_invalid("Unix file metadata")

    def test_cli_inspection_and_non_macos_packaging_guard(self):
        self.write()
        result = subprocess.run([sys.executable, "-I", str(support.ROOT / "scripts/package_ios.py"),
                                 "verify-release", "--artifact-dir", str(self.directory), "--print-version"],
                                cwd=support.ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.version)
        with patch.object(package.sys, "platform", "win32"):
            with self.assertRaisesRegex(ValueError, "requires macOS"):
                package.package_archive("missing", "missing", self.directory)


if __name__ == "__main__":
    unittest.main()
