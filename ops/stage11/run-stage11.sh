#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${LOGTRACE_ENV_FILE:-${REPO_DIR}/ops/vm-runtime.env}"
MODE="${1:-all}"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="${SCRIPT_DIR}/reports"
REPORT_FILE="${REPORT_DIR}/stage11-${TIMESTAMP}.md"
CREATED_BATCH_ID=""
CREATED_ATTACK_LOG_ID=""
SCENARIO_START_SQL=""
MYSQL_ROOT_CLI=()

log() {
  local message="$*"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >&2
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >>"$REPORT_FILE"
}

fail() {
  local message="$*"
  printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >&2
  printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >>"$REPORT_FILE"
  exit 1
}

run_report() {
  log "+ $1"
  "$@" 2>&1 | tee -a "$REPORT_FILE"
}

load_env() {
  [[ -f "$ENV_FILE" ]] || fail "runtime env missing: ${ENV_FILE}. Copy ops/vm-runtime.env.example to ops/vm-runtime.env first."
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a
}

set_defaults() {
  : "${LOGTRACE_BACKEND_URL:=http://127.0.0.1:8080}"
  : "${LOGTRACE_TOMCAT_URL:=http://127.0.0.1:18080}"
  : "${LOGTRACE_TOMCAT_LOG_DIR:=/opt/log-trace/vulhub-logs/tomcat}"
  : "${LOGTRACE_AUTO_SEAL_SOURCE:=tomcat-cve-2017-12615}"
  : "${LOGTRACE_STAGE11_USERNAME:=admin}"
  : "${LOGTRACE_STAGE11_PASSWORD:=Admin@123456}"
  : "${LOGTRACE_STAGE11_DISPLAY_NAME:=Stage11 Admin}"
  : "${LOGTRACE_STAGE11_MAX_WAIT_SECONDS:=420}"
  : "${LOGTRACE_STAGE11_POLL_SECONDS:=10}"
  : "${LOGTRACE_STAGE11_NOISE_COUNT:=20}"
  : "${LOGTRACE_NODE1_JDBC_USERNAME:=logtrace_app}"
  : "${LOGTRACE_NODE2_JDBC_USERNAME:=logtrace_app}"
  : "${LOGTRACE_NODE3_JDBC_USERNAME:=logtrace_app}"
  : "${LOGTRACE_STAGE11_TAMPER_MYSQL_CLI:=sudo mysql -Dlogtrace_node1}"
  read -r -a MYSQL_ROOT_CLI <<<"$LOGTRACE_STAGE11_TAMPER_MYSQL_CLI"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

mysql_query() {
  local host="$1"
  local db="$2"
  local user="$3"
  local pass="$4"
  local sql="$5"
  MYSQL_PWD="$pass" mysql -N -B -h"$host" -u"$user" -D"$db" -e "$sql"
}

mysql_table() {
  local host="$1"
  local db="$2"
  local user="$3"
  local pass="$4"
  local sql="$5"
  MYSQL_PWD="$pass" mysql -h"$host" -u"$user" -D"$db" -e "$sql"
}

json_post() {
  local endpoint="$1"
  local body="$2"
  shift 2
  curl -fsS -X POST "${LOGTRACE_BACKEND_URL}${endpoint}" \
    -H "Content-Type: application/json" \
    "$@" \
    -d "$body"
}

preflight() {
  mkdir -p "$REPORT_DIR"
  : >"$REPORT_FILE"
  log "# Stage11 report ${TIMESTAMP}"
  log "mode=${MODE}"
  log "env=${ENV_FILE}"

  require_command curl
  require_command python3
  require_command mysql
  require_command sudo

  [[ "$MODE" =~ ^(missing|modified|extra|all)$ ]] || fail "invalid mode: ${MODE}. Use missing, modified, extra, or all."
  [[ -n "${LOGTRACE_NODE1_JDBC_PASSWORD:-}" ]] || fail "LOGTRACE_NODE1_JDBC_PASSWORD is required"
  [[ -n "${LOGTRACE_NODE2_JDBC_PASSWORD:-}" ]] || fail "LOGTRACE_NODE2_JDBC_PASSWORD is required"
  [[ -n "${LOGTRACE_NODE3_JDBC_PASSWORD:-}" ]] || fail "LOGTRACE_NODE3_JDBC_PASSWORD is required"
  curl -fsS "${LOGTRACE_BACKEND_URL}/swagger-ui.html" >/dev/null || fail "backend is not reachable: ${LOGTRACE_BACKEND_URL}"
  curl -fsS "${LOGTRACE_TOMCAT_URL}/" >/dev/null || fail "Tomcat is not reachable: ${LOGTRACE_TOMCAT_URL}"
  [[ -d "$LOGTRACE_TOMCAT_LOG_DIR" ]] || fail "Tomcat log dir not found: ${LOGTRACE_TOMCAT_LOG_DIR}"

  log "checking tamper procedures on node1"
  mysql_table 127.0.0.1 logtrace_node1 "$LOGTRACE_NODE1_JDBC_USERNAME" "$LOGTRACE_NODE1_JDBC_PASSWORD" \
    "SHOW PROCEDURE STATUS WHERE Db='logtrace_node1' AND Name LIKE 'sp_tamper_%';"
}

get_token() {
  log "registering admin if needed"
  curl -sS -X POST "${LOGTRACE_BACKEND_URL}/api/auth/register" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${LOGTRACE_STAGE11_USERNAME}\",\"password\":\"${LOGTRACE_STAGE11_PASSWORD}\",\"display_name\":\"${LOGTRACE_STAGE11_DISPLAY_NAME}\"}" \
    >/tmp/logtrace-stage11-register.json || true

  log "logging in admin"
  TOKEN="$(curl -fsS -X POST "${LOGTRACE_BACKEND_URL}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${LOGTRACE_STAGE11_USERNAME}\",\"password\":\"${LOGTRACE_STAGE11_PASSWORD}\"}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token') or d.get('accessToken') or '')")"
  [[ -n "$TOKEN" ]] || fail "failed to obtain JWT"
  log "JWT acquired"
}

