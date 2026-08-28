# 短命：只改当前 bash。不要写 profile.d / apt。
# 由 /etc/bash.bashrc 加载，因此交互 bash 里直接敲 proxy-on / proxy-off。

proxy-on() {
  local gw port url
  port="${WSL_WIN_PROXY_PORT:-7897}"
  gw="$(ip route show default 2>/dev/null | awk '{print $3; exit}')"
  if [ -z "$gw" ]; then
    echo "proxy-on: 没有默认网关" >&2
    return 1
  fi
  url="http://${gw}:${port}"
  export http_proxy="$url" https_proxy="$url" HTTP_PROXY="$url" HTTPS_PROXY="$url" ALL_PROXY="$url" all_proxy="$url"
  export no_proxy="localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
  export NO_PROXY="$no_proxy"
  echo "proxy ON ${url}（仅当前 shell）"
}

proxy-off() {
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy no_proxy NO_PROXY
  echo "proxy OFF"
}
