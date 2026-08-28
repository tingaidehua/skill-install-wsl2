#!/usr/bin/env bash
# 安装全局短命 proxy-on / proxy-off（bash 函数），去掉会持久化的 profile.d / apt 代理。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

install -m 0644 "$ROOT/wsl-proxy-cmd.bash" /etc/wsl-proxy-cmd.bash
install -m 0755 "$ROOT/proxy-on" /usr/local/bin/proxy-on
install -m 0755 "$ROOT/proxy-off" /usr/local/bin/proxy-off

rm -f /etc/profile.d/99-wsl-win-proxy.sh /etc/apt/apt.conf.d/99-wsl-win-proxy

marker="# wsl-proxy-cmd"
if ! grep -qF "$marker" /etc/bash.bashrc 2>/dev/null; then
  cat >> /etc/bash.bashrc <<'EOF'

# wsl-proxy-cmd
[ -f /etc/wsl-proxy-cmd.bash ] && . /etc/wsl-proxy-cmd.bash
EOF
fi

echo "installed: bash 里 proxy-on / proxy-off（仅当前 shell；登录不会自动开）"
