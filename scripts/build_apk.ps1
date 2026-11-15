# 架构参数供 CI 多 ABI 构建复用；缺省保持本地单架构 arm64-v8a 行为
param(
    [string]$TargetPlatform = 'android-arm64',
    [string]$Abi = 'arm64-v8a'
)

. "$PSScriptRoot\common.ps1"

Write-Host "`n=== Kira APK 构建脚本 ===" -ForegroundColor Green

# JVM 清理仅用于本地 Windows；Linux/macOS 与 CI 不枚举或结束宿主进程。
$isWindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$cleanupBuildJdks = $isWindowsHost -and -not $env:CI
$jdkBaseline = @()

try {
    # 切到仓库根目录
    Push-Location (Join-Path $PSScriptRoot '..')

    # 读取 pubspec.yaml 中的版本号
    $pubspec = Get-Content 'pubspec.yaml' -Raw
    if ($pubspec -match '(?m)^version:\s*(\S+)') {
        $version = $Matches[1].Split('+')[0]
        $versionFull = $Matches[1] -replace '\+', '-'
    } else {
        throw '无法从 pubspec.yaml 解析版本号'
    }
    Write-Host "版本号: v$version" -ForegroundColor Yellow


    # 构建 APK
    Write-Host "`n正在构建 APK ($TargetPlatform, release)..." -ForegroundColor Yellow
    $copyAuthKeyDefine = Get-CopyAuthKeyDefine
    if (-not $copyAuthKeyDefine) {
        Write-Host "未设置 COPY_AUTH_KEY，接口登录入口将不出现在应用中" -ForegroundColor DarkYellow
    }
    $buildArgs = @(
        'build', 'apk',
        '--release',
        '--target-platform', $TargetPlatform
    )
    if ($copyAuthKeyDefine) { $buildArgs += $copyAuthKeyDefine }

    # 构建前记录已有 JVM，收尾只清理本次构建新起的守护进程
    if ($cleanupBuildJdks) { $jdkBaseline = @(Get-JavaProcessIds) }

    $buildLog = Join-Path ([System.IO.Path]::GetTempPath()) 'kira_build_apk.log'
    & flutter @buildArgs 2>&1 | Tee-Object -FilePath $buildLog

    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk 失败 (exit code: $LASTEXITCODE)"
    }

    # 重复类 = 插件 Dart/native 版本不一致,这种包装机即白屏
    $duplicates = Select-String -Path $buildLog -Pattern 'is defined multiple times', 'Duplicate class'
    if ($duplicates) {
        $duplicates | Select-Object -First 20 | ForEach-Object { Write-Host $_.Line -ForegroundColor DarkYellow }
        throw "构建日志出现重复类，APK 自洽性检查失败（Dart 侧与 native 侧插件版本不一致）"
    }

    Write-Host "自洽性检查通过：未发现重复类" -ForegroundColor Green

    # 定位输出 APK
    $apkDir = 'build\app\outputs\flutter-apk'
    $srcApk = Join-Path $apkDir 'app-release.apk'
    if (-not (Test-Path $srcApk)) {
        throw "未找到构建产物: $srcApk"
    }

    # 重命名
    $newName = "kira-v$versionFull-$Abi.apk"
    $destApk = Join-Path $apkDir $newName
    if (Test-Path $destApk) { Remove-Item $destApk -Force }
    Move-Item -Path $srcApk -Destination $destApk -Force
    Write-Host "已重命名: $newName" -ForegroundColor Green

    # 打开所在文件夹（并选中文件）；CI 环境下跳过
    if ($isWindowsHost -and -not $env:CI) {
        $fullPath = (Resolve-Path $destApk).Path
        Write-Host "`n构建产物: $fullPath" -ForegroundColor Green
        Start-Process explorer.exe -ArgumentList "/select,`"$fullPath`""
    } else {
        Write-Host "`n构建产物: $destApk" -ForegroundColor Green
    }
}
catch {
    Write-Host "错误: $_" -ForegroundColor Red
    exit 1
}
finally {
    if ($cleanupBuildJdks) {
        Write-Host "`n正在结束构建 JVM..." -ForegroundColor DarkGray
        Stop-GradleJdks -Baseline $jdkBaseline
    }
    Pop-Location
}
