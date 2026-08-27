# skill-install-wsl2

Agent Skill：在 Windows GPU 上安装 WSL2 Ubuntu（`pmpp-ubuntu`）与 CUDA，并用一份 `config.env` 把本机 WSL SSH 经公网 frp 暴露出去，供外地以 root SSH 进来跑 CUDA / 调模型。

**只改 `config.env`，只跑本目录 `scripts/`。** 不要把真实 IP、frp token、私钥写进仓库。

## Install

```text
gh skill install tingaidehua/skill-install-wsl2 skill-install-wsl2 --agent cursor --scope user
```

或 clone 后把目录拷到 Cursor / Codex 的 skills 路径：

```powershell
git clone https://github.com/tingaidehua/skill-install-wsl2.git
# 技能本体在 skills/skill-install-wsl2/
```

## Configure

1. 复制并编辑 `config.env`（生成 token：`python -c "import secrets; print(secrets.token_urlsafe(24))"`）。
2. 按 `SKILL.md` 跑 `scripts/apply-frps.sh`、`apply-wsl.sh`、`apply-windows.ps1`。
3. 外地连接：`ssh -F <SSH_CONFIG_PATH> <SSH_HOST_ALIAS>`。

## License

MIT
