#!/bin/sh
# Windows 必须有一个一直不退出的 wsl.exe 客户端，外地 SSH/frp 不算。
# 本脚本在 WSL 里睡死即可；frpc/sshd 的保活交给 systemd，不要让 Windows 轮询。
exec sleep infinity