wait_next_minute() {
  local current
  current="$(date -u '+%Y%m%d%H%M')"
  log "waiting for a fresh UTC minute window"
  while [[ "$(date -u '+%Y%m%d%H%M')" == "$current" ]]; do
    sleep 1
  done
  SCENARIO_START_SQL="$(date -u '+%Y-%m-%d %H:%M:00')"
  log "new window started at $(date -u '+%Y-%m-%dT%H:%M:%SZ'); scenario_start_sql=${SCENARIO_START_SQL}"
}

trigger_traffic() {
  log "triggering normal GET traffic"
  for _ in 1 2 3; do
    curl -fsS "${LOGTRACE_TOMCAT_URL}/" >/dev/null || true
    sleep 1
  done

  log "triggering attack PUT traffic"
  curl -i -sS -X PUT "${LOGTRACE_TOMCAT_URL}/shell.jsp/" \
    -H "Content-Range: bytes 0-5/6" \
    -H "Content-Type: application/octet-stream" \
    --data-binary '<%out.println("stage11");%>' | tee -a "$REPORT_FILE"

  log "recent Tomcat access log lines"
  tail -n 30 "${LOGTRACE_TOMCAT_LOG_DIR}"/localhost_access_log.*.txt 2>/dev/null | tee -a "$REPORT_FILE" || true
}

latest_attack_batch_sql() {
  cat <<SQL
SELECT b.batch_id
FROM log_batches b
JOIN log_records r ON r.batch_id = b.batch_id
WHERE b.source='${LOGTRACE_AUTO_SEAL_SOURCE}'
  AND b.seal_status='CHAIN_COMMITTED'
  AND b.chain_tx_id IS NOT NULL
  AND r.request_method='PUT'
  AND r.request_uri='/shell.jsp/'
  AND b.start_time >= '${SCENARIO_START_SQL}'
ORDER BY b.start_time DESC
LIMIT 1;
SQL
}

wait_chain_committed_batch() {
  local deadline=$((SECONDS + LOGTRACE_STAGE11_MAX_WAIT_SECONDS))
  local batch_id=""
  log "waiting for auto seal to CHAIN_COMMITTED"
  while (( SECONDS < deadline )); do
    batch_id="$(mysql_query 127.0.0.1 logtrace_node1 "$LOGTRACE_NODE1_JDBC_USERNAME" "$LOGTRACE_NODE1_JDBC_PASSWORD" "$(latest_attack_batch_sql)" | tail -n 1 || true)"
    if [[ -n "$batch_id" ]]; then
      printf '%s' "$batch_id"
      return 0
    fi
    log "waiting for auto seal... elapsed=${SECONDS}s"
    sleep "$LOGTRACE_STAGE11_POLL_SECONDS"
  done
  fail "no CHAIN_COMMITTED attack batch found within ${LOGTRACE_STAGE11_MAX_WAIT_SECONDS}s"
}

