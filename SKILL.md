---
name: skill-install-wsl2
description: >-
  安装 WSL2 Ubuntu（pmpp-ubuntu）与 CUDA，并用一份 config.env 把本机 WSL SSH
  经公网 frp 暴露出去，供外地 SSH 以 root 稳定跑 CUDA / 调模型。含短命 proxy-on/off
  （Windows Clash 7897）、link-win-ssh.py（Gitee/OpenSSH 拒绝 drvfs 过宽私钥）。
  在用户提到 启动 WSL2、安装 WSL、CUDA、nvcc、frp、公网 SSH、远程调试模型、
  wsl-gpu、WSL 代理、proxy-on、7897、Gitee SSH、Permissions too open、frpc 在哪跑、黑框闪现 时使用。
---

# WSL2 + CUDA + 公网 SSH（一份配置）

目的：Windows GPU 上的 WSL2 跑 CUDA / 调模型；外地 SSH 进来，尽量满网速、少掉线。

**正确道路：只改 `config.env`，只跑本目录 `scripts/`。不要另写 toml / systemd / 第二套模板。**

`.cursor/skills/skill-install-wsl2/config.env` 是唯一配置。不要把真实 IP、token、密钥路径写进将公开的副本。

已有发行版 `pmpp-ubuntu` 时先探测，不要重装。

## 脚本一览（`scripts/`）

