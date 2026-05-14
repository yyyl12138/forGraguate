# Backend Tech Stack

## Purpose

This document freezes the Stage 4 backend technology stack and deployment boundary.

The backend is designed to run on `node1`, the Ubuntu VM that also hosts the main MySQL schema, Filebeat, Vulhub, and the frontend. `node2` and `node3` are reached through dedicated MySQL datasources for plaintext log and batch replicas.

## Runtime

| Item | Selection |
|---|---|
| Language | Java 21 |
| Framework | Spring Boot 3.5.12 |
| Build | Maven Wrapper |
| HTTP | Spring Web MVC |
| Validation | Jakarta Bean Validation |
| Security | Spring Security |
| Token | JWT access token, refresh token digest stored in MySQL |
| Database access | MyBatis |
| Database driver | MySQL Connector/J |
| Pool | HikariCP |
| OpenAPI | springdoc-openapi, plus static `docs/openapi.yaml` |
| Test | JUnit 5, Mockito, Testcontainers MySQL |

The local development machine may use a newer JDK, but the Maven compiler release must stay at `21`.

## Node1 Deployment Boundary

`node1` runs the Spring Boot process and owns the default business datasource:

```text
node1 datasource -> logtrace_node1
node2 datasource -> logtrace_node2
node3 datasource -> logtrace_node3
```

`logtrace_node1` stores users, authentication audit, operation audit, write audit, node1 plaintext logs, node1 batch metadata, and demo-only tamper procedures.

`logtrace_node2` and `logtrace_node3` store only `log_records` and `log_batches`. They must not contain authentication, audit, or tamper procedure objects.

## Backend Modules

| Module | Responsibility |
|---|---|
| `auth` | Register, login, logout, refresh token, current-user query, login audit. |
| `ingest` | Receive Filebeat/mock payloads, parse Tomcat access logs, create CanonicalLog. |
| `replica` | Stage 9.5 main-write plus frozen outbox sync from `node1` to `node2` and `node3`. |
| `batch` | Seal 60-second batches and persist local batch metadata. |
| `merkle` | Generate `log_id`, canonical JSON, `leaf_hash`, and `merkle_root`. |
| `ledger` | Fabric Gateway abstraction; Stage 4 uses mock implementation. |
| `integrity` | Compare ledger Root with three MySQL replica Roots and classify differences. |
| `audit` | Record system operations such as log search, sealing, integrity check, and demo actions. |

## JSON And Time Contract

- Public API JSON uses `snake_case`.
- Java code may use camelCase fields and Jackson naming strategy.
- Public timestamps use UTC millisecond precision: `YYYY-MM-DDTHH:mm:ss.SSSZ`.
- Hashes are 64 lowercase hex strings.
- Batch windows are fixed 60-second half-open intervals: `[start_time, end_time)`.

## Fabric Gateway Strategy

Stage 4 defines a `LedgerGatewayClient` interface matching the chaincode ABI:

- `CreateBatchEvidence`
- `GetBatchEvidence`
- `QueryBatchEvidenceByTimeRange`
- `QueryBatchEvidenceBySource`
- `VerifyBatchRoot`

The default Stage 4 implementation is `MockLedgerGatewayClient`, backed by in-memory state or local test fixtures. The real Fabric Gateway Java client implementation must be added later without changing controllers or service contracts.

## Security Defaults

- `/api/auth/register`, `/api/auth/login`, and `/api/auth/refresh` are public.
- Other `/api/**` endpoints require a bearer access token.
- `ADMIN` and `AUDITOR` may read audit endpoints.
- Passwords are stored only as BCrypt hashes.
- Refresh tokens are stored only as SHA-256 digests.
- Failed login attempts are audited.

## Stage 4 Non-Goals

- Do not connect to the real Fabric network.
- Do not require real Filebeat input.
- Do not execute Vulhub attack scripts.
- Do not expose a database tamper API.
- Do not change the frozen chaincode ABI, hash contract, or MySQL schema unless a later stage explicitly revises them.
