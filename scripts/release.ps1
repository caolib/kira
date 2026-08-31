# 支持 -ResumeTag v1.2.3 直接从 CLI 恢复指定版本（跳过版本选择交互）
param([string]$ResumeTag = '')

. "$PSScriptRoot\common.ps1"

Write-Host "`n=== Kira 发布脚本 ===" -ForegroundColor Green

# ---------- 辅助函数 ----------

# 检查 tag 是否已存在于本地
function Test-LocalTagExists {
    param([string]$Tag)
    git rev-parse -q --verify "refs/tags/$Tag" 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

# 检查 tag 是否已推送到远端
function Test-RemoteTagExists {
    param([string]$Tag)
    $out = git ls-remote --tags origin "refs/tags/$Tag" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "警告: 无法查询远程 tag 列表" -ForegroundColor Yellow
        return $false
    }
    return [bool]($out | Select-String -Quiet $Tag)
}

# 检查 release commit 是否已存在（按提交信息匹配）
function Test-ReleaseCommitExists {
    param([string]$Tag)
    $msg = "chore: release $Tag"
    $found = git log --oneline -10 --grep=$msg 2>$null
    return ($found -ne $null -and $found.Count -gt 0)
}

# 检查 pubspec.yaml 版本号是否已更新
function Test-PubspecUpdated {
    param([string]$Version)
    $content = Get-Content 'pubspec.yaml' -Raw
    return $content -match "(?m)^version: $([regex]::Escape($Version))\+"
}

# 检查 CHANGELOG.md 是否已包含该版本条目（通过匹配版本号字符串）
function Test-ChangelogUpdated {
    param([string]$Tag)
    if (-not (Test-Path 'docs/CHANGELOG.md')) { return $false }
    $content = Get-Content 'docs/CHANGELOG.md' -Raw
    # 匹配 "v1.3.1" 或 "1.3.1"（gen-commit 输出格式可能带或不带 v 前缀）
    $ver = $Tag.TrimStart('v')
    return $content -match [regex]::Escape($ver)
}

# 安全执行 git 命令，失败时打印提示但不直接退出（用于可恢复的步骤）
function Invoke-GitSafe {
    param([string[]]$Arguments, [string]$FailMessage)
    $result = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "警告: $FailMessage" -ForegroundColor Yellow
        Write-Host $result -ForegroundColor DarkGray
        return $false
    }
    return $true
}

# ---------- 主流程 ----------

