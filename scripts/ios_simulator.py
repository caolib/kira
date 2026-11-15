#!/usr/bin/env python3
"""Select an installed iPhone simulator and run the real Flutter startup gate."""

import argparse
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


SPEC = importlib.util.spec_from_file_location("kira_ios_ci", Path(__file__).with_name("ios_ci.py"))
ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci)
PACKAGE_SPEC = importlib.util.spec_from_file_location("kira_ios_package", Path(__file__).with_name("package_ios.py"))
package = importlib.util.module_from_spec(PACKAGE_SPEC)
PACKAGE_SPEC.loader.exec_module(package)


def run_versioned_flutter_test(command, log_path, timeout, pubspec="pubspec.yaml"):
    # Flutter 3.44.2 TestCommand has no --build-name/--build-number options.
    # Normalize only this CI invocation's source version, then restore the exact original bytes.
    pubspec = Path(pubspec)
    original = pubspec.read_bytes()
    name, number = package.version_parts(package.pubspec_version(pubspec))
    pattern = rb"(?m)^(\xef\xbb\xbf)?version:[^\r\n]*(?=\r?$)"
    normalized, count = re.subn(pattern, lambda match: (match.group(1) or b"") +
                                f"version: {name}+{number}".encode("ascii"), original)
    ci.require(count == 1, "Expected exactly one pubspec version line for simulator smoke")
    changed = normalized != original
    try:
        if changed:
            pubspec.write_bytes(normalized)
        return ci.run_logged(command, log_path, timeout)
    finally:
        if changed or pubspec.read_bytes() != original:
            pubspec.write_bytes(original)
        ci.require(pubspec.read_bytes() == original, "Simulator failed to restore the exact pubspec bytes")