attack_log_id_for_batch() {
  local batch_id="$1"
  mysql_query 127.0.0.1 logtrace_node1 "$LOGTRACE_NODE1_JDBC_USERNAME" "$LOGTRACE_NODE1_JDBC_PASSWORD" \
    "SELECT log_id FROM log_records WHERE batch_id='${batch_id}' AND request_method='PUT' AND request_uri='/shell.jsp/' LIMIT 1;" | tail -n 1
}

integrity_check() {
  local batch_id="$1"
  curl -fsS -X POST "${LOGTRACE_BACKEND_URL}/api/integrity/check" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"batch_id\":\"${batch_id}\"}"
}

write_json() {
  local path="$1"
  python3 -m json.tool >"$path"
  cat "$path" | tee -a "$REPORT_FILE"
}

assert_clean_before_tamper() {
  local batch_id="$1"
  local json_file="${REPORT_DIR}/${batch_id}-before.json"
  log "integrity check before tamper: ${batch_id}"
  integrity_check "$batch_id" | write_json "$json_file"
  python3 - "$json_file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if data.get("abnormal_nodes") or data.get("differences"):
    raise SystemExit("batch is already abnormal before tamper")
PY
}

assert_after_tamper() {
  local batch_id="$1"
  local expected_type="$2"
  local json_file="${REPORT_DIR}/${batch_id}-after-${expected_type}.json"
  log "integrity check after tamper: ${batch_id}"
  integrity_check "$batch_id" | write_json "$json_file"
  python3 - "$json_file" "$expected_type" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
expected = sys.argv[2]
nodes = data.get("abnormal_nodes") or []
types = {item.get("type") for item in data.get("differences") or []}
if nodes != ["node1"]:
    raise SystemExit(f"expected abnormal_nodes ['node1'], got {nodes}")
if expected not in types:
    raise SystemExit(f"expected difference {expected}, got {sorted(types)}")
if "BATCH_ROOT_MISMATCH" not in types:
    raise SystemExit(f"expected BATCH_ROOT_MISMATCH, got {sorted(types)}")
print("PASS", expected, "nodes=", nodes, "types=", sorted(types))
PY
}

show_three_replicas() {
  local batch_id="$1"
  local log_id="${2:-}"
  local filter
  if [[ -n "$log_id" ]]; then
    filter="batch_id='${batch_id}' AND log_id='${log_id}'"
  else
    filter="batch_id='${batch_id}'"
  fi

  log "three-replica snapshot for ${batch_id} ${log_id}"
  mysql_table 127.0.0.1 logtrace_node1 "$LOGTRACE_NODE1_JDBC_USERNAME" "$LOGTRACE_NODE1_JDBC_PASSWORD" \
    "SELECT 'node1' AS node, log_id, request_method, request_uri, status_code, source_node, LEFT(leaf_hash,12) AS leaf FROM log_records WHERE ${filter} ORDER BY log_id LIMIT 25;" | tee -a "$REPORT_FILE"
  mysql_table 192.168.88.102 logtrace_node2 "$LOGTRACE_NODE2_JDBC_USERNAME" "$LOGTRACE_NODE2_JDBC_PASSWORD" \
    "SELECT 'node2' AS node, log_id, request_method, request_uri, status_code, source_node, LEFT(leaf_hash,12) AS leaf FROM log_records WHERE ${filter} ORDER BY log_id LIMIT 25;" | tee -a "$REPORT_FILE"
  mysql_table 192.168.88.103 logtrace_node3 "$LOGTRACE_NODE3_JDBC_USERNAME" "$LOGTRACE_NODE3_JDBC_PASSWORD" \
    "SELECT 'node3' AS node, log_id, request_method, request_uri, status_code, source_node, LEFT(leaf_hash,12) AS leaf FROM log_records WHERE ${filter} ORDER BY log_id LIMIT 25;" | tee -a "$REPORT_FILE"
}

