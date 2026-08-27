#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/load-config.sh"

# frps 0.71 不认 transport.heartbeatInterval，多写字段会直接起不来
cat <<EOF
# generated from skill-install-wsl2/config.env — do not edit by hand
bindPort = ${FRP_BIND_PORT}
auth.method = "token"
auth.token = "${FRP_TOKEN}"
allowPorts = [
  { start = ${FRP_SSH_REMOTE_PORT}, end = ${FRP_SSH_REMOTE_PORT} }
]
EOF
