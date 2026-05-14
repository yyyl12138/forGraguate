-- Stage 9.5 migration for node1 only.
-- Adds the frozen outbox used to asynchronously append logs/batches to node2 and node3.

CREATE TABLE IF NOT EXISTS logtrace_node1.replica_sync_tasks (
  task_id VARCHAR(64) NOT NULL,
  task_type ENUM('LOG_RECORD', 'BATCH_METADATA', 'BATCH_CHAIN_COMMIT') NOT NULL,
  target_source_node ENUM('node2', 'node3') NOT NULL,
  business_key VARCHAR(128) NOT NULL,
  batch_id VARCHAR(96) NOT NULL,
  source VARCHAR(64) NOT NULL,
  status ENUM('PENDING', 'IN_PROGRESS', 'SUCCEEDED', 'FAILED') NOT NULL DEFAULT 'PENDING',
  payload_json LONGTEXT NOT NULL,
  payload_hash CHAR(64) NOT NULL,
  payload_signature CHAR(64) NOT NULL,
  attempt_count INT UNSIGNED NOT NULL DEFAULT 0,
  next_retry_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  last_error TEXT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

  PRIMARY KEY (task_id),
  UNIQUE KEY uk_replica_sync_business_target (task_type, target_source_node, business_key),
  KEY idx_replica_sync_status_retry (status, next_retry_at),
  KEY idx_replica_sync_batch_status (batch_id, status),
  KEY idx_replica_sync_target_status (target_source_node, status),

  CONSTRAINT ck_replica_sync_task_id CHECK (task_id REGEXP '^rst_[a-f0-9]{32}$'),
  CONSTRAINT ck_replica_sync_payload_json CHECK (JSON_VALID(payload_json)),
  CONSTRAINT ck_replica_sync_payload_hash CHECK (payload_hash REGEXP '^[a-f0-9]{64}$'),
  CONSTRAINT ck_replica_sync_payload_signature CHECK (payload_signature REGEXP '^[a-f0-9]{64}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
