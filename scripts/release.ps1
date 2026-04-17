. "$PSScriptRoot\common.ps1"

Write-Host "`n=== Kira 发布脚本 ===" -ForegroundColor Green

try {
    # 1. 获取当前最新的tag
    $currentTag = Get-CurrentTag
    Write-Host "当前最新tag: $currentTag" -ForegroundColor Yellow

    # 解析版本号
    $version = $currentTag.Substring(1)
    $parts = $version.Split('.') | ForEach-Object { [int]$_ }
    $major, $minor, $patch = $parts

    $nextPatch = "v$major.$minor.$($patch + 1)"
    $nextMinor = "v$major.$($minor + 1).0"
    $nextMajor = "v$($major + 1).0.0"

    Write-Host "`n请选择新版本号:"
    Write-Host "  1) Patch: $nextPatch"
    Write-Host "  2) Minor: $nextMinor"
    Write-Host "  3) Major: $nextMajor"
    Write-Host "  4) 手动输入"
    $choice = Read-Host "请输入选项 (1-4)"

    switch ($choice) {
        '1' { $newTag = $nextPatch }
        ''  { $newTag = $nextPatch }
        '2' { $newTag = $nextMinor }
        '3' { $newTag = $nextMajor }
        '4' {
            $newTag = Read-Host "请输入新版本号 (格式: v1.2.3)"
            if ($newTag -notmatch '^v\d+\.\d+\.\d+$') {
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
    try { Start-Process zed -ArgumentList 'docs/CHANGELOG.md' -ErrorAction Stop }
    catch {
        try { Start-Process code -ArgumentList 'docs/CHANGELOG.md' -ErrorAction Stop }
        catch {
            Write-Host "无法打开编辑器: $_" -ForegroundColor Red
            Write-Host "请手动编辑 docs/CHANGELOG.md"
        }
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
