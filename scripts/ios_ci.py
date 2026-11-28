#!/usr/bin/env python3
"""Small iOS CI helpers: configuration gates, bounded logs and release notes."""

import argparse
import base64
import hashlib
import json
import os
import plistlib
import queue
import re
import signal
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET
from pathlib import Path


FLUTTER_VERSION = "3.44.2"
BUNDLE_ID = "io.github.caolib.kira"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_config(root):
    import yaml

    root = Path(root)
    require((root / ".flutter-version").read_text(encoding="utf-8").strip() == FLUTTER_VERSION,
            "iOS CI requires the pinned Flutter 3.44.2 SDK")
    pubspec = yaml.safe_load((root / "pubspec.yaml").read_text(encoding="utf-8"))
    require(pubspec.get("flutter", {}).get("config", {}).get("enable-swift-package-manager") is False,
            "iOS CI is CocoaPods-only; disable Flutter Swift Package Manager")
    require(pubspec.get("dev_dependencies", {}).get("integration_test", {}).get("sdk") == "flutter",
            "The Flutter SDK integration_test dev dependency is required")
    require((root / "integration_test/ios_startup_test.dart").is_file(), "Missing iOS startup integration test")
    podfile = (root / "ios/Podfile").read_text(encoding="utf-8")
    require(re.search(r"(?m)^\s*platform\s+:ios,\s*['\"]14\.0['\"]", podfile),
            "Podfile must target iOS 14.0")
    require("flutter_install_all_ios_pods" in podfile, "Podfile must install the locked Flutter plugins")
    project = (root / "ios/Runner.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    targets = re.findall(r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*\"?([^;\"\s]+)\"?\s*;", project)
    require(targets and all(value in ("14.0", "14") for value in targets),
            "All explicit Xcode deployment targets must be iOS 14.0")
    identifiers = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*\"?([^;\"\s]+)\"?\s*;", project)
    require(identifiers and BUNDLE_ID in identifiers and
            all(value == BUNDLE_ID or value.startswith(BUNDLE_ID + ".") for value in identifiers),
            "Runner and test bundle IDs must use io.github.caolib.kira")
    for configuration in ("Debug", "Release", "Profile"):
        xcconfig = root / f"ios/Flutter/{configuration}.xcconfig"
        text = xcconfig.read_text(encoding="utf-8")
        pods = f"Pods-Runner.{configuration.lower()}.xcconfig"
        require(pods in text and 'Generated.xcconfig' in text, f"Missing {configuration} Pods/Generated includes")
        require(text.index(pods) < text.index("Generated.xcconfig"), f"{configuration}: Pods must precede Generated")
        require(f"{configuration}.xcconfig" in project, f"Xcode project must reference {configuration}.xcconfig")
    info = plistlib.loads((root / "ios/Runner/Info.plist").read_bytes())
    require(isinstance(info.get("UIApplicationSceneManifest"), dict), "Keep the UIScene lifecycle manifest")
    require("com.pravera.flutter_foreground_task.refresh" in info.get("BGTaskSchedulerPermittedIdentifiers", [])
            and "fetch" in info.get("UIBackgroundModes", []), "Missing foreground plugin BGTask launch registration settings")
    require(info.get("NSPhotoLibraryAddUsageDescription") and info.get("NSLocalNetworkUsageDescription"),
            "Missing photo add-only/local-network permission descriptions")
    privacy = plistlib.loads((root / "ios/Runner/PrivacyInfo.xcprivacy").read_bytes())
    require(privacy.get("NSPrivacyTracking", False) is False and isinstance(privacy.get("NSPrivacyAccessedAPITypes"), list),
            "Missing or invalid application privacy manifest")
    require("PrivacyInfo.xcprivacy" in project, "Application privacy manifest must be included by Xcode")
    for name in ("Main", "LaunchScreen"):
        ET.parse(root / f"ios/Runner/Base.lproj/{name}.storyboard")
    print("PASS: Flutter pin, CocoaPods, iOS 14, bundle IDs, startup test and native resources")


def secret_variants(environment):
    secret = environment.get("COPY_AUTH_KEY", "")
    if not secret:
        return []
    variants = {secret, base64.b64encode(secret.encode()).decode(),
                base64.b64encode(("COPY_AUTH_KEY=" + secret).encode()).decode()}
    variants.update(line for line in secret.splitlines() if line)
    variants.add(json.dumps(secret, ensure_ascii=False)[1:-1])
    return sorted(variants, key=len, reverse=True)


def redact(text, variants):
    for value in variants:
        text = text.replace(value, "***")
    return text


def terminate_process(process):
    if os.name == "posix":
        # The parent can exit while an Xcode/Dart child still owns stdout; kill the whole group.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=5)
    elif process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def run_logged(command, log_path, timeout, environment=None):
    """Stream merged output without saving a command line or raw business secret."""
    require(command and timeout > 0, "A command and positive timeout are required")
    environment = dict(os.environ if environment is None else environment)
    variants = secret_variants(environment)
    log_path = Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding="utf-8", errors="replace", bufsize=1,
                               env=environment, start_new_session=os.name == "posix")
    lines = queue.Queue()

    def read_output():
        try:
            for line in process.stdout:
                lines.put(line)
        finally:
            lines.put(None)

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    deadline, timed_out = time.monotonic() + timeout, False
    try:
        with log_path.open("w", encoding="utf-8") as log:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    timed_out = True
                    terminate_process(process)
                    message = f"Command timed out after {timeout:g} seconds.\n"
                    log.write(message)
                    print(message, end="", flush=True)
                    break
                try:
                    line = lines.get(timeout=min(remaining, 0.5))
                except queue.Empty:
                    continue
                if line is None:
                    break
                clean = redact(line, variants)
                log.write(clean)
                log.flush()
                print(clean, end="", flush=True)
            if not timed_out:
                try:
                    code = process.wait(timeout=max(0.01, deadline - time.monotonic()))
                except subprocess.TimeoutExpired:
                    terminate_process(process)
                    timed_out = True
                    message = f"Command timed out after {timeout:g} seconds.\n"
                    log.write(message)
                    print(message, end="", flush=True)
                else:
                    return code if code >= 0 else 128 - code
        return 124
    finally:
        terminate_process(process)
        reader.join(timeout=1)
        process.stdout.close()


