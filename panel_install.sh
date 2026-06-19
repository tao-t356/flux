#!/bin/bash
set -e

# 解决 macOS 下 tr 可能出现的非法字节序列问题
export LANG=en_US.UTF-8
export LC_ALL=C



# 全局下载地址配置
VERSION="${FLUX_PANEL_VERSION:-2.0.8-beta}"
REPO="${FLUX_PANEL_REPO:-tao-t356/flux}"
RELEASE_BASE_URL="${FLUX_RELEASE_BASE_URL:-https://github.com/${REPO}/releases/download/${VERSION}}"
RAW_BRANCH="${FLUX_RAW_BRANCH:-main}"
RAW_BASE_URL="${FLUX_RAW_BASE_URL:-https://raw.githubusercontent.com/${REPO}/${RAW_BRANCH}}"
BACKEND_IMAGE="${BACKEND_IMAGE:-ghcr.io/tao-t356/flux-springboot-backend:${VERSION}}"
FRONTEND_IMAGE="${FRONTEND_IMAGE:-ghcr.io/tao-t356/flux-vite-frontend:${VERSION}}"
GITHUB_PROXY="${FLUX_GITHUB_PROXY:-}"

COUNTRY=$(curl -fsSL --connect-timeout 5 https://ipinfo.io/country 2>/dev/null || true)
if [ -z "$GITHUB_PROXY" ] && [ "$COUNTRY" = "CN" ]; then
    GITHUB_PROXY="https://ghfast.top"
fi

with_github_proxy() {
  local url="$1"
  if [ -n "$GITHUB_PROXY" ]; then
    echo "${GITHUB_PROXY%/}/$url"
  else
    echo "$url"
  fi
}

DOCKER_COMPOSEV4_URL=$(with_github_proxy "${RELEASE_BASE_URL}/docker-compose-v4.yml")
DOCKER_COMPOSEV6_URL=$(with_github_proxy "${RELEASE_BASE_URL}/docker-compose-v6.yml")
DOCKER_COMPOSEV4_RAW_URL=$(with_github_proxy "${RAW_BASE_URL}/docker-compose-v4.yml")
DOCKER_COMPOSEV6_RAW_URL=$(with_github_proxy "${RAW_BASE_URL}/docker-compose-v6.yml")



# 根据IPv6支持情况选择docker-compose URL
get_docker_compose_url() {
  if check_ipv6_support > /dev/null 2>&1; then
    echo "$DOCKER_COMPOSEV6_URL"
  else
    echo "$DOCKER_COMPOSEV4_URL"
  fi
}

get_docker_compose_fallback_url() {
  if check_ipv6_support > /dev/null 2>&1; then
    echo "$DOCKER_COMPOSEV6_RAW_URL"
  else
    echo "$DOCKER_COMPOSEV4_RAW_URL"
  fi
}

download_docker_compose() {
  local target="${1:-docker-compose.yml}"
  local url
  local fallback_url

  url=$(get_docker_compose_url)
  fallback_url=$(get_docker_compose_fallback_url)

  echo "📡 选择配置文件：$(basename "$url")"
  if curl -fL --retry 3 --connect-timeout 15 -o "$target" "$url"; then
    return 0
  fi

  if [ "$fallback_url" != "$url" ]; then
    echo "⚠️ Release 下载失败，尝试从 main 分支下载配置文件..."
    curl -fL --retry 3 --connect-timeout 15 -o "$target" "$fallback_url"
    echo "✅ 已从 main 分支下载配置文件"
    return 0
  fi

  return 1
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ 请使用 root 权限运行此脚本。"
    exit 1
  fi
}

detect_docker_cmd() {
  if command -v docker-compose &> /dev/null; then
    DOCKER_CMD="docker-compose"
    return 0
  fi
  if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_CMD="docker compose"
    return 0
  fi
  return 1
}

install_base_tools() {
  if command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release
  elif command -v dnf &> /dev/null; then
    dnf install -y ca-certificates curl gnupg
  elif command -v yum &> /dev/null; then
    yum install -y ca-certificates curl gnupg
  elif command -v apk &> /dev/null; then
    apk add --no-cache ca-certificates curl
  elif command -v zypper &> /dev/null; then
    zypper --non-interactive install ca-certificates curl
  elif command -v pacman &> /dev/null; then
    pacman -Sy --noconfirm ca-certificates curl
  fi
}

get_os_name() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "${PRETTY_NAME:-${NAME:-$ID}}"
  else
    uname -s
  fi
}

