$ErrorActionPreference = "Continue"
$ConfigPath = Join-Path $PSScriptRoot "config.env"
$Wsl = "$env:SystemRoot\System32\wsl.exe"
$Log = Join-Path $PSScriptRoot "watchdog.log"
$Distro = "pmpp-ubuntu"

if (Test-Path -LiteralPath $ConfigPath) {
    Get-Content -LiteralPath $ConfigPath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        if ($line.StartsWith("WSL_DISTRO=")) { $Distro = $line.Substring(11).Trim() }
    }
}

function Write-Log([string]$Message) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    try {
        Add-Content -Path $Log -Value $line -Encoding UTF8
        $item = Get-Item $Log -ErrorAction SilentlyContinue
        if ($item -and $item.Length -gt 1048576) {
            Set-Content -Path $Log -Value $line -Encoding UTF8
        }
    } catch {}
}

function Invoke-Wsl([string[]]$InnerArgs) {
    $all = @("-d", $Distro, "-u", "root") + $InnerArgs
    $p = Start-Process -FilePath $Wsl -ArgumentList $all -Wait -PassThru -WindowStyle Hidden
    return $p.ExitCode
}

try {
    if (Test-Path (Join-Path $PSScriptRoot "Start-WslKeepAlive.ps1")) {
        & (Join-Path $PSScriptRoot "Start-WslKeepAlive.ps1")
    }
    $health = Invoke-Wsl @("--", "bash", "/usr/local/sbin/frpc-healthcheck.sh")
    Write-Log "healthcheck exit=$health"
    exit $health
} catch {
    Write-Log ("error " + $_.Exception.Message)
    exit 1
}
