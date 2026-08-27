#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/load-config.sh"

TAR="${FRP_TARBALL:-/tmp/${FRP_TARBALL_NAME}}"
if [[ ! -s "$TAR" ]]; then
  echo "缺少 $TAR 。在 Windows 上下载后 scp 到服务器 /tmp/" >&2
  exit 1
fi

tar -xzf "$TAR" -C /tmp
install -m 0755 "/tmp/frp_${FRP_VERSION}_linux_amd64/frps" /usr/local/bin/frps
install -d -m 0755 /etc/frp
"$script_dir/render-frps.toml.sh" > /etc/frp/frps.toml
chmod 600 /etc/frp/frps.toml

cat > /etc/systemd/system/frps.service <<UNIT
[Unit]
Description=frp server
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.toml
Restart=always
RestartSec=2
KillMode=process
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now frps
systemctl restart frps
sleep 1
systemctl --no-pager --full status frps --lines=12
ss -tlnp | grep ":${FRP_BIND_PORT}" || true