def select_simulator(listing):
    runtimes = {runtime["identifier"]: runtime for runtime in listing.get("runtimes", [])
                if runtime.get("isAvailable") is True and
                runtime.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-")}
    candidates = []
    for runtime_id, devices in listing.get("devices", {}).items():
        runtime = runtimes.get(runtime_id)
        if runtime is None:
            continue
        version = tuple(int(value) for value in runtime.get("version", "0").split("."))
        for device in devices:
            udid = device.get("udid", "")
            if (device.get("isAvailable") is True and device.get("name", "").startswith("iPhone")
                    and re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", udid)):
                # iOS 26 is preferred to cover the current UIScene lifecycle; no fixed model/UDID.
                rank = (version[0] == 26, version, device.get("state") == "Booted", device["name"], udid)
                candidates.append((rank, {"udid": udid, "name": device["name"], "runtime": runtime_id,
                                          "runtime_name": runtime.get("name", runtime_id),
                                          "version": runtime.get("version"), "state": device.get("state")}))
    if not candidates:
        raise ValueError("No available installed iPhone/iOS simulator runtime; startup gate cannot run")
    return max(candidates, key=lambda candidate: candidate[0])[1]


def list_simulators(output):
    result = subprocess.run(["xcrun", "simctl", "list", "-j", "available"], check=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(result.stdout, encoding="utf-8")
    return json.loads(result.stdout)


def smoke(diagnostics, boot_timeout, test_timeout, pubspec="pubspec.yaml"):
    diagnostics = Path(diagnostics)
    diagnostics.mkdir(parents=True, exist_ok=True)
    listing = list_simulators(diagnostics / "simulators-available.json")
    selected = select_simulator(listing)
    (diagnostics / "selected-simulator.json").write_text(json.dumps(selected, indent=2) + "\n", encoding="utf-8")
    print(f"Selected {selected['name']} / {selected['runtime_name']} / {selected['udid']}", flush=True)
    if selected["state"] != "Booted":
        code = ci.run_logged(["xcrun", "simctl", "boot", selected["udid"]], diagnostics / "simulator-boot.log", 60)
        if code:
            return code
    # bootstatus can otherwise wait indefinitely; the helper kills its process group on timeout.
    code = ci.run_logged(["xcrun", "simctl", "bootstatus", selected["udid"], "-b"],
                         diagnostics / "simulator-bootstatus.log", boot_timeout)
    if code:
        return code
    # No simctl launch shortcut: the Flutter integration_test asserts rendering and plugin behavior.
    return run_versioned_flutter_test(["flutter", "test", "--no-pub", "integration_test/ios_startup_test.dart",
                                       "-d", selected["udid"], "--reporter", "expanded"],
                                      diagnostics / "simulator-flutter-test.log", test_timeout, pubspec)


def diagnostics(output):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    failures = []
    selected_path = output / "selected-simulator.json"
    selected_udid = json.loads(selected_path.read_text(encoding="utf-8"))["udid"] if selected_path.is_file() else "booted"
    for label, command in (
            ("simulator-list-final", ["xcrun", "simctl", "list", "-j", "available"]),
            ("simulator-unified-log", ["xcrun", "simctl", "spawn", selected_udid, "log", "show", "--last", "20m",
                                       "--style", "compact", "--predicate", 'process == "Runner"'])):
        try:
            code = ci.run_logged(command, output / (label + ".log"), 90)
            if code:
                failures.append(f"{label}: exit {code}")
        except (OSError, subprocess.SubprocessError) as error:
            failures.append(f"{label}: {error}")
    roots = [Path.home() / "Library/Logs/DiagnosticReports",
             Path.home() / "Library/Developer/CoreSimulator/Devices"]
    copied = []
    # Only this run's crash files, not simulator preferences/data (which can include defines).
    cutoff = time.time() - 3 * 60 * 60
    for root in roots:
        if not root.is_dir():
            continue
        pattern = "**/data/Library/Logs/CrashReporter/*" if root.name == "Devices" else "*"
        for path in root.glob(pattern):
            if not path.is_file() or path.suffix not in (".ips", ".crash", ".diag") or path.stat().st_mtime < cutoff:
                continue
            relative = path.relative_to(root).as_posix().replace("/", "--")
            target = output / "crashes" / f"{root.name}--{relative}"
            target.parent.mkdir(parents=True, exist_ok=True)
            text = path.read_text(encoding="utf-8", errors="replace")
            target.write_text(ci.redact(text, ci.secret_variants(os.environ)), encoding="utf-8")
            copied.append(str(target))
    # Snapshot only the simulator's results, before Release introduces COPY_AUTH_KEY.
    # Raw device xcresult/activity logs may contain the encoded DART_DEFINES command line.
    results = []
    result_roots = ((Path("build/ios"), "**/*.xcresult"),
                    (Path.home() / "Library/Developer/Xcode/DerivedData", "*/Logs/Test/*.xcresult"))
    for index, (root, pattern) in enumerate(result_roots):
        if not root.is_dir():
            continue
        for path in root.glob(pattern):
            if not path.is_dir() or path.stat().st_mtime < cutoff:
                continue
            target = output / "simulator-xcresult" / f"{index}-{path.relative_to(root).as_posix().replace('/', '--')}"
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(path, target, symlinks=True)
            results.append(str(target))
    report = {"collected_crash_reports": copied, "diagnostic_failures": failures,
              "simulator_xcresult_snapshots": results,
              "device_xcresult": "Not retained: raw device build metadata may contain business defines."}
    (output / "simulator-diagnostics.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    for failure in failures:
        print(f"Diagnostic warning: {failure}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    test = subparsers.add_parser("smoke")
    test.add_argument("--diagnostics", default="artifacts/ios-diagnostics")
    test.add_argument("--boot-timeout", type=float, default=240)
    test.add_argument("--test-timeout", type=float, default=1800)
    test.add_argument("--pubspec", default="pubspec.yaml")
    collect = subparsers.add_parser("diagnostics")
    collect.add_argument("--output", default="artifacts/ios-diagnostics")
    args = parser.parse_args()
    try:
        if args.command == "smoke":
            return smoke(args.diagnostics, args.boot_timeout, args.test_timeout, args.pubspec)
        diagnostics(args.output)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"iOS simulator gate failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
