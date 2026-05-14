# MySQL Replica Strategy

## Responsibility Split

`node1` is the main business database. It stores users, audits, plaintext logs, batch metadata, demo tamper procedures, and the Stage 9.5 replica sync outbox.

`node2` and `node3` are plaintext verification replicas. They store only `log_records` and `log_batches`.

The project does not use MySQL primary-replica replication. Database-level replication would copy later `DELETE` or `UPDATE` operations from `node1` into `node2/node3`, which would weaken the cross-replica tamper-detection model.

## Stage 9.5 Write Model

`/api/logs/ingest` writes accepted logs to `node1` and creates frozen `replica_sync_tasks` rows in the same `node1` transaction. Each task contains:

- `payload_json`: the append snapshot generated at ingest/seal time.
- `payload_hash`: SHA-256 of the exact payload text.
- `payload_signature`: HMAC-SHA256 of the payload hash.
- target node, batch id, business key, retry status, and diagnostic error.

The background sync worker writes `node2/node3` from the frozen payload only. It does not read the current contents of `node1.log_records` when copying a log. Therefore, if an attacker later deletes or updates `node1.log_records`, that mutation is not propagated to verification replicas.

Log replication is append-only and idempotent. Duplicate `log_id` or duplicate Filebeat offsets do not create a new row and do not require deleting or updating replica logs.

## Seal Gate

`/api/batches/seal` is the consistency boundary:

1. Drain runnable sync tasks for the target `batch_id`.
2. Refuse sealing if any `LOG_RECORD` task for the batch is not `SUCCEEDED`.
3. Read the target time window from `node1`, `node2`, and `node3`.
4. Recompute every stored leaf hash from `normalized_message`.
5. Require identical `log_count`, ordered `log_id`, and `leaf_hash` across all three replicas.
6. Insert `log_batches` via frozen `BATCH_METADATA` tasks and require those tasks to complete before Fabric submission.
7. After Fabric success, write `CHAIN_COMMITTED` to `node1` and enqueue `BATCH_CHAIN_COMMIT` tasks for `node2/node3`.

If `node1` was modified after ingest, seal refuses to anchor the polluted batch. If a replica is temporarily down, ingest can still complete, but seal is blocked until the outbox catches up.

## Tamper Coverage

After a batch is sealed, inserting many normal-looking logs into `node1` changes the node1 Merkle Root and produces `EXTRA_LOG` / `BATCH_ROOT_MISMATCH` during integrity check. The ledger root and log count remain the evidence anchor.

Before a batch is sealed, normal-looking fake logs that enter through the legitimate ingest path are an input trust problem. The system reduces this risk with authentication, source/path control, deterministic `log_id`, file-offset de-duplication, audit records, and the seal gate, but it does not claim to prove whether pre-seal input content is semantically genuine.

## Threat Model Boundary

Covered: attacker can modify `node1.log_records` after ingest/seal.

Not covered as an automatic-recovery guarantee: attacker fully controls the backend process, HMAC secret, all three MySQL servers, or the original log source before collection.
