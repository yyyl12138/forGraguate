# Hash And Batch Contract

## Purpose

This document freezes the deterministic hashing and batching contract shared by:

- Spring Boot log normalization and batch sealing
- Three MySQL plaintext replicas
- Go chaincode ABI tests
- Integrity-check recomputation
- Frontend mock data and demo fixtures

The goal is reproducible `leaf_hash` and `merkle_root` values across all implementations.

## Versions

| Item | Value |
|---|---|
| Hash algorithm | `SHA-256` |
| Hash output encoding | 64 lowercase hex characters |
| Canonicalization version | `clog-v1` |
| Canonical log schema | `docs/canonical-log.schema.json` |
| Ledger schema version | `1` |
| Batch window | 60 seconds |

Hash strings must not include `0x`, algorithm prefixes, whitespace, or uppercase hex.

## Time Contract

Every time value entering hash input must use UTC millisecond precision:

```text
YYYY-MM-DDTHH:mm:ss.SSSZ
```

Example conversion from Tomcat access log:

```text
22/Apr/2026:10:05:01 +0800 -> 2026-04-22T02:05:01.000Z
```

Local timezone strings must be normalized before hashing.

## Batch Window Contract

Batches use fixed 60 second windows and half-open interval semantics:

```text
[start_time, end_time)
```

For event time `2026-04-22T02:05:42.000Z`, the batch is:

```text
start_time = 2026-04-22T02:05:00.000Z
end_time   = 2026-04-22T02:06:00.000Z
batch_id   = bch_v1_tomcat-cve-2017-12615_20260422T020500Z
```

Empty batches must not be sealed and must not be submitted to Fabric.

## CanonicalLog Fields

`CanonicalLog` is the hash input object for one normalized log.

Required top-level fields:

- `pri`
- `version`
- `timestamp`
- `hostname`
- `app_name`
- `procid`
- `msgid`
- `structured_data`
- `msg`
- `raw_message`
- `source`
- `batch_id`
- `log_id`

Required `structured_data` fields:

- `source_ip`
- `source_port`
- `dest_ip`
- `dest_port`
- `container_id`
- `container_name`
- `service_name`
- `request_method`
- `request_uri`
- `status_code`
- `response_size`
- `log_type`
- `batch_id`

Unknown string fields use `"-"`. Unknown numeric fields use `null`. Floating point numbers are not allowed.

The schema is defined in `docs/canonical-log.schema.json` and uses `additionalProperties: false`.

## Excluded Fields

These fields must not be included in the Canonical JSON used for `leaf_hash`:

- `leaf_hash`
- `source_node`
- MySQL auto-increment IDs
- MySQL timestamps such as `created_at` or `updated_at`
- Fabric `tx_id`
- Chaincode commit timestamp
- Merkle proof path
- Runtime Filebeat metadata not frozen before sealing
- Frontend display-only fields
- Demo tamper flags

## Log ID Contract

`log_id` is generated once by the backend and written unchanged to all MySQL replicas.

Production preferred input:

```text
LOGTRACE_LOG_ID_V1
{source}
{file_path}
{file_offset}
{raw_message}
```

Algorithm:

```text
log_id = "log_v1_" + first_32_hex_chars(SHA-256(input))
```

Rules:

- `source` is the business source, for example `tomcat-cve-2017-12615`.
- `file_path` is the collected file path on `node1`, for example `/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.2026-04-22.txt`.
- `file_offset` is the byte offset or stable collector offset for the log line.
- `raw_message` is the exact source log line before normalization.
- If local mock data has no stable file offset, the backend may generate a UUIDv7 or ULID once and persist it as `log_id`.
- Databases must not generate or rewrite `log_id`.

## Canonical JSON Contract

Canonical JSON is generated from `CanonicalLog` with these rules:

- UTF-8 encoding.
- Object keys sorted by Unicode code point in ascending order at every nesting level.
- No insignificant whitespace.
- Strings are JSON escaped by RFC 8259 rules.
- Integers are decimal JSON numbers.
- Null values are JSON `null`.
- Floating point numbers are forbidden.
- Arrays are not used in `clog-v1`.
- Unknown fields are forbidden.

Equivalent command-line shape when using Python:

```python
json.dumps(canonical_log, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
```

This Python expression is a reference illustration, not a dependency requirement.

## Leaf Hash Contract

Leaf hash input is:

```text
LOGTRACE_LEAF_V1
{canonical_json}
```

