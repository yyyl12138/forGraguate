-- Local mock data for Stage 2.
-- Load this after creating the three Stage 2 schemas:
--   logtrace_node1: main business database
--   logtrace_node2: plaintext log replica database
--   logtrace_node3: plaintext log replica database
-- Default data is a clean three-replica baseline.

SET @batch_id = 'bch_v1_tomcat-cve-2017-12615_20260422T020500Z';
SET @source = 'tomcat-cve-2017-12615';
SET @root = '36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f';

SET @log1 = '{"app_name":"tomcat","batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","hostname":"node1","log_id":"log_v1_81d6381d1672fc38b4353b5d56a4c0f2","msg":"GET / -> 200","msgid":"WEB_ACCESS","pri":134,"procid":"-","raw_message":"172.18.0.1 - - [22/Apr/2026:10:05:01 +0800] \\"GET / HTTP/1.1\\" 200 11230","source":"tomcat-cve-2017-12615","structured_data":{"batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","container_id":"-","container_name":"tomcat-cve-2017-12615","dest_ip":"-","dest_port":8080,"log_type":"access","request_method":"GET","request_uri":"/","response_size":11230,"service_name":"tomcat","source_ip":"172.18.0.1","source_port":null,"status_code":200},"timestamp":"2026-04-22T02:05:01.000Z","version":1}';
SET @log2 = '{"app_name":"tomcat","batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","hostname":"node1","log_id":"log_v1_47138f44da836f20ad0aeede367810e3","msg":"GET /docs/ -> 200","msgid":"WEB_ACCESS","pri":134,"procid":"-","raw_message":"172.18.0.1 - - [22/Apr/2026:10:05:18 +0800] \\"GET /docs/ HTTP/1.1\\" 200 2147","source":"tomcat-cve-2017-12615","structured_data":{"batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","container_id":"-","container_name":"tomcat-cve-2017-12615","dest_ip":"-","dest_port":8080,"log_type":"access","request_method":"GET","request_uri":"/docs/","response_size":2147,"service_name":"tomcat","source_ip":"172.18.0.1","source_port":null,"status_code":200},"timestamp":"2026-04-22T02:05:18.000Z","version":1}';
SET @log3 = '{"app_name":"tomcat","batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","hostname":"node1","log_id":"log_v1_ec926baf07e1dcb3e870c78fbfb0c9a8","msg":"PUT /shell.jsp/ -> 201","msgid":"EXPLOIT_ATTEMPT","pri":134,"procid":"-","raw_message":"172.18.0.1 - - [22/Apr/2026:10:05:42 +0800] \\"PUT /shell.jsp/ HTTP/1.1\\" 201 32","source":"tomcat-cve-2017-12615","structured_data":{"batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z","container_id":"-","container_name":"tomcat-cve-2017-12615","dest_ip":"-","dest_port":8080,"log_type":"access","request_method":"PUT","request_uri":"/shell.jsp/","response_size":32,"service_name":"tomcat","source_ip":"172.18.0.1","source_port":null,"status_code":201},"timestamp":"2026-04-22T02:05:42.000Z","version":1}';

-- Node1 main business data and baseline plaintext replica.
USE logtrace_node1;
DELETE FROM system_operation_audit WHERE username IN ('admin', 'auditor');
DELETE FROM user_login_audit WHERE username IN ('admin', 'auditor');
DELETE FROM user_refresh_tokens WHERE user_id IN (
  SELECT user_id FROM app_users WHERE username IN ('admin', 'auditor')
);
DELETE FROM app_users WHERE username IN ('admin', 'auditor');
DELETE FROM log_batches WHERE batch_id = @batch_id;
DELETE FROM log_records WHERE batch_id = @batch_id;

-- BCrypt placeholder hashes only. Do not treat these as documented plaintext passwords.
INSERT INTO app_users (
  username, password_hash, display_name, role, status, registered_at, last_login_at
) VALUES
('admin', '$2a$10$REPLACE_WITH_ADMIN_BCRYPT_HASH_PLACEHOLDER', 'System Administrator', 'ADMIN', 'ACTIVE', '2026-04-22 02:00:00.000', NULL),
('auditor', '$2a$10$REPLACE_WITH_AUDITOR_BCRYPT_HASH_PLACEHOLDER', 'Security Auditor', 'AUDITOR', 'ACTIVE', '2026-04-22 02:00:00.000', NULL);

