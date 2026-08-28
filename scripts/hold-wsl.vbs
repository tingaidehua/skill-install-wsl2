Option Explicit
' CREATE_NO_WINDOW: wscript.Run(...,0) 仍可能给 wsl.exe 分配控制台。
Const CREATE_NO_WINDOW = 134217728
Const SW_HIDE = 0
Dim sh, wsl, cmd, startup, proc, pid
Set sh = CreateObject("WScript.Shell")
wsl = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\wsl.exe"
cmd = """" & wsl & """ -d DISTRO_PLACEHOLDER -u root -- /usr/local/sbin/wsl-host-hold.sh"
Set startup = GetObject("winmgmts:Win32_ProcessStartup").SpawnInstance_
startup.ShowWindow = SW_HIDE
startup.CreateFlags = CREATE_NO_WINDOW
Set proc = GetObject("winmgmts:Win32_Process")
proc.Create cmd, Null, startup, pid
