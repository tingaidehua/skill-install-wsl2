$ErrorActionPreference = "Continue"
$Ensure = Join-Path $PSScriptRoot "Ensure-WslFrp.ps1"
$Keep = Join-Path $PSScriptRoot "Start-WslKeepAlive.ps1"
$Interval = 20
$cfg = Join-Path $PSScriptRoot "config.env"
if (Test-Path $cfg) {
    Get-Content $cfg | ForEach-Object {
        if ($_.Trim().StartsWith("WATCHDOG_INTERVAL_SEC=")) {
            $Interval = [int]($_.Split("=", 2)[1].Trim())
        }
    }
}

function Invoke-Ensure {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Ensure
    } catch {}
}

if (Test-Path $Keep) { & $Keep }
Invoke-Ensure
try {
    Register-ObjectEvent -InputObject ([Microsoft.Win32.SystemEvents]) -EventName "PowerModeChanged" -Action { Invoke-Ensure } | Out-Null
} catch {}
while ($true) {
    Start-Sleep -Seconds $Interval
    if (Test-Path $Keep) { & $Keep }
    Invoke-Ensure
}
