#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/health-check.env"
ENV_FILE="${1:-$DEFAULT_ENV_FILE}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${SSH_USER:=yangli}"
: "${SSH_OPTIONS:=-o BatchMode=yes -o ConnectTimeout=5}"
: "${NODE1_HOST:=node1}"
: "${NODE1_IP:=192.168.88.101}"
: "${NODE2_HOST:=node2}"
: "${NODE2_IP:=192.168.88.102}"
: "${NODE3_HOST:=node3}"
: "${NODE3_IP:=192.168.88.103}"
: "${ORDERER_HOST:=orderer.example.com}"
: "${PEER1_HOST:=peer0.org1.example.com}"
: "${PEER2_HOST:=peer0.org2.example.com}"
: "${FABRIC_WORKSPACE:=/home/yangli/Documents/fabric-workspace/network}"
: "${FABRIC_BIN_DIR:=/home/yangli/Documents/fabric-workspace/bin}"
: "${DOCKER_COMPOSE_FILE:=/home/yangli/Documents/fabric-workspace/network/docker/docker-compose.yaml}"
: "${DOCKER_NETWORK_NAME:=fabric_net}"
: "${REPORT_DIR:=${SCRIPT_DIR}/reports}"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/stage6-health-check-${TIMESTAMP}.md"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
RESULT_LINES=()

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

sanitize_detail() {
  printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/|/\//g'
}

record_result() {
  local status="$1"
  local title="$2"
  local detail="$3"
  local safe_detail
  safe_detail="$(sanitize_detail "$detail")"

  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
  esac

  RESULT_LINES+=("- [${status}] ${title}: ${safe_detail}")
  printf '[%s] %s: %s\n' "$status" "$title" "$safe_detail"
}

run_capture() {
  local output
  if output="$("$@" 2>&1)"; then
    printf '%s' "$output"
    return 0
  fi
  printf '%s' "$output"
  return 1
}

run_remote_capture() {
  local host="$1"
  local output
  if output="$(ssh ${SSH_OPTIONS} "${SSH_USER}@${host}" "$2" 2>&1)"; then
    printf '%s' "$output"
    return 0
  fi
  printf '%s' "$output"
  return 1
}

has_host_mapping() {
  local host="$1"
  local expected_ip="$2"
  local output
  output="$(run_capture getent hosts "$host")" || return 1
  printf '%s\n' "$output" | awk '{print $1}' | grep -Fxq "$expected_ip"
}

current_ipv4_contains() {
  local expected_ip="$1"
  local output
  output="$(run_capture hostname -I)" || return 1
  printf '%s\n' "$output" | tr ' ' '\n' | grep -Fxq "$expected_ip"
}

binary_path() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi

  if [[ -x "${FABRIC_BIN_DIR}/${name}" ]]; then
    printf '%s' "${FABRIC_BIN_DIR}/${name}"
    return 0
  fi

  return 1
}

check_local_hostname() {
  local actual
  actual="$(run_capture hostname)" || {
    record_result "FAIL" "node1 主机名读取" "无法读取本机 hostname"
    return
  }

  actual="$(trim "$actual")"
  if [[ "$actual" == "$NODE1_HOST" ]]; then
    record_result "PASS" "node1 主机名" "当前主机名为 ${actual}"
  else
    record_result "FAIL" "node1 主机名" "期望 ${NODE1_HOST}，实际 ${actual}"
  fi
}

check_local_ip() {
  local output
  output="$(run_capture hostname -I)" || {
    record_result "FAIL" "node1 IP" "无法读取本机 IPv4"
    return
  }

  if current_ipv4_contains "$NODE1_IP"; then
    record_result "PASS" "node1 IP" "本机 IPv4 包含 ${NODE1_IP}，实际 ${output}"
  else
    record_result "FAIL" "node1 IP" "本机 IPv4 不包含 ${NODE1_IP}，实际 ${output}"
  fi
}

check_hosts_mapping() {
  local host="$1"
  local ip="$2"
  local output
  output="$(run_capture getent hosts "$host")" || {
    record_result "FAIL" "hosts 解析 ${host}" "getent hosts ${host} 失败"
    return
  }

  if has_host_mapping "$host" "$ip"; then
    record_result "PASS" "hosts 解析 ${host}" "解析到 ${ip}，实际 ${output}"
  else
    record_result "FAIL" "hosts 解析 ${host}" "期望 ${ip}，实际 ${output}"
  fi
}

