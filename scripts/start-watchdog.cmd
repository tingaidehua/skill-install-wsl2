@echo off
start "" /min powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%USERPROFILE%\.local\frp-wsl-watchdog\Watch-WslFrp.ps1"
