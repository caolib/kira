# kira 一键启动脚本（Herdr Core 托管，复用 run-kira driver）
# Windows 入口；设备参数可由命令行、环境变量或不入库的 run.local.json 配置。

param(
    [Parameter(Position = 0)]
    [ValidateSet('win', 'mumu', 'emu')]
    [string]$Target,
    [switch]$Stop,
    [switch]$Log,
    [switch]$NoWait,
    [switch]$Wait,
    [string]$MuMuManager,
    [int]$MuMuIndex,
    [string]$MuMuAdbAddr,
    [string]$EmulatorName,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Driver = Join-Path $RepoRoot '.claude/skills/run-kira/driver.mjs'
$ExplicitOptions = @{} + $PSBoundParameters
if (-not $ConfigPath) { $ConfigPath = Join-Path $RepoRoot '.claude/skills/run-kira/run.local.json' }
if ($Wait -and $NoWait) { throw '-Wait 与 -NoWait 不能同时使用' }

# 只有设备启动需要本机配置；帮助、日志与停止不依赖它。
$LocalConfig = $null
function Get-RunOption {
    param([string]$Name, [string]$EnvironmentName, $Default)
    if ($ExplicitOptions.ContainsKey($Name)) { return $ExplicitOptions[$Name] }
    $value = [Environment]::GetEnvironmentVariable($EnvironmentName)
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    if ($LocalConfig) {
        $property = $LocalConfig.PSObject.Properties[$Name]
        if ($property -and $null -ne $property.Value) { return $property.Value }
    }
    return $Default
}

function Resolve-MuMuManager {
    if ($MuMuManager) {
        $candidate = $MuMuManager
        if (-not [IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $RepoRoot $candidate }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
        throw "找不到 MuMuManager: $candidate"
    }
    $command = Get-Command MuMuManager.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    if ($programFiles) {
        $candidate = Join-Path $programFiles 'Netease/MuMu/nx_main/MuMuManager.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw '找不到 MuMuManager；请指定 -MuMuManager、KIRA_MUMU_MANAGER 或本机配置中的 MuMuManager'
}

function Resolve-AndroidEmulator {
    $command = Get-Command emulator -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $roots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    $adb = Get-Command adb -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($adb) { $roots += Split-Path -Parent (Split-Path -Parent $adb.Source) }
    if ($env:LOCALAPPDATA) { $roots += Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    foreach ($root in $roots) {
        if (-not $root) { continue }
        $candidate = Join-Path $root 'emulator/emulator.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw '找不到 Android SDK emulator；请加入 PATH 或设置 ANDROID_SDK_ROOT / ANDROID_HOME，或用 -EmulatorName 明确选择已有 AVD'
}

function Test-Run {
    $state = node $Driver has
    if ($LASTEXITCODE -gt 1) { throw "无法查询 Herdr 运行状态: $state" }
    return ($LASTEXITCODE -eq 0)
}

if ($Stop) {
    node $Driver stop --yes
    exit $LASTEXITCODE
}
if ($Log) {
    node $Driver log 40
    exit $LASTEXITCODE
}
if (-not $Target) {
    Write-Host @"
用法: .\scripts\run.ps1 <win|mumu|emu> [-Stop] [-Log] [-Wait]

  win   Windows 桌面运行
  mumu  MuMu 模拟器（自动查找安装位置；可配置实例与 ADB 地址）
  emu   Android emulator（自动选择唯一 AVD；多个时传 -EmulatorName）

  默认     设备准备后异步启动，Flutter 编译在后台继续
  -Stop    停止并清理 Herdr 中的 kira 运行终端
  -Log     查看最近 40 行运行输出
  -Wait    等到 Flutter 就绪后返回（默认不等待）
  -NoWait  兼容旧参数，与默认异步行为相同

设备选项: -MuMuManager、-MuMuIndex、-MuMuAdbAddr、-EmulatorName
配置优先级: 命令行 > KIRA_* 环境变量 > run.local.json > 通用默认值
本机配置: .claude/skills/run-kira/run.local.json（不入库；可用 -ConfigPath 指定）

示例:
  .\scripts\run.ps1 win
  .\scripts\run.ps1 win -Wait
  .\scripts\run.ps1 mumu
"@
    exit 0
}

if (Test-Path -LiteralPath $ConfigPath) {
    $LocalConfig = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
$MuMuManager = [string](Get-RunOption 'MuMuManager' 'KIRA_MUMU_MANAGER' '')
$MuMuIndex = [int](Get-RunOption 'MuMuIndex' 'KIRA_MUMU_INDEX' 0)
$MuMuAdbAddr = [string](Get-RunOption 'MuMuAdbAddr' 'KIRA_MUMU_ADB_ADDR' '127.0.0.1:16384')
$EmulatorName = [string](Get-RunOption 'EmulatorName' 'KIRA_EMULATOR_NAME' '')

# 先准备目标设备，失败时保留原来运行中的 app。
$DeviceArg = switch ($Target) {
    'win' { 'windows' }
    'mumu' {
        if ($MuMuIndex -lt 0) { throw 'MuMuIndex 必须为非负整数' }
        if ($MuMuAdbAddr -notmatch '^127\.0\.0\.1:\d+$') { throw 'MuMuAdbAddr 必须是 127.0.0.1:<端口>' }
        $manager = Resolve-MuMuManager
        Write-Host "启动 MuMu 实例 $MuMuIndex ..."
        & $manager control -v $MuMuIndex launch | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "MuMu 启动失败，退出码 $LASTEXITCODE" }
        Write-Host "等待模拟器就绪并连接 adb $MuMuAdbAddr ..."
        $ok = $false
        $connection = ''
        for ($i = 0; $i -lt 24; $i++) {
            $connection = adb connect $MuMuAdbAddr 2>&1 | Out-String
            $devices = adb devices
            if ($LASTEXITCODE -ne 0) { throw "adb devices 失败: $devices" }
            if ($devices -match ([regex]::Escape($MuMuAdbAddr) + '\s+device')) { $ok = $true; break }
            Start-Sleep -Seconds 5
        }
        if (-not $ok) { throw "adb 连接 $MuMuAdbAddr 超时: $connection" }
        $MuMuAdbAddr
    }
    'emu' {
        if (-not $EmulatorName) {
            $emulator = Resolve-AndroidEmulator
            $avds = @(& $emulator -list-avds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($LASTEXITCODE -ne 0) { throw "读取 AVD 列表失败，退出码 $LASTEXITCODE" }
            if ($avds.Count -eq 0) { throw '没有已安装的 AVD；请先在 Android Studio 创建模拟器' }
            if ($avds.Count -gt 1) { throw "有多个 AVD，请用 -EmulatorName 选择: $($avds -join ', ')" }
            $EmulatorName = $avds[0].Trim()
        }
        Write-Host "启动 Android 模拟器 $EmulatorName ..."
        flutter emulators --launch $EmulatorName | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "模拟器启动失败，退出码 $LASTEXITCODE" }
        $serial = $null
        for ($i = 0; $i -lt 24; $i++) {
            $devices = adb devices
            if ($LASTEXITCODE -ne 0) { throw "adb devices 失败: $devices" }
            foreach ($line in $devices) {
                if ($line -notmatch '^(emulator-\d+)\s+device') { continue }
                $candidate = $Matches[1]
                $name = @(adb -s $candidate emu avd name)
                if ($LASTEXITCODE -eq 0 -and $name.Count -gt 0 -and $name[0].Trim() -eq $EmulatorName) {
                    $serial = $candidate
                    break
                }
            }
            if ($serial) { break }
            Start-Sleep -Seconds 5
        }
        if (-not $serial) { throw "等待模拟器 $EmulatorName 上线超时，请手动检查" }
        $serial
    }
}

if (Test-Run) {
    Write-Host 'kira 已在 Herdr 中运行，先停止旧进程...'
    node $Driver stop --yes
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
$env:KIRA_DEVICE = $DeviceArg
$env:KIRA_TARGET = $Target
Write-Host "启动: flutter run -d $DeviceArg"

. "$PSScriptRoot/common.ps1"
if (-not (Get-CopyAuthKeyDefine)) {
    Write-Host '未设置 COPY_AUTH_KEY，接口登录入口将不出现在应用中' -ForegroundColor DarkYellow
}
if ($Wait) { node $Driver start --wait } else { node $Driver start }
exit $LASTEXITCODE