check_ping() {
  local host="$1"
  local output
  output="$(run_capture ping -c 1 -W 2 "$host")" || {
    record_result "FAIL" "ping ${host}" "连通性失败：${output}"
    return
  }
  record_result "PASS" "ping ${host}" "网络连通"
}

check_remote_hostname() {
  local host="$1"
  local expected="$2"
  local output
  output="$(run_remote_capture "$host" "hostname")" || {
    record_result "FAIL" "SSH ${host}" "SSH 登录或 hostname 读取失败：${output}"
    return
  }

  output="$(trim "$output")"
  if [[ "$output" == "$expected" ]]; then
    record_result "PASS" "SSH ${host}" "远端 hostname 为 ${output}"
  else
    record_result "FAIL" "SSH ${host}" "期望 hostname ${expected}，实际 ${output}"
  fi
}

check_command_available() {
  local label="$1"
  shift
  local output
  output="$(run_capture "$@")" || {
    record_result "FAIL" "$label" "$output"
    return
  }
  record_result "PASS" "$label" "$output"
}

check_remote_command_available() {
  local host="$1"
  local label="$2"
  local command="$3"
  local output
  output="$(run_remote_capture "$host" "$command")" || {
    record_result "FAIL" "${label}" "$output"
    return
  }
  record_result "PASS" "${label}" "$output"
}

check_path_exists() {
  local label="$1"
  local path="$2"
  if [[ -e "$path" ]]; then
    record_result "PASS" "$label" "存在 ${path}"
  else
    record_result "FAIL" "$label" "不存在 ${path}"
  fi
}

check_fabric_binary() {
  local name="$1"
  local path
  local output

  path="$(binary_path "$name")" || {
    record_result "FAIL" "Fabric 二进制 ${name}" "未找到 ${name}，也未在 ${FABRIC_BIN_DIR}/${name} 发现可执行文件"
    return
  }

  output="$(run_capture "$path" version)" || output="$(run_capture "$path" --version)" || {
    record_result "FAIL" "Fabric 二进制 ${name}" "找到 ${path}，但执行版本命令失败"
    return
  }

  record_result "PASS" "Fabric 二进制 ${name}" "${path} | ${output}"
}

check_remote_fabric_binary() {
  local host="$1"
  local name="$2"
  local command_text
  local output

  command_text="if command -v ${name} >/dev/null 2>&1; then \$(command -v ${name}) version 2>/dev/null || \$(command -v ${name}) --version 2>/dev/null; elif [[ -x '${FABRIC_BIN_DIR}/${name}' ]]; then '${FABRIC_BIN_DIR}/${name}' version 2>/dev/null || '${FABRIC_BIN_DIR}/${name}' --version 2>/dev/null; else exit 127; fi"
  output="$(run_remote_capture "$host" "$command_text")" || {
    record_result "FAIL" "远端 Fabric 二进制 ${name}@${host}" "未找到可执行文件，或版本命令失败：${output}"
    return
  }

  record_result "PASS" "远端 Fabric 二进制 ${name}@${host}" "$output"
}

check_proxy_bypass() {
  local raw="${NO_PROXY:-${no_proxy:-}}"
  local hosts_ok=true
  local node_ip_ok=true
  local localhost_ok=true

  if [[ -z "$raw" ]]; then
    record_result "FAIL" "NO_PROXY/no_proxy" "未设置代理绕过环境变量"
    return
  fi

  if [[ "$raw" != *"localhost"* || "$raw" != *"127.0.0.1"* ]]; then
    localhost_ok=false
  fi

  if [[ "$raw" != *"192.168.88.0/24"* ]]; then
    for ip in "$NODE1_IP" "$NODE2_IP" "$NODE3_IP"; do
      if [[ "$raw" != *"$ip"* ]]; then
        node_ip_ok=false
      fi
    done
  fi

  for host in "$NODE1_HOST" "$NODE2_HOST" "$NODE3_HOST" "$ORDERER_HOST" "$PEER1_HOST" "$PEER2_HOST"; do
    if [[ "$raw" != *"$host"* ]]; then
      hosts_ok=false
    fi
  done

  if [[ "$localhost_ok" == true && "$node_ip_ok" == true && "$hosts_ok" == true ]]; then
    record_result "PASS" "NO_PROXY/no_proxy" "$raw"
  else
    record_result "FAIL" "NO_PROXY/no_proxy" "当前值为 ${raw}；需覆盖 localhost/127.0.0.1、三节点 IP（或 192.168.88.0/24）以及 Fabric 主机名"
  fi
}