INSERT INTO system_operation_audit (
  user_id, username, operation_type, target_type, target_id, result, client_ip, user_agent, detail, occurred_at
)
SELECT
  user_id,
  username,
  'REGISTER',
  'USER',
  CAST(user_id AS CHAR),
  'SUCCESS',
  '127.0.0.1',
  'mock-data-loader',
  JSON_OBJECT('source', 'docs/mysql-mock-data.sql'),
  '2026-04-22 02:00:00.000'
FROM app_users
WHERE username IN ('admin', 'auditor');

INSERT INTO log_records (
  log_id, batch_id, source, source_node, event_time, hostname, app_name, pri, version, procid, msgid, msg,
  source_ip, source_port, dest_ip, dest_port, container_id, container_name, service_name,
  request_method, request_uri, status_code, response_size, log_type,
  raw_message, normalized_message, leaf_hash, file_path, file_offset, ingest_sequence
) VALUES
('log_v1_81d6381d1672fc38b4353b5d56a4c0f2', @batch_id, @source, 'node1', '2026-04-22 02:05:01.000', 'node1', 'tomcat', 134, 1, '-', 'WEB_ACCESS', 'GET / -> 200', '172.18.0.1', NULL, '-', 8080, '-', 'tomcat-cve-2017-12615', 'tomcat', 'GET', '/', 200, 11230, 'access', '172.18.0.1 - - [22/Apr/2026:10:05:01 +0800] "GET / HTTP/1.1" 200 11230', @log1, '5c5f724c953881890458c9075397e9319020da7325205ee46528770229854a92', '/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.2026-04-22.txt', 0, 1),
('log_v1_47138f44da836f20ad0aeede367810e3', @batch_id, @source, 'node1', '2026-04-22 02:05:18.000', 'node1', 'tomcat', 134, 1, '-', 'WEB_ACCESS', 'GET /docs/ -> 200', '172.18.0.1', NULL, '-', 8080, '-', 'tomcat-cve-2017-12615', 'tomcat', 'GET', '/docs/', 200, 2147, 'access', '172.18.0.1 - - [22/Apr/2026:10:05:18 +0800] "GET /docs/ HTTP/1.1" 200 2147', @log2, 'd4be4a0278f1f7071bde5849d212fbdfb3d743f4c8ee57f73af69c4b1c2f723b', '/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.2026-04-22.txt', 82, 2),
('log_v1_ec926baf07e1dcb3e870c78fbfb0c9a8', @batch_id, @source, 'node1', '2026-04-22 02:05:42.000', 'node1', 'tomcat', 134, 1, '-', 'EXPLOIT_ATTEMPT', 'PUT /shell.jsp/ -> 201', '172.18.0.1', NULL, '-', 8080, '-', 'tomcat-cve-2017-12615', 'tomcat', 'PUT', '/shell.jsp/', 201, 32, 'access', '172.18.0.1 - - [22/Apr/2026:10:05:42 +0800] "PUT /shell.jsp/ HTTP/1.1" 201 32', @log3, 'f65deb87cc8f2f5949bcfc80357e742d096d0fb8030fcf29a31cfdf6df86b7f8', '/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.2026-04-22.txt', 164, 3);

INSERT INTO log_batches (
  batch_id, source, source_node, start_time, end_time, log_count, merkle_root,
  schema_version, hash_algorithm, canonicalization_version, seal_status, chain_tx_id, chain_committed_at
) VALUES (
  @batch_id, @source, 'node1', '2026-04-22 02:05:00.000', '2026-04-22 02:06:00.000', 3, @root,
  1, 'SHA-256', 'clog-v1', 'CHAIN_COMMITTED', 'mock_tx_20260422_020500', '2026-04-22 02:06:01.000'
);

