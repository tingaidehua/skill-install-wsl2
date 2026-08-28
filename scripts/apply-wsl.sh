#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/load-config.sh"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openssh-server curl python3

install -d -m 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
if [[ "${WSL_USER}" != "root" ]]; then
  install -d -m 700 "/home/${WSL_USER}/.ssh"
  touch "/home/${WSL_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${WSL_USER}/.ssh/authorized_keys"
  chown -R "${WSL_USER}:${WSL_USER}" "/home/${WSL_USER}/.ssh"
fi

if [[ -n "${SSH_PUBKEY:-}" ]]; then
  grep -qxF "$SSH_PUBKEY" /root/.ssh/authorized_keys || echo "$SSH_PUBKEY" >> /root/.ssh/authorized_keys
  if [[ "${WSL_USER}" != "root" ]]; then
    grep -qxF "$SSH_PUBKEY" "/home/${WSL_USER}/.ssh/authorized_keys" || echo "$SSH_PUBKEY" >> "/home/${WSL_USER}/.ssh/authorized_keys"
  fi
fi

python3 "$script_dir/link-win-ssh.py" || true

# sshd 只听回环：外网只能走 frp，避免 WSL NAT 端口暴露混乱
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-wsl-frp.conf <<EOF
ListenAddress 127.0.0.1
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
TCPKeepAlive yes
ClientAliveInterval ${SSH_SERVER_ALIVE_INTERVAL}
ClientAliveCountMax ${SSH_SERVER_ALIVE_COUNT_MAX}
Compression no
AcceptEnv TERM COLORTERM
EOF

TAR="${FRP_TARBALL:-/tmp/${FRP_TARBALL_NAME}}"
if [[ ! -s "$TAR" ]]; then
  echo "缺少 $TAR 。从 Windows /mnt/c/... 拷进来，不要让 WSL 直连 GitHub Releases" >&2
  exit 1
fi
tar -xzf "$TAR" -C /tmp
install -m 0755 "/tmp/frp_${FRP_VERSION}_linux_amd64/frpc" /usr/local/bin/frpc
install -d -m 0755 /etc/frp
"$script_dir/render-frpc.toml.sh" > /etc/frp/frpc.toml
chmod 600 /etc/frp/frpc.toml

cat > /usr/local/sbin/frpc-healthcheck.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
systemctl start ssh || true
if ! ss -tlnH | grep -q '127.0.0.1:${WSL_SSH_PORT}'; then
  systemctl restart ssh || true
  sleep 1
fi
systemctl start frpc || true
python3 - <<'PY'
import json, urllib.request, subprocess, sys, time
ADMIN = "http://127.0.0.1:${FRP_ADMIN_PORT}/api/status"
NAME = "${FRP_PROXY_NAME}"

def status_ok():
    try:
        with urllib.request.urlopen(ADMIN, timeout=3) as r:
            data = json.load(r)
    except Exception:
        return False
    dumped = json.dumps(data).lower()
    return NAME.lower() in dumped and "running" in dumped

if status_ok():
    sys.exit(0)
subprocess.run(["systemctl", "restart", "frpc"], check=False)
time.sleep(2)
sys.exit(0 if status_ok() else 1)
PY
EOF
chmod 0755 /usr/local/sbin/frpc-healthcheck.sh

cat > /etc/systemd/system/frpc.service <<UNIT
[Unit]
Description=frp client
After=network-online.target ssh.service
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/local/bin/frpc -c /etc/frp/frpc.toml
Restart=always
RestartSec=2
KillMode=process
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/frpc-healthcheck.service <<'UNIT'
[Unit]
Description=frpc healthcheck
After=frpc.service ssh.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/frpc-healthcheck.sh
UNIT

cat > /etc/systemd/system/frpc-healthcheck.timer <<EOF
[Unit]
Description=frpc healthcheck every ${HEALTHCHECK_INTERVAL_SEC}s

[Timer]
OnBootSec=15s
OnUnitActiveSec=${HEALTHCHECK_INTERVAL_SEC}s
AccuracySec=5s
Persistent=true
Unit=frpc-healthcheck.service

[Install]
WantedBy=timers.target
EOF

if [[ -f /etc/wsl.conf ]]; then
  if ! grep -q 'systemd=true' /etc/wsl.conf; then
    printf '\n[boot]\nsystemd=true\n' >> /etc/wsl.conf
  fi
else
  printf '[boot]\nsystemd=true\n' > /etc/wsl.conf
fi

# root 交互 SSH 也开彩色提示符（默认 root .bashrc 不认 xterm-256color）
if [[ -f /root/.bashrc ]]; then
  sed -i 's/xterm-color) color_prompt=yes;;/xterm-color|*-256color|xterm-256color) color_prompt=yes;;/' /root/.bashrc
  sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /root/.bashrc
fi

# CUDA：setup 脚本只改了执行时的 HOME/.bashrc；SSH/非登录壳要靠 PATH 里的命令
if [[ -x /usr/local/cuda/bin/nvcc ]]; then
  ln -sfn /usr/local/cuda/bin/nvcc /usr/local/bin/nvcc
fi
if [[ -x /usr/lib/wsl/lib/nvidia-smi ]]; then
  ln -sfn /usr/lib/wsl/lib/nvidia-smi /usr/local/bin/nvidia-smi
  printf '%s\n' /usr/lib/wsl/lib /usr/local/cuda/lib64 > /etc/ld.so.conf.d/wsl-libcuda.conf
  ldconfig || true
fi
cat > /etc/profile.d/wsl-cuda.sh <<'EOF'
export CUDA_HOME=/usr/local/cuda
export PATH="/usr/local/cuda/bin:/usr/lib/wsl/lib:${PATH}"
export LD_LIBRARY_PATH="/usr/lib/wsl/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
EOF
chmod 644 /etc/profile.d/wsl-cuda.sh

install -m 0755 "$script_dir/wsl-host-hold.sh" /usr/local/sbin/wsl-host-hold.sh

bash "$script_dir/install-wsl-proxy-cmd.sh"

systemctl mask wsl-pro.service 2>/dev/null || true

systemctl daemon-reload
systemctl enable --now ssh frpc frpc-healthcheck.timer
systemctl restart ssh frpc
sleep 2
systemctl --no-pager --full status frpc --lines=16
curl -fsS --max-time 3 "http://127.0.0.1:${FRP_ADMIN_PORT}/api/status" || true
echo
echo "防火墙放行 TCP ${FRP_BIND_PORT} 和 TCP ${FRP_SSH_REMOTE_PORT} 后，外地用 Host ${SSH_HOST_ALIAS} 登录"