The first line is followed by a single LF byte (`0x0a`). There is no trailing newline after `{canonical_json}`.

Algorithm:

```text
leaf_hash = lowercase_hex(SHA-256(utf8("LOGTRACE_LEAF_V1\n" + canonical_json)))
```

## Merkle Tree Contract

Leaves are sorted before tree construction:

```text
timestamp ASC, log_id ASC
```

Rules:

- The sorted leaf list is the only valid Merkle input order.
- A single-leaf batch Root equals the only `leaf_hash`.
- For an odd number of nodes at any level, duplicate the last node.
- Parent hash input is:

```text
LOGTRACE_MERKLE_NODE_V1
{left_hex}
{right_hex}
```

The lines are separated by LF bytes. There is no trailing newline after `{right_hex}`.

Algorithm:

```text
parent_hash = lowercase_hex(SHA-256(utf8("LOGTRACE_MERKLE_NODE_V1\n" + left_hex + "\n" + right_hex)))
```

The final remaining hash is `merkle_root`.

## Tomcat Test Vector

Shared fields:

```text
source     = tomcat-cve-2017-12615
batch_id   = bch_v1_tomcat-cve-2017-12615_20260422T020500Z
file_path  = /opt/log-trace/vulhub-logs/tomcat/localhost_access_log.2026-04-22.txt
start_time = 2026-04-22T02:05:00.000Z
end_time   = 2026-04-22T02:06:00.000Z
```

Raw Tomcat access logs:

```text
172.18.0.1 - - [22/Apr/2026:10:05:01 +0800] "GET / HTTP/1.1" 200 11230
172.18.0.1 - - [22/Apr/2026:10:05:18 +0800] "GET /docs/ HTTP/1.1" 200 2147
172.18.0.1 - - [22/Apr/2026:10:05:42 +0800] "PUT /shell.jsp/ HTTP/1.1" 201 32
```

File offsets used for deterministic `log_id` generation:

```text
0
82
164
```

### CanonicalLog 1

```json
{"app_name":"tomcat","batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","hostname":"node1","log_id":"log_v1_81d6381d1672fc38b4353b5d56a4c0f2","msg":"GET / -> 200","msgid":"WEB_ACCESS","pri":134,"procid":"-","raw_message":"172.18.0.1 - - [22/Apr/2026:10:05:01 +0800] \"GET / HTTP/1.1\" 200 11230","source":"tomcat-cve-2017-12615","structured_data":{"batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","container_id":"-","container_name":"tomcat-cve-2017-12615","dest_ip":"-","dest_port":8080,"log_type":"access","request_method":"GET","request_uri":"/","response_size":11230,"service_name":"tomcat","source_ip":"172.18.0.1","source_port":null,"status_code":200},"timestamp":"2026-04-22T02:05:01.000Z","version":1}
```

Expected values:

```text
log_id    = log_v1_81d6381d1672fc38b4353b5d56a4c0f2
leaf_hash = 5c5f724c953881890458c9075397e9319020da7325205ee46528770229854a92
```

### CanonicalLog 2

```json
{"app_name":"tomcat","batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","hostname":"node1","log_id":"log_v1_47138f44da836f20ad0aeede367810e3","msg":"GET /docs/ -> 200","msgid":"WEB_ACCESS","pri":134,"procid":"-","raw_message":"172.18.0.1 - - [22/Apr/2026:10:05:18 +0800] \"GET /docs/ HTTP/1.1\" 200 2147","source":"tomcat-cve-2017-12615","structured_data":{"batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","container_id":"-","container_name":"tomcat-cve-2017-12615","dest_ip":"-","dest_port":8080,"log_type":"access","request_method":"GET","request_uri":"/docs/","response_size":2147,"service_name":"tomcat","source_ip":"172.18.0.1","source_port":null,"status_code":200},"timestamp":"2026-04-22T02:05:18.000Z","version":1}
```

Expected values:

```text
log_id    = log_v1_47138f44da836f20ad0aeede367810e3
leaf_hash = d4be4a0278f1f7071bde5849d212fbdfb3d743f4c8ee57f73af69c4b1c2f723b
```

### CanonicalLog 3

