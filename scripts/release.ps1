. "$PSScriptRoot\common.ps1"

Write-Host "`n=== Kira 发布脚本 ===" -ForegroundColor Green

try {
    # 1. 获取当前最新的tag
    $currentTag = Get-CurrentTag
    Write-Host "当前最新tag: $currentTag" -ForegroundColor Yellow

    # 解析版本号（支持预发布后缀，如 v1.0.2-beta）
    $version = $currentTag.Substring(1)
    $dashIdx = $version.IndexOf('-')
    if ($dashIdx -ge 0) {
        $preRelease = $version.Substring($dashIdx)
        $version = $version.Substring(0, $dashIdx)
    } else {
        $preRelease = ''
    }
    $parts = $version.Split('.') | ForEach-Object { [int]$_ }
    $major, $minor, $patch = $parts

    $nextPatch = "v$major.$minor.$($patch + 1)"
    $nextMinor = "v$major.$($minor + 1).0"
    $nextMajor = "v$($major + 1).0.0"

    Write-Host "`n请选择新版本号:"
    Write-Host "  1) Patch: $nextPatch"
    Write-Host "  2) Minor: $nextMinor"
    Write-Host "  3) Major: $nextMajor"
    if ($preRelease) {
        Write-Host "  4) 预发布: $nextPatch$preRelease"
        Write-Host "  5) 手动输入"
        $choice = Read-Host "请输入选项 (1-5)"
    } else {
        Write-Host "  4) 手动输入"
        $choice = Read-Host "请输入选项 (1-4)"
    }

    $semverPattern = '^v\d+\.\d+\.\d+(-[\w.]+)?$'

    switch ($choice) {
        '1' { $newTag = $nextPatch }
        ''  { $newTag = $nextPatch }
        '2' { $newTag = $nextMinor }
        '3' { $newTag = $nextMajor }
        '4' {
            if ($preRelease) {
                $newTag = "$nextPatch$preRelease"
            } else {
                $newTag = Read-Host "请输入新版本号 (格式: v1.2.3 或 v1.2.3-beta)"
                if ($newTag -notmatch $semverPattern) {
                    Write-Host "错误: 版本号格式不正确" -ForegroundColor Red
                    exit 1
                }
            }
        }
        '5' {
            $newTag = Read-Host "请输入新版本号 (格式: v1.2.3 或 v1.2.3-beta)"
            if ($newTag -notmatch $semverPattern) {
                Write-Host "错误: 版本号格式不正确" -ForegroundColor Red
                exit 1
            }
        }
        default {
            Write-Host "无效选项" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "`n新版本: $newTag" -ForegroundColor Green

    # 2. 使用 gen-commit 生成 CHANGELOG.md
    Write-Host "`n正在更新 CHANGELOG.md..." -ForegroundColor Yellow
    Invoke-RunCommand gen-commit @()
    Write-Host "CHANGELOG.md 已更新" -ForegroundColor Green

    # 打开编辑器
    Write-Host "`n正在打开 CHANGELOG.md 供编辑..." -ForegroundColor Yellow
    try { Start-Process explorer.exe -ArgumentList 'docs\CHANGELOG.md' -ErrorAction Stop }
    catch {
        Write-Host "无法打开文件: $_" -ForegroundColor Red
        Write-Host "请手动编辑 docs/CHANGELOG.md"
    }
    Read-Host "`n编辑完成后按回车继续"

    # 3. 更新pubspec.yaml中的版本号
    Write-Host "`n正在更新 pubspec.yaml..." -ForegroundColor Yellow
    $newVersion = $newTag.Substring(1)
    Update-PubspecVersion $newVersion
    Write-Host "pubspec.yaml 版本号已更新为 $newVersion" -ForegroundColor Green

    # 4. Git操作
    Write-Host "`n正在提交更改..." -ForegroundColor Yellow
    Invoke-RunCommand git @('add', 'docs/CHANGELOG.md', 'pubspec.yaml')
    Invoke-RunCommand git @('commit', '-m', "chore: release $newTag")
    Write-Host "已创建commit" -ForegroundColor Green

    # 5. 创建tag
    Write-Host "`n正在创建tag..." -ForegroundColor Yellow
    Invoke-RunCommand git @('tag', '-a', $newTag, '-m', "Release $newTag")
    Write-Host "已创建tag: $newTag" -ForegroundColor Green

    # 推送
    Write-Host "`n正在推送到远程仓库..." -ForegroundColor Yellow
    Invoke-RunCommand git @('push', 'origin', 'main')
    Invoke-RunCommand git @('push', 'origin', $newTag)
    Write-Host "已推送到远程仓库" -ForegroundColor Green

    # 6. 输出GitHub Actions链接
    $repoUrl = Get-RepoUrl
    $repoPath = Get-RepoPath $repoUrl

    Write-Host "`n=== 发布完成 ===" -ForegroundColor Green
    Write-Host "版本: $newTag" -ForegroundColor Green
    if ($repoPath) {
        Write-Host "GitHub Actions: https://github.com/$repoPath/actions" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "错误: $_" -ForegroundColor Red
    exit 1
}
