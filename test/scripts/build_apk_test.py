"""Run build scripts with fake Flutter/CIM commands; never build or stop real JVMs."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PWSH = shutil.which("pwsh")


@unittest.skipUnless(PWSH, "PowerShell 7 is required")
class BuildApkTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kira-build-apk-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in ("build_apk.ps1", "common.ps1"):
            shutil.copyfile(ROOT / "scripts" / name, scripts / name)
        (self.root / "pubspec.yaml").write_text("name: kira\nversion: 1.7.7+660\n", encoding="utf-8")
        self.launcher = self.root / "launch.ps1"
        self.launcher.write_text(r'''
param([string]$Target, [string]$Abi)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
$global:CimCalls = 0
function global:Get-CimInstance {
    param($ClassName, $Filter, $ErrorAction)
    if ($env:CI -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'CIM must not run on CI or non-Windows'
    }
    $global:CimCalls++
    [pscustomobject]@{ ProcessId = 101; CommandLine = 'java GradleDaemon' }
    if ($global:CimCalls -gt 1) {
        [pscustomobject]@{ ProcessId = 102; CommandLine = 'java GradleDaemon' }
        [pscustomobject]@{ ProcessId = 103; CommandLine = 'java unrelated.App' }
    }
}
function global:Stop-Process {
    param($Id, [switch]$Force, $ErrorAction)
    Add-Content -Path "$PSScriptRoot/stopped.txt" -Value $Id
}
function global:Start-Process {
    param($FilePath, $ArgumentList)
    if ($env:CI -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'Explorer must not run on CI or non-Windows'
    }
    Set-Content -Path "$PSScriptRoot/explorer.txt" -Value $FilePath
}
function global:flutter {
    Set-Content -Path "$PSScriptRoot/flutter-args.txt" -Value ($args -join '|')
    if ($env:KIRA_FAKE_BUILD -eq 'fail') {
        $global:LASTEXITCODE = 23
        Write-Output 'fixture compilation failure'
        return
    }
    $directory = Join-Path (Get-Location) 'build/app/outputs/flutter-apk'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    Set-Content -Path (Join-Path $directory 'app-release.apk') -Value 'fake APK'
    if ($env:KIRA_FAKE_BUILD -eq 'duplicate') { Write-Output 'Duplicate class fixture.Example' }
    $global:LASTEXITCODE = 0
}
& "$PSScriptRoot/scripts/build_apk.ps1" -TargetPlatform $Target -Abi $Abi
exit $LASTEXITCODE
''', encoding="utf-8")

    def run_build(self, *, ci=True, result="success", target="android-arm64", abi="arm64-v8a"):
        env = os.environ.copy()
        env.pop("COPY_AUTH_KEY", None)
        env.pop("CI", None)
        env["KIRA_FAKE_BUILD"] = result
        if ci:
            env["CI"] = "true"
        return subprocess.run([PWSH, "-NoProfile", "-File", str(self.launcher), target, abi],
                              cwd=ROOT, env=env, text=True, encoding="utf-8", errors="replace",
                              capture_output=True, timeout=30)

    def test_ci_builds_all_abis_without_cim_or_process_cleanup(self):
        for target, abi in (("android-arm", "armeabi-v7a"), ("android-arm64", "arm64-v8a"),
                            ("android-x64", "x86_64")):
            with self.subTest(abi=abi):
                result = self.run_build(target=target, abi=abi)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue((self.root / f"build/app/outputs/flutter-apk/kira-v1.7.7-660-{abi}.apk").is_file())
                self.assertIn(f"--target-platform|{target}", (self.root / "flutter-args.txt").read_text())
                self.assertFalse((self.root / "stopped.txt").exists())
                self.assertFalse((self.root / "explorer.txt").exists())

    def test_flutter_failure_is_not_hidden(self):
        result = self.run_build(result="fail")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exit code: 23", result.stdout + result.stderr)
        self.assertFalse((self.root / "stopped.txt").exists())

    def test_duplicate_classes_still_block_release(self):
        result = self.run_build(result="duplicate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Duplicate class", result.stdout + result.stderr)
        self.assertFalse((self.root / "build/app/outputs/flutter-apk/kira-v1.7.7-660-arm64-v8a.apk").exists())

    def test_local_cleanup_is_windows_only_and_preserves_baseline(self):
        result = self.run_build(ci=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        if sys.platform == "win32":
            self.assertEqual((self.root / "stopped.txt").read_text().strip(), "102")
            self.assertTrue((self.root / "explorer.txt").exists())
        else:
            self.assertFalse((self.root / "stopped.txt").exists())
            self.assertFalse((self.root / "explorer.txt").exists())

    def test_common_helpers_are_safe_when_called_directly_in_ci(self):
        env = os.environ.copy()
        env["CI"] = "true"
        result = subprocess.run([PWSH, "-NoProfile", "-Command", r'''
$ErrorActionPreference = 'Stop'
. './scripts/common.ps1'
function Get-CimInstance { throw 'CIM must not run' }
function Stop-Process { throw 'Must not stop a process' }
$ids = @(Get-JavaProcessIds)
if ($ids.Count -ne 0) { throw 'Expected empty baseline' }
Stop-GradleJdks -Baseline @()
'''], cwd=self.root, env=env, text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
