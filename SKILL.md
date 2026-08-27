---
name: skill-install-wsl2
license: MIT
description: >-
  安装 WSL2 Ubuntu（pmpp-ubuntu）与 CUDA，并用一份 config.env 把本机 WSL SSH
  经公网 frp 暴露出去，供外地 SSH 以 root 稳定跑 CUDA / 调模型。在用户提到 启动 WSL2、
  安装 WSL、CUDA、nvcc、frp、公网 SSH、远程调试模型、wsl-gpu 时使用。
---

# WSL2 + CUDA + 公网 SSH（一份配置）

目的：Windows GPU 上的 WSL2 跑 CUDA / 调模型；外地 SSH 进来，尽量满网速、少掉线。

**正确道路：只改 `config.env`，只跑本目录 `scripts/`。不要另写 toml / systemd / 第二套模板。**

`.cursor/skills/skill-install-wsl2/config.env` 是唯一配置。不要把真实 IP、token、密钥路径写进将公开的副本。

已有发行版 `pmpp-ubuntu` 时先探测，不要重装。

## 权威事实

- Windows NVIDIA 驱动是 GPU 权威；WSL 里禁止再装 NVIDIA 驱动。
- CUDA 和 SSH 都在 **WSL** 里。轻量/ECS 只跑 **frps**，不当编译机。
- 公网登录用户一律 **`WSL_USER=root`**。发行版自带 `ubuntu` 用户，ssh config 写 `User ubuntu` 就会变成 `ubuntu@主机`。
- 公网 `22` 是轻量机自己的 SSH；WSL 的 22 只听 `127.0.0.1`，对外映射到 `FRP_SSH_REMOTE_PORT`（默认 60022）。
- 外地 SSH **不算** Windows 在用 WSL。必须常驻 `wsl -d <distro> -u root -- sleep infinity`。`vmIdleTimeout` 用正数毫秒（默认一个月 2592000000），**禁止 -1**。
- `wsl.exe -l` 输出是 UTF-16 LE。PowerShell 的 `curl` 是 `Invoke-WebRequest`，要用 `curl.exe`。PowerShell 会展开 `$`，不要把 `$PATH` 写进 `wsl bash -lc "..."`。
- 从 Windows 写入的 `.sh` 先去 CRLF。
- WSL NAT「localhost 代理未转发」只是警告；但 **SSH/frp 禁止走 HTTP(S)_PROXY**。
- 不需要再做一份配置模板：`config.env` + `scripts/` 就是模板。

## 探测

```powershell
wsl --version
nvidia-smi
```

```python
import subprocess
p = subprocess.run(["wsl", "-l", "-v"], capture_output=True)
print(p.stdout.decode("utf-16-le", errors="replace"))
```

- 有内核、默认版本 2 → WSL2 可用
- 列表含 `pmpp-ubuntu` 且 VERSION=2 → 跳到 CUDA 或公网 SSH
- 无发行版 → 导入
- Windows `nvidia-smi` 失败 → 先修 Windows 驱动

不要 `winget install Canonical.Ubuntu.2404`（会长时间卡在启动安装）；用 rootfs import。

## 导入发行版

磁盘：`pmpp-4th/wsl-ubuntu/`（gitignore）。rootfs：`pmpp-4th/.cache/`。

1. `wsl --set-default-version 2`
2. 下载 Ubuntu 24.04 rootfs（约 340MB）：

   `https://cloud-images.ubuntu.com/wsl/releases/noble/current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz`

3. import：

```text
wsl --import pmpp-ubuntu <PMPP_ROOT>/wsl-ubuntu <PMPP_ROOT>/.cache/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz --version 2
wsl --set-default pmpp-ubuntu
```

4. 验收：`wsl -d pmpp-ubuntu --exec uname -a` 含 `microsoft-standard-WSL2`
5. `/etc/wsl.conf` 必须 `[boot] systemd=true`（`apply-wsl.sh` 会写）。改完要 `wsl --shutdown` 再开一次才生效。imported rootfs **没有** openssh-server，`authorized_keys` 可能是空文件。

## CUDA

不要在 PowerShell 里手拼 PATH：

```text
wsl -d pmpp-ubuntu -u root --exec bash <PMPP_ROOT>/scripts/setup-wsl-cuda.sh
wsl -d pmpp-ubuntu -u root --exec bash <PMPP_ROOT>/scripts/run-vecadd.sh
```