def ordered_set_dependencies(text):
    return sorted(set(re.findall(r"(?m)^\s+- (OrderedSet(?:/[^ (]+)? \([^\r\n)]+\))", text)))


def native_lock_report(lock_path, tracked, output, initial_lock=None):
    lock = Path(lock_path)
    require(lock.is_file(), "CocoaPods did not produce ios/Podfile.lock")
    text = lock.read_text(encoding="utf-8")
    ordered_set = ordered_set_dependencies(text)
    lines = ["Native dependency lock: " + ("tracked; deployment install enforced" if tracked else
             "generated on this run; not yet locked in source control"),
             "Podfile.lock SHA-256: " + hashlib.sha256(lock.read_bytes()).hexdigest(),
             "OrderedSet resolved dependencies: " + (", ".join(ordered_set) if ordered_set else "not present")]
    if initial_lock:
        initial = Path(initial_lock)
        require(initial.is_file(), "Missing initial CocoaPods lock snapshot")
        previous = ordered_set_dependencies(initial.read_text(encoding="utf-8"))
        changed = initial.read_bytes() != lock.read_bytes()
        lines.append("Podfile.lock changed after simulator/device build: " + ("YES; compare retained snapshots" if changed else "no"))
        lines.append("OrderedSet change during build: " +
                     (f"{', '.join(previous) or 'not present'} -> {', '.join(ordered_set) or 'not present'}"
                      if previous != ordered_set else "none"))
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    return lines


def release_notes(version, toolchain, native_lock, environment):
    required = ("GITHUB_REPOSITORY", "GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT")
    for key in required:
        require(environment.get(key), f"{key} is required for source provenance")
    require(re.fullmatch(r"[0-9a-fA-F]{40}", environment["GITHUB_SHA"]), "Expected the full source commit SHA")
    require(environment.get("VERIFY_ANALYSIS") == "success", "Static analysis did not pass")
    require(environment.get("VERIFY_SCRIPTS") == "success", "Script/configuration contracts did not pass")
    require(environment.get("FLUTTER_TESTS") == "success", "Unexpected full Flutter test status")
    require(environment.get("SIMULATOR_TEST") == "success", "Unexpected iOS simulator test status")
    require("Flutter 3.44.2" in toolchain and "Xcode 26.3" in toolchain, "Missing pinned toolchain provenance")
    server = environment.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
    run = f"{server}/{environment['GITHUB_REPOSITORY']}/actions/runs/{environment['GITHUB_RUN_ID']}"
    body = [f"# kira {version} — iOS 未签名构建", "", f"- 源码 SHA：`{environment['GITHUB_SHA']}`",
            f"- 构建记录：{run}（attempt {environment['GITHUB_RUN_ATTEMPT']}）",
            "- 配置/脚本合约：通过", "- 静态分析：通过", "- 全量 Flutter 测试：通过",
            "- iOS 模拟器烟测：通过（Flutter integration_test，包含首帧门禁）", "- Device Release / IPA / SHA-256 校验：通过", "",
            "## 工具链", "", "```text", toolchain.strip(), "```", "", "## 原生依赖", "",
            "```text", native_lock.strip(), "```", "", "## 安装限制", "",
            "此 IPA 未签名，不能直接安装，需自行使用有效签名及匹配的 provisioning profile 重签/侧载。",
            "未配置 Apple 证书、未执行 codesign 或 IPA export；允许 linker 自动生成的纯 ad-hoc 段，不用于 TestFlight/App Store。",
            "重签时须匹配 bundle ID、所有嵌入 framework、权限与设备授权。",
            "模拟器通过不等于重签后真机验收，首次授权、冷启动、离线下载与图标切换仍需验证。"]
    note = environment.get("NOTE", "")
    if note:
        body.extend(["", "## 构建说明", "", note])
    return "\n".join(body) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    check = subparsers.add_parser("check-config")
    check.add_argument("--repo", default=".")
    run = subparsers.add_parser("run")
    run.add_argument("--timeout", type=float, required=True)
    run.add_argument("--log", required=True)
    run.add_argument("arguments", nargs=argparse.REMAINDER)
    lock = subparsers.add_parser("native-lock")
    lock.add_argument("--lock", default="ios/Podfile.lock")
    lock.add_argument("--tracked", choices=("true", "false"), required=True)
    lock.add_argument("--output", required=True)
    lock.add_argument("--initial-lock")
    notes = subparsers.add_parser("notes")
    notes.add_argument("--version", required=True)
    notes.add_argument("--toolchain", required=True)
    notes.add_argument("--native-lock", required=True)
    notes.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        if args.command == "check-config":
            check_config(args.repo)
        elif args.command == "run":
            command = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
            return run_logged(command, args.log, args.timeout)
        elif args.command == "native-lock":
            native_lock_report(args.lock, args.tracked == "true", args.output, args.initial_lock)
        else:
            toolchain = Path(args.toolchain).read_text(encoding="utf-8")
            native_lock = Path(args.native_lock).read_text(encoding="utf-8")
            body = release_notes(args.version, toolchain, native_lock, os.environ)
            output = Path(args.output)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(body, encoding="utf-8", newline="\n")
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException, ET.ParseError) as error:
        print(f"iOS CI failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
