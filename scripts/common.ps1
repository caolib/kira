function Get-CopyAuthKeyDefine {
    # 拷贝接口登录的签名密钥 = 官方 APK 签名证书 DER 的 MD5 hex。
    # 它不入库：从环境变量 COPY_AUTH_KEY 读取，取不到就返回空（接口登录
    # 入口在应用里自动隐藏）。
    $key = $env:COPY_AUTH_KEY
    if ([string]::IsNullOrWhiteSpace($key)) { return '' }
    return "--dart-define=COPY_AUTH_KEY=$($key.Trim())"
}

function Get-JavaProcessIds {
    @(Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty ProcessId)
}

function Stop-GradleJdks {
    # flutter build apk 结束后 Gradle/Kotlin 守护进程会常驻占用 JDK。
    # 只结束构建开始后才出现、且命令行匹配 Gradle/Kotlin 守护类名的 java 进程：
    # 基线之前已存在的 IDE、其他项目或常驻 JVM 一律不动。
    param([string[]]$Baseline = @())

    Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $Baseline -notcontains $_.ProcessId } |
        Where-Object {
            $cmd = $_.CommandLine
            $cmd -and ($cmd -like '*GradleDaemon*' -or
                       $cmd -like '*KotlinCompileDaemon*' -or
                       $cmd -like '*GradleWrapperMain*' -or
                       $cmd -like '*GradleWorkerMain*')
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
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
