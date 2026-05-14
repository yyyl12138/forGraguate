-- Stage 7 host-install initialization for node3.
-- This script creates only the node3 plaintext replica schema.

CREATE DATABASE IF NOT EXISTS logtrace_node3
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_bin;

CREATE TABLE IF NOT EXISTS logtrace_node3.log_records (
  log_id VARCHAR(39) NOT NULL,
  batch_id VARCHAR(96) NOT NULL,
  source VARCHAR(64) NOT NULL,
  source_node ENUM('node1', 'node2', 'node3') NOT NULL,

  event_time DATETIME(3) NOT NULL,
  hostname VARCHAR(255) NOT NULL,
  app_name VARCHAR(48) NOT NULL,
  pri TINYINT UNSIGNED NOT NULL,
  version TINYINT UNSIGNED NOT NULL,
  procid VARCHAR(64) NOT NULL DEFAULT '-',
  msgid VARCHAR(32) NOT NULL,
  msg TEXT NOT NULL,

  source_ip VARCHAR(45) NOT NULL DEFAULT '-',
  source_port INT UNSIGNED NULL,
  dest_ip VARCHAR(45) NOT NULL DEFAULT '-',
  dest_port INT UNSIGNED NULL,
  container_id VARCHAR(128) NOT NULL DEFAULT '-',
  container_name VARCHAR(128) NOT NULL DEFAULT '-',
  service_name VARCHAR(64) NOT NULL,
  request_method VARCHAR(16) NOT NULL DEFAULT '-',
  request_uri TEXT NOT NULL,
  status_code SMALLINT UNSIGNED NULL,
  response_size BIGINT UNSIGNED NULL,
  log_type VARCHAR(32) NOT NULL,

  raw_message TEXT NOT NULL,
  normalized_message JSON NOT NULL,
  leaf_hash CHAR(64) NOT NULL,

  file_path VARCHAR(512) NULL,
  file_offset BIGINT UNSIGNED NULL,
  ingest_sequence BIGINT UNSIGNED NULL,

  inserted_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

  PRIMARY KEY (log_id),
  UNIQUE KEY uk_log_source_file_offset (source, file_path, file_offset),
  KEY idx_log_batch_order (batch_id, event_time, log_id),
  KEY idx_log_batch_leaf (batch_id, leaf_hash),
  KEY idx_log_source_time (source, event_time),
  KEY idx_log_event_time (event_time),
  KEY idx_log_source_ip_time (source_ip, event_time),
  KEY idx_log_method_time (request_method, event_time),
  KEY idx_log_status_time (status_code, event_time),
  KEY idx_log_msgid_time (msgid, event_time),
  KEY idx_log_request_uri (request_uri(255)),

  CONSTRAINT ck_log_id_format CHECK (log_id REGEXP '^log_v1_[a-f0-9]{32}$'),
  CONSTRAINT ck_batch_id_format CHECK (batch_id REGEXP '^bch_v1_[a-z0-9][a-z0-9-]*_[0-9]{8}T[0-9]{6}Z$'),
  CONSTRAINT ck_leaf_hash_format CHECK (leaf_hash REGEXP '^[a-f0-9]{64}$'),
  CONSTRAINT ck_hash_not_in_normalized CHECK (
    JSON_CONTAINS_PATH(normalized_message, 'one', '$.leaf_hash') = 0
    AND JSON_CONTAINS_PATH(normalized_message, 'one', '$.source_node') = 0
  ),
  CONSTRAINT ck_rfc5424_pri CHECK (pri BETWEEN 0 AND 191),
  CONSTRAINT ck_rfc5424_version CHECK (version = 1),
  CONSTRAINT ck_source_port CHECK (source_port IS NULL OR source_port <= 65535),
  CONSTRAINT ck_dest_port CHECK (dest_port IS NULL OR dest_port <= 65535),
  CONSTRAINT ck_status_code CHECK (status_code IS NULL OR status_code BETWEEN 100 AND 599)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS logtrace_node3.log_batches (
  batch_id VARCHAR(96) NOT NULL,
  source VARCHAR(64) NOT NULL,
  source_node ENUM('node1', 'node2', 'node3') NOT NULL,

  start_time DATETIME(3) NOT NULL,
  end_time DATETIME(3) NOT NULL,
  log_count INT UNSIGNED NOT NULL,
  merkle_root CHAR(64) NOT NULL,

  schema_version INT UNSIGNED NOT NULL DEFAULT 1,
  hash_algorithm VARCHAR(16) NOT NULL DEFAULT 'SHA-256',
  canonicalization_version VARCHAR(16) NOT NULL DEFAULT 'clog-v1',

  seal_status ENUM('SEALED_PENDING_CHAIN', 'CHAIN_COMMITTED') NOT NULL DEFAULT 'SEALED_PENDING_CHAIN',
  chain_tx_id VARCHAR(128) NULL,
  chain_committed_at DATETIME(3) NULL,

  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

  PRIMARY KEY (batch_id),
  KEY idx_batch_source_time (source, start_time, end_time),
  KEY idx_batch_status_time (seal_status, start_time),
  KEY idx_batch_chain_tx_id (chain_tx_id),

  CONSTRAINT ck_batch_id_format_batches CHECK (batch_id REGEXP '^bch_v1_[a-z0-9][a-z0-9-]*_[0-9]{8}T[0-9]{6}Z$'),
  CONSTRAINT ck_batch_merkle_root_format CHECK (merkle_root REGEXP '^[a-f0-9]{64}$'),
  CONSTRAINT ck_batch_log_count CHECK (log_count > 0),
  CONSTRAINT ck_batch_time_order CHECK (start_time < end_time),
  CONSTRAINT ck_batch_window_60s CHECK (TIMESTAMPDIFF(MICROSECOND, start_time, end_time) = 60000000),
  CONSTRAINT ck_batch_schema_version CHECK (schema_version = 1),
  CONSTRAINT ck_batch_hash_algorithm CHECK (hash_algorithm = 'SHA-256'),
  CONSTRAINT ck_batch_canonicalization_version CHECK (canonicalization_version = 'clog-v1')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
