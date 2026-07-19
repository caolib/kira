# kira 一键启动脚本（psmux 托管，复用 run-kira driver）
# 用法: .\scripts\run.ps1 [win|mumu|emu] [-Stop] [-Log]
#   win   flutter run -d win --dart-define-from-file=.env
#   mumu  启动 MuMu 模拟器 → adb connect 127.0.0.1:16384 → flutter run -d 127 --dart-define-from-file=.env
#   emu   flutter emulators --launch Medium_Phone_API_36 → flutter run -d emu --dart-define-from-file=.env
# 无参数: 打印用法

param(
    [Parameter(Position = 0)]
    [ValidateSet('win', 'mumu', 'emu')]
    [string]$Target,
    [switch]$Stop,
    [switch]$Log
)

$SessionName = 'kira'
$MuMuManager = 'C:\Program Files\Netease\MuMu\nx_main\MuMuManager.exe'
$MuMuAdbAddr = '127.0.0.1:16384'
$EmulatorName = 'Medium_Phone_API_36'
$Driver = '.claude/skills/run-kira/driver.mjs'

function Test-Session {
    psmux has-session -t $SessionName 2>$null
    return ($LASTEXITCODE -eq 0)
}

if ($Stop) {
    node $Driver stop --yes
    exit $LASTEXITCODE
}

if ($Log) {
    if (Test-Session) {
        node $Driver log 40
    } else {
        Write-Host "session $SessionName 不存在"
    }
    exit 0
}

if (-not $Target) {
    Write-Host @"
用法: .\scripts\run.ps1 <win|mumu|emu> [-Stop] [-Log]

  win   Windows 桌面运行
  mumu  MuMu 模拟器 (127.0.0.1:16384)
  emu   Android emulator ($EmulatorName)

  -Stop 停止并清理 psmux session
  -Log  查看最近 40 行运行输出

示例:
  .\scripts\run.ps1 win
  .\scripts\run.ps1 mumu
"@
    exit 0
}

# 已运行则先停掉（冷启动全新设备）
if (Test-Session) {
    Write-Host "session $SessionName 已在运行，先停止旧进程..."
    node $Driver stop --yes
    Start-Sleep -Seconds 2
}

# ---- 设备准备，解析出 flutter -d 参数 ----
$DeviceArg = switch ($Target) {
    'win'  { 'windows' }
    'mumu' {
        Write-Host "启动 MuMu 模拟器..."
        if (-not (Test-Path $MuMuManager)) { throw "找不到 MuMuManager: $MuMuManager" }
        & $MuMuManager control -v 0 launch | Out-Null
        Write-Host "等待模拟器就绪并连接 adb $MuMuAdbAddr ..."
        $ok = $false
        for ($i = 0; $i -lt 24; $i++) {
            adb connect $MuMuAdbAddr 2>&1 | Out-Null
            $devices = adb devices
            if ($devices -match ([regex]::Escape($MuMuAdbAddr) + '\s+device')) { $ok = $true; break }
            Start-Sleep -Seconds 5
        }
        if (-not $ok) { throw "adb 连接 $MuMuAdbAddr 超时，请手动检查模拟器状态" }
        Write-Host "MuMu 已连接"
        '127'
    }
    'emu'  {
        Write-Host "启动 Android 模拟器 $EmulatorName ..."
        flutter emulators --launch $EmulatorName | Out-Null
        Write-Host "等待模拟器上线..."
        $ok = $false
        for ($i = 0; $i -lt 24; $i++) {
            $devices = adb devices
            if ($devices -match 'emulator-\d+\s+device') { $ok = $true; break }
            Start-Sleep -Seconds 5
        }
        if (-not $ok) { throw "等待模拟器上线超时，请手动检查" }
        Write-Host "模拟器已上线"
        'emu'
    }
}

# ---- 通过 driver 启动（session 名、就绪轮询统一） ----
$env:KIRA_DEVICE = $DeviceArg
Write-Host "启动: flutter run -d $DeviceArg --dart-define-from-file=.env"
node $Driver start
exit $LASTEXITCODE
