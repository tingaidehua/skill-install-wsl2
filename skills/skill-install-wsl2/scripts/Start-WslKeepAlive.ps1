$ErrorActionPreference = "Continue"
$Distro = "pmpp-ubuntu"
$Wsl = "$env:SystemRoot\System32\wsl.exe"
$cfg = Join-Path $PSScriptRoot "config.env"
if (Test-Path -LiteralPath $cfg) {
    Get-Content -LiteralPath $cfg -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line.StartsWith("WSL_DISTRO=")) { $Distro = $line.Substring(11).Trim() }
    }
}

function Get-WslKeepAlive {
    Get-CimInstance Win32_Process -Filter "Name='wsl.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match [regex]::Escape($Distro) -and $_.CommandLine -match "sleep" }
}

if (-not (Get-WslKeepAlive)) {
    Start-Process -FilePath $Wsl -ArgumentList @("-d", $Distro, "-u", "root", "--", "sleep", "infinity") -WindowStyle Hidden
}
