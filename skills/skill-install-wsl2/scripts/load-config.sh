#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

skill_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$skill_root/config.env}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "missing $CONFIG_FILE" >&2
  exit 1
fi

# 去掉 CRLF 后 source
tmp_cfg="$(mktemp)"
tr -d '\r' < "$CONFIG_FILE" > "$tmp_cfg"
# shellcheck disable=SC1090
set -a
source "$tmp_cfg"
set +a
rm -f "$tmp_cfg"

if [[ "${FRP_TOKEN:-}" == "CHANGE_ME_GENERATE_A_TOKEN" || -z "${FRP_TOKEN:-}" ]]; then
  echo "先改 config.env 里的 FRP_TOKEN" >&2
  exit 1
fi