check_remote_proxy_bypass() {
  local host="$1"
  local output
  output="$(run_remote_capture "$host" "printf '%s' \"\${NO_PROXY:-\${no_proxy:-}}\"")" || {
    record_result "FAIL" "远端代理绕过 ${host}" "无法读取远端 NO_PROXY/no_proxy：${output}"
    return
  }

  if [[ -z "$output" ]]; then
    record_result "FAIL" "远端代理绕过 ${host}" "远端未设置 NO_PROXY/no_proxy"
  else
    record_result "PASS" "远端代理绕过 ${host}" "$output"
  fi
}

check_docker_network() {
  local output
  output="$(run_capture docker network inspect "$DOCKER_NETWORK_NAME")" || {
    record_result "WARN" "Docker 网络 ${DOCKER_NETWORK_NAME}" "尚未创建或无法 inspect；若阶段8前未创建需补建"
    return
  }

  record_result "PASS" "Docker 网络 ${DOCKER_NETWORK_NAME}" "$output"
}

write_report() {
  {
    printf '# 阶段6基础设施健康检查报告\n\n'
    printf -- '- 生成时间：%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf -- '- 执行节点：%s\n' "${NODE1_HOST}"
    printf -- '- 检查脚本：%s\n' "${SCRIPT_DIR}/infrastructure-health-check.sh"
    printf -- '- 配置文件：%s\n\n' "$ENV_FILE"

    printf '## 汇总\n\n'
    printf -- '- PASS: %s\n' "$PASS_COUNT"
    printf -- '- WARN: %s\n' "$WARN_COUNT"
    printf -- '- FAIL: %s\n\n' "$FAIL_COUNT"

    printf '## 明细\n\n'
    printf '%s\n' "${RESULT_LINES[@]}"
    printf '\n## 结论\n\n'

    if [[ "$FAIL_COUNT" -eq 0 ]]; then
      printf '阶段6检查通过，可进入下一阶段；如仍存在 WARN，进入阶段7前需人工复核。\n'
    else
      printf '阶段6检查未通过，必须先修复全部 FAIL 项，再进入阶段7。\n'
    fi
  } > "$REPORT_FILE"
}

printf '开始执行阶段6基础设施健康检查...\n'

check_local_hostname
check_local_ip
check_hosts_mapping "$NODE1_HOST" "$NODE1_IP"
check_hosts_mapping "$NODE2_HOST" "$NODE2_IP"
check_hosts_mapping "$NODE3_HOST" "$NODE3_IP"
check_hosts_mapping "$ORDERER_HOST" "$NODE1_IP"
check_hosts_mapping "$PEER1_HOST" "$NODE2_IP"
check_hosts_mapping "$PEER2_HOST" "$NODE3_IP"

check_ping "$NODE2_HOST"
check_ping "$NODE3_HOST"
check_remote_hostname "$NODE2_HOST" "$NODE2_HOST"
check_remote_hostname "$NODE3_HOST" "$NODE3_HOST"

check_command_available "node1 docker" docker --version
check_command_available "node1 docker compose" docker compose version
check_command_available "node1 go" go version
check_remote_command_available "$NODE2_HOST" "node2 docker" "docker --version"
check_remote_command_available "$NODE2_HOST" "node2 docker compose" "docker compose version"
check_remote_command_available "$NODE2_HOST" "node2 go" "go version"
check_remote_command_available "$NODE3_HOST" "node3 docker" "docker --version"
check_remote_command_available "$NODE3_HOST" "node3 docker compose" "docker compose version"
check_remote_command_available "$NODE3_HOST" "node3 go" "go version"

check_path_exists "Fabric 工作区" "$FABRIC_WORKSPACE"
check_path_exists "Fabric Docker Compose 文件" "$DOCKER_COMPOSE_FILE"
check_fabric_binary "peer"
check_fabric_binary "orderer"
check_fabric_binary "configtxgen"
check_fabric_binary "cryptogen"
check_remote_fabric_binary "$NODE2_HOST" "peer"

check_proxy_bypass
check_remote_proxy_bypass "$NODE2_HOST"
check_remote_proxy_bypass "$NODE3_HOST"
check_docker_network

write_report

printf '\n报告已生成：%s\n' "$REPORT_FILE"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