try {
    # ========== 阶段 0: 确定目标版本 ==========

    if ($ResumeTag) {
        # CLI 恢复模式
        if ($ResumeTag -notmatch '^v\d+\.\d+\.\d+(-[\w.]+)?$') {
            Write-Host "错误: -ResumeTag 格式不正确，应为 v1.2.3 或 v1.2.3-beta" -ForegroundColor Red
            exit 1
        }
        $newTag = $ResumeTag
        Write-Host "恢复模式: 目标版本 $newTag" -ForegroundColor Yellow
    }
    else {
        # 交互模式：检查是否有未完成的发布
        $currentTag = Get-CurrentTag
        Write-Host "当前最新tag: $currentTag" -ForegroundColor Yellow

        # 检测未完成的发布：当前 tag 是否已推送到远端
        $tagOnRemote = Test-RemoteTagExists $currentTag
        $hasUnfinished = -not $tagOnRemote -and (Test-LocalTagExists $currentTag)

        if ($hasUnfinished) {
            Write-Host "`n检测到未完成的发布: $currentTag (tag 已存在但未推送)" -ForegroundColor Yellow
            $resume = Read-Host "是否继续完成该发布? (Y/n, 输入 n 选择新版本)"
            if ($resume -ne 'n' -and $resume -ne 'N') {
                $newTag = $currentTag
                Write-Host "继续完成 $newTag 的发布" -ForegroundColor Green
            }
        }

        if (-not $newTag) {
            # 正常选择新版本
            $version = $currentTag.Substring(1)
            $dashIdx = $version.IndexOf('-')
            if ($dashIdx -ge 0) {
                $preRelease = $version.Substring($dashIdx)
                $version = $version.Substring(0, $dashIdx)
            }
            else {
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
            }
            else {
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
                    }
                    else {
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
        }
    }

    Write-Host "`n目标版本: $newTag" -ForegroundColor Green

    # 检查 tag 是否已推送（已完成的发布）
    if (Test-RemoteTagExists $newTag) {
        Write-Host "版本 $newTag 已推送，无需重复发布" -ForegroundColor Green
        exit 0
    }

    $newVersion = $newTag.Substring(1)

    # ========== 阶段 1: CHANGELOG ==========

    if (Test-ChangelogUpdated $newTag) {
        Write-Host "`n[跳过] CHANGELOG.md 已包含 $newTag 条目" -ForegroundColor DarkGray
    }
    else {
        Write-Host "`n正在更新 CHANGELOG.md..." -ForegroundColor Yellow
        Invoke-RunCommand gen-commit @()

        if (-not (Test-ChangelogUpdated $newTag)) {
            Write-Host "警告: gen-commit 可能未生成 $newTag 的条目，请检查 CHANGELOG.md" -ForegroundColor Yellow
        }
        else {
            Write-Host "CHANGELOG.md 已更新" -ForegroundColor Green
        }

        Write-Host "`n正在打开 CHANGELOG.md 供编辑..." -ForegroundColor Yellow
        try { Start-Process explorer.exe -ArgumentList 'docs\CHANGELOG.md' -ErrorAction Stop }
        catch {
            Write-Host "无法打开文件: $_" -ForegroundColor Red
            Write-Host "请手动编辑 docs/CHANGELOG.md"
        }
        Read-Host "`n编辑完成后按回车继续"
    }

    # ========== 阶段 2: pubspec.yaml ==========

    if (Test-PubspecUpdated $newVersion) {
        Write-Host "`n[跳过] pubspec.yaml 版本号已是 $newVersion" -ForegroundColor DarkGray
    }
    else {
        Write-Host "`n正在更新 pubspec.yaml..." -ForegroundColor Yellow
        Update-PubspecVersion $newVersion
        Write-Host "pubspec.yaml 版本号已更新为 $newVersion" -ForegroundColor Green
    }

    # ========== 阶段 3: commit ==========

    if (Test-ReleaseCommitExists $newTag) {
        Write-Host "`n[跳过] release commit 已存在" -ForegroundColor DarkGray
    }
    else {
        Write-Host "`n正在提交更改..." -ForegroundColor Yellow
        Invoke-RunCommand git @('add', 'docs/CHANGELOG.md', 'pubspec.yaml')

        # 检查是否有实际变更需要提交
        $status = git status --porcelain -- 'docs/CHANGELOG.md' 'pubspec.yaml' 2>$null
        if ($status) {
            Invoke-RunCommand git @('commit', '-m', "chore: release $newTag")
            Write-Host "已创建commit" -ForegroundColor Green
        }
        else {
            Write-Host "无变更需要提交" -ForegroundColor DarkGray
        }
    }

    # ========== 阶段 4: tag ==========

    if (Test-LocalTagExists $newTag) {
        Write-Host "`n[跳过] tag $newTag 已存在" -ForegroundColor DarkGray
    }
    else {
        Write-Host "`n正在创建tag..." -ForegroundColor Yellow
        Invoke-RunCommand git @('tag', '-a', $newTag, '-m', "Release $newTag")
        Write-Host "已创建tag: $newTag" -ForegroundColor Green
    }

    # ========== 阶段 5: 推送（原子操作） ==========

    # 检查 main 分支是否领先于远端
    $localHead = (git rev-parse HEAD 2>$null).Trim()
    $remoteHead = (git rev-parse origin/main 2>$null).Trim()
    $mainNeedsPush = $localHead -ne $remoteHead

    if (-not $mainNeedsPush -and (Test-RemoteTagExists $newTag)) {
        Write-Host "`n[跳过] 所有内容已推送" -ForegroundColor DarkGray
    }
    else {
        Write-Host "`n正在推送到远程仓库..." -ForegroundColor Yellow

        # 使用 --atomic 确保 main 和 tag 要么都推送成功，要么都失败
        $pushArgs = @('push', '--atomic', 'origin')
        if ($mainNeedsPush) { $pushArgs += 'main' }
        $pushArgs += $newTag

        $pushed = Invoke-GitSafe $pushArgs "推送失败"

        if (-not $pushed) {
            # atomic push 失败，尝试分别推送以便给出更明确的错误
            Write-Host "`n原子推送失败，尝试分步推送以定位问题..." -ForegroundColor Yellow

            if ($mainNeedsPush) {
                $ok = Invoke-GitSafe @('push', 'origin', 'main') "推送 main 分支失败"
                if (-not $ok) { throw "推送 main 分支失败，请检查网络或权限后重新运行脚本" }
            }

            $ok = Invoke-GitSafe @('push', 'origin', $newTag) "推送 tag 失败"
            if (-not $ok) { throw "推送 tag $newTag 失败，请检查网络或权限后重新运行脚本" }
        }

        Write-Host "已推送到远程仓库" -ForegroundColor Green
    }

    # ========== 完成 ==========

    $repoUrl = Get-RepoUrl
    $repoPath = Get-RepoPath $repoUrl

    Write-Host "`n=== 发布完成 ===" -ForegroundColor Green
    Write-Host "版本: $newTag" -ForegroundColor Green
    if ($repoPath) {
        Write-Host "`nGitHub Actions 将自动构建各架构 APK (arm/arm64/x86/x86_64) 与 Windows 安装包，" -ForegroundColor Yellow
        Write-Host "并创建 Release 上传全部产物。" -ForegroundColor Yellow
        Write-Host "进度查看: https://github.com/$repoPath/actions" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "`n错误: $_" -ForegroundColor Red
    Write-Host "`n提示: 修复问题后重新运行脚本即可，已完成的步骤会自动跳过。" -ForegroundColor Yellow
    Write-Host "也可以手动指定版本继续: .\scripts\release.ps1 -ResumeTag <tag>" -ForegroundColor Yellow
    exit 1
}