install_compose_plugin() {
  if detect_docker_cmd; then
    return 0
  fi

  echo "🔧 正在安装 Docker Compose 插件..."
  if command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y docker-compose-plugin || true
  elif command -v dnf &> /dev/null; then
    dnf install -y docker-compose-plugin || true
  elif command -v yum &> /dev/null; then
    yum install -y docker-compose-plugin || true
  elif command -v apk &> /dev/null; then
    apk add --no-cache docker-cli-compose || true
  elif command -v zypper &> /dev/null; then
    zypper --non-interactive install docker-compose-plugin || true
  elif command -v pacman &> /dev/null; then
    pacman -S --noconfirm docker-compose || true
  fi
}

start_docker_service() {
  if command -v systemctl &> /dev/null; then
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker
  elif command -v service &> /dev/null; then
    service docker start
  elif command -v rc-service &> /dev/null; then
    rc-update add docker boot >/dev/null 2>&1 || true
    rc-service docker start
  fi
}

install_docker() {
  require_root
  echo "🔧 未检测到 Docker/Compose，正在根据当前 VPS 系统自动安装..."
  echo "🖥️ 当前系统：$(get_os_name)"

  install_base_tools

  if command -v apk &> /dev/null; then
    apk add --no-cache docker docker-cli docker-cli-compose
  elif command -v pacman &> /dev/null; then
    pacman -S --noconfirm docker docker-compose
  else
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
  fi

  start_docker_service
  install_compose_plugin
}

ensure_panel_images() {
  if docker image inspect "$BACKEND_IMAGE" >/dev/null 2>&1 && docker image inspect "$FRONTEND_IMAGE" >/dev/null 2>&1; then
    echo "✅ 检测到本地面板镜像"
    return 0
  fi

  echo "🔽 正在拉取面板镜像..."
  if docker pull "$BACKEND_IMAGE" && docker pull "$FRONTEND_IMAGE"; then
    echo "✅ 面板镜像拉取完成"
    return 0
  fi

  echo "❌ 面板镜像拉取失败。请等待 GitHub Actions 构建完成，或确认 GHCR 镜像已公开："
  echo "   $BACKEND_IMAGE"
  echo "   $FRONTEND_IMAGE"
  exit 1
}

# 检查 docker-compose 或 docker compose 命令，可在安装面板时自动安装
check_docker() {
  local auto_install="${1:-0}"

  if ! command -v docker &> /dev/null || ! detect_docker_cmd; then
    if [ "$auto_install" = "1" ]; then
      install_docker
    else
      echo "错误：未检测到 docker 或 docker-compose 命令。请先安装 Docker，或选择 1 安装爱转角转发面板时自动安装。"
      exit 1
    fi
  fi

  if ! detect_docker_cmd; then
    install_compose_plugin
  fi

  if ! command -v docker &> /dev/null || ! detect_docker_cmd; then
    echo "❌ Docker 已尝试安装，但仍未检测到 docker compose 或 docker-compose。请检查系统软件源或 Docker 安装日志。"
    exit 1
  fi

  echo "✅ 检测到 Docker 命令：$DOCKER_CMD"
}

# 检测系统是否支持 IPv6
check_ipv6_support() {
  echo "🔍 检测 IPv6 支持..."

  # 检查是否有 IPv6 地址（排除 link-local 地址）
  if ip -6 addr show | grep -v "scope link" | grep -q "inet6"; then
    echo "✅ 检测到系统支持 IPv6"
    return 0
  elif ifconfig 2>/dev/null | grep -v "fe80:" | grep -q "inet6"; then
    echo "✅ 检测到系统支持 IPv6"
    return 0
  else
    echo "⚠️ 未检测到 IPv6 支持"
    return 1
  fi
}



