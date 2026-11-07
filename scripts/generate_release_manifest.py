#!/usr/bin/env python3
"""在仓库根目录执行；为正式 Release 生成并上传 release.json。"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path


INSTALLERS = (
    ("android", "arm64-v8a", "arm64-v8a.apk"),
    ("android", "armeabi-v7a", "armeabi-v7a.apk"),
    ("android", "x86_64", "x86_64.apk"),
    ("windows", "x64", "windows-x64-setup.exe"),
)
RELEASE_TIMEZONE = timezone(timedelta(hours=8))


def read_version(pubspec, tag):
    matches = re.findall(
        r"^version:[ \t]*(\d+\.\d+\.\d+)\+(\d+)[ \t]*(?:#.*)?$",
        Path(pubspec).read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if len(matches) != 1:
        raise ValueError("Expected one stable version with a build number in pubspec.yaml")
    version, build = matches[0]
    if tag != f"v{version}":
        raise ValueError(f"Release tag {tag!r} does not match pubspec version v{version}")
    return version, int(build)


def expected_installers(version, build):
    return {
        f"kira-v{version}-{build}-{suffix}": (platform, arch)
        for platform, arch, suffix in INSTALLERS
    }


def gh(*args):
    subprocess.run(["gh", *args], check=True)


def fetch_release(repo, tag):
    # 只有明确的 404 才允许创建；网络、认证或权限错误不能当成不存在。
    result = subprocess.run(
        ["gh", "api", "--include", f"repos/{repo}/releases/tags/{tag}"],
        capture_output=True,
        encoding="utf-8",
    )
    status = re.match(r"HTTP/\S+\s+(\d{3})\b", result.stdout)
    if result.returncode != 0:
        if status and status[1] == "404":
            return None
        sys.stderr.write(result.stderr)
        result.check_returncode()
    if not status or status[1] != "200":
        raise ValueError(f"Unexpected GitHub response: {result.stdout}")
    headers_and_body = re.split(r"\r?\n\r?\n", result.stdout, maxsplit=1)
    if len(headers_and_body) != 2:
        raise ValueError("GitHub response has no JSON body")
    return json.loads(headers_and_body[1])


def installer_assets(release, repo, tag, expected):
    if release.get("tag_name") != tag:
        raise ValueError("Release tag does not match the requested tag")
    if release.get("draft") is not False or release.get("prerelease") is not False:
        raise ValueError("Expected a published stable Release")
    if release.get("html_url") != f"https://github.com/{repo}/releases/tag/{tag}":
        raise ValueError("Unexpected Release page URL")
    assets = release.get("assets")
    if not isinstance(assets, list):
        raise ValueError("Release assets must be a list")
    installers = {}
    seen = set()
    for asset in assets:
        if not isinstance(asset, dict) or not isinstance(asset.get("name"), str):
            raise ValueError("Release asset has no valid name")
        name = asset["name"]
        if name in seen:
            raise ValueError(f"Duplicate Release asset: {name}")
        seen.add(name)
        if name == "release.json":
            continue
        if name not in expected:
            raise ValueError(f"Unexpected installer or version: {name}")
        if asset.get("state") != "uploaded":
            raise ValueError(f"Installer is not fully uploaded: {name}")
        if type(asset.get("size")) is not int or asset["size"] <= 0:
            raise ValueError(f"Installer has no valid byte size: {name}")
        url = f"https://github.com/{repo}/releases/download/{tag}/{name}"
        if asset.get("browser_download_url") != url:
            raise ValueError(f"Unexpected installer download URL: {name}")
        installers[name] = asset
    missing = expected.keys() - installers.keys()
    if missing:
        raise ValueError(f"Missing Release installers: {', '.join(sorted(missing))}")
    return installers


def download_asset(repo, tag, asset, directory):
    gh(
        "release", "download", tag, f"--repo={repo}",
        "--pattern", asset["name"], "--dir", str(directory),
    )
    path = Path(directory) / asset["name"]
    if path.stat().st_size != asset["size"]:
        raise ValueError(f"Downloaded asset size mismatch: {asset['name']}")
    return path


def asset_sha256(repo, tag, asset):
    digest = asset.get("digest")
    if digest is not None:
        if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            raise ValueError(f"Invalid GitHub asset digest: {asset['name']}")
        return digest.removeprefix("sha256:")
    # 旧资产可能没有 digest；下载到独立空目录，只读数据，不执行安装包。
    with tempfile.TemporaryDirectory(prefix="kira-release-asset-") as directory:
        path = download_asset(repo, tag, asset, directory)
        checksum = hashlib.sha256()
        with path.open("rb") as file:
            for chunk in iter(lambda: file.read(1024 * 1024), b""):
                checksum.update(chunk)
        return checksum.hexdigest()


def build_manifest(release, repo, tag, version, build):
    expected = expected_installers(version, build)
    installers = installer_assets(release, repo, tag, expected)
    name = release.get("name")
    notes = release.get("body")
    published_at = release.get("published_at")
    if not isinstance(name, str) or not isinstance(notes, str):
        raise ValueError("Release title and notes must be strings")
    if not isinstance(published_at, str):
        raise ValueError("Release has no publication time")
    timestamp = datetime.fromisoformat(published_at.replace("Z", "+00:00"))
    if timestamp.utcoffset() is None:
        raise ValueError("Release publication time has no timezone")
    return {
        "schema_version": 1,
        "version": version,
        "build_number": build,
        "tag": tag,
        "name": name,
        "published_at": timestamp.astimezone(RELEASE_TIMEZONE).isoformat(timespec="seconds"),
        "release_url": release["html_url"],
        "release_notes": notes,
        "assets": [
            {
                "name": asset_name,
                "platform": platform,
                "arch": arch,
                "size": installers[asset_name]["size"],
                "download_url": installers[asset_name]["browser_download_url"],
                "sha256": asset_sha256(repo, tag, installers[asset_name]),
            }
            for asset_name, (platform, arch) in expected.items()
        ],
    }


def create_release(repo, tag, pubspec, artifacts, notes):
    version, build = read_version(pubspec, tag)
    expected = expected_installers(version, build)
    release = fetch_release(repo, tag)
    if release is None:
        paths = sorted(Path(artifacts).iterdir())
        if {path.name for path in paths} != expected.keys():
            raise ValueError("Build artifacts do not match all expected Release installers")
        if any(not path.is_file() or path.stat().st_size == 0 for path in paths):
            raise ValueError("Build artifacts must be non-empty files")
        if not Path(notes).read_text(encoding="utf-8").strip():
            raise ValueError("Release notes are empty")
        gh(
            "release", "create", tag, *(str(path) for path in paths),
            f"--repo={repo}", "--verify-tag", f"--title=App {tag}",
            "--notes-file", str(notes),
        )
        release = fetch_release(repo, tag)
        if release is None:
            raise ValueError("Created Release could not be read back")
    else:
        print(f"Reusing published Release {tag}; installers will not be overwritten")
    installer_assets(release, repo, tag, expected)


def publish_manifest(repo, tag, pubspec, output):
    version, build = read_version(pubspec, tag)
    release = fetch_release(repo, tag)
    if release is None:
        raise ValueError(f"Release {tag} does not exist")
    manifest = build_manifest(release, repo, tag, version, build)
    output = Path(output)
    if output.name != "release.json":
        raise ValueError("Manifest output must be named release.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8", newline="\n") as file:
        json.dump(manifest, file, ensure_ascii=False, indent=2)
        file.write("\n")
    existing = next((asset for asset in release["assets"] if asset["name"] == "release.json"), None)
    if existing is not None:
        if existing.get("state") != "uploaded" or type(existing.get("size")) is not int or existing["size"] <= 0:
            raise ValueError("Existing release.json is not fully uploaded")
        with tempfile.TemporaryDirectory(prefix="kira-release-json-") as directory:
            path = download_asset(repo, tag, existing, directory)
            existing_manifest = json.loads(path.read_text(encoding="utf-8"))
            if json.dumps(existing_manifest, sort_keys=True) != json.dumps(manifest, sort_keys=True):
                raise ValueError("Existing release.json differs; refusing to overwrite it")
        print(f"release.json for {tag} is already correct; skipping upload")
        return
    gh("release", "upload", tag, str(output), f"--repo={repo}")
    print(f"Uploaded release.json for {tag}")


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("create", "upload"):
        subparser = commands.add_parser(command)
        subparser.add_argument("--repo", required=True)
        subparser.add_argument("--tag", required=True)
        subparser.add_argument("--pubspec", default="pubspec.yaml")
        if command == "create":
            subparser.add_argument("--artifacts", required=True)
            subparser.add_argument("--notes", required=True)
        else:
            subparser.add_argument("--output", default="build/release/release.json")
    args = parser.parse_args()
    if args.command == "create":
        create_release(args.repo, args.tag, args.pubspec, args.artifacts, args.notes)
    else:
        publish_manifest(args.repo, args.tag, args.pubspec, args.output)


if __name__ == "__main__":
    main()
