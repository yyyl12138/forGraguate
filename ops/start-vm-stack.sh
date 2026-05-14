#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${1:-${SCRIPT_DIR}/vm-runtime.env}"

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

run() {
  log "+ $*"
  "$@"
}

require_file() {
  local path="$1"
  local label="$2"
  [[ -f "$path" ]] || fail "${label} not found: ${path}"
}

require_dir() {
  local path="$1"
  local label="$2"
  [[ -d "$path" ]] || fail "${label} not found: ${path}"
}

require_command() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || fail "required command not found: ${name}"
}

mask() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    printf '<empty>'
  elif (( ${#value} <= 6 )); then
    printf '******'
  else
    printf '%s******%s' "${value:0:2}" "${value: -2}"
  fi
}

load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    fail "runtime env missing: ${ENV_FILE}. Copy ${SCRIPT_DIR}/vm-runtime.env.example to ${ENV_FILE}, then replace every CHANGE_ME value."
  fi
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a
}

set_defaults() {
  : "${LOGTRACE_PROJECT_DIR:=${REPO_DIR}}"
  : "${LOGTRACE_BACKEND_DIR:=${LOGTRACE_PROJECT_DIR}/backend}"
  : "${LOGTRACE_BACKEND_PROFILE:=}"
  : "${LOGTRACE_BACKEND_LOG:=/var/log/logtrace/backend.log}"
  : "${LOGTRACE_BACKEND_PID_FILE:=/var/run/logtrace/backend.pid}"
  : "${LOGTRACE_BACKEND_URL:=http://127.0.0.1:8080}"
  : "${LOGTRACE_TOMCAT_URL:=http://127.0.0.1:18080}"
  : "${LOGTRACE_TOMCAT_LOG_DIR:=/opt/log-trace/vulhub-logs/tomcat}"
  : "${LOGTRACE_FABRIC_DOCKER_DIR:=/home/yangli/Documents/fabric-workspace/network/docker}"
  : "${LOGTRACE_FABRIC_COMPOSE_FILE:=${LOGTRACE_FABRIC_DOCKER_DIR}/docker-compose.yaml}"
  : "${LOGTRACE_NODE2_HOST:=node2}"
  : "${LOGTRACE_NODE3_HOST:=node3}"
  : "${LOGTRACE_SSH_USER:=${LOGTRACE_SERVICE_USER:-${USER:-yangli}}}"
  : "${LOGTRACE_SSH_OPTIONS:=-o BatchMode=yes -o ConnectTimeout=6}"
  : "${LOGTRACE_FABRIC_NODE1_SERVICES:=orderer.example.com}"
  : "${LOGTRACE_FABRIC_NODE2_SERVICES:=couchdb0 peer0.org1.example.com cli}"
  : "${LOGTRACE_FABRIC_NODE3_SERVICES:=couchdb1 peer0.org2.example.com}"
  : "${LOGTRACE_VULHUB_DIR:=/home/yangli/Documents/vulhub/tomcat/CVE-2017-12615}"
  : "${LOGTRACE_FILEBEAT_CONFIG:=/etc/filebeat/filebeat.yml}"
  : "${LOGTRACE_FILEBEAT_SERVICE:=filebeat}"
  : "${LOGTRACE_RELAY_ENV:=${LOGTRACE_PROJECT_DIR}/ops/stage10/relay.env}"
  : "${LOGTRACE_RELAY_SYSTEMD_SERVICE:=log-relay.service}"
  : "${LOGTRACE_RELAY_SPOOL_GLOB:=/var/spool/logtrace-stage10/filebeat-stage10*}"
  : "${LOGTRACE_RELAY_STATE_PATH:=/var/lib/logtrace-stage10/relay-state.json}"
  : "${LOGTRACE_RELAY_DEAD_LETTER_PATH:=/var/lib/logtrace-stage10/dead-letter.ndjson}"
  : "${LOGTRACE_RELAY_BATCH_SIZE:=200}"
  : "${LOGTRACE_RELAY_FLUSH_INTERVAL_SECONDS:=2}"
  : "${LOGTRACE_RELAY_SOURCE:=tomcat-cve-2017-12615}"
  : "${LOGTRACE_RELAY_APP_NAME:=tomcat}"
  : "${LOGTRACE_RELAY_HOSTNAME:=node1}"
  : "${LOGTRACE_RELAY_DEFAULT_FILE_PATH:=${LOGTRACE_TOMCAT_LOG_DIR}/localhost_access_log.current.txt}"
  : "${LOGTRACE_RELAY_ENDPOINT:=http://127.0.0.1:8080/api/internal/ingest/filebeat}"
  : "${LOGTRACE_RELAY_SHARED_TOKEN:=${LOGTRACE_INTERNAL_INGEST_SHARED_TOKEN:-}}"
  : "${LOGTRACE_SERVICE_USER:=${USER:-yangli}}"
}

check_no_placeholder() {
  local name="$1"
  local value="${!name:-}"
  [[ -n "$value" ]] || fail "${name} is required in ${ENV_FILE}"
  [[ "$value" != *CHANGE_ME* ]] || fail "${name} still contains CHANGE_ME in ${ENV_FILE}"
  [[ "$value" != replace-with-* ]] || fail "${name} still contains a placeholder in ${ENV_FILE}"
}

env_file_value() {
  local file="$1"
  local name="$2"
  awk -F= -v key="$name" '
    $0 !~ /^[[:space:]]*#/ && $1 == key {
      value = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^'\''|'\''$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

detect_filebeat() {
  local candidates=()
  if [[ -n "${LOGTRACE_FILEBEAT_BIN:-}" ]]; then
    candidates+=("$LOGTRACE_FILEBEAT_BIN")
  fi
  candidates+=("/usr/local/filebeat/filebeat")
  while IFS= read -r path; do
    candidates+=("$path")
  done < <(compgen -G "/usr/local/filebeat-*/filebeat" || true)
  if command -v filebeat >/dev/null 2>&1; then
    candidates+=("$(command -v filebeat)")
  fi

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      LOGTRACE_FILEBEAT_BIN="$candidate"
      export LOGTRACE_FILEBEAT_BIN
      return 0
    fi
  done
  fail "filebeat binary not found. Set LOGTRACE_FILEBEAT_BIN in ${ENV_FILE}; expected under /usr/local on this VM."
}

mysql_check() {
  local label="$1"
  local host="$2"
  local db="$3"
  local user="$4"
  local pass="$5"
  log "checking MySQL ${label}: ${host}/${db} as ${user}"
  MYSQL_PWD="$pass" mysql -N -B -h"$host" -u"$user" -D"$db" -e "SELECT @@hostname, @@time_zone, @@character_set_server, @@collation_server;" >/tmp/logtrace-mysql-${label}.out
  sed "s/^/[mysql ${label}] /" "/tmp/logtrace-mysql-${label}.out"
}

prepare_dirs() {
  log "creating runtime directories"
  sudo mkdir -p \
    "$LOGTRACE_TOMCAT_LOG_DIR" \
    /var/spool/logtrace-stage10 \
    /var/lib/logtrace-stage10 \
    "$(dirname "$LOGTRACE_BACKEND_LOG")" \
    "$(dirname "$LOGTRACE_BACKEND_PID_FILE")" \
    "$(dirname "$LOGTRACE_RELAY_ENV")"
  sudo chown -R "$LOGTRACE_SERVICE_USER:$LOGTRACE_SERVICE_USER" \
    "$LOGTRACE_TOMCAT_LOG_DIR" \
    /var/spool/logtrace-stage10 \
    /var/lib/logtrace-stage10 \
    "$(dirname "$LOGTRACE_BACKEND_LOG")" \
    "$(dirname "$LOGTRACE_BACKEND_PID_FILE")" \
    "$(dirname "$LOGTRACE_RELAY_ENV")"
}

preflight() {
  log "preflight: project=${LOGTRACE_PROJECT_DIR}, env=${ENV_FILE}"
  require_command sudo
  require_command curl
  require_command python3
  require_command java
  require_command mvn
  require_command docker
  require_command mysql
  require_command systemctl
  require_command ssh
  docker compose version >/dev/null 2>&1 || fail "docker compose v2 is required"
  detect_filebeat

  check_no_placeholder LOGTRACE_NODE1_JDBC_PASSWORD
  check_no_placeholder LOGTRACE_NODE2_JDBC_PASSWORD
  check_no_placeholder LOGTRACE_NODE3_JDBC_PASSWORD
  check_no_placeholder LOGTRACE_JWT_SECRET
  check_no_placeholder LOGTRACE_INTERNAL_INGEST_SHARED_TOKEN
  check_no_placeholder LOGTRACE_REPLICA_SYNC_SECRET
  check_no_placeholder LOGTRACE_RELAY_SHARED_TOKEN

  require_dir "$LOGTRACE_PROJECT_DIR" "project dir"
  require_dir "$LOGTRACE_BACKEND_DIR" "backend dir"
  require_dir "$LOGTRACE_FABRIC_DOCKER_DIR" "Fabric docker dir"
  require_file "$LOGTRACE_FABRIC_COMPOSE_FILE" "Fabric compose file"
  require_dir "$LOGTRACE_VULHUB_DIR" "Vulhub dir"
  require_file "${LOGTRACE_PROJECT_DIR}/ops/stage10/log-relay.py" "relay script"
  require_file "${LOGTRACE_BACKEND_DIR}/src/main/resources/application.yml" "backend application.yml on VM"
  require_file "$LOGTRACE_FILEBEAT_CONFIG" "deployed Filebeat config"
  require_file "$LOGTRACE_RELAY_ENV" "deployed relay env"
  require_file "$LOGTRACE_LEDGER_TLS_CERT_PATH" "Fabric TLS certificate"
  require_file "$LOGTRACE_LEDGER_CLIENT_CERT_PATH" "Fabric client certificate"
  require_dir "$LOGTRACE_LEDGER_CLIENT_KEY_DIR" "Fabric client key dir"

  log "filebeat binary: ${LOGTRACE_FILEBEAT_BIN}"
  log "backend log: ${LOGTRACE_BACKEND_LOG}"
  log "relay token: $(mask "$LOGTRACE_RELAY_SHARED_TOKEN")"
  local deployed_relay_token
  deployed_relay_token="$(env_file_value "$LOGTRACE_RELAY_ENV" LOGTRACE_RELAY_SHARED_TOKEN)"
  if [[ -n "$deployed_relay_token" && "$deployed_relay_token" != "$LOGTRACE_INTERNAL_INGEST_SHARED_TOKEN" ]]; then
    fail "relay token in ${LOGTRACE_RELAY_ENV} does not match LOGTRACE_INTERNAL_INGEST_SHARED_TOKEN; update Stage10 relay.env or backend application.yml/env"
  fi

  mysql_check node1 127.0.0.1 logtrace_node1 "$LOGTRACE_NODE1_JDBC_USERNAME" "$LOGTRACE_NODE1_JDBC_PASSWORD"
  mysql_check node2 192.168.88.102 logtrace_node2 "$LOGTRACE_NODE2_JDBC_USERNAME" "$LOGTRACE_NODE2_JDBC_PASSWORD"
  mysql_check node3 192.168.88.103 logtrace_node3 "$LOGTRACE_NODE3_JDBC_USERNAME" "$LOGTRACE_NODE3_JDBC_PASSWORD"
}

start_fabric() {
  log "starting Fabric containers on node1 only: ${LOGTRACE_FABRIC_NODE1_SERVICES}"
  (cd "$LOGTRACE_FABRIC_DOCKER_DIR" && docker compose -f "$LOGTRACE_FABRIC_COMPOSE_FILE" up -d ${LOGTRACE_FABRIC_NODE1_SERVICES})

  log "starting Fabric containers on ${LOGTRACE_NODE2_HOST}: ${LOGTRACE_FABRIC_NODE2_SERVICES}"
  ssh ${LOGTRACE_SSH_OPTIONS} "${LOGTRACE_SSH_USER}@${LOGTRACE_NODE2_HOST}" \
    "cd '${LOGTRACE_FABRIC_DOCKER_DIR}' && docker compose -f '${LOGTRACE_FABRIC_COMPOSE_FILE}' up -d ${LOGTRACE_FABRIC_NODE2_SERVICES}"

  log "starting Fabric containers on ${LOGTRACE_NODE3_HOST}: ${LOGTRACE_FABRIC_NODE3_SERVICES}"
  ssh ${LOGTRACE_SSH_OPTIONS} "${LOGTRACE_SSH_USER}@${LOGTRACE_NODE3_HOST}" \
    "cd '${LOGTRACE_FABRIC_DOCKER_DIR}' && docker compose -f '${LOGTRACE_FABRIC_COMPOSE_FILE}' up -d ${LOGTRACE_FABRIC_NODE3_SERVICES}"

  log "Fabric containers visible on node1"
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'orderer.example.com|peer0.org1.example.com|peer0.org2.example.com|couchdb0|couchdb1|cli|NAMES' || true
  log "Fabric containers visible on ${LOGTRACE_NODE2_HOST}"
  ssh ${LOGTRACE_SSH_OPTIONS} "${LOGTRACE_SSH_USER}@${LOGTRACE_NODE2_HOST}" \
    "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'peer0.org1.example.com|couchdb0|cli|NAMES' || true"
  log "Fabric containers visible on ${LOGTRACE_NODE3_HOST}"
  ssh ${LOGTRACE_SSH_OPTIONS} "${LOGTRACE_SSH_USER}@${LOGTRACE_NODE3_HOST}" \
    "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'peer0.org2.example.com|couchdb1|NAMES' || true"
}

start_vulhub() {
  log "starting Vulhub Tomcat"
  (cd "$LOGTRACE_VULHUB_DIR" && docker compose up -d)
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'tomcat|cve|8080|18080|NAMES' || true
}

check_stage10_services() {
  log "checking deployed Filebeat config"
  sudo "$LOGTRACE_FILEBEAT_BIN" test config -c "$LOGTRACE_FILEBEAT_CONFIG"
  log "checking deployed relay service"
  sudo systemctl cat "$LOGTRACE_RELAY_SYSTEMD_SERVICE" >/tmp/logtrace-relay-service.txt
  sed -n '1,40p' /tmp/logtrace-relay-service.txt | sed 's/^/[relay-service] /'
}

start_backend() {
  if [[ -n "$LOGTRACE_BACKEND_PROFILE" ]]; then
    log "starting backend with Spring profile '${LOGTRACE_BACKEND_PROFILE}'"
  else
    log "starting backend with deployed application.yml and no explicit Spring profile"
  fi
  if [[ -f "$LOGTRACE_BACKEND_PID_FILE" ]]; then
    local old_pid
    old_pid="$(cat "$LOGTRACE_BACKEND_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" >/dev/null 2>&1; then
      log "stopping previous backend pid=${old_pid}"
      kill "$old_pid" || true
      for _ in $(seq 1 10); do
        kill -0 "$old_pid" >/dev/null 2>&1 || break
        sleep 1
      done
    fi
  fi

  : >"$LOGTRACE_BACKEND_LOG"
  (
    cd "$LOGTRACE_BACKEND_DIR"
    if [[ -n "$LOGTRACE_BACKEND_PROFILE" ]]; then
      nohup mvn spring-boot:run -Dspring-boot.run.profiles="$LOGTRACE_BACKEND_PROFILE" \
        >>"$LOGTRACE_BACKEND_LOG" 2>&1 &
    else
      nohup mvn spring-boot:run >>"$LOGTRACE_BACKEND_LOG" 2>&1 &
    fi
    echo $! >"$LOGTRACE_BACKEND_PID_FILE"
  )
  log "backend pid=$(cat "$LOGTRACE_BACKEND_PID_FILE"), log=${LOGTRACE_BACKEND_LOG}"
}

wait_for_backend() {
  log "waiting for backend health endpoint"
  for i in $(seq 1 60); do
    if curl -fsS "${LOGTRACE_BACKEND_URL}/swagger-ui.html" >/dev/null 2>&1; then
      log "backend-up: ${LOGTRACE_BACKEND_URL}"
      return 0
    fi
    if (( i % 6 == 0 )); then
      log "backend still starting... ${i}/60"
      tail -n 20 "$LOGTRACE_BACKEND_LOG" | sed 's/^/[backend] /' || true
    fi
    sleep 2
  done
  tail -n 80 "$LOGTRACE_BACKEND_LOG" | sed 's/^/[backend] /' || true
  fail "backend did not become reachable at ${LOGTRACE_BACKEND_URL}"
}

restart_services() {
  log "restarting Filebeat and relay"
  sudo systemctl restart "$LOGTRACE_FILEBEAT_SERVICE"
  sudo systemctl restart "$LOGTRACE_RELAY_SYSTEMD_SERVICE"
  sudo systemctl --no-pager --full status "$LOGTRACE_FILEBEAT_SERVICE" | sed -n '1,12p' || true
  sudo systemctl --no-pager --full status "$LOGTRACE_RELAY_SYSTEMD_SERVICE" | sed -n '1,12p' || true
}

print_summary() {
  log "runtime summary"
  printf '  backend url: %s\n' "$LOGTRACE_BACKEND_URL"
  printf '  backend pid: %s\n' "$(cat "$LOGTRACE_BACKEND_PID_FILE" 2>/dev/null || printf '<missing>')"
  printf '  backend log: %s\n' "$LOGTRACE_BACKEND_LOG"
  printf '  tomcat url:  %s\n' "$LOGTRACE_TOMCAT_URL"
  printf '  tomcat logs: %s\n' "$LOGTRACE_TOMCAT_LOG_DIR"
  printf '  filebeat:    %s\n' "$LOGTRACE_FILEBEAT_BIN"
  printf '  spool files:\n'
  ls -lh /var/spool/logtrace-stage10 2>/dev/null | sed 's/^/    /' || true
  printf '  recent tomcat access logs:\n'
  ls -lh "$LOGTRACE_TOMCAT_LOG_DIR" 2>/dev/null | tail -n 10 | sed 's/^/    /' || true
  printf '  recent batches on node1:\n'
  MYSQL_PWD="$LOGTRACE_NODE1_JDBC_PASSWORD" mysql -h127.0.0.1 -u"$LOGTRACE_NODE1_JDBC_USERNAME" -Dlogtrace_node1 \
    -e "SELECT batch_id, source, log_count, seal_status, chain_tx_id FROM log_batches ORDER BY start_time DESC LIMIT 5;" 2>/dev/null \
    | sed 's/^/    /' || true
  printf '\nNext: run bash %s/ops/stage11/run-stage11.sh all\n' "$LOGTRACE_PROJECT_DIR"
}

main() {
  load_env
  set_defaults
  prepare_dirs
  preflight
  start_fabric
  start_vulhub
  check_stage10_services
  start_backend
  wait_for_backend
  restart_services
  print_summary
}

main "$@"
