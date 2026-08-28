# 已废弃：不要再注册每分钟任务。frpc 健康检查在 WSL systemd；Windows 只登录挂一次 hold-wsl.vbs。
Unregister-ScheduledTask -TaskName "WslFrpWatchdog" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "WslFrpNetworkReconnect" -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "unregistered WslFrpWatchdog / WslFrpNetworkReconnect"
