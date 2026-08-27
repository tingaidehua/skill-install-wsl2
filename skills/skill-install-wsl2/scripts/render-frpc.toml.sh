#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/load-config.sh"

bool() {
  case "${1,,}" in
    true|1|yes) echo true ;;
    *) echo false ;;
  esac
}

mux="$(bool "$FRP_TCP_MUX")"
comp="$(bool "$FRP_USE_COMPRESSION")"
enc="$(bool "$FRP_USE_ENCRYPTION")"
fail_exit="$(bool "$FRP_LOGIN_FAIL_EXIT")"

cat <<EOF
# generated from skill-install-wsl2/config.env — do not edit by hand
serverAddr = "${FRP_SERVER_ADDR}"
serverPort = ${FRP_BIND_PORT}
auth.method = "token"
auth.token = "${FRP_TOKEN}"
loginFailExit = ${fail_exit}
transport.tcpMux = ${mux}
transport.useCompression = ${comp}
transport.useEncryption = ${enc}
transport.heartbeatInterval = ${FRP_HEARTBEAT_INTERVAL}
transport.heartbeatTimeout = ${FRP_HEARTBEAT_TIMEOUT}
transport.dialServerTimeout = ${FRP_DIAL_TIMEOUT}
transport.poolCount = ${FRP_POOL_COUNT}
webServer.addr = "127.0.0.1"
webServer.port = ${FRP_ADMIN_PORT}

[[proxies]]
name = "${FRP_PROXY_NAME}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${WSL_SSH_PORT}
remotePort = ${FRP_SSH_REMOTE_PORT}
transport.useCompression = false
transport.useEncryption = false
EOF
