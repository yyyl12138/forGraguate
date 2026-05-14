#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${1:-${REPO_DIR}/ops/vm-runtime.env}"
MODE="${STAGE12_MODE:-demo}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

fail() {
  printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  bash ops/stage12/run-stage12-preflight.sh [env-file]
  bash ops/stage12/run-stage12-preflight.sh --check-only [env-file]

Default mode creates a fresh real-time demo batch by sending GET and PUT
traffic to Vulhub Tomcat, then waits for auto seal to CHAIN_COMMITTED.
--check-only only verifies services and API reachability.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--check-only" ]]; then
  MODE="check-only"
  ENV_FILE="${2:-${REPO_DIR}/ops/vm-runtime.env}"
fi

load_env() {
  [[ -f "$ENV_FILE" ]] || fail "runtime env missing: ${ENV_FILE}"
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a
}

set_defaults() {
  : "${LOGTRACE_PROJECT_DIR:=${REPO_DIR}}"
  : "${LOGTRACE_BACKEND_URL:=http://127.0.0.1:8080}"
  : "${LOGTRACE_TOMCAT_URL:=http://127.0.0.1:18080}"
  : "${LOGTRACE_TOMCAT_LOG_DIR:=/opt/log-trace/vulhub-logs/tomcat}"
  : "${LOGTRACE_FILEBEAT_SERVICE:=filebeat}"
  : "${LOGTRACE_RELAY_SYSTEMD_SERVICE:=log-relay.service}"
  : "${LOGTRACE_RELAY_SPOOL_GLOB:=/var/spool/logtrace-stage10/filebeat-stage10*}"
  : "${LOGTRACE_RELAY_DEAD_LETTER_PATH:=/var/lib/logtrace-stage10/dead-letter.ndjson}"
  : "${LOGTRACE_NODE1_JDBC_USERNAME:=logtrace_app}"
  : "${LOGTRACE_NODE1_JDBC_PASSWORD:=123456}"
  : "${LOGTRACE_STAGE12_USERNAME:=${LOGTRACE_STAGE11_USERNAME:-admin}}"
  : "${LOGTRACE_STAGE12_PASSWORD:=${LOGTRACE_STAGE11_PASSWORD:-Admin@123456}}"
  : "${LOGTRACE_STAGE12_DISPLAY_NAME:=Stage12 Admin}"
  : "${LOGTRACE_STAGE12_SOURCE:=tomcat-cve-2017-12615}"
  : "${LOGTRACE_STAGE12_FRONTEND_URL:=http://192.168.88.101:5173}"
  : "${LOGTRACE_STAGE12_MAX_WAIT_SECONDS:=420}"
  : "${LOGTRACE_STAGE12_POLL_SECONDS:=10}"
  : "${LOGTRACE_STAGE12_NORMAL_GET_COUNT:=3}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

require_file() {
  [[ -f "$1" ]] || fail "$2 not found: $1"
}

require_dir() {
  [[ -d "$1" ]] || fail "$2 not found: $1"
}

require_commands() {
  require_command curl
  require_command python3
  require_command mysql
  require_command systemctl
}

check_services() {
  log "checking backend: ${LOGTRACE_BACKEND_URL}/swagger-ui.html"
  curl -fsS "${LOGTRACE_BACKEND_URL}/swagger-ui.html" >/dev/null || fail "backend is not reachable"

  log "checking Tomcat: ${LOGTRACE_TOMCAT_URL}/"
  curl -fsS "${LOGTRACE_TOMCAT_URL}/" >/dev/null || fail "Tomcat is not reachable"

  log "checking systemd services"
  systemctl is-active --quiet "$LOGTRACE_FILEBEAT_SERVICE" || fail "${LOGTRACE_FILEBEAT_SERVICE} is not active"
  systemctl is-active --quiet "$LOGTRACE_RELAY_SYSTEMD_SERVICE" || fail "${LOGTRACE_RELAY_SYSTEMD_SERVICE} is not active"

  require_dir "$LOGTRACE_TOMCAT_LOG_DIR" "Tomcat log dir"
  if ! compgen -G "${LOGTRACE_TOMCAT_LOG_DIR}/localhost_access_log.*.txt" >/dev/null; then
    fail "Tomcat access log file not found under ${LOGTRACE_TOMCAT_LOG_DIR}"
  fi

  log "checking spool glob: ${LOGTRACE_RELAY_SPOOL_GLOB}"
  if ! compgen -G "$LOGTRACE_RELAY_SPOOL_GLOB" >/dev/null; then
    warn "no relay spool files matched yet; this can be normal before new traffic"
  fi

  if [[ -f "$LOGTRACE_RELAY_DEAD_LETTER_PATH" ]]; then
    local dead_count
    dead_count="$(wc -l <"$LOGTRACE_RELAY_DEAD_LETTER_PATH" | tr -d ' ')"
    log "dead-letter lines: ${dead_count}"
  fi
}

mysql_query() {
  MYSQL_PWD="$LOGTRACE_NODE1_JDBC_PASSWORD" mysql \
    -N -B -h127.0.0.1 -u"$LOGTRACE_NODE1_JDBC_USERNAME" -Dlogtrace_node1 \
    -e "$1"
}

latest_batches() {
  mysql_query "SELECT batch_id, source, log_count, seal_status, COALESCE(chain_tx_id, '')
               FROM log_batches
               WHERE source='${LOGTRACE_STAGE12_SOURCE}'
               ORDER BY start_time DESC
               LIMIT 5;"
}

register_or_login() {
  log "registering demo account if needed: ${LOGTRACE_STAGE12_USERNAME}"
  local register_status
  register_status="$(curl -sS -o /tmp/logtrace-stage12-register.json -w '%{http_code}' \
    -X POST "${LOGTRACE_BACKEND_URL}/api/auth/register" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${LOGTRACE_STAGE12_USERNAME}\",\"password\":\"${LOGTRACE_STAGE12_PASSWORD}\",\"display_name\":\"${LOGTRACE_STAGE12_DISPLAY_NAME}\"}" || true)"
  if [[ "$register_status" != "200" && "$register_status" != "201" && "$register_status" != "409" && "$register_status" != "400" ]]; then
    warn "register returned HTTP ${register_status}; continuing with login"
    sed 's/^/[register] /' /tmp/logtrace-stage12-register.json >&2 || true
  fi

  log "logging in demo account"
  local login_json
  login_json="$(curl -fsS -X POST "${LOGTRACE_BACKEND_URL}/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${LOGTRACE_STAGE12_USERNAME}\",\"password\":\"${LOGTRACE_STAGE12_PASSWORD}\"}")"
  TOKEN="$(printf '%s' "$login_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")"
  [[ -n "$TOKEN" ]] || fail "login did not return an access token"
  export TOKEN
  log "JWT acquired"
}