# 配置 Docker 启用 IPv6
configure_docker_ipv6() {
  echo "🔧 配置 Docker IPv6 支持..."

  # 检查操作系统类型
  OS_TYPE=$(uname -s)

  if [[ "$OS_TYPE" == "Darwin" ]]; then
    # macOS 上 Docker Desktop 已默认支持 IPv6
    echo "✅ macOS Docker Desktop 默认支持 IPv6"
    return 0
  fi

  # Docker daemon 配置文件路径
  DOCKER_CONFIG="/etc/docker/daemon.json"

  # 检查是否需要 sudo
  if [[ $EUID -ne 0 ]]; then
    SUDO_CMD="sudo"
  else
    SUDO_CMD=""
  fi

  # 检查 Docker 配置文件
  if [ -f "$DOCKER_CONFIG" ]; then
    # 检查是否已经配置了 IPv6
    if grep -q '"ipv6"' "$DOCKER_CONFIG"; then
      echo "✅ Docker 已配置 IPv6 支持"
    else
      echo "📝 更新 Docker 配置以启用 IPv6..."
      # 备份原配置
      $SUDO_CMD cp "$DOCKER_CONFIG" "${DOCKER_CONFIG}.backup"

      # 使用 jq 或 sed 添加 IPv6 配置
      if command -v jq &> /dev/null; then
        $SUDO_CMD jq '. + {"ipv6": true, "fixed-cidr-v6": "fd00::/80"}' "$DOCKER_CONFIG" > /tmp/daemon.json && $SUDO_CMD mv /tmp/daemon.json "$DOCKER_CONFIG"
      else
        # 如果没有 jq，使用 sed
        $SUDO_CMD sed -i 's/^{$/{\n  "ipv6": true,\n  "fixed-cidr-v6": "fd00::\/80",/' "$DOCKER_CONFIG"
      fi

      echo "🔄 重启 Docker 服务..."
      if command -v systemctl &> /dev/null; then
        $SUDO_CMD systemctl restart docker
      elif command -v service &> /dev/null; then
        $SUDO_CMD service docker restart
      else
        echo "⚠️ 请手动重启 Docker 服务"
      fi
      sleep 5
    fi
  else
    # 创建新的配置文件
    echo "📝 创建 Docker 配置文件..."
    $SUDO_CMD mkdir -p /etc/docker
    echo '{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/80"
}' | $SUDO_CMD tee "$DOCKER_CONFIG" > /dev/null

    echo "🔄 重启 Docker 服务..."
    if command -v systemctl &> /dev/null; then
      $SUDO_CMD systemctl restart docker
    elif command -v service &> /dev/null; then
      $SUDO_CMD service docker restart
    else
      echo "⚠️ 请手动重启 Docker 服务"
    fi
    sleep 5
  fi
}

# 显示菜单
show_menu() {
  echo "==============================================="
  echo "      爱转角转发面板管理脚本"
  echo "==============================================="
  echo "请选择操作："
  echo "1. 安装爱转角转发面板"
  echo "2. 更新爱转角转发面板"
  echo "3. 卸载爱转角转发面板"
  echo "4. 退出"
  echo "==============================================="
}

generate_random() {
  if command -v openssl &> /dev/null; then
    openssl rand -hex 32
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c64
  fi
}

is_valid_port() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

is_port_in_use() {
  local port="$1"
  local port_hex

  if command -v ss &> /dev/null; then
    ss -H -ltnu 2>/dev/null | awk '{print $5}' | grep -Eq "(^|[^0-9])${port}$" && return 0
  fi

  if command -v netstat &> /dev/null; then
    netstat -tuln 2>/dev/null | awk 'NR > 2 {print $4}' | grep -Eq "(^|[^0-9])${port}$" && return 0
  fi

  port_hex=$(printf '%04X' "$port")
  if [ -r /proc/net/tcp ]; then
    awk -v p=":$port_hex" '$2 ~ p "$" { found=1 } END { exit found ? 0 : 1 }' \
      /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6 2>/dev/null && return 0
  fi

  return 1
}

find_available_port() {
  local port="$1"
  local reserved_port="${2:-}"

  while [ "$port" -le 65535 ]; do
    if [ "$port" != "$reserved_port" ] && ! is_port_in_use "$port"; then
      echo "$port"
      return 0
    fi
    port=$((port + 1))
  done

  echo "❌ 从 $1 到 65535 未找到可用端口。" >&2
  return 1
}

load_panel_ports_from_env() {
  if [ -z "${FRONTEND_PORT:-}" ]; then
    FRONTEND_PORT=$(read_env_value FRONTEND_PORT || true)
  fi
  FRONTEND_PORT="${FRONTEND_PORT:-6366}"

  if [ -z "${BACKEND_PORT:-}" ]; then
    BACKEND_PORT=$(read_env_value BACKEND_PORT || true)
  fi
  BACKEND_PORT="${BACKEND_PORT:-6365}"
}

open_local_firewall_ports() {
  local frontend_port="${1:-$FRONTEND_PORT}"
  local backend_port="${2:-$BACKEND_PORT}"
  local opened=0

  echo "🔓 正在检查本机防火墙端口..."

  if command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -qi "Status: active"; then
    ufw allow "${frontend_port}/tcp" >/dev/null 2>&1 || true
    ufw allow "${backend_port}/tcp" >/dev/null 2>&1 || true
    echo "✅ 已放行 ufw：TCP $frontend_port / TCP $backend_port"
    opened=1
  fi

  if command -v firewall-cmd &> /dev/null && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${frontend_port}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port="${backend_port}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    echo "✅ 已放行 firewalld：TCP $frontend_port / TCP $backend_port"
    opened=1
  fi

  if [ "$opened" = "0" ]; then
    echo "ℹ️ 未检测到已启用的 ufw/firewalld，本机防火墙跳过"
  fi

  echo "⚠️ 如果外网打不开，还需要在 VPS 控制台安全组放行 TCP $frontend_port 和 TCP $backend_port"
}