| 文件 | 何时跑 | 做什么 |
|------|--------|--------|
| `load-config.sh` | 被其它 `.sh` source | 读 `config.env` |
| `render-frps.toml.sh` / `render-frpc.toml.sh` / `render-ssh-config.sh` | 被 apply 调用 | 从 config 生成 toml / Host 段 |
| `apply-frps.sh` | 轻量/ECS 上 | 装 frps、systemd |
| `apply-wsl.sh` | WSL root | sshd 回环、**frpc systemd**、`wsl-host-hold.sh`、CUDA 链接、proxy、`link-win-ssh.py` |
| `apply-windows.ps1` | Windows | `.wslconfig`、ssh 片段、HKCU Run 挂一次 hold；**注销**旧计划任务；**不要**写 Startup |
| `wsl-host-hold.sh` | 装到 `/usr/local/sbin/` | `exec sleep infinity`。Windows 登录用 `wsl.exe` 跑它一次 |
| `hold-wsl.vbs` | 模板；`apply-windows` 写入 `~\.local\frp-wsl-watchdog\`（填发行版名） | WMI `CREATE_NO_WINDOW=0x08000000` 启动 wsl。`WshShell.Run wsl,0` 仍会弹黑框 |
| `Register-Tasks.ps1` | 仅清理 | 注销 `WslFrpWatchdog` / `WslFrpNetworkReconnect`。不要再注册每分钟任务 |
| `frpc-healthcheck.sh` | 由 `apply-wsl.sh` 写到 WSL | systemd timer 调 bash+python 查 frpc；不要从 Windows 调 |
| `wsl-proxy-cmd.bash` | 被 bashrc source | 短命函数 `proxy-on` / `proxy-off` |
| `install-wsl-proxy-cmd.sh` | `apply-wsl` 或单独补装 | 装函数；删掉会持久化的 profile.d/apt 代理 |
| `proxy-on` / `proxy-off` | 只应 **source** | 直接执行会失败（环境变量带不回父 shell） |
| `link-win-ssh.py` | `apply-wsl` 或单独 | Windows `config` → `/root/.ssh/config`，私钥拷到 ext4 `chmod 600` |

`.sh` / `.bash` / `.py` 从 Windows 拷进 WSL 先去 CRLF：`sed -i 's/\r$//' scripts/*`

## 权威事实

- Windows NVIDIA 驱动是 GPU 权威；WSL 里禁止再装 NVIDIA 驱动。
- CUDA 和 SSH 都在 **WSL** 里。轻量/ECS 只跑 **frps**，不当编译机。
- 公网登录用户一律 **`WSL_USER=root`**。发行版自带 `ubuntu` 用户，ssh config 写 `User ubuntu` 就会变成 `ubuntu@主机`。
- 公网 `22` 是轻量机自己的 SSH；WSL 的 22 只听 `127.0.0.1`，对外映射到 `FRP_SSH_REMOTE_PORT`（默认 60022）。
- 外地 SSH **不算** Windows 在用 WSL。登录时挂一次 `wsl ... /usr/local/sbin/wsl-host-hold.sh`（里面就是 `sleep infinity`）。frpc 用 WSL 里 systemd，**禁止**计划任务/PowerShell 每 20 秒再拉 `wsl.exe`（会闪黑框）。`vmIdleTimeout` 用正数毫秒，**禁止 -1**。
- `wsl.exe -l` 输出是 UTF-16 LE。PowerShell 的 `curl` 是 `Invoke-WebRequest`，要用 `curl.exe`。PowerShell 会展开 `$`，不要把 `$PATH` 写进 `wsl bash -lc "..."`。
- WSL NAT「localhost 代理未转发」只是警告。访问 Windows Clash **不能用 `127.0.0.1:7897`**，也不能用 `/etc/resolv.conf` 的 `nameserver`（常见 `10.255.255.254`）。要用 `ip route` 默认网关（常见 `172.x.x.1`）的 **7897**。Clash 需允许局域网连接。
- **SSH/frp 禁止走 HTTP(S)_PROXY**（外地 ssh config 和 systemd `frpc` 都不要设）。
- 不要整目录 symlink `/root/.ssh` → Windows `.ssh`（会盖掉 sshd `authorized_keys`）。客户端私钥必须在 ext4 上 `600`：drvfs 常见 `0444`，Gitee 会 `Permissions are too open` 然后 git 退回 HTTPS 要账号密码。
- 不需要再做一份配置模板：`config.env` + `scripts/` 就是模板。

## 谁跑在哪

Windows **不跑 frp**。

| 进程 | 位置 |
|------|------|
| NVIDIA 驱动 | Windows |
| Clash mixed 7897 | Windows |
| CUDA、`sshd`、`frpc`、`frpc-healthcheck.timer` | **WSL Linux**（systemd） |
| `frps` | **公网轻量/ECS Ubuntu**（不是这台 Windows，也不是 WSL 编译机） |
| `wsl-host-hold.sh` | WSL 里 `sleep infinity`；由登录时的一个 `wsl.exe` 客户端挂住 |

外地 SSH / frp 隧道 **不算** Windows 的 WSL 客户端。只在 WSL 里跑 systemd，虚拟机仍可能 idle `poweroff`。所以登录挂 **一次** `wsl.exe … wsl-host-hold.sh` 就够。

**禁止：** PowerShell/`Watch-WslFrp` 每 20 秒再 exec `wsl.exe`、每分钟计划任务、Startup **和** HKCU Run 各启动一次（会闪两次黑框）、`start /min` 的 `.cmd`、`WshShell.Run "wsl.exe", 0`（SW_HIDE 仍会给 wsl 开控制台）。

正确：只 HKCU Run → `wscript //B hold-wsl.vbs` → WMI `CreateFlags=CREATE_NO_WINDOW`。Startup 里的 `hold-wsl.vbs` / `start-wsl-*.cmd` 删掉。frpc 挂了由 WSL 里 timer 重启，不要从 Windows 调 healthcheck。

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

```text
sed -i 's/\r$//' scripts/*.sh scripts/*.bash scripts/*.py
bash apply-frps.sh
wsl -d pmpp-ubuntu -u root -- bash <skill-dir>/scripts/apply-wsl.sh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <skill-dir>\scripts\apply-windows.ps1
```

轻量机上跑 `apply-frps.sh` 时把 skill 拷过去或设 `CONFIG_FILE=`。

`apply-wsl.sh` 还会：sshd 只听回环、root 密钥登录、`force_color_prompt`（绿用户名、蓝路径，不要改成红的）、mask `wsl-pro.service`、安装 `/usr/local/sbin/wsl-host-hold.sh`、短命 `proxy-on`/`proxy-off`、`link-win-ssh.py`（失败不阻断 frp）。

`apply-windows.ps1` 会写 `.wslconfig`、ssh config 片段，把 HKCU `WslFrpWatchdog` 设成只跑一次 `~\.local\frp-wsl-watchdog\hold-wsl.vbs`（按 `WSL_DISTRO` 生成，WMI 无窗口），并 **删掉** Startup 里 wsl/frp/hold 项、注销旧任务、删掉旧 `Watch-WslFrp.ps1` 等。`.wslconfig` 变更要等 WSL 下次完整重启才生效；不要为改超时特意 `wsl --shutdown` 把外地踢掉。

### 5. 稳定与满网速

- frp：`tcpMux/compression/encryption = false`；心跳只配在 **frpc**（frps 写 `transport.heartbeatInterval` 会起不来）
- SSH：`Compression no`、`IPQoS throughput`、`ServerAliveInterval 15`；sshd `AcceptEnv TERM COLORTERM`
- Windows：登录挂一次 `wsl-host-hold.sh`；`vmIdleTimeout=2592000000`；`autoProxy=false`；插电/电池待机与休眠超时 0
- frpc：`Restart=always` + **WSL 内** `frpc-healthcheck.timer`（bash）。不要 Windows 轮询，不要 `.cmd` / 每分钟任务（会闪黑框）。
- 外地 `scp`/`rsync` 不要 `-C`

## WSL 走 Windows 代理（Clash mixed 7897）

Linux 惯例：当前 shell 的 `http_proxy` / `https_proxy` / `ALL_PROXY` + `NO_PROXY`。短命：登录不自动开，关掉终端就没了。

不要写 `/etc/profile.d`、不要写 apt 全局代理、不要给 systemd `frpc` 或外地 SSH 客户端设 `HTTP_PROXY`。曾经写过 `99-wsl-win-proxy` 的，`install-wsl-proxy-cmd.sh` 会删掉。

### 只补代理（已经跑过 apply）

```text
wsl -d pmpp-ubuntu -u root -- bash <skill-dir>/scripts/install-wsl-proxy-cmd.sh
```

函数进 `/etc/bash.bashrc`。带连字符的 `proxy-on()` **不能**放进 dash 会 source 的 `/etc/profile.d`（`[[` / `local` 同样会解析失败，看起来「装了但 `$http_proxy` 为空」）。

### 每天怎么用

新开的交互 bash：

```text
proxy-on
proxy-off
```

已经开着的会话先：`. /etc/wsl-proxy-cmd.bash`

换端口：`WSL_WIN_PROXY_PORT=7890 proxy-on`

`wsl -d ... -- cmd` 非 login/非 interactive **不会**带代理。要代理用交互 SSH，或 `bash -ic 'proxy-on; ...'`。

### 正常输出

```text
proxy ON http://172.28.112.1:7897（仅当前 shell）
```

网关随 WSL 重启会变，脚本每次 `ip route show default` 现算。只要是 `http://<网关>:7897`，不要改成 `127.0.0.1`。

```text
echo "$http_proxy"
curl -sS -o /dev/null -w "%{http_code} %{time_total}\n" --max-time 15 https://github.com
```

有代理时 GitHub 常见几秒内 HTTP 200；直连经常 `curl (28) timeout`。`NO_PROXY` 含 localhost 和 RFC1918。连公网轻量机 / 查 frpc 前可先 `proxy-off`。

### 不要做什么

- `export http_proxy=http://127.0.0.1:7897`
- 把代理写进 frpc systemd、ssh `ProxyCommand`、Windows/外地 SSH 环境
- 把代理写进 profile.d / apt 当「全局常开」

## WSL 用 Windows 的 `~/.ssh`（Gitee / Codeup / Git）

Windows 上 `%USERPROFILE%\.ssh` 可以是指向 OneDrive 的 junction，那是权威私钥。WSL **不要**把 `/root/.ssh` 换成那个目录。

| 留在 Windows | 留在 WSL ext4 |
|--------------|----------------|
| `config` 原文、OneDrive/junction 里的私钥 | `/root/.ssh/authorized_keys`（sshd 登录本机） |
| Windows OpenSSH 的 ACL（给 Windows 用） | `/root/.ssh/config` + **私钥拷贝 `600`**（WSL `ssh`/`git`） |

Windows `IdentityFile C:\Users\...` 在 Linux 无效。直接指 `/mnt/c/...` 时 drvfs 几乎都是 `0444`/`0777`。GitHub 有时仍会 Offering；**Gitee 会拒绝**，git 于是改走 HTTPS 要账号密码。

```text
wsl -d pmpp-ubuntu -u root -- python3 <skill-dir>/scripts/link-win-ssh.py
```

多个 Windows 用户：`WIN_SSH_DIR=/mnt/c/Users/<you>/.ssh`。改了 Windows `config` 或轮换密钥后重新跑。不要 chmod 整个 `/mnt/c`。

验收：

```text
ls -l /root/.ssh          # 私钥 -rw------- ，目录 drwx------
ssh -G gitee.com | grep identityfile    # /root/.ssh/id_ed25519_2 这类
ssh -o BatchMode=yes git@gitee.com      # Hi ... successfully authenticated
```

仓库 remote 用 SSH，不要 HTTPS：

```text
git remote -v
# 坏：https://gitee.com/org/repo.git  → 要账号密码
# 好：git@gitee.com:org/repo.git
git remote set-url origin git@gitee.com:<org>/<repo>.git
```

`authorized_keys` 脚本不会覆盖。Windows 侧 ACL 仍按本机 `setup_ssh_junction.ps1` 收紧（那是 Windows OpenSSH，与 WSL 0444 是两回事）。

## 外地电脑

拷私钥，把 `render-ssh-config.sh` 生成的 Host 段贴进**那台电脑自己的** ssh config。必须 `User root`（或 `WSL_USER`），不要 `User ubuntu`。路径含空格用 `-F`。不要设 `HTTP_PROXY`。

## 踩坑（按症状找）

**安装与脚本**

- `winget` 装 Ubuntu 会卡在「正在启动程序包安装」→ rootfs import。
- GitHub timeout → Windows 上下包再 scp；不要让轻量机/WSL 直连 Releases。需要上网时在 **那个 WSL shell** 里 `proxy-on`。
- PowerShell `curl` / `< file` / `$变量` / 把 `grep|head` 当 cmdlet → 用 `curl.exe`、`scp`、仓库脚本、Python 解码 UTF-16。
- CRLF → `pipefail: invalid option name`。一律去 `\r`。
- 不要另做 toml 模板；改端口只改 `config.env` 再跑脚本。

**连不上 / 马上掉线**

- 60022 **timeout**：防火墙没开 7000 或 60022。
- 60022 **Connection refused**：包到了机器但 frps 没挂上代理（frpc 没连上 7000、WSL 刚起、刚重启过 frps）。轻量机 `ss` 看到 `*:60022` 才算通。
- SSH 设了代理 → 各种怪 refused/极慢。
- 登上立刻 `The system will power off now!`（`root@… on hvc0`）：不是轻量机关机。Windows 认为没有 `wsl.exe` 连接。处理：登录挂一次 `wsl-host-hold.sh` + 正数 `vmIdleTimeout`。**不要**用 PowerShell 死循环每 20 秒再 exec `wsl.exe`。
- Windows 睡眠 / 未登录桌面 → 隧道没了。本机当 GPU 服务器：开机并登录一次。
- 桌面总闪黑框：旧 `Watch-WslFrp` / `.cmd` / 每分钟任务 / **Startup+Run 各启动一次 wsl**。只留 HKCU Run 的 `hold-wsl.vbs`（WMI `CREATE_NO_WINDOW`），不要 `WshShell.Run wsl.exe`。
- 计划任务 `AtStartup` 拒绝访问；`RepetitionDuration` 不能用 `TimeSpan.MaxValue`。
- 健康检查乱 `systemctl restart frpc` 会踢训练 SSH；只在 `/api/status` 没有 running 时重启。
- 不要随便 `systemctl restart frps`（60022 会暂时没人听）。

**登录用户与终端**

- 提示符 `ubuntu@…`：客户端 `User ubuntu`。改成 `User root`。root 用 `PermitRootLogin prohibit-password`。
- root SSH 黑白提示符：默认 `.bashrc` 不认 `xterm-256color`。`apply-wsl.sh` 打开 `force_color_prompt`。
- CUDA 命令找不到：没走 `/usr/local/bin` 链接。跑 `apply-wsl.sh` 或手工链接。

**Git / Gitee / Windows 密钥**

- `Gitee HTTPS 需要账号密码`：remote 是 `https://`，或 SSH 钥被拒绝后 git 回退 HTTPS。改成 `git@gitee.com:...` 并跑 `link-win-ssh.py`。
- `Permissions 0444 ... too open` / `UNPROTECTED PRIVATE KEY FILE`：正在用 `/mnt/c/...` 上的钥。拷到 `/root/.ssh` 且 `600`。`ls -l /root/.ssh` 正常 **不能**说明 drvfs 上那份正常。
- 整目录 symlink `/root/.ssh` → sshd 公钥丢了或和 Windows 客户端配置搅在一起。
- 直接 `Include /mnt/c/Users/<you>/.ssh/config`：里面的 `C:\` 路径无效。
- `pad-oneplus` 的 `127.0.0.1` 在 WSL 里要靠 localhost 转发才能打到 Windows；不行就在 Windows 上 ssh。

**Cursor / VS Code Remote SSH**

- SSH 通了还要在 WSL 装约 100MB `cursor-server`（`downloads.cursor.com`）。走 frp 时慢，安装超时 30s，日志 `Install in progress, sleeping...`。
- 超时后不要连点 Connect。第二次抢同一把锁：`Could not acquire lock after multiple attempts`。清 `/run/user/0/cursor-remote-lock*` 或等第一次下完。
- 可在 Windows 上下 `cursor-reh-linux-x64.tar.gz`，拷到 `/root/.cursor-server/bin/linux-x64/<commit>/` 再解压。或 SSH 里 `proxy-on` 后再连 Remote。

**WSL 代理**

- `proxy-on: command not found`：`. /etc/wsl-proxy-cmd.bash`，或新开交互 bash。
- 提示「短命代理进不了子进程」：PATH 脚本盖过了函数，或用了 `sh`。`type proxy-on` 应为 `function`。
- `127.0.0.1:7897` 失败、网关 `:7897` 成功：正常。
- Clash 拒绝：未允许局域网；mixed 口不是 7897。
- 登录后 `$http_proxy` 为空：短命设计。要上网再 `proxy-on`。
- 代理开着 GitHub 仍 timeout：先看 `$http_proxy` 是不是网关，再在 Windows 测同一口。

**frp 配置**

- **frpc 在 WSL，frps 在公网 Ubuntu，Windows 不跑 frp。**
- frps 不支持 `transport.heartbeatInterval`（`json: unknown field`）。心跳只写 frpc。
- `wsl-pro.service` 因 `cmd.exe: exec format error` 狂重启 → mask，与隧道无关。

**隐私**

- skill 里只留占位符。真实 token/IP/密钥只存在使用者本机 `config.env` 和生成文件，不要回写仓库。

## Agent 约束

- 只改 `config.env` 再跑 `scripts/`。
- CUDA 磁盘/rootfs 只进 `pmpp-4th`。
- 不要 `wsl --install` 交互式补用户。
- 不要为「改超时」主动 `wsl --shutdown` 打断外地会话。
- 不要用计划任务轮询 `wsl.exe` 保活，不要把 hold 同时放进 Startup 和 Run，不要写回 `Watch-WslFrp.ps1`。
- 同一失败且环境未变时不要机械重试 winget / GitHub 直连。
- 不要把 `HTTP_PROXY` 写进 frpc 或登录自动 profile.d；不要整目录 symlink Windows `.ssh`。
- 不要把使用者真实 IP、token、密钥写进本 skill。

## 连接方法

```text
ssh -F <SSH_CONFIG_PATH> <SSH_HOST_ALIAS>
```

等价：

```text
ssh -p <FRP_SSH_REMOTE_PORT> -o Compression=no -o IPQoS=throughput -o ServerAliveInterval=15 -o ServerAliveCountMax=8 -i <SSH_IDENTITY> root@<FRP_SERVER_ADDR>
```

验收：`whoami` 为 `root`；`uname -a` 含 `microsoft-standard-WSL2`；提示符有颜色；`nvidia-smi -L` 能看到 GPU。长任务用 `tmux`。