create_clean_attack_batch() {
  wait_next_minute
  trigger_traffic
  local batch_id
  batch_id="$(wait_chain_committed_batch)"
  log "BATCH_ID=${batch_id}"
  local attack_log_id
  attack_log_id="$(attack_log_id_for_batch "$batch_id")"
  [[ -n "$attack_log_id" ]] || fail "attack log not found in ${batch_id}"
  log "ATTACK_LOG_ID=${attack_log_id}"
  show_three_replicas "$batch_id" "$attack_log_id"
  assert_clean_before_tamper "$batch_id"
  CREATED_BATCH_ID="$batch_id"
  CREATED_ATTACK_LOG_ID="$attack_log_id"
}

scenario_missing() {
  log "## Scenario missing: delete attack log"
  local batch_id attack_log_id
  create_clean_attack_batch
  batch_id="$CREATED_BATCH_ID"
  attack_log_id="$CREATED_ATTACK_LOG_ID"
  "${MYSQL_ROOT_CLI[@]}" -e "CALL sp_tamper_delete_by_pattern('${batch_id}', 'log_id', '${attack_log_id}', 'EQUAL');"
  show_three_replicas "$batch_id" "$attack_log_id"
  assert_after_tamper "$batch_id" "MISSING_LOG"
  log "SCENARIO_RESULT missing PASS batch=${batch_id} attack_log=${attack_log_id}"
}

scenario_modified() {
  log "## Scenario modified: update attack URI"
  local batch_id attack_log_id
  create_clean_attack_batch
  batch_id="$CREATED_BATCH_ID"
  attack_log_id="$CREATED_ATTACK_LOG_ID"
  "${MYSQL_ROOT_CLI[@]}" -e "CALL sp_tamper_update_by_pattern('${batch_id}', 'log_id', '${attack_log_id}', 'EQUAL', 'request_uri', '/index.jsp');"
  show_three_replicas "$batch_id" "$attack_log_id"
  assert_after_tamper "$batch_id" "MODIFIED_LOG"
  log "SCENARIO_RESULT modified PASS batch=${batch_id} attack_log=${attack_log_id}"
}

scenario_extra() {
  log "## Scenario extra: insert noise logs"
  local batch_id attack_log_id
  create_clean_attack_batch
  batch_id="$CREATED_BATCH_ID"
  attack_log_id="$CREATED_ATTACK_LOG_ID"
  "${MYSQL_ROOT_CLI[@]}" -e "CALL sp_tamper_insert_noise('${batch_id}', ${LOGTRACE_STAGE11_NOISE_COUNT}, '/stage11-normal-looking');"
  log "noise count by replica"
  mysql_table 127.0.0.1 logtrace_node1 "$LOGTRACE_NODE1_JDBC_USERNAME" "$LOGTRACE_NODE1_JDBC_PASSWORD" \
    "SELECT 'node1' AS node, COUNT(*) AS noise_rows FROM log_records WHERE batch_id='${batch_id}' AND request_uri LIKE '/stage11-normal-looking/%';" | tee -a "$REPORT_FILE"
  mysql_table 192.168.88.102 logtrace_node2 "$LOGTRACE_NODE2_JDBC_USERNAME" "$LOGTRACE_NODE2_JDBC_PASSWORD" \
    "SELECT 'node2' AS node, COUNT(*) AS noise_rows FROM log_records WHERE batch_id='${batch_id}' AND request_uri LIKE '/stage11-normal-looking/%';" | tee -a "$REPORT_FILE"
  mysql_table 192.168.88.103 logtrace_node3 "$LOGTRACE_NODE3_JDBC_USERNAME" "$LOGTRACE_NODE3_JDBC_PASSWORD" \
    "SELECT 'node3' AS node, COUNT(*) AS noise_rows FROM log_records WHERE batch_id='${batch_id}' AND request_uri LIKE '/stage11-normal-looking/%';" | tee -a "$REPORT_FILE"
  assert_after_tamper "$batch_id" "EXTRA_LOG"
  log "SCENARIO_RESULT extra PASS batch=${batch_id} attack_log=${attack_log_id}"
}

main() {
  load_env
  set_defaults
  preflight
  get_token
  case "$MODE" in
    missing) scenario_missing ;;
    modified) scenario_modified ;;
    extra) scenario_extra ;;
    all)
      scenario_missing
      scenario_modified
      scenario_extra
      ;;
  esac
  log "stage11 completed; report=${REPORT_FILE}"
}

main "$@"
