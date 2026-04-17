function Get-CurrentTag {
    $tags = git tag --sort=-v:refname 2>$null
    if ($tags) { return $tags[0] }
    return 'v0.0.0'
}

function Update-PubspecVersion {
    param([string]$Version)
    $file = 'pubspec.yaml'
    $content = Get-Content $file -Raw
    $content = $content -replace '(?m)^version: .*', "version: $Version"
    Set-Content $file $content -NoNewline
}

function Invoke-RunCommand {
    param([string]$Command, [string[]]$Arguments)
    $result = & $Command @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "命令执行失败: $Command $($Arguments -join ' ')`n$result"
    }
}

function Get-RepoUrl {
    return (git config --get remote.origin.url).Trim()
}

function Get-RepoPath {
    param([string]$Url)
    if ($Url -match 'github\.com[:/](.+/.+?)(\.git)?$') {
        return $Matches[1] -replace '\.git$', ''
    }
    return $null
}
