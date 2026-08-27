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
Copy-Item -Force (Join-Path $PSScriptRoot "Ensure-WslFrp.ps1") (Join-Path $watchDir "Ensure-WslFrp.ps1")
Copy-Item -Force (Join-Path $PSScriptRoot "Watch-WslFrp.ps1") (Join-Path $watchDir "Watch-WslFrp.ps1")
Copy-Item -Force (Join-Path $PSScriptRoot "Start-WslKeepAlive.ps1") (Join-Path $watchDir "Start-WslKeepAlive.ps1")
Copy-Item -Force (Join-Path $PSScriptRoot "start-watchdog.cmd") (Join-Path $watchDir "start-watchdog.cmd")
Copy-Item -Force $ConfigPath (Join-Path $watchDir "config.env")

$startup = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\start-wsl-frp-watchdog.cmd"
Copy-Item -Force (Join-Path $watchDir "start-watchdog.cmd") $startup
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "WslFrpWatchdog" -Value (Join-Path $watchDir "start-watchdog.cmd")

try { & (Join-Path $PSScriptRoot "Register-Tasks.ps1") } catch { Write-Host $_.Exception.Message }

try {
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change hibernate-timeout-ac 0 | Out-Null
    powercfg /change standby-timeout-dc 0 | Out-Null
} catch {}

Write-Host "Windows 侧完成。防火墙放行 TCP $($c["FRP_BIND_PORT"]) 和 TCP $($c["FRP_SSH_REMOTE_PORT"])"
Write-Host "ssh -F `"$sshPath`" $($c["SSH_HOST_ALIAS"])"
