-- Stage 7 host-install initialization for node1.
-- This script creates only the node1 business schema and keeps the
-- demo-only tamper procedures on node1.

CREATE DATABASE IF NOT EXISTS logtrace_node1
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_bin;

CREATE TABLE IF NOT EXISTS logtrace_node1.app_users (
  user_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  username VARCHAR(64) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  display_name VARCHAR(128) NOT NULL,
  role ENUM('ADMIN', 'AUDITOR', 'OPERATOR') NOT NULL DEFAULT 'OPERATOR',
  status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  registered_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  last_login_at DATETIME(3) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

  PRIMARY KEY (user_id),
  UNIQUE KEY uk_app_user_username (username),
  KEY idx_app_user_role_status (role, status),

  CONSTRAINT ck_app_user_username CHECK (username REGEXP '^[A-Za-z0-9_][A-Za-z0-9_.-]{2,63}$'),
  CONSTRAINT ck_app_user_password_hash CHECK (CHAR_LENGTH(password_hash) >= 20)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS logtrace_node1.user_login_audit (
  login_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NULL,
  username VARCHAR(64) NOT NULL,
  success TINYINT(1) NOT NULL,
  client_ip VARCHAR(45) NOT NULL DEFAULT '-',
  user_agent VARCHAR(512) NOT NULL DEFAULT '-',
  failure_reason VARCHAR(255) NULL,
  logged_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (login_id),
  KEY idx_login_audit_user_time (user_id, logged_at),
  KEY idx_login_audit_username_time (username, logged_at),
  KEY idx_login_audit_success_time (success, logged_at),

  CONSTRAINT fk_login_audit_user FOREIGN KEY (user_id)
    REFERENCES logtrace_node1.app_users(user_id)
    ON DELETE SET NULL,
  CONSTRAINT ck_login_audit_success CHECK (success IN (0, 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS logtrace_node1.user_refresh_tokens (
  token_id VARCHAR(64) NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  token_hash CHAR(64) NOT NULL,
  expires_at DATETIME(3) NOT NULL,
  revoked_at DATETIME(3) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  last_used_at DATETIME(3) NULL,

  PRIMARY KEY (token_id),
  UNIQUE KEY uk_refresh_token_hash (token_hash),
  KEY idx_refresh_token_user (user_id),
  KEY idx_refresh_token_expiry (expires_at),

  CONSTRAINT fk_refresh_token_user FOREIGN KEY (user_id)
    REFERENCES logtrace_node1.app_users(user_id)
    ON DELETE CASCADE,
  CONSTRAINT ck_refresh_token_id CHECK (token_id REGEXP '^rt_[A-Za-z0-9_-]{16,61}$'),
  CONSTRAINT ck_refresh_token_hash CHECK (token_hash REGEXP '^[a-f0-9]{64}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS logtrace_node1.system_operation_audit (
  audit_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NULL,
  username VARCHAR(64) NULL,
  operation_type ENUM(
    'REGISTER',
    'LOGIN',
    'LOG_SEARCH',
    'SEAL_BATCH',
    'INTEGRITY_CHECK',
    'DEMO_ATTACK',
    'DEMO_TAMPER',
    'LOG_INGEST',
    'COMMIT_CHAIN_TX'
  ) NOT NULL,
  target_type VARCHAR(64) NULL,
  target_id VARCHAR(128) NULL,
  result ENUM('SUCCESS', 'FAILED') NOT NULL,
  client_ip VARCHAR(45) NOT NULL DEFAULT '-',
  user_agent VARCHAR(512) NOT NULL DEFAULT '-',
  detail JSON NULL,
  occurred_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (audit_id),
  KEY idx_operation_audit_user_time (user_id, occurred_at),
  KEY idx_operation_audit_type_time (operation_type, occurred_at),
  KEY idx_operation_audit_target (target_type, target_id),

  CONSTRAINT fk_operation_audit_user FOREIGN KEY (user_id)
    REFERENCES logtrace_node1.app_users(user_id)
    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS logtrace_node1.log_records (
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

CREATE TABLE IF NOT EXISTS logtrace_node1.log_batches (
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

CREATE TABLE IF NOT EXISTS logtrace_node1.replica_write_audit (
  write_id VARCHAR(64) NOT NULL,
  batch_id VARCHAR(96) NULL,
  source VARCHAR(64) NOT NULL,
  target_source_node ENUM('node1', 'node2', 'node3') NOT NULL,
  operation_type ENUM('INGEST_LOGS', 'SEAL_BATCH', 'COMMIT_CHAIN_TX') NOT NULL,
  status ENUM('SUCCESS', 'FAILED') NOT NULL,
  error_message TEXT NULL,
  attempted_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (write_id, target_source_node, operation_type),
  KEY idx_audit_batch (batch_id),
  KEY idx_audit_status_time (status, attempted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

DELIMITER //

DROP PROCEDURE IF EXISTS logtrace_node1.sp_tamper_delete_by_pattern//
CREATE PROCEDURE logtrace_node1.sp_tamper_delete_by_pattern(
  IN p_batch_id VARCHAR(96),
  IN p_match_field VARCHAR(64),
  IN p_match_value TEXT,
  IN p_match_mode VARCHAR(16)
)
BEGIN
  IF p_batch_id IS NULL OR p_batch_id NOT REGEXP '^bch_v1_[a-z0-9][a-z0-9-]*_[0-9]{8}T[0-9]{6}Z$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid batch_id';
  END IF;

  IF p_match_field NOT IN ('log_id', 'msgid', 'request_method', 'request_uri', 'source_ip', 'status_code', 'raw_message', 'msg') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid match_field';
  END IF;

  IF UPPER(p_match_mode) NOT IN ('EQUAL', 'LIKE') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid match_mode';
  END IF;

  DELETE FROM logtrace_node1.log_records
  WHERE batch_id = p_batch_id
    AND (
      (UPPER(p_match_mode) = 'EQUAL' AND
        CASE p_match_field
          WHEN 'log_id' THEN log_id
          WHEN 'msgid' THEN msgid
          WHEN 'request_method' THEN request_method
          WHEN 'request_uri' THEN request_uri
          WHEN 'source_ip' THEN source_ip
          WHEN 'status_code' THEN CAST(status_code AS CHAR)
          WHEN 'raw_message' THEN raw_message
          WHEN 'msg' THEN msg
        END = p_match_value)
      OR
      (UPPER(p_match_mode) = 'LIKE' AND
        CASE p_match_field
          WHEN 'log_id' THEN log_id
          WHEN 'msgid' THEN msgid
          WHEN 'request_method' THEN request_method
          WHEN 'request_uri' THEN request_uri
          WHEN 'source_ip' THEN source_ip
          WHEN 'status_code' THEN CAST(status_code AS CHAR)
          WHEN 'raw_message' THEN raw_message
          WHEN 'msg' THEN msg
        END LIKE p_match_value)
    );
END//

DROP PROCEDURE IF EXISTS logtrace_node1.sp_tamper_update_by_pattern//
CREATE PROCEDURE logtrace_node1.sp_tamper_update_by_pattern(
  IN p_batch_id VARCHAR(96),
  IN p_match_field VARCHAR(64),
  IN p_match_value TEXT,
  IN p_match_mode VARCHAR(16),
  IN p_target_field VARCHAR(64),
  IN p_new_value TEXT
)
BEGIN
  IF p_batch_id IS NULL OR p_batch_id NOT REGEXP '^bch_v1_[a-z0-9][a-z0-9-]*_[0-9]{8}T[0-9]{6}Z$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid batch_id';
  END IF;

  IF p_match_field NOT IN ('log_id', 'msgid', 'request_method', 'request_uri', 'source_ip', 'status_code', 'raw_message', 'msg') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid match_field';
  END IF;

  IF UPPER(p_match_mode) NOT IN ('EQUAL', 'LIKE') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid match_mode';
  END IF;

  IF p_target_field NOT IN ('request_uri', 'source_ip', 'status_code', 'raw_message', 'msg') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid target_field';
  END IF;

  IF p_target_field = 'status_code' AND (
    p_new_value NOT REGEXP '^[0-9]{3}$'
    OR CAST(p_new_value AS UNSIGNED) < 100
    OR CAST(p_new_value AS UNSIGNED) > 599
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid status_code';
  END IF;

  UPDATE logtrace_node1.log_records
  SET
    request_uri = IF(p_target_field = 'request_uri', p_new_value, request_uri),
    source_ip = IF(p_target_field = 'source_ip', p_new_value, source_ip),
    status_code = IF(p_target_field = 'status_code', CAST(p_new_value AS UNSIGNED), status_code),
    raw_message = IF(p_target_field = 'raw_message', p_new_value, raw_message),
    msg = IF(p_target_field = 'msg', p_new_value, msg),
    normalized_message =
      CASE p_target_field
        WHEN 'request_uri' THEN JSON_SET(normalized_message, '$.structured_data.request_uri', p_new_value)
        WHEN 'source_ip' THEN JSON_SET(normalized_message, '$.structured_data.source_ip', p_new_value)
        WHEN 'status_code' THEN JSON_SET(normalized_message, '$.structured_data.status_code', CAST(p_new_value AS UNSIGNED))
        WHEN 'raw_message' THEN JSON_SET(normalized_message, '$.raw_message', p_new_value)
        WHEN 'msg' THEN JSON_SET(normalized_message, '$.msg', p_new_value)
        ELSE normalized_message
      END,
    leaf_hash = SHA2(CONCAT('LOGTRACE_TAMPER_UPDATE_V1\n', log_id, '\n', p_target_field, '\n', COALESCE(p_new_value, '')), 256),
    updated_at = CURRENT_TIMESTAMP(3)
  WHERE batch_id = p_batch_id
    AND (
      (UPPER(p_match_mode) = 'EQUAL' AND
        CASE p_match_field
          WHEN 'log_id' THEN log_id
          WHEN 'msgid' THEN msgid
          WHEN 'request_method' THEN request_method
          WHEN 'request_uri' THEN request_uri
          WHEN 'source_ip' THEN source_ip
          WHEN 'status_code' THEN CAST(status_code AS CHAR)
          WHEN 'raw_message' THEN raw_message
          WHEN 'msg' THEN msg
        END = p_match_value)
      OR
      (UPPER(p_match_mode) = 'LIKE' AND
        CASE p_match_field
          WHEN 'log_id' THEN log_id
          WHEN 'msgid' THEN msgid
          WHEN 'request_method' THEN request_method
          WHEN 'request_uri' THEN request_uri
          WHEN 'source_ip' THEN source_ip
          WHEN 'status_code' THEN CAST(status_code AS CHAR)
          WHEN 'raw_message' THEN raw_message
          WHEN 'msg' THEN msg
        END LIKE p_match_value)
    );
END//

DROP PROCEDURE IF EXISTS logtrace_node1.sp_tamper_insert_noise//
CREATE PROCEDURE logtrace_node1.sp_tamper_insert_noise(
  IN p_batch_id VARCHAR(96),
  IN p_noise_count INT UNSIGNED,
  IN p_request_uri_prefix VARCHAR(255)
)
BEGIN
  DECLARE v_i INT UNSIGNED DEFAULT 0;
  DECLARE v_source VARCHAR(64);
  DECLARE v_start_time DATETIME(3);
  DECLARE v_event_time DATETIME(3);
  DECLARE v_log_id VARCHAR(39);
  DECLARE v_uri TEXT;
  DECLARE v_raw TEXT;
  DECLARE v_normalized JSON;
  DECLARE v_leaf_hash CHAR(64);

  IF p_batch_id IS NULL OR p_batch_id NOT REGEXP '^bch_v1_[a-z0-9][a-z0-9-]*_[0-9]{8}T[0-9]{6}Z$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid batch_id';
  END IF;

  IF p_noise_count IS NULL OR p_noise_count = 0 OR p_noise_count > 1000 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid noise_count';
  END IF;

  SELECT source, start_time
  INTO v_source, v_start_time
  FROM logtrace_node1.log_batches
  WHERE batch_id = p_batch_id
  LIMIT 1;

  IF v_source IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'batch not found';
  END IF;

  WHILE v_i < p_noise_count DO
    SET v_event_time = TIMESTAMPADD(SECOND, v_i % 60, v_start_time);
    SET v_uri = CONCAT(COALESCE(NULLIF(p_request_uri_prefix, ''), '/noise'), '/', v_i);
    SET v_raw = CONCAT('10.255.0.', v_i % 255, ' - - [tampered] "GET ', v_uri, ' HTTP/1.1" 404 0');
    SET v_log_id = CONCAT('log_v1_', LEFT(SHA2(CONCAT('LOGTRACE_NOISE_LOG_ID_V1\n', p_batch_id, '\n', v_i, '\n', v_raw), 256), 32));
    SET v_normalized = JSON_OBJECT(
      'app_name', 'tamper-noise',
      'batch_id', p_batch_id,
      'hostname', 'node1',
      'log_id', v_log_id,
      'msg', CONCAT('GET ', v_uri, ' -> 404'),
      'msgid', 'WEB_ACCESS',
      'pri', 134,
      'procid', '-',
      'raw_message', v_raw,
      'source', v_source,
      'structured_data', JSON_OBJECT(
        'batch_id', p_batch_id,
        'container_id', '-',
        'container_name', 'tamper-noise',
        'dest_ip', '-',
        'dest_port', 8080,
        'log_type', 'access',
        'request_method', 'GET',
        'request_uri', v_uri,
        'response_size', 0,
        'service_name', 'tamper-noise',
        'source_ip', CONCAT('10.255.0.', v_i % 255),
        'source_port', CAST(NULL AS UNSIGNED),
        'status_code', 404
      ),
      'timestamp', DATE_FORMAT(v_event_time, '%Y-%m-%dT%H:%i:%s.000Z'),
      'version', 1
    );
    SET v_leaf_hash = SHA2(CONCAT('LOGTRACE_TAMPER_NOISE_V1\n', v_log_id, '\n', v_raw), 256);

    INSERT INTO logtrace_node1.log_records (
      log_id, batch_id, source, source_node, event_time, hostname, app_name, pri, version, procid, msgid, msg,
      source_ip, source_port, dest_ip, dest_port, container_id, container_name, service_name,
      request_method, request_uri, status_code, response_size, log_type,
      raw_message, normalized_message, leaf_hash, file_path, file_offset, ingest_sequence
    ) VALUES (
      v_log_id, p_batch_id, v_source, 'node1', v_event_time, 'node1', 'tamper-noise', 134, 1, '-', 'WEB_ACCESS', CONCAT('GET ', v_uri, ' -> 404'),
      CONCAT('10.255.0.', v_i % 255), NULL, '-', 8080, '-', 'tamper-noise', 'tamper-noise',
      'GET', v_uri, 404, 0, 'access',
      v_raw, v_normalized, v_leaf_hash, NULL, NULL, NULL
    );

    SET v_i = v_i + 1;
  END WHILE;
END//

DELIMITER ;