api_get() {
  curl -fsS "$1" -H "Authorization: Bearer ${TOKEN}"
}

api_post_json() {
  curl -fsS -X POST "$1" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "$2"
}

exercise_basic_apis() {
  log "checking authenticated APIs"
  api_get "${LOGTRACE_BACKEND_URL}/api/auth/me" >/tmp/logtrace-stage12-me.json
  api_get "${LOGTRACE_BACKEND_URL}/api/batches?source=${LOGTRACE_STAGE12_SOURCE}&page=0&size=5" >/tmp/logtrace-stage12-batches.json
  api_get "${LOGTRACE_BACKEND_URL}/api/ledger/batches?source=${LOGTRACE_STAGE12_SOURCE}" >/tmp/logtrace-stage12-ledger.json
  api_get "${LOGTRACE_BACKEND_URL}/api/audits/logins?page=0&size=5" >/tmp/logtrace-stage12-logins.json
  log "authenticated APIs reachable"
}

wait_for_fresh_window() {
  log "waiting for a fresh UTC minute window"
  local initial_minute
  initial_minute="$(date -u '+%Y-%m-%dT%H:%M')"
  while [[ "$(date -u '+%Y-%m-%dT%H:%M')" == "$initial_minute" ]]; do
    sleep 1
  done
  WINDOW_START="$(date -u '+%Y-%m-%dT%H:%M:00Z')"
  EXPECTED_BATCH_ID="bch_v1_${LOGTRACE_STAGE12_SOURCE}_$(date -u '+%Y%m%dT%H%M00Z')"
  export WINDOW_START EXPECTED_BATCH_ID
  log "fresh window started: ${WINDOW_START}"
  log "expected batch_id: ${EXPECTED_BATCH_ID}"
}

