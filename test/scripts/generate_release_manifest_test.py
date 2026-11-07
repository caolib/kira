# 在仓库根目录执行：python -I -m unittest discover -s test/scripts -p 'generate_release_manifest_test.py'
import copy
import hashlib
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/generate_release_manifest.py"
SPEC = importlib.util.spec_from_file_location("release_manifest", SCRIPT)
manifest_script = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manifest_script)


class ReleaseManifestTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = "test/repo"
        self.tag = "v1.7.6"
        self.version = "1.7.6"
        self.build = 629
        self.pubspec = self.root / "pubspec.yaml"
        self.pubspec.write_text("name: kira\nversion: 1.7.6+629\n", encoding="utf-8")
        self.notes = self.root / "notes.md"
        self.notes.write_text('- 修复 "下载"\n- 路径 C:\\资料\n', encoding="utf-8")
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()
        self.payloads = {
            name: f"signed installer: {name}\n".encode()
            for name in manifest_script.expected_installers(self.version, self.build)
        }
        for name, payload in self.payloads.items():
            (self.artifacts / name).write_bytes(payload)
        self.release = {
            "tag_name": self.tag,
            "name": f"App {self.tag}",
            "body": self.notes.read_text(encoding="utf-8"),
            "html_url": f"https://github.com/{self.repo}/releases/tag/{self.tag}",
            "published_at": "2026-11-07T20:30:00Z",
            "draft": False,
            "prerelease": False,
            "assets": [
                {
                    "name": name,
                    "state": "uploaded",
                    "size": len(payload),
                    "browser_download_url": f"https://github.com/{self.repo}/releases/download/{self.tag}/{name}",
                    "digest": f"sha256:{hashlib.sha256(payload).hexdigest()}",
                }
                for name, payload in self.payloads.items()
            ],
        }
        self.output = self.root / "output/release.json"

    def build_manifest(self):
        return manifest_script.build_manifest(
            self.release, self.repo, self.tag, self.version, self.build,
        )

    def create_release(self):
        manifest_script.create_release(
            self.repo, self.tag, self.pubspec, self.artifacts, self.notes,
        )

    def publish_manifest(self):
        manifest_script.publish_manifest(self.repo, self.tag, self.pubspec, self.output)

    def mock_download(self, *args):
        self.assertEqual(args[:3], ("release", "download", self.tag))
        self.assertIn(f"--repo={self.repo}", args)
        name = args[args.index("--pattern") + 1]
        directory = Path(args[args.index("--dir") + 1])
        self.assertEqual(list(directory.iterdir()), [])
        (directory / name).write_bytes(self.payloads[name])

    def add_existing_manifest(self, data):
        payload = json.dumps(data, ensure_ascii=False, sort_keys=True).encode("utf-8")
        self.payloads["release.json"] = payload
        self.release["assets"].append({
            "name": "release.json",
            "state": "uploaded",
            "size": len(payload),
        })

    def test_manifest_has_all_installers_and_exact_metadata(self):
        with patch.object(manifest_script, "gh") as gh:
            data = self.build_manifest()
        gh.assert_not_called()
        self.assertEqual(data["schema_version"], 1)
        self.assertEqual(data["version"], self.version)
        self.assertEqual(data["build_number"], self.build)
        self.assertIsInstance(data["build_number"], int)
        self.assertEqual(data["tag"], self.tag)
        self.assertEqual(data["name"], self.release["name"])
        self.assertEqual(data["published_at"], "2026-11-08T04:30:00+08:00")
        self.assertEqual(data["release_notes"], self.release["body"])
        self.assertEqual(data["release_url"], self.release["html_url"])
        self.assertEqual(len(data["assets"]), 4)
        self.assertEqual(
            {(asset["platform"], asset["arch"]) for asset in data["assets"]},
            {("android", "arm64-v8a"), ("android", "armeabi-v7a"),
             ("android", "x86_64"), ("windows", "x64")},
        )
        for asset in data["assets"]:
            payload = self.payloads[asset["name"]]
            self.assertEqual(asset["size"], len(payload))
            self.assertEqual(asset["sha256"], hashlib.sha256(payload).hexdigest())
            self.assertEqual(asset["download_url"],
                             f"https://github.com/{self.repo}/releases/download/{self.tag}/{asset['name']}")

    def test_existing_manifest_is_not_an_installer(self):
        expected = self.build_manifest()
        self.add_existing_manifest(expected)
        self.assertEqual(self.build_manifest(), expected)

    def test_missing_installer_is_rejected_before_hashing(self):
        self.release["assets"].pop()
        with patch.object(manifest_script, "asset_sha256") as checksum:
            with self.assertRaisesRegex(ValueError, "Missing Release installers"):
                self.build_manifest()
        checksum.assert_not_called()

    def test_wrong_build_and_unexpected_assets_are_rejected(self):
        for name in ("kira-v1.7.6-630-arm64-v8a.apk", "checksums.txt", "../package.apk"):
            with self.subTest(name=name):
                release = copy.deepcopy(self.release)
                release["assets"][0]["name"] = name
                with self.assertRaisesRegex(ValueError, "Unexpected installer or version"):
                    manifest_script.build_manifest(release, self.repo, self.tag, self.version, self.build)

    def test_duplicate_assets_are_rejected(self):
        self.release["assets"].append(copy.deepcopy(self.release["assets"][0]))
        with self.assertRaisesRegex(ValueError, "Duplicate Release asset"):
            self.build_manifest()

    def test_incomplete_upload_and_invalid_size_are_rejected(self):
        for field, value in (("state", "new"), ("size", 0), ("size", True), ("size", "123")):
            with self.subTest(field=field, value=value):
                release = copy.deepcopy(self.release)
                release["assets"][0][field] = value
                with self.assertRaises(ValueError):
                    manifest_script.build_manifest(release, self.repo, self.tag, self.version, self.build)

    def test_draft_prerelease_and_wrong_tag_are_rejected(self):
        for field, value in (("draft", True), ("prerelease", True), ("tag_name", "CI")):
            with self.subTest(field=field):
                release = copy.deepcopy(self.release)
                release[field] = value
                with self.assertRaises(ValueError):
                    manifest_script.build_manifest(release, self.repo, self.tag, self.version, self.build)

    def test_noncanonical_download_and_release_urls_are_rejected(self):
        self.release["assets"][0]["browser_download_url"] = "https://mirror.example/package.apk"
        with self.assertRaisesRegex(ValueError, "Unexpected installer download URL"):
            self.build_manifest()
        self.release["html_url"] = "https://github.com/other/repo/releases/tag/v1.7.6"
        with self.assertRaisesRegex(ValueError, "Unexpected Release page URL"):
            self.build_manifest()

    def test_invalid_publication_time_is_rejected(self):
        for timestamp in (None, "invalid", "2026-11-07T20:30:00"):
            with self.subTest(timestamp=timestamp):
                self.release["published_at"] = timestamp
                with self.assertRaises(ValueError):
                    self.build_manifest()

    def test_missing_digest_downloads_remote_bytes_in_isolated_directory(self):
        asset = self.release["assets"][0]
        asset.pop("digest")
        # 本地重建包不能充当已经发布的包。
        (self.artifacts / asset["name"]).write_bytes(b"different rebuild")
        with patch.object(manifest_script, "gh", side_effect=self.mock_download) as gh:
            data = self.build_manifest()
        self.assertEqual(gh.call_count, 1)
        self.assertEqual(data["assets"][0]["sha256"],
                         hashlib.sha256(self.payloads[asset["name"]]).hexdigest())

    def test_fallback_download_size_mismatch_fails(self):
        asset = self.release["assets"][0]
        asset["digest"] = None
        asset["size"] += 1
        with patch.object(manifest_script, "gh", side_effect=self.mock_download):
            with self.assertRaisesRegex(ValueError, "Downloaded asset size mismatch"):
                self.build_manifest()

    def test_invalid_digest_is_not_silently_ignored(self):
        for digest in ("sha256:broken", "md5:" + "0" * 32, 123, ""):
            with self.subTest(digest=digest):
                self.release["assets"][0]["digest"] = digest
                with self.assertRaisesRegex(ValueError, "Invalid GitHub asset digest"):
                    self.build_manifest()

    def test_tag_and_pubspec_must_agree_before_api_calls(self):
        for tag in ("main", "v1.7.5", "v1.7.6-beta1"):
            with self.subTest(tag=tag):
                with patch.object(manifest_script, "fetch_release") as fetch:
                    with self.assertRaisesRegex(ValueError, "does not match pubspec"):
                        manifest_script.create_release(self.repo, tag, self.pubspec, self.artifacts, self.notes)
                fetch.assert_not_called()

    def test_pubspec_requires_one_version_and_build_number(self):
        for content in ("version: 1.7.6\n", "version: 1.7.6+629\nversion: 1.7.6+630\n"):
            with self.subTest(content=content):
                self.pubspec.write_text(content, encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "Expected one stable version"):
                    manifest_script.read_version(self.pubspec, self.tag)

    def test_create_uploads_all_installers_and_verifies_existing_tag(self):
        with patch.object(manifest_script, "fetch_release", side_effect=[None, self.release]):
            with patch.object(manifest_script, "gh") as gh:
                self.create_release()
        args = gh.call_args.args
        self.assertEqual(args[:3], ("release", "create", self.tag))
        self.assertEqual({Path(value).name for value in args[3:7]}, set(self.payloads))
        self.assertIn("--verify-tag", args)
        self.assertIn(f"--title=App {self.tag}", args)
        self.assertEqual(args[-2:], ("--notes-file", str(self.notes)))

    def test_retry_reuses_release_without_uploading_rebuilt_installers(self):
        for path in self.artifacts.iterdir():
            path.write_bytes(b"different rebuild")
        with patch.object(manifest_script, "fetch_release", return_value=self.release):
            with patch.object(manifest_script, "gh") as gh:
                self.create_release()
        gh.assert_not_called()

    def test_invalid_local_artifacts_fail_before_create(self):
        (self.artifacts / next(iter(self.payloads))).unlink()
        with patch.object(manifest_script, "fetch_release", return_value=None):
            with patch.object(manifest_script, "gh") as gh:
                with self.assertRaisesRegex(ValueError, "Build artifacts do not match"):
                    self.create_release()
        gh.assert_not_called()

    def test_empty_local_installer_fails_before_create(self):
        (self.artifacts / next(iter(self.payloads))).write_bytes(b"")
        with patch.object(manifest_script, "fetch_release", return_value=None):
            with patch.object(manifest_script, "gh") as gh:
                with self.assertRaisesRegex(ValueError, "non-empty files"):
                    self.create_release()
        gh.assert_not_called()

    def test_partial_existing_release_is_not_modified(self):
        self.release["assets"].pop()
        with patch.object(manifest_script, "fetch_release", return_value=self.release):
            with patch.object(manifest_script, "gh") as gh:
                with self.assertRaisesRegex(ValueError, "Missing Release installers"):
                    self.create_release()
        gh.assert_not_called()

    def test_create_failure_propagates(self):
        failure = subprocess.CalledProcessError(1, ["gh", "release", "create"])
        with patch.object(manifest_script, "fetch_release", return_value=None) as fetch:
            with patch.object(manifest_script, "gh", side_effect=failure):
                with self.assertRaises(subprocess.CalledProcessError):
                    self.create_release()
        self.assertEqual(fetch.call_count, 1)

    def test_publish_serializes_utf8_and_uploads_only_manifest(self):
        with patch.object(manifest_script, "fetch_release", return_value=self.release):
            with patch.object(manifest_script, "gh") as gh:
                self.publish_manifest()
        data = json.loads(self.output.read_text(encoding="utf-8"))
        self.assertEqual(data, self.build_manifest())
        self.assertIn("修复".encode("utf-8"), self.output.read_bytes())
        self.assertTrue(self.output.read_bytes().endswith(b"\n"))
        gh.assert_called_once_with("release", "upload", self.tag, str(self.output), f"--repo={self.repo}")

    def test_correct_existing_manifest_is_validated_then_skipped(self):
        self.add_existing_manifest(self.build_manifest())
        with patch.object(manifest_script, "fetch_release", return_value=self.release):
            with patch.object(manifest_script, "gh", side_effect=self.mock_download) as gh:
                self.publish_manifest()
        self.assertEqual(gh.call_count, 1)
        self.assertEqual(gh.call_args.args[:2], ("release", "download"))

    def test_wrong_existing_manifest_is_not_overwritten(self):
        wrong = self.build_manifest()
        wrong["build_number"] += 1
        self.add_existing_manifest(wrong)
        with patch.object(manifest_script, "fetch_release", return_value=self.release):
            with patch.object(manifest_script, "gh", side_effect=self.mock_download) as gh:
                with self.assertRaisesRegex(ValueError, "refusing to overwrite"):
                    self.publish_manifest()
        self.assertEqual(gh.call_count, 1)
        self.assertNotIn("upload", gh.call_args.args)

    def test_existing_manifest_checks_json_types_not_just_numeric_equality(self):
        wrong = self.build_manifest()
        wrong["schema_version"] = True
        self.add_existing_manifest(wrong)
        with patch.object(manifest_script, "fetch_release", return_value=self.release):
            with patch.object(manifest_script, "gh", side_effect=self.mock_download):
                with self.assertRaisesRegex(ValueError, "refusing to overwrite"):
                    self.publish_manifest()

    def test_missing_release_cannot_publish_manifest(self):
        with patch.object(manifest_script, "fetch_release", return_value=None):
            with patch.object(manifest_script, "gh") as gh:
                with self.assertRaisesRegex(ValueError, "does not exist"):
                    self.publish_manifest()
        gh.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_upload_failure_propagates_without_clobber_or_delete(self):
        failure = subprocess.CalledProcessError(1, ["gh", "release", "upload"])
        with patch.object(manifest_script, "fetch_release", return_value=self.release):
            with patch.object(manifest_script, "gh", side_effect=failure) as gh:
                with self.assertRaises(subprocess.CalledProcessError):
                    self.publish_manifest()
        self.assertNotIn("--clobber", gh.call_args.args)
        self.assertEqual(gh.call_count, 1)

    def test_existing_local_output_is_not_overwritten(self):
        self.output.parent.mkdir()
        self.output.write_text("keep this file", encoding="utf-8")
        with patch.object(manifest_script, "fetch_release", return_value=self.release):
            with patch.object(manifest_script, "gh") as gh:
                with self.assertRaises(FileExistsError):
                    self.publish_manifest()
        gh.assert_not_called()
        self.assertEqual(self.output.read_text(encoding="utf-8"), "keep this file")

    def test_api_200_parses_headers_and_json(self):
        for newline in ("\n", "\r\n"):
            with self.subTest(newline=newline):
                output = f"HTTP/2.0 200 OK{newline}Content-Type: application/json{newline}{newline}"
                result = subprocess.CompletedProcess([], 0, output + json.dumps(self.release), "")
                with patch.object(manifest_script.subprocess, "run", return_value=result):
                    self.assertEqual(manifest_script.fetch_release(self.repo, self.tag), self.release)

    def test_only_explicit_api_404_means_missing_release(self):
        result = subprocess.CompletedProcess([], 1, "HTTP/2.0 404 Not Found\n\n{}", "gh: Not Found (HTTP 404)")
        with patch.object(manifest_script.subprocess, "run", return_value=result):
            self.assertIsNone(manifest_script.fetch_release(self.repo, self.tag))
        for stdout, stderr in (("HTTP/2.0 403 Forbidden\n\n{}", "forbidden"),
                               ("", "network failure")):
            with self.subTest(stderr=stderr):
                result = subprocess.CompletedProcess([], 1, stdout, stderr)
                with patch.object(manifest_script.subprocess, "run", return_value=result):
                    with patch.object(manifest_script.sys, "stderr") as log:
                        with self.assertRaises(subprocess.CalledProcessError):
                            manifest_script.fetch_release(self.repo, self.tag)
                        log.write.assert_called_once_with(stderr)


if __name__ == "__main__":
    unittest.main()
