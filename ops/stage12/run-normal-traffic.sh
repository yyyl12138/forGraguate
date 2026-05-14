#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${1:-${REPO_DIR}/ops/vm-runtime.env}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  exit 1
}

load_env() {
  [[ -f "$ENV_FILE" ]] || fail "runtime env missing: ${ENV_FILE}"
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a
}

set_defaults() {
  : "${LOGTRACE_TOMCAT_URL:=http://127.0.0.1:18080}"
  : "${LOGTRACE_TOMCAT_LOG_DIR:=/opt/log-trace/vulhub-logs/tomcat}"
  : "${LOGTRACE_STAGE12_NORMAL_MIN_SLEEP:=1}"
  : "${LOGTRACE_STAGE12_NORMAL_MAX_SLEEP:=5}"
  : "${LOGTRACE_STAGE12_NORMAL_BURST_MIN:=1}"
  : "${LOGTRACE_STAGE12_NORMAL_BURST_MAX:=4}"
}

rand_between() {
  local min="$1"
  local max="$2"
  if (( max <= min )); then
    printf '%s\n' "$min"
    return 0
  fi
  printf '%s\n' $(( min + RANDOM % (max - min + 1) ))
}

random_ip() {
  printf '198.51.100.%s\n' "$(rand_between 1 254)"
}

random_user_agent() {
  local agents=(
    "Mozilla/5.0 Stage12Browser/1.0"
    "curl/8.5 stage12-health"
    "LogTraceSyntheticClient/2026"
    "Apache-HttpClient stage12"
    "Mozilla/5.0 Chrome/Stage12"
  )
  printf '%s\n' "${agents[$((RANDOM % ${#agents[@]}))]}"
}

random_path() {
  local paths=(
    "/"
    "/index.jsp"
    "/docs"
    "/assets/app.js"
    "/favicon.ico"
    "/health"
    "/search"
    "/api/status"
  )
  local path="${paths[$((RANDOM % ${#paths[@]}))]}"
  local query="sid=$(printf '%04x' "$RANDOM")&page=$(rand_between 1 9)&t=$(date +%s)"
  if [[ "$path" == "/" ]]; then
    printf '/?%s\n' "$query"
  else
    printf '%s?%s\n' "$path" "$query"
  fi
}

preflight() {
  command -v curl >/dev/null 2>&1 || fail "curl is required"
  curl -fsS "${LOGTRACE_TOMCAT_URL}/" >/dev/null || fail "Tomcat is not reachable: ${LOGTRACE_TOMCAT_URL}"
  [[ -d "$LOGTRACE_TOMCAT_LOG_DIR" ]] || fail "Tomcat log dir not found: ${LOGTRACE_TOMCAT_LOG_DIR}"
}

main() {
  load_env
  set_defaults
  preflight
  log "normal traffic started; stop with Ctrl+C"
  log "Tomcat URL: ${LOGTRACE_TOMCAT_URL}"
  log "Note: random IP is sent as X-Forwarded-For only; current Tomcat parser may still store Docker gateway IP."
  while true; do
    burst="$(rand_between "$LOGTRACE_STAGE12_NORMAL_BURST_MIN" "$LOGTRACE_STAGE12_NORMAL_BURST_MAX")"
    for _ in $(seq 1 "$burst"); do
      ip="$(random_ip)"
      ua="$(random_user_agent)"
      path="$(random_path)"
      status="$(curl -sS -o /dev/null -w '%{http_code}' \
        -H "X-Forwarded-For: ${ip}" \
        -H "User-Agent: ${ua}" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        "${LOGTRACE_TOMCAT_URL}${path}" || true)"
      log "GET ${path} status=${status} simulated_ip=${ip}"
      sleep "$(rand_between 0 1)"
    done
    sleep "$(rand_between "$LOGTRACE_STAGE12_NORMAL_MIN_SLEEP" "$LOGTRACE_STAGE12_NORMAL_MAX_SLEEP")"
  done
}

main "$@"
