. "$PSScriptRoot\common.ps1"

Write-Host "`n=== Kira APK 构建脚本 ===" -ForegroundColor Green

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

    # 检查 .env
    if (-not (Test-Path '.env')) {
        throw '缺少 .env 文件'
    }

    # 构建 APK
    Write-Host "`n正在构建 APK (android-arm64, release)..." -ForegroundColor Yellow
    & flutter build apk `
        --release `
        --target-platform android-arm64 `
        --dart-define-from-file=.env
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk 失败 (exit code: $LASTEXITCODE)"
    }

    # 定位输出 APK
    $apkDir = 'build\app\outputs\flutter-apk'
    $srcApk = Join-Path $apkDir 'app-release.apk'
    if (-not (Test-Path $srcApk)) {
        throw "未找到构建产物: $srcApk"
    }

    # 重命名
    $newName = "kira-v$versionFull-arm64.apk"
    $destApk = Join-Path $apkDir $newName
    if (Test-Path $destApk) { Remove-Item $destApk -Force }
    Move-Item -Path $srcApk -Destination $destApk -Force
    Write-Host "已重命名: $newName" -ForegroundColor Green

    # 打开所在文件夹（并选中文件）
    $fullPath = (Resolve-Path $destApk).Path
    Write-Host "`n构建产物: $fullPath" -ForegroundColor Green
    Start-Process explorer.exe -ArgumentList "/select,`"$fullPath`""
}
catch {
    Write-Host "错误: $_" -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}