或 `pmpp-4th/scripts/run-cuda-demo.ps1`。先最小 `nvcc` + `cudart`，不要一上来装完整 `cuda-toolkit`。

`setup-wsl-cuda.sh` 只往**当时 HOME** 的 `.bashrc` 写 PATH。SSH 非登录命令找不到 `nvidia-smi`/`nvcc`。`apply-wsl.sh` 会做：

- `/usr/local/bin/nvcc`、`/usr/local/bin/nvidia-smi` 符号链接
- `/etc/profile.d/wsl-cuda.sh` + `ldconfig`

验收：`nvidia-smi -L` 能看到 GPU；`nvcc --version` 存在；`./vecadd` 打印 `PASS`。

本 skill **不装 PyTorch**。没有 `torch` 时只能编译 CUDA，还不能直接训模型；框架另装。长训练用 `tmux`。

## 公网 SSH（按序做）

拓扑：外地 → `FRP_SERVER_ADDR:FRP_SSH_REMOTE_PORT` → 轻量 frps → 本机 WSL frpc → `127.0.0.1:22`（root 密钥登录）。

### 1. 只改 `config.env`

至少：`FRP_SERVER_ADDR`、`FRP_TOKEN`、`SSH_IDENTITY`、`SSH_PUBKEY`、`FRP_SERVER_SSH_IDENTITY`。`WSL_USER` 保持 `root`。

```text
python -c "import secrets; print(secrets.token_urlsafe(24))"
```

吞吐已关 mux/压缩/加密。不要再手写 frps.toml / frpc.toml。

### 2. 轻量防火墙（先开，否则 frpc 连不上、60022 没人听）

来源 `0.0.0.0/0`：

| 协议 | 端口 | 作用 |
|------|------|------|
| TCP | `FRP_BIND_PORT`（7000） | frpc 连 frps |
| TCP | `FRP_SSH_REMOTE_PORT`（60022） | 外地 SSH |

不要用 22 映射 WSL。不要开 7500 面板。

### 3. 在 Windows 上下 frp 包

国内云主机和 WSL 直连 GitHub Releases 经常 `curl (28) timeout`。用 `curl.exe` 在能访问 GitHub 的 Windows 上下，再拷：

```text
curl.exe -L -o %TEMP%\frp_0.71.0_linux_amd64.tar.gz https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_linux_amd64.tar.gz
scp -F <SSH_CONFIG_PATH> %TEMP%\frp_0.71.0_linux_amd64.tar.gz <FRP_SERVER_SSH_HOST_ALIAS>:/tmp/
wsl -d pmpp-ubuntu -u root -- cp /mnt/c/Users/<you>/AppData/Local/Temp/frp_0.71.0_linux_amd64.tar.gz /tmp/
```

版本与 `FRP_VERSION` 一致。PowerShell 不要用 `< file` 重定向给 ssh，用 `scp`。

### 4. 跑脚本

`.sh` 先 `sed -i 's/\r$//' scripts/*.sh`。把 skill 目录拷到轻量机，或设 `CONFIG_FILE=`。

```text
bash apply-frps.sh
wsl -d pmpp-ubuntu -u root -- bash <skill-dir>/scripts/apply-wsl.sh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <skill-dir>\scripts\apply-windows.ps1
```

`apply-wsl.sh` 还会：sshd 只听回环、root 密钥登录、`force_color_prompt`（与 ubuntu 用户同一套绿/蓝提示符）、mask 掉会刷日志的 `wsl-pro.service`。

`apply-windows.ps1` 会写 `.wslconfig`、ssh config 片段、开机看门狗，并启动 **`Start-WslKeepAlive.ps1`（`sleep infinity`）**。`.wslconfig` 变更要等 WSL 下次完整重启才生效；保活进程立刻生效，不要为改超时特意 `wsl --shutdown` 把外地踢掉。

### 5. 稳定与满网速

- frp：`tcpMux/compression/encryption = false`；心跳只配在 **frpc**（frps 写 `transport.heartbeatInterval` 会起不来）
- SSH：`Compression no`、`IPQoS throughput`、`ServerAliveInterval 15`；sshd `AcceptEnv TERM COLORTERM`
- Windows：常驻 `sleep infinity`；`vmIdleTimeout=2592000000`；`autoProxy=false`；插电/电池待机与休眠超时 0
- 看门狗：frpc `Restart=always` + 健康检查（仅代理非 running 才重启 frpc）；登录启动 + HKCU Run + 每分钟任务 + 断网事件。不要用无管理员的 `AtStartup`。
- 外地 `scp`/`rsync` 不要 `-C`

