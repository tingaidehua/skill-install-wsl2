#!/usr/bin/env python3
"""Rewrite Windows OpenSSH config paths for WSL. Do not replace /root/.ssh (sshd authorized_keys)."""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

WIN_DRIVE = re.compile(r'^["\']?([A-Za-z]):[\\/](.*)$')


def wsl_path(raw: str, win_ssh: Path) -> str:
    s = raw.strip().strip('"').strip("'")
    if s.startswith("~/.ssh/"):
        return str(win_ssh / s[len("~/.ssh/") :])
    if s.startswith("~/"):
        # leftover home-relative; still map via Windows .ssh parent? keep as-is under win_ssh parent
        return s
    m = WIN_DRIVE.match(s)
    if m:
        drive, rest = m.group(1).lower(), m.group(2).replace("\\", "/")
        return f"/mnt/{drive}/{rest}"
    if "\\" in s:
        s = s.replace("\\", "/")
        m = WIN_DRIVE.match(s)
        if m:
            drive, rest = m.group(1).lower(), m.group(2)
            return f"/mnt/{drive}/{rest}"
    return s


def rewrite_line(line: str, win_ssh: Path) -> str:
    raw = line.rstrip("\n")
    stripped = raw.lstrip()
    indent = raw[: len(raw) - len(stripped)]
    if not stripped:
        return "\n" if line.endswith("\n") or line == "\n" else line
    low = stripped.lower()
    if low.startswith("include "):
        rest = stripped.split(None, 1)[1].strip()
        return f"{indent}Include {wsl_path(rest, win_ssh)}\n"
    for key in ("IdentityFile", "UserKnownHostsFile", "CertificateFile", "IdentityAgent"):
        if low.startswith(key.lower() + " "):
            rest = stripped.split(None, 1)[1].strip()
            return f"{indent}{key} {wsl_path(rest, win_ssh)}\n"
    return raw + "\n"


def resolve_includes(src: Path, win_ssh: Path, seen: set[Path]) -> list[str]:
    src = src.resolve()
    if src in seen:
        return []
    seen.add(src)
    out: list[str] = []
    text = src.read_text(encoding="utf-8", errors="replace")
    for line in text.splitlines(True):
        stripped = line.lstrip()
        if stripped.lower().startswith("include ") and not stripped.startswith("#"):
            inc = Path(wsl_path(line.split(None, 1)[1].strip(), win_ssh))
            if inc.is_file():
                out.append(f"# Include {inc}\n")
                out.extend(resolve_includes(inc, win_ssh, seen))
                continue
        out.append(rewrite_line(line, win_ssh))
    return out


def is_private_key(path: Path) -> bool:
    try:
        first = path.read_bytes()[:80]
    except OSError:
        return False
    return b"PRIVATE KEY" in first or first.startswith(b"PuTTY-User-Key")


def materialize_identity(src: Path, dest_dir: Path) -> Path:
    dest = dest_dir / src.name
    dest.write_bytes(src.read_bytes())
    os.chmod(dest, 0o600)
    pub = src.with_name(src.name + ".pub")
    if pub.is_file():
        dest_pub = dest_dir / pub.name
        dest_pub.write_bytes(pub.read_bytes())
        os.chmod(dest_pub, 0o644)
    return dest


def rewrite_identity_files(lines: list[str], dest_dir: Path) -> list[str]:
    out: list[str] = []
    copied: dict[Path, Path] = {}
    for line in lines:
        raw = line.rstrip("\n")
        stripped = raw.lstrip()
        indent = raw[: len(raw) - len(stripped)]
        if stripped.lower().startswith("identityfile "):
            src = Path(stripped.split(None, 1)[1].strip())
            if src.is_file() and is_private_key(src):
                key = src.resolve()
                if key not in copied:
                    copied[key] = materialize_identity(src, dest_dir)
                out.append(f"{indent}IdentityFile {copied[key]}\n")
                continue
        out.append(line if line.endswith("\n") else line + "\n")
    return out


def detect_win_ssh() -> Path:
    env = os.environ.get("WIN_SSH_DIR", "").strip()
    if env:
        p = Path(env)
        if not p.is_dir():
            raise SystemExit(f"WIN_SSH_DIR 不是目录: {p}")
        return p
    found = []
    for p in Path("/mnt/c/Users").glob("*/.ssh"):
        if p.is_dir() and (p / "config").is_file():
            found.append(p)
    if len(found) == 1:
        return found[0]
    if not found:
        raise SystemExit("找不到 /mnt/c/Users/<you>/.ssh/config ，请设 WIN_SSH_DIR")
    raise SystemExit("多个 Windows .ssh，请设 WIN_SSH_DIR 为其中一个:\n" + "\n".join(str(x) for x in found))


def main() -> None:
    dest_dir = Path(os.environ.get("WSL_SSH_HOME", "/root/.ssh"))
    dest_dir.mkdir(mode=0o700, exist_ok=True)
    os.chmod(dest_dir, 0o700)
    win_ssh = detect_win_ssh()
    src = win_ssh / "config"
    if not src.is_file():
        raise SystemExit(f"没有 {src}")
    lines = [
        f"# generated from {src} — 不要整目录 symlink Windows .ssh（会盖掉 sshd authorized_keys）\n",
        f"UserKnownHostsFile {win_ssh / 'known_hosts'}\n",
        "\n",
    ]
    lines.extend(resolve_includes(src, win_ssh, set()))
    lines = rewrite_identity_files(lines, dest_dir)
    dest = dest_dir / "config"
    dest.write_text("".join(lines), encoding="utf-8")
    os.chmod(dest, 0o600)
    ak = dest_dir / "authorized_keys"
    if not ak.exists():
        ak.write_text("", encoding="utf-8")
        os.chmod(ak, 0o600)
    print(f"WSL ssh config -> {dest}")
    print(f"私钥已拷到 {dest_dir} 并 chmod 600（drvfs 上 0444 会被 OpenSSH 拒绝）")
    print("sshd authorized_keys 未改")


if __name__ == "__main__":
    sys.exit(main())