trigger_realtime_traffic() {
  log "triggering normal GET traffic"
  for _ in $(seq 1 "$LOGTRACE_STAGE12_NORMAL_GET_COUNT"); do
    curl -fsS "${LOGTRACE_TOMCAT_URL}/" >/dev/null || true
    sleep 1
  done

  log "triggering attack PUT traffic"
  curl -fsS -o /tmp/logtrace-stage12-put.out -w 'PUT_HTTP_STATUS=%{http_code}\n' \
    -X PUT "${LOGTRACE_TOMCAT_URL}/shell.jsp/" \
    -H 'Content-Range: bytes 0-5/6' \
    -H 'Content-Type: application/octet-stream' \
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
      WHERE batch_id='${EXPECTED_BATCH_ID}' AND request_method='PUT' AND request_uri LIKE '%/shell.jsp%'
      ORDER BY inserted_at DESC
      LIMIT 1;" | head -n 1 || true)"
    if [[ -n "${ATTACK_LOG_ID:-}" ]]; then
      export ATTACK_LOG_ID
      log "attack log found: ${ATTACK_LOG_ID}"
      return 0
    fi
    log "waiting for ingest... elapsed=${elapsed}s"
    sleep "$LOGTRACE_STAGE12_POLL_SECONDS"
    elapsed=$((elapsed + LOGTRACE_STAGE12_POLL_SECONDS))
  done
  print_diagnostics
  fail "attack log was not ingested for ${EXPECTED_BATCH_ID}"
}

wait_for_committed_batch() {
  log "waiting for auto seal to CHAIN_COMMITTED"
  local elapsed=0
  while (( elapsed <= LOGTRACE_STAGE12_MAX_WAIT_SECONDS )); do
    local row
    row="$(mysql_query "SELECT batch_id, log_count, seal_status, COALESCE(chain_tx_id, '')
      FROM log_batches
      WHERE batch_id='${EXPECTED_BATCH_ID}'
      LIMIT 1;" | head -n 1 || true)"
    if [[ -n "$row" ]]; then
      log "batch row: ${row}"
      if awk -F'\t' '{ exit ($3 == "CHAIN_COMMITTED" && length($4) > 0 ? 0 : 1) }' <<<"$row"; then
        BATCH_ID="$(awk -F'\t' '{print $1}' <<<"$row")"
        CHAIN_TX_ID="$(awk -F'\t' '{print $4}' <<<"$row")"
        export BATCH_ID CHAIN_TX_ID
        return 0
      fi
    fi
    log "waiting for seal... elapsed=${elapsed}s"
    sleep "$LOGTRACE_STAGE12_POLL_SECONDS"
    elapsed=$((elapsed + LOGTRACE_STAGE12_POLL_SECONDS))
  done
  print_diagnostics
  fail "batch did not reach CHAIN_COMMITTED: ${EXPECTED_BATCH_ID}"
}