-- Node2 baseline
USE logtrace_node2;
DELETE FROM log_batches WHERE batch_id = @batch_id;
DELETE FROM log_records WHERE batch_id = @batch_id;
INSERT INTO log_records (
  log_id, batch_id, source, source_node, event_time, hostname, app_name, pri, version, procid, msgid, msg,
  source_ip, source_port, dest_ip, dest_port, container_id, container_name, service_name,
  request_method, request_uri, status_code, response_size, log_type,
  raw_message, normalized_message, leaf_hash, file_path, file_offset, ingest_sequence, inserted_at, updated_at
)
SELECT
  log_id, batch_id, source, 'node2', event_time, hostname, app_name, pri, version, procid, msgid, msg,
  source_ip, source_port, dest_ip, dest_port, container_id, container_name, service_name,
  request_method, request_uri, status_code, response_size, log_type,
  raw_message, normalized_message, leaf_hash, file_path, file_offset, ingest_sequence, inserted_at, updated_at
FROM logtrace_node1.log_records WHERE batch_id = @batch_id;
INSERT INTO log_batches (
  batch_id, source, source_node, start_time, end_time, log_count, merkle_root,
  schema_version, hash_algorithm, canonicalization_version, seal_status, chain_tx_id, chain_committed_at,
  created_at, updated_at
)
SELECT
  batch_id, source, 'node2', start_time, end_time, log_count, merkle_root,
  schema_version, hash_algorithm, canonicalization_version, seal_status, chain_tx_id, chain_committed_at,
  created_at, updated_at
FROM logtrace_node1.log_batches WHERE batch_id = @batch_id;

-- Node3 baseline
USE logtrace_node3;
DELETE FROM log_batches WHERE batch_id = @batch_id;
DELETE FROM log_records WHERE batch_id = @batch_id;
INSERT INTO log_records (
  log_id, batch_id, source, source_node, event_time, hostname, app_name, pri, version, procid, msgid, msg,
  source_ip, source_port, dest_ip, dest_port, container_id, container_name, service_name,
  request_method, request_uri, status_code, response_size, log_type,
  raw_message, normalized_message, leaf_hash, file_path, file_offset, ingest_sequence, inserted_at, updated_at
)
SELECT
  log_id, batch_id, source, 'node3', event_time, hostname, app_name, pri, version, procid, msgid, msg,
  source_ip, source_port, dest_ip, dest_port, container_id, container_name, service_name,
  request_method, request_uri, status_code, response_size, log_type,
  raw_message, normalized_message, leaf_hash, file_path, file_offset, ingest_sequence, inserted_at, updated_at
FROM logtrace_node1.log_records WHERE batch_id = @batch_id;
INSERT INTO log_batches (
  batch_id, source, source_node, start_time, end_time, log_count, merkle_root,
  schema_version, hash_algorithm, canonicalization_version, seal_status, chain_tx_id, chain_committed_at,
  created_at, updated_at
)
SELECT
  batch_id, source, 'node3', start_time, end_time, log_count, merkle_root,
  schema_version, hash_algorithm, canonicalization_version, seal_status, chain_tx_id, chain_committed_at,
  created_at, updated_at
FROM logtrace_node1.log_batches WHERE batch_id = @batch_id;

-- Demo tamper calls below are examples for the independent hacker simulation script.
-- Backend normal business flow must not call these procedures.

-- Tamper scenario A: node1 deletes the attack log through the demo stored procedure.
-- Expected node1 recomputed root:
--   0972d52b9c5a49a54287486521fc89f52a15fc1313f153daea8afd8b9cf05660
--
-- CALL logtrace_node1.sp_tamper_delete_by_pattern(
--   'bch_v1_tomcat-cve-2017-12615_20260422T020500Z',
--   'request_uri',
--   '%shell.jsp%',
--   'LIKE'
-- );

-- Tamper scenario B: node1 modifies the attack URI through the demo stored procedure.
-- The stored procedure updates leaf_hash with a tamper-domain digest, so backend
-- integrity checking should detect MODIFIED_LOG and BATCH_ROOT_MISMATCH.
--
-- CALL logtrace_node1.sp_tamper_update_by_pattern(
--   'bch_v1_tomcat-cve-2017-12615_20260422T020500Z',
--   'request_uri',
--   '%shell.jsp%',
--   'LIKE',
--   'request_uri',
--   '/shell.jsp'
-- );

-- Tamper scenario C: node1 inserts irrelevant noise logs through the demo stored procedure.
-- Backend integrity checking should detect EXTRA_LOG and BATCH_ROOT_MISMATCH.
--
-- CALL logtrace_node1.sp_tamper_insert_noise(
--   'bch_v1_tomcat-cve-2017-12615_20260422T020500Z',
--   20,
--   '/noise'
-- );