## 外地电脑

拷私钥，把 `render-ssh-config.sh` 生成的 Host 段贴进**那台电脑自己的** ssh config。必须 `User root`（或 `WSL_USER`），不要 `User ubuntu`。路径含空格用 `-F`。不要设 `HTTP_PROXY`。

## 踩坑（按症状找）

**安装与脚本**

- `winget` 装 Ubuntu 会卡在「正在启动程序包安装」→ rootfs import。
- GitHub timeout → Windows 上下包再 scp；不要让轻量机/WSL 直连 Releases。
- PowerShell `curl` / `< file` / `$变量` / 把 `grep|head` 当 cmdlet → 用 `curl.exe`、`scp`、仓库脚本、Python 解码 UTF-16。
- CRLF → `pipefail: invalid option name`。一律去 `\r`。
- 不要另做 toml 模板；改端口只改 `config.env` 再跑脚本。

**连不上 / 马上掉线**

- 60022 **timeout**：防火墙没开 7000 或 60022。
- 60022 **Connection refused**：包到了机器但 frps 没挂上代理（frpc 没连上 7000、WSL 刚起、刚重启过 frps）。轻量机 `ss` 看到 `*:60022` 才算通。
- SSH 设了代理 → 各种怪 refused/极慢。
- 登上立刻 `The system will power off now!`（`root@… on hvc0`）：不是轻量机关机。Windows 认为没有 `wsl.exe` 连接，把虚拟机 poweroff。远程 frp 会话不算。看门狗 `Start-Process -Wait` 一退出就会触发。`vmIdleTimeout=-1` 在部分版本等于立刻关机。处理：常驻 `sleep infinity` + 正数超时。
- Windows 睡眠 / 未登录桌面 → 隧道没了。本机当 GPU 服务器：开机并登录一次。
- 计划任务 `AtStartup` 拒绝访问；`RepetitionDuration` 不能用 `TimeSpan.MaxValue`。
- 健康检查乱 `systemctl restart frpc` 会踢训练 SSH；只在 `/api/status` 没有 running 时重启。
- 不要随便 `systemctl restart frps`（60022 会暂时没人听）。

**登录用户与终端**

- 提示符 `ubuntu@…`：客户端 `User ubuntu`。改成 `User root`。root 用 `PermitRootLogin prohibit-password`。
- root SSH 黑白提示符：默认 `.bashrc` 不认 `xterm-256color`。`apply-wsl.sh` 打开 `force_color_prompt`，颜色与 ubuntu 用户一致（绿用户名、蓝路径），不要改成红的。
- CUDA 命令找不到：没走 `/usr/local/bin` 链接。跑 `apply-wsl.sh` 或手工链接。

**frp 配置**

- frps 不支持 `transport.heartbeatInterval`（`json: unknown field`）。心跳只写 frpc。
- `wsl-pro.service` 在部分环境会因 `cmd.exe: exec format error` 疯狂重启；mask 掉即可，与隧道无关。

**隐私**

- skill 里只留占位符。真实 token/IP/密钥只存在使用者本机 `config.env` 和生成文件，不要回写仓库。

## Agent 约束

- 只改 `config.env` 再跑 `scripts/`。
- CUDA 磁盘/rootfs 只进 `pmpp-4th`。
- 不要 `wsl --install` 交互式补用户。
- 不要为「改超时」主动 `wsl --shutdown` 打断外地会话；保活进程优先。
- 同一失败且环境未变时不要机械重试 winget / GitHub 直连。

## 连接方法

```text
ssh -F <SSH_CONFIG_PATH> <SSH_HOST_ALIAS>
```

等价：

```text
ssh -p <FRP_SSH_REMOTE_PORT> -o Compression=no -o IPQoS=throughput -o ServerAliveInterval=15 -o ServerAliveCountMax=8 -i <SSH_IDENTITY> root@<FRP_SERVER_ADDR>
```

验收：`whoami` 为 `root`；`uname -a` 含 `microsoft-standard-WSL2`；提示符有颜色；`nvidia-smi -L` 能看到 GPU。长任务用 `tmux`。