verify_batch_apis() {
  log "checking batch detail, ledger detail, log search, integrity, and audits"
  api_get "${LOGTRACE_BACKEND_URL}/api/batches/${BATCH_ID}" >/tmp/logtrace-stage12-batch-detail.json
  api_get "${LOGTRACE_BACKEND_URL}/api/ledger/batches/${BATCH_ID}" >/tmp/logtrace-stage12-ledger-detail.json
  api_get "${LOGTRACE_BACKEND_URL}/api/logs/search?batch_id=${BATCH_ID}&request_uri=%2Fshell.jsp%2F&page=0&size=10" >/tmp/logtrace-stage12-logs.json
  api_post_json "${LOGTRACE_BACKEND_URL}/api/integrity/check" "{\"batch_id\":\"${BATCH_ID}\"}" >/tmp/logtrace-stage12-integrity.json
  api_get "${LOGTRACE_BACKEND_URL}/api/audits/operations?page=0&size=5" >/tmp/logtrace-stage12-operations.json

  LEDGER_ROOT="$(python3 -c "import json; print(json.load(open('/tmp/logtrace-stage12-integrity.json'))['ledger_root'])")"
  ABNORMAL_COUNT="$(python3 -c "import json; print(len(json.load(open('/tmp/logtrace-stage12-integrity.json'))['abnormal_nodes']))")"
  LOG_TOTAL="$(python3 -c "import json; print(json.load(open('/tmp/logtrace-stage12-logs.json'))['total'])")"
  export LEDGER_ROOT ABNORMAL_COUNT LOG_TOTAL

  [[ "$ABNORMAL_COUNT" == "0" ]] || fail "fresh demo batch integrity is abnormal; see /tmp/logtrace-stage12-integrity.json"
  [[ "$LOG_TOTAL" != "0" ]] || fail "log search did not find /shell.jsp/ for ${BATCH_ID}"
}

print_diagnostics() {
  warn "diagnostics"
  systemctl --no-pager --full status "$LOGTRACE_FILEBEAT_SERVICE" | sed -n '1,12p' >&2 || true
  systemctl --no-pager --full status "$LOGTRACE_RELAY_SYSTEMD_SERVICE" | sed -n '1,12p' >&2 || true
  ls -lh /var/spool/logtrace-stage10 >&2 || true
  tail -n 20 "${LOGTRACE_TOMCAT_LOG_DIR}"/localhost_access_log.*.txt >&2 || true
  if [[ -f "$LOGTRACE_RELAY_DEAD_LETTER_PATH" ]]; then
    tail -n 20 "$LOGTRACE_RELAY_DEAD_LETTER_PATH" >&2 || true
  fi
  latest_batches | sed 's/^/[batch] /' >&2 || true
}

print_summary() {
  cat <<EOF

Stage 12 preflight PASS

Frontend URL:
  ${LOGTRACE_STAGE12_FRONTEND_URL}

Login:
  username=${LOGTRACE_STAGE12_USERNAME}
  password=${LOGTRACE_STAGE12_PASSWORD}

Fresh demo batch:
  batch_id=${BATCH_ID:-<not-created-in-check-only-mode>}
  attack_log_id=${ATTACK_LOG_ID:-<not-created-in-check-only-mode>}
  ledger_root=${LEDGER_ROOT:-<not-created-in-check-only-mode>}
  chain_tx_id=${CHAIN_TX_ID:-<not-created-in-check-only-mode>}

Browser pages:
  ${LOGTRACE_STAGE12_FRONTEND_URL}/batches
  ${LOGTRACE_STAGE12_FRONTEND_URL}/batches/${BATCH_ID:-<batch_id>}
  ${LOGTRACE_STAGE12_FRONTEND_URL}/ledger?batch_id=${BATCH_ID:-<batch_id>}
  ${LOGTRACE_STAGE12_FRONTEND_URL}/logs
  ${LOGTRACE_STAGE12_FRONTEND_URL}/integrity?batch_id=${BATCH_ID:-<batch_id>}
  ${LOGTRACE_STAGE12_FRONTEND_URL}/audits

Temporary API evidence:
  /tmp/logtrace-stage12-batch-detail.json
  /tmp/logtrace-stage12-ledger-detail.json
  /tmp/logtrace-stage12-logs.json
  /tmp/logtrace-stage12-integrity.json
  /tmp/logtrace-stage12-operations.json
EOF
}

main() {
  load_env
  set_defaults
  require_commands
  require_file "$ENV_FILE" "runtime env"
  check_services
  register_or_login
  exercise_basic_apis
  log "recent committed batches"
  latest_batches | sed 's/^/[batch] /' || true

  if [[ "$MODE" == "check-only" ]]; then
    BATCH_ID=""
    print_summary
    return 0
  fi

  wait_for_fresh_window
  trigger_realtime_traffic
  wait_for_attack_log
  wait_for_committed_batch
  verify_batch_apis
  print_summary
}

main "$@"