```json
{"app_name":"tomcat","batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","hostname":"node1","log_id":"log_v1_ec926baf07e1dcb3e870c78fbfb0c9a8","msg":"PUT /shell.jsp/ -> 201","msgid":"EXPLOIT_ATTEMPT","pri":134,"procid":"-","raw_message":"172.18.0.1 - - [22/Apr/2026:10:05:42 +0800] \"PUT /shell.jsp/ HTTP/1.1\" 201 32","source":"tomcat-cve-2017-12615","structured_data":{"batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","container_id":"-","container_name":"tomcat-cve-2017-12615","dest_ip":"-","dest_port":8080,"log_type":"access","request_method":"PUT","request_uri":"/shell.jsp/","response_size":32,"service_name":"tomcat","source_ip":"172.18.0.1","source_port":null,"status_code":201},"timestamp":"2026-04-22T02:05:42.000Z","version":1}
```

Expected values:

```text
log_id    = log_v1_ec926baf07e1dcb3e870c78fbfb0c9a8
leaf_hash = f65deb87cc8f2f5949bcfc80357e742d096d0fb8030fcf29a31cfdf6df86b7f8
```

### Merkle Calculation

Sorted leaves:

```text
L1 = 5c5f724c953881890458c9075397e9319020da7325205ee46528770229854a92
L2 = d4be4a0278f1f7071bde5849d212fbdfb3d743f4c8ee57f73af69c4b1c2f723b
L3 = f65deb87cc8f2f5949bcfc80357e742d096d0fb8030fcf29a31cfdf6df86b7f8
```

Odd leaf handling duplicates `L3`:

```text
P12 = SHA-256("LOGTRACE_MERKLE_NODE_V1\n" + L1 + "\n" + L2)
    = 0972d52b9c5a49a54287486521fc89f52a15fc1313f153daea8afd8b9cf05660

P33 = SHA-256("LOGTRACE_MERKLE_NODE_V1\n" + L3 + "\n" + L3)
    = 4689ed2b647fa30bfdcbbe5440ea06a25e2a205d7489866f65c03a8b23a52e11

merkle_root = SHA-256("LOGTRACE_MERKLE_NODE_V1\n" + P12 + "\n" + P33)
            = 36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f
```

Expected `BatchEvidence` digest fields:

```text
log_count   = 3
merkle_root = 36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f
```

## Counterexample Vectors

These vectors are used to verify that the contract detects common tampering patterns.

### Deletion

Deleting any log changes `log_count` and `merkle_root`.

```text
delete CanonicalLog 1 -> root = 571cb2ba9ca13cf770233e50b562b049c079b20a275ee778789cd23156a3e63f
delete CanonicalLog 2 -> root = d328b35c44ee4889403d4cdf9f75bb32d1955784fb327ffbc8aa23db4c6791ed
delete CanonicalLog 3 -> root = 0972d52b9c5a49a54287486521fc89f52a15fc1313f153daea8afd8b9cf05660
```

### Modification

Changing attack URI from `/shell.jsp/` to `/shell.jsp` produces:

```text
root = 2fb469bce99df648d7a9aa5877ea4cd37fffa38fe1c085a27932edf658fc2b5f
```

Changing attack source IP from `172.18.0.1` to `10.0.0.9` produces:

```text
root = 522097d76314d85acf24a967f25eeec8f6f7320e32114c0071a5479d968a92fd
```

### Reordering

Reading the same three logs in a different database order must still produce:

```text
root = 36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f
```

This is guaranteed only if implementations sort by:

```text
timestamp ASC, log_id ASC
```

### Duplicate Raw Logs

Two identical raw messages with different file offsets must produce different `log_id` and `leaf_hash` values.

```text
duplicate log_id values:
log_v1_81d6381d1672fc38b4353b5d56a4c0f2
log_v1_ead450500d29f141164ff5a0f5f9ed63

duplicate leaf values:
5c5f724c953881890458c9075397e9319020da7325205ee46528770229854a92
aee5036b042ce1a07e0279aa6982a32a960d92859bae46023a5453953a4ccebc

duplicate batch root:
c7536d002d867b06c1c97a0fb526890dbf2de04e92f235cb4a4327a462c82c13
```

Deleting one duplicate record changes the duplicate batch root and is detectable.

## Implementation Checklist

Any backend, chaincode test, or integrity checker implementation must pass these assertions:

- The three Tomcat sample logs produce exactly the listed `log_id` values.
- The Canonical JSON byte string has sorted keys and no extra spaces.
- Each `leaf_hash` equals the listed value.
- The three-leaf Merkle Root equals `36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f`.
- The same logs in reverse order still produce the same Root.
- Deletion and modification cases produce the listed counterexample Roots.
- A single-leaf batch Root equals the only leaf hash.
- Empty batches are rejected before Merkle calculation.