normalize_cors_allowed_origins() {
  local value="${1:-*}"
  local origin
  local result=""
  local old_ifs="$IFS"

  if [ "$value" = "*" ]; then
    echo "*"
    return 0
  fi

  IFS=','
  for origin in $value; do
    origin=$(printf '%s' "$origin" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$origin" ]; then
      continue
    fi
    case "$origin" in
      http://*|https://*)
        ;;
      *)
        origin="https://$origin"
        ;;
    esac

    if [ -z "$result" ]; then
      result="$origin"
    else
      result="$result,$origin"
    fi
  done
  IFS="$old_ifs"

  echo "${result:-*}"
}

format_access_host() {
  local host="$1"
  host=$(printf '%s' "$host" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  host="${host#http://}"
  host="${host#https://}"
  host="${host%%/*}"

  if [[ "$host" =~ ^\[([^]]+)\](:[0-9]+)?$ ]]; then
    host="${BASH_REMATCH[1]}"
  elif [[ "$host" =~ ^([^:]+):[0-9]+$ ]]; then
    host="${BASH_REMATCH[1]}"
  fi

  if [[ "$host" == *:* && "$host" != \[* ]]; then
    echo "[$host]"
  else
    echo "$host"
  fi
}

strip_access_host_brackets() {
  local host="$1"
  if [[ "$host" =~ ^\[([^]]+)\]$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$host"
  fi
}

is_ipv4_address() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_ip_literal() {
  local host
  host=$(strip_access_host_brackets "$1")
  is_ipv4_address "$host" || [[ "$host" == *:* ]]
}

resolve_host_ips() {
  local host
  host=$(strip_access_host_brackets "$(format_access_host "$1")")

  if [ -z "$host" ] || [ "$host" = "服务器IP" ]; then
    return 0
  fi

  if is_ip_literal "$host"; then
    echo "$host"
    return 0
  fi

  if command -v getent &> /dev/null; then
    getent ahosts "$host" 2>/dev/null | awk '{print $1}' | sort -u
  elif command -v dig &> /dev/null; then
    dig +short A "$host" 2>/dev/null
    dig +short AAAA "$host" 2>/dev/null
  elif command -v host &> /dev/null; then
    host "$host" 2>/dev/null | awk '/has address/ {print $4} /has IPv6 address/ {print $5}' | sort -u
  fi
}

has_ip_in_list() {
  local needle="$1"
  local value

  while IFS= read -r value; do
    if [ "$value" = "$needle" ]; then
      return 0
    fi
  done

  return 1
}

check_http_url() {
  local url="$1"
  curl -fsS --connect-timeout 4 --max-time 8 -o /dev/null "$url" >/dev/null 2>&1
}

get_saved_access_host() {
  local host

  if [ -n "${FLUX_PANEL_ACCESS_HOST:-}" ]; then
    format_access_host "$FLUX_PANEL_ACCESS_HOST"
    return 0
  fi
  if [ -n "${PANEL_ACCESS_HOST:-}" ]; then
    format_access_host "$PANEL_ACCESS_HOST"
    return 0
  fi

  host=$(read_env_value FLUX_PANEL_ACCESS_HOST || true)
  if [ -n "$host" ]; then
    format_access_host "$host"
    return 0
  fi

  host=$(read_env_value PANEL_ACCESS_HOST || true)
  if [ -n "$host" ]; then
    format_access_host "$host"
    return 0
  fi

  return 1
}

detect_machine_public_host() {
  local host
  local url

  for url in \
    "https://api.ipify.org" \
    "https://ipv4.icanhazip.com" \
    "https://ifconfig.me/ip"
  do
    host=$(curl -4 -fsSL --connect-timeout 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)
    if [ -n "$host" ]; then
      format_access_host "$host"
      return 0
    fi
  done

  for url in \
    "https://api64.ipify.org" \
    "https://ifconfig.co/ip"
  do
    host=$(curl -fsSL --connect-timeout 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)
    if [ -n "$host" ]; then
      format_access_host "$host"
      return 0
    fi
  done

  host=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  if [ -n "$host" ]; then
    format_access_host "$host"
    return 0
  fi

  echo "服务器IP"
}

detect_public_host() {
  local host

  host=$(get_saved_access_host || true)
  if [ -n "$host" ]; then
    echo "$host"
    return 0
  fi

  detect_machine_public_host
}

read_env_value() {
  local key="$1"
  if [ ! -f ".env" ]; then
    return 1
  fi

  awk -F= -v key="$key" '
    $1 == key {
      sub(/^[^=]*=/, "")
      gsub(/^"/, "")
      gsub(/"$/, "")
      print
      exit
    }
  ' .env
}

set_env_value() {
  local key="$1"
  local value="$2"
  local tmp_file

  tmp_file=".env.$$"
  if [ -f ".env" ]; then
    awk -v key="$key" -v value="$value" '
      BEGIN { found = 0 }
      $0 ~ "^" key "=" {
        print key "=" value
        found = 1
        next
      }
      { print }
      END {
        if (!found) {
          print key "=" value
        }
      }
    ' .env > "$tmp_file" && mv "$tmp_file" .env
  else
    printf '%s=%s\n' "$key" "$value" > .env
  fi
}

env_value_or_default() {
  local key="$1"
  local default_value="$2"
  local current_value

  current_value=$(read_env_value "$key" || true)
  if [ -n "$current_value" ]; then
    echo "$current_value"
  else
    echo "$default_value"
  fi
}

ensure_panel_env_file() {
  local jwt_secret
  local cors_allowed_origins
  local java_opts_value

  load_panel_ports_from_env
  if ! is_valid_port "$FRONTEND_PORT"; then
    echo "❌ FRONTEND_PORT 必须是 1-65535 之间的数字。"
    exit 1
  fi
  if ! is_valid_port "$BACKEND_PORT"; then
    echo "❌ BACKEND_PORT 必须是 1-65535 之间的数字。"
    exit 1
  fi
  if [ "$BACKEND_PORT" = "$FRONTEND_PORT" ]; then
    echo "❌ BACKEND_PORT 不能和 FRONTEND_PORT 使用同一个端口。"
    exit 1
  fi

  jwt_secret=$(env_value_or_default JWT_SECRET "${JWT_SECRET:-}")
  if [ -z "$jwt_secret" ]; then
    jwt_secret=$(generate_random)
  fi
  cors_allowed_origins=$(normalize_cors_allowed_origins "$(env_value_or_default CORS_ALLOWED_ORIGINS "${CORS_ALLOWED_ORIGINS:-*}")")
  java_opts_value=$(env_value_or_default JAVA_OPTS "${JAVA_OPTS:--Xms128m -Xmx384m -Dfile.encoding=UTF-8 -Duser.timezone=Asia/Shanghai}")

  umask 077
  set_env_value JWT_SECRET "$jwt_secret"
  set_env_value JWT_EXPIRE_DAYS "$(env_value_or_default JWT_EXPIRE_DAYS "${JWT_EXPIRE_DAYS:-7}")"
  set_env_value CORS_ALLOWED_ORIGINS "$cors_allowed_origins"
  set_env_value FRONTEND_PORT "$FRONTEND_PORT"
  set_env_value BACKEND_PORT "$BACKEND_PORT"
  set_env_value FLUX_PANEL_ACCESS_HOST "$PANEL_ACCESS_HOST_VALUE"
  set_env_value BACKEND_IMAGE "$BACKEND_IMAGE"
  set_env_value FRONTEND_IMAGE "$FRONTEND_IMAGE"
  set_env_value FLUX_PANEL_VERSION "$VERSION"
  set_env_value FLUX_PANEL_REPO "$REPO"
  set_env_value FLUX_GITHUB_PROXY "$GITHUB_PROXY"
  set_env_value FLUX_FORCE_SECURE_NODE_TRANSPORT "$(env_value_or_default FLUX_FORCE_SECURE_NODE_TRANSPORT "${FLUX_FORCE_SECURE_NODE_TRANSPORT:-true}")"
  set_env_value LOGIN_MAX_ATTEMPTS "$(env_value_or_default LOGIN_MAX_ATTEMPTS "${LOGIN_MAX_ATTEMPTS:-5}")"
  set_env_value LOGIN_WINDOW_SECONDS "$(env_value_or_default LOGIN_WINDOW_SECONDS "${LOGIN_WINDOW_SECONDS:-300}")"
  set_env_value LOGIN_LOCK_SECONDS "$(env_value_or_default LOGIN_LOCK_SECONDS "${LOGIN_LOCK_SECONDS:-900}")"
  set_env_value JAVA_OPTS "\"$java_opts_value\""

  echo "✅ 已检查并补齐 .env 配置"
  echo "✅ 前端端口：$FRONTEND_PORT"
  echo "✅ 后端端口：$BACKEND_PORT"
}

select_access_host() {
  local prompt_mode="${1:-always}"
  local default_host
  local input_host
  local saved_host

  if [ -n "${FLUX_PANEL_ACCESS_HOST:-}" ] || [ -n "${PANEL_ACCESS_HOST:-}" ]; then
    PANEL_ACCESS_HOST_VALUE=$(detect_public_host)
    export PANEL_ACCESS_HOST="$PANEL_ACCESS_HOST_VALUE"
    echo "✅ 访问域名/IP：$PANEL_ACCESS_HOST_VALUE"
    return 0
  fi

  saved_host=$(get_saved_access_host || true)
  if [ "$prompt_mode" = "if-missing" ] && [ -n "$saved_host" ]; then
    PANEL_ACCESS_HOST_VALUE="$saved_host"
    export PANEL_ACCESS_HOST="$PANEL_ACCESS_HOST_VALUE"
    echo "✅ 访问域名/IP：$PANEL_ACCESS_HOST_VALUE"
    return 0
  fi

  if [ -n "$saved_host" ]; then
    default_host="$saved_host"
  else
    default_host=$(detect_machine_public_host)
  fi

  echo "🌐 请填写面板访问域名或服务器 IP，用于生成访问地址和预填面板后端地址。"
  echo "   已解析到本机的域名可直接填写；没有域名直接回车使用自动检测值。"
  read -p "访问域名或服务器 IP（默认 $default_host）: " input_host
  input_host="${input_host:-$default_host}"
  PANEL_ACCESS_HOST_VALUE=$(format_access_host "$input_host")

  if [ -z "$PANEL_ACCESS_HOST_VALUE" ]; then
    echo "❌ 访问域名/IP 不能为空。"
    exit 1
  fi

  export PANEL_ACCESS_HOST="$PANEL_ACCESS_HOST_VALUE"
  echo "✅ 访问域名/IP：$PANEL_ACCESS_HOST_VALUE"
}

print_access_diagnostics() {
  local access_host="$1"
  local frontend_port="$2"
  local backend_port="$3"
  local machine_host
  local machine_ip
  local access_url
  local ip_url
  local resolved_ips

  machine_host=$(detect_machine_public_host)
  machine_ip=$(strip_access_host_brackets "$machine_host")
  access_url="http://$access_host:$frontend_port"
  ip_url="http://$machine_host:$frontend_port"

  echo "🎉 部署完成"
  echo "🌐 面板访问地址: $access_url"
  if [ "$machine_host" != "$access_host" ] && [ "$machine_host" != "服务器IP" ]; then
    echo "🌐 服务器 IP 访问地址: $ip_url"
  fi
  echo "💡 默认管理员账号: facker668 / wohenshuai"
  echo "⚠️  登录后请立即修改默认密码！"

  echo ""
  echo "🔎 访问自检："
  if check_http_url "http://127.0.0.1:$frontend_port"; then
    echo "✅ 本机前端端口正常：http://127.0.0.1:$frontend_port"
  else
    echo "⚠️ 本机前端端口未响应，请先执行：docker ps && docker logs vite-frontend --tail 80"
  fi

  if [ "$access_host" != "$machine_host" ] && ! is_ip_literal "$access_host"; then
    resolved_ips=$(resolve_host_ips "$access_host" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    if [ -z "$resolved_ips" ]; then
      echo "⚠️ 域名暂未解析到 IP：$access_host"
    else
      echo "✅ 域名解析结果：$resolved_ips"
      if [ "$machine_host" != "服务器IP" ] && ! printf '%s\n' $resolved_ips | has_ip_in_list "$machine_ip"; then
        echo "⚠️ 域名解析结果和当前服务器公网 IP 不一致：$machine_ip"
      fi
    fi
  fi

  if [ "$access_host" != "服务器IP" ]; then
    if check_http_url "$access_url"; then
      echo "✅ 服务器访问面板地址正常：$access_url"
    else
      echo "⚠️ 服务器访问面板地址失败。若本机端口正常，优先检查域名解析、VPS 安全组和防火墙。"
    fi
  fi

  echo "ℹ️ 外网访问面板需要放行 TCP $frontend_port；节点连接面板需要放行 TCP $backend_port。"
  echo "ℹ️ 如果域名开启了 CDN/代理，$frontend_port 这种非 80/443 端口可能打不开，请关闭代理或配置 80/443 反向代理。"
}

js_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_frontend_runtime_config() {
  local access_host="${1:-$(detect_public_host)}"
  local backend_port="${2:-${BACKEND_PORT:-}}"
  local panel_backend_address
  local js_access_host
  local js_backend_port
  local js_panel_backend_address

  if [ -z "$backend_port" ]; then
    backend_port=$(read_env_value BACKEND_PORT || true)
  fi
  backend_port="${backend_port:-6365}"
  panel_backend_address="${access_host}:${backend_port}"
  js_access_host=$(js_escape "$access_host")
  js_backend_port=$(js_escape "$backend_port")
  js_panel_backend_address=$(js_escape "$panel_backend_address")

  if ! docker ps --format "{{.Names}}" | grep -q "^vite-frontend$"; then
    echo "⚠️ 未检测到前端容器，跳过写入前端运行时配置"
    return 0
  fi

  if docker exec -i vite-frontend sh -c 'cat > /usr/share/nginx/html/runtime-config.js' <<EOF
window.AIZHUANJIAO_RUNTIME_CONFIG = {
  panelBackendAddress: "$js_panel_backend_address",
  backendHost: "$js_access_host",
  backendPort: "$js_backend_port"
};
EOF
  then
    echo "✅ 面板后端地址已预填：$panel_backend_address"
  else
    echo "⚠️ 写入前端运行时配置失败，请在网站配置中手动填写：$panel_backend_address"
  fi
}

# 删除脚本自身
delete_self() {
  if [ "${KEEP_INSTALL_SCRIPT:-0}" = "1" ]; then
    echo "ℹ️ KEEP_INSTALL_SCRIPT=1，保留脚本文件"
    return 0
  fi
  echo ""
  echo "🗑️ 操作已完成，正在清理脚本文件..."
  SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
  sleep 1
  rm -f "$SCRIPT_PATH" && echo "✅ 脚本文件已删除" || echo "❌ 删除脚本文件失败"
}



# 获取配置参数
get_config_params() {
  echo "🔧 正在生成配置参数："

  if [ -z "${FRONTEND_PORT:-}" ]; then
    FRONTEND_PORT=$(find_available_port 6366)
  elif ! is_valid_port "$FRONTEND_PORT"; then
    echo "❌ FRONTEND_PORT 必须是 1-65535 之间的数字。"
    exit 1
  elif is_port_in_use "$FRONTEND_PORT"; then
    echo "❌ FRONTEND_PORT=$FRONTEND_PORT 已被占用，请换一个端口。"
    exit 1
  fi

  if [ -z "${BACKEND_PORT:-}" ]; then
    BACKEND_PORT=$(find_available_port 6365 "$FRONTEND_PORT")
  elif ! is_valid_port "$BACKEND_PORT"; then
    echo "❌ BACKEND_PORT 必须是 1-65535 之间的数字。"
    exit 1
  elif [ "$BACKEND_PORT" = "$FRONTEND_PORT" ]; then
    echo "❌ BACKEND_PORT 不能和 FRONTEND_PORT 使用同一个端口。"
    exit 1
  elif is_port_in_use "$BACKEND_PORT"; then
    echo "❌ BACKEND_PORT=$BACKEND_PORT 已被占用，请换一个端口。"
    exit 1
  fi

  echo "✅ 前端端口：$FRONTEND_PORT"
  echo "✅ 后端端口：$BACKEND_PORT"

  CORS_ALLOWED_ORIGINS=$(normalize_cors_allowed_origins "${CORS_ALLOWED_ORIGINS:-*}")
  echo "✅ 允许跨域来源：$CORS_ALLOWED_ORIGINS"

  select_access_host always

  # 生成JWT密钥
  JWT_SECRET=$(generate_random)
}

# 安装功能
install_panel() {
  echo "🚀 开始安装爱转角转发面板..."
  check_docker 1
  get_config_params
  open_local_firewall_ports "$FRONTEND_PORT" "$BACKEND_PORT"

  echo "🔽 下载必要文件..."
  download_docker_compose docker-compose.yml
  echo "✅ 文件准备完成"

  # 自动检测并配置 IPv6 支持
  if check_ipv6_support; then
    echo "🚀 系统支持 IPv6，自动启用 IPv6 配置..."
    configure_docker_ipv6
  fi

  ensure_panel_images

  umask 077
  cat > .env <<EOF
JWT_SECRET=$JWT_SECRET
JWT_EXPIRE_DAYS=${JWT_EXPIRE_DAYS:-7}
CORS_ALLOWED_ORIGINS=$CORS_ALLOWED_ORIGINS
FRONTEND_PORT=$FRONTEND_PORT
BACKEND_PORT=$BACKEND_PORT
FLUX_PANEL_ACCESS_HOST=$PANEL_ACCESS_HOST_VALUE
BACKEND_IMAGE=$BACKEND_IMAGE
FRONTEND_IMAGE=$FRONTEND_IMAGE
FLUX_PANEL_VERSION=$VERSION
FLUX_PANEL_REPO=$REPO
FLUX_GITHUB_PROXY=$GITHUB_PROXY
FLUX_FORCE_SECURE_NODE_TRANSPORT=${FLUX_FORCE_SECURE_NODE_TRANSPORT:-true}
LOGIN_MAX_ATTEMPTS=${LOGIN_MAX_ATTEMPTS:-5}
LOGIN_WINDOW_SECONDS=${LOGIN_WINDOW_SECONDS:-300}
LOGIN_LOCK_SECONDS=${LOGIN_LOCK_SECONDS:-900}
JAVA_OPTS="${JAVA_OPTS:--Xms128m -Xmx384m -Dfile.encoding=UTF-8 -Duser.timezone=Asia/Shanghai}"
EOF

  echo "🚀 启动 docker 服务..."
  $DOCKER_CMD up -d
  PANEL_ACCESS_HOST_VALUE="${PANEL_ACCESS_HOST_VALUE:-$(detect_public_host)}"
  write_frontend_runtime_config "$PANEL_ACCESS_HOST_VALUE" "$BACKEND_PORT"
  print_access_diagnostics "$PANEL_ACCESS_HOST_VALUE" "$FRONTEND_PORT" "$BACKEND_PORT"


}

# 更新功能
update_panel() {
  echo "🔄 开始更新爱转角转发面板..."
  check_docker
  load_panel_ports_from_env
  select_access_host if-missing
  ensure_panel_env_file
  open_local_firewall_ports "$FRONTEND_PORT" "$BACKEND_PORT"

  echo "🔽 下载最新配置文件..."
  download_docker_compose docker-compose.yml
  echo "✅ 下载完成"

  # 自动检测并配置 IPv6 支持
  if check_ipv6_support; then
    echo "🚀 系统支持 IPv6，自动启用 IPv6 配置..."
    configure_docker_ipv6
  fi

  # 先发送 SIGTERM 信号，让应用优雅关闭
  docker stop -t 30 springboot-backend 2>/dev/null || true
  docker stop -t 10 vite-frontend 2>/dev/null || true

  # 等待 WAL 文件同步
  echo "⏳ 等待数据同步..."
  sleep 5

  # 然后再完全停止
  $DOCKER_CMD down

  echo "⬇️ 拉取最新镜像..."
  $DOCKER_CMD pull

  echo "🚀 启动更新后的服务..."
  $DOCKER_CMD up -d
  write_frontend_runtime_config "$PANEL_ACCESS_HOST_VALUE" "${BACKEND_PORT:-$(read_env_value BACKEND_PORT || true)}"

  # 等待服务启动
  echo "⏳ 等待服务启动..."

  # 检查后端容器健康状态
  echo "🔍 检查后端服务状态..."
  for i in {1..90}; do
    if docker ps --format "{{.Names}}" | grep -q "^springboot-backend$"; then
      BACKEND_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' springboot-backend 2>/dev/null || echo "unknown")
      if [[ "$BACKEND_HEALTH" == "healthy" ]]; then
        echo "✅ 后端服务健康检查通过"
        break
      elif [[ "$BACKEND_HEALTH" == "starting" ]]; then
        # 继续等待
        :
      elif [[ "$BACKEND_HEALTH" == "unhealthy" ]]; then
        echo "⚠️ 后端健康状态：$BACKEND_HEALTH"
      fi
    else
      echo "⚠️ 后端容器未找到或未运行"
      BACKEND_HEALTH="not_running"
    fi
    if [ $i -eq 90 ]; then
      echo "❌ 后端服务启动超时（90秒）"
      echo "🔍 当前状态：$(docker inspect -f '{{.State.Health.Status}}' springboot-backend 2>/dev/null || echo '容器不存在')"
      echo "🛑 更新终止"
      return 1
    fi
    # 每15秒显示一次进度
    if [ $((i % 15)) -eq 1 ]; then
      echo "⏳ 等待后端服务启动... ($i/90) 状态：${BACKEND_HEALTH:-unknown}"
    fi
    sleep 1
  done

  echo "✅ 更新完成"
  print_access_diagnostics "$PANEL_ACCESS_HOST_VALUE" "$FRONTEND_PORT" "$BACKEND_PORT"
}



# 卸载功能
uninstall_panel() {
  echo "🗑️ 开始卸载爱转角转发面板..."
  check_docker

  if [[ ! -f "docker-compose.yml" ]]; then
    echo "⚠️ 未找到 docker-compose.yml 文件，正在下载以完成卸载..."
    download_docker_compose docker-compose.yml
    echo "✅ docker-compose.yml 下载完成"
  fi

  read -p "确认卸载爱转角转发面板吗？此操作将停止并删除所有容器和数据 (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ 取消卸载"
    return 0
  fi

  echo "🛑 停止并删除容器、镜像、卷..."
  $DOCKER_CMD down --rmi all --volumes --remove-orphans
  echo "🧹 删除配置文件..."
  rm -f docker-compose.yml .env
  echo "✅ 卸载完成"
}

# 主逻辑
main() {

  # 显示交互式菜单
  while true; do
    show_menu
    read -p "请输入选项 (1-4): " choice

    case $choice in
      1)
        install_panel
        delete_self
        exit 0
        ;;
      2)
        update_panel
        delete_self
        exit 0
        ;;
      3)
        uninstall_panel
        delete_self
        exit 0
        ;;
      4)
        echo "👋 退出脚本"
        delete_self
        exit 0
        ;;
      *)
        echo "❌ 无效选项，请输入 1-4"
        echo ""
        ;;
    esac
  done
}

# 执行主函数
main
