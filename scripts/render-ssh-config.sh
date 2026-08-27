#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/load-config.sh"

cat <<EOF
Host ${FRP_SERVER_SSH_HOST_ALIAS}
    HostName ${FRP_SERVER_ADDR}
    User ${FRP_SERVER_SSH_USER}
    Port ${FRP_SERVER_SSH_PORT}
    IdentityFile ${FRP_SERVER_SSH_IDENTITY}
    IdentitiesOnly yes

Host ${SSH_HOST_ALIAS}
    HostName ${FRP_SERVER_ADDR}
    User ${WSL_USER}
    Port ${FRP_SSH_REMOTE_PORT}
    IdentityFile ${SSH_IDENTITY}
    IdentitiesOnly yes
    Compression ${SSH_COMPRESSION}
    TCPKeepAlive yes
    ServerAliveInterval ${SSH_SERVER_ALIVE_INTERVAL}
    ServerAliveCountMax ${SSH_SERVER_ALIVE_COUNT_MAX}
    IPQoS ${SSH_IPQOS}
    # 禁止走 HTTP/HTTPS 代理，否则 Connection refused / 极慢
    ProxyCommand none
EOF
