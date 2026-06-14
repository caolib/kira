$projectRoot = Split-Path $PSScriptRoot -Parent

$pubspec = Join-Path $projectRoot "pubspec.yaml"

$versionCode = [int](git -C $projectRoot rev-list --count HEAD).Trim() + 1

(Get-Content $pubspec) | ForEach-Object {
    if ($_ -match '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
        "version: $($Matches[1])+$versionCode"
    } else {
        $_
    }
} | Set-Content $pubspec

Write-Host "Updated versionCode -> $versionCode"