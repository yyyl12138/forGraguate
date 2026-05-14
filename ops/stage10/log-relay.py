#!/usr/bin/env python3
import glob
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path


def env_int(name: str, default: int) -> int:
    value = os.getenv(name, str(default)).strip()
    return int(value) if value else default


SPOOL_GLOB = os.getenv("LOGTRACE_RELAY_SPOOL_GLOB", "/var/spool/logtrace-stage10/filebeat-stage10*")
STATE_PATH = Path(os.getenv("LOGTRACE_RELAY_STATE_PATH", "/var/lib/logtrace-stage10/relay-state.json"))
DEAD_LETTER_PATH = Path(os.getenv("LOGTRACE_RELAY_DEAD_LETTER_PATH", "/var/lib/logtrace-stage10/dead-letter.ndjson"))
ENDPOINT = os.getenv("LOGTRACE_RELAY_ENDPOINT", "http://127.0.0.1:8080/api/internal/ingest/filebeat")
SHARED_TOKEN = os.getenv("LOGTRACE_RELAY_SHARED_TOKEN", "")
SOURCE = os.getenv("LOGTRACE_RELAY_SOURCE", "tomcat-cve-2017-12615")
APP_NAME = os.getenv("LOGTRACE_RELAY_APP_NAME", "tomcat")
HOSTNAME = os.getenv("LOGTRACE_RELAY_HOSTNAME", "node1")
DEFAULT_FILE_PATH = os.getenv(
    "LOGTRACE_RELAY_DEFAULT_FILE_PATH",
    "/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.current.txt",
)
BATCH_SIZE = env_int("LOGTRACE_RELAY_BATCH_SIZE", 200)
FLUSH_INTERVAL_SECONDS = env_int("LOGTRACE_RELAY_FLUSH_INTERVAL_SECONDS", 2)
TERMINAL_DISPOSITIONS = {"ACCEPTED", "DUPLICATE", "REJECTED_LATE", "FAILED"}


def load_state() -> dict:
    if not STATE_PATH.exists():
        return {"files": {}}
    with STATE_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def save_state(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    with STATE_PATH.open("w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, sort_keys=True, indent=2)


def append_dead_letter(item: dict) -> None:
    DEAD_LETTER_PATH.parent.mkdir(parents=True, exist_ok=True)
    with DEAD_LETTER_PATH.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(item, ensure_ascii=False, sort_keys=True))
        handle.write("\n")


def build_request(records: list[dict]) -> dict:
    first = records[0]
    return {
        "source": first["source"],
        "hostname": first["hostname"],
        "app_name": first["app_name"],
        "file_path": first["file_path"],
        "records": [
            {"raw_message": item["raw_message"], "file_offset": item["file_offset"]}
            for item in records
        ],
    }


def post_records(payload: dict) -> dict:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        ENDPOINT,
        data=body,
        headers={
            "Content-Type": "application/json",
            "X-Logtrace-Machine-Token": SHARED_TOKEN,
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read().decode("utf-8"))


def classify_response(batch: list[dict], response: dict) -> list[dict]:
    dead = []
    by_offset = {}
    for result in response.get("logs", []):
        by_offset[result.get("file_offset")] = result
    for record in batch:
        result = by_offset.get(record["file_offset"])
        if result is None:
            raise RuntimeError(f"missing backend result for file_offset={record['file_offset']}")
        disposition = result.get("disposition")
        if disposition in {"REJECTED_LATE", "FAILED"}:
            dead.append({**record, "detail": disposition, "backend_result": result})
            continue
        if disposition not in TERMINAL_DISPOSITIONS:
            raise RuntimeError(
                f"unexpected backend disposition for file_offset={record['file_offset']}: {disposition}"
            )
    return dead


def parse_line(line: str) -> dict | None:
    event = json.loads(line)
    raw_message = event.get("message")
    if raw_message is None or not str(raw_message).strip():
        return None
    file_path = (
        event.get("log", {}).get("file", {}).get("path")
        or event.get("log", {}).get("source", {}).get("address")
        or DEFAULT_FILE_PATH
    )
    offset = event.get("log", {}).get("offset")
    if offset is None:
        return None
    source = event.get("logtrace_source") or event.get("fields", {}).get("logtrace_source") or SOURCE
    hostname = event.get("logtrace_hostname") or event.get("fields", {}).get("logtrace_hostname") or HOSTNAME
    app_name = event.get("logtrace_app_name") or event.get("fields", {}).get("logtrace_app_name") or APP_NAME
    return {
        "raw_message": str(raw_message),
        "file_offset": int(offset),
        "file_path": str(file_path),
        "source": str(source),
        "hostname": str(hostname),
        "app_name": str(app_name),
        "raw_event": event,
    }


def flush_group(group: list[dict], state: dict, state_key: str) -> None:
    if not group:
        return
    response = post_records(build_request(group))
    dead = classify_response(group, response)
    for item in dead:
        append_dead_letter(item)
    state["files"][state_key] = group[-1]["state_offset"]
    save_state(state)


def consume_file(path: str, state: dict) -> None:
    state_key = os.path.abspath(path)
    start_offset = int(state.get("files", {}).get(state_key, 0))
    file_size = os.path.getsize(path)
    if start_offset > file_size:
        start_offset = 0
        state["files"][state_key] = 0
        save_state(state)
    current_group: list[dict] = []
    current_group_key = None
    last_flush_at = time.time()

    with open(path, "r", encoding="utf-8") as handle:
        handle.seek(start_offset)
        while True:
            line_offset = handle.tell()
            line = handle.readline()
            if not line:
                break
            parsed = parse_line(line)
            if parsed is None:
                append_dead_letter({"detail": "invalid filebeat event", "line": line.rstrip("\n")})
                state["files"][state_key] = handle.tell()
                save_state(state)
                continue
            parsed["state_offset"] = handle.tell()
            group_key = (
                parsed["source"],
                parsed["hostname"],
                parsed["app_name"],
                parsed["file_path"],
            )
            if current_group_key is None:
                current_group_key = group_key
            if group_key != current_group_key or len(current_group) >= BATCH_SIZE or time.time() - last_flush_at >= FLUSH_INTERVAL_SECONDS:
                flush_group(current_group, state, state_key)
                current_group = []
                current_group_key = group_key
                last_flush_at = time.time()
            current_group.append(parsed)
        flush_group(current_group, state, state_key)


def main() -> None:
    if not SHARED_TOKEN:
        raise SystemExit("LOGTRACE_RELAY_SHARED_TOKEN is required")
    state = load_state()
    while True:
        for path in sorted(glob.glob(SPOOL_GLOB)):
            if os.path.isfile(path):
                try:
                    consume_file(path, state)
                except urllib.error.HTTPError as error:
                    raise SystemExit(f"relay HTTP error: {error.code} {error.reason}") from error
                except urllib.error.URLError as error:
                    raise SystemExit(f"relay URL error: {error.reason}") from error
        time.sleep(FLUSH_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
