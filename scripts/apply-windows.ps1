param()
$ErrorActionPreference = "Stop"
$SkillDir = Split-Path $PSScriptRoot -Parent
$ConfigPath = Join-Path $SkillDir "config.env"

function Get-SkillConfig([string]$Path) {
    $map = @{}
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $eq = $line.IndexOf("=")
        if ($eq -lt 1) { return }
        $k = $line.Substring(0, $eq).Trim()
        $v = $line.Substring($eq + 1).Trim()
        $map[$k] = $v
    }
    return $map
}

$c = Get-SkillConfig $ConfigPath
$wslconfig = @"
[wsl2]
vmIdleTimeout=$($c["WSL_VM_IDLE_TIMEOUT"])
localhostForwarding=$($c["WSL_LOCALHOST_FORWARDING"])
autoProxy=$($c["WSL_AUTO_PROXY"])

[experimental]
autoMemoryReclaim=disabled
hostAddressLoopback=true
"@
Set-Content -LiteralPath (Join-Path $env:USERPROFILE ".wslconfig") -Value $wslconfig.Trim() -Encoding ASCII

$snippet = @"
Host $($c["FRP_SERVER_SSH_HOST_ALIAS"])
    HostName $($c["FRP_SERVER_ADDR"])
    User $($c["FRP_SERVER_SSH_USER"])
    Port $($c["FRP_SERVER_SSH_PORT"])
    IdentityFile $($c["FRP_SERVER_SSH_IDENTITY"])
    IdentitiesOnly yes

Host $($c["SSH_HOST_ALIAS"])
    HostName $($c["FRP_SERVER_ADDR"])
    User $($c["WSL_USER"])
    Port $($c["FRP_SSH_REMOTE_PORT"])
    IdentityFile $($c["SSH_IDENTITY"])
    IdentitiesOnly yes
    Compression $($c["SSH_COMPRESSION"])
    TCPKeepAlive yes
    ServerAliveInterval $($c["SSH_SERVER_ALIVE_INTERVAL"])
    ServerAliveCountMax $($c["SSH_SERVER_ALIVE_COUNT_MAX"])
    IPQoS $($c["SSH_IPQOS"])
    ProxyCommand none
"@

$sshPath = $c["SSH_CONFIG_PATH"]
$markerStart = "# BEGIN skill-install-wsl2"
$markerEnd = "# END skill-install-wsl2"
$block = "$markerStart`r`n$snippet`r`n$markerEnd"
$dir = Split-Path $sshPath -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
if (Test-Path -LiteralPath $sshPath) {
    $cur = Get-Content -LiteralPath $sshPath -Raw -Encoding UTF8
    if ($cur -match "(?s)# BEGIN skill-install-wsl2.*# END skill-install-wsl2") {
        $cur = [regex]::Replace($cur, "(?s)# BEGIN skill-install-wsl2.*# END skill-install-wsl2", $block.TrimEnd())
    } else {
        $cur = $cur.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
    }
    Set-Content -LiteralPath $sshPath -Value $cur -Encoding UTF8
} else {
    Set-Content -LiteralPath $sshPath -Value ($block + "`r`n") -Encoding UTF8
}

$watchDir = Join-Path $env:USERPROFILE ".local\frp-wsl-watchdog"
New-Item -ItemType Directory -Force -Path $watchDir | Out-Null
$distro = $c["WSL_DISTRO"]
$vbs = @"
Option Explicit
Const CREATE_NO_WINDOW = 134217728
Const SW_HIDE = 0
Dim sh, wsl, cmd, startup, proc, pid
Set sh = CreateObject("WScript.Shell")
wsl = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\wsl.exe"
cmd = """" & wsl & """ -d $distro -u root -- /usr/local/sbin/wsl-host-hold.sh"
Set startup = GetObject("winmgmts:Win32_ProcessStartup").SpawnInstance_
startup.ShowWindow = SW_HIDE
startup.CreateFlags = CREATE_NO_WINDOW
Set proc = GetObject("winmgmts:Win32_Process")
proc.Create cmd, Null, startup, pid
"@
Set-Content -LiteralPath (Join-Path $watchDir "hold-wsl.vbs") -Value $vbs -Encoding ASCII
Copy-Item -Force $ConfigPath (Join-Path $watchDir "config.env")

# 旧轮询看门狗：删掉
foreach ($n in @("Ensure-WslFrp.ps1","Watch-WslFrp.ps1","Start-WslKeepAlive.ps1","WslSilent.ps1","start-watchdog.cmd","start-watchdog.vbs")) {
    $p = Join-Path $watchDir $n
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -match 'Watch-WslFrp|Ensure-WslFrp' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Unregister-ScheduledTask -TaskName "WslFrpWatchdog" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "WslFrpNetworkReconnect" -Confirm:$false -ErrorAction SilentlyContinue

$holdVbs = Join-Path $watchDir "hold-wsl.vbs"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "WslFrpWatchdog" -Value "wscript.exe //nologo //B `"$holdVbs`""

$startupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
Get-ChildItem -LiteralPath $startupDir -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'wsl|frp|watchdog|hold-wsl' } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 现在挂住一次（无窗口）
$wsl = Join-Path $env:SystemRoot "System32\wsl.exe"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $wsl
$psi.Arguments = "-d $distro -u root -- /usr/local/sbin/wsl-host-hold.sh"
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
[void][Diagnostics.Process]::Start($psi)

try {
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change hibernate-timeout-ac 0 | Out-Null
    powercfg /change standby-timeout-dc 0 | Out-Null
} catch {}

Write-Host "Windows 侧完成。登录只挂一次 wsl-host-hold.sh；frpc 健康检查在 WSL systemd。"
Write-Host "ssh -F `"$sshPath`" $($c["SSH_HOST_ALIAS"])"
