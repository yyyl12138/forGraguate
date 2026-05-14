# 阶段9.5：防污染异步副本同步操作手册

本手册用于在真实三虚拟机环境中验收 Stage 9.5：

- `node1` 主写日志与冻结 outbox。
- `node2/node3` 从冻结 payload 异步追加副本。
- `node1.log_records` 后续 `DELETE/UPDATE` 不会传播到副本。
- `/api/batches/seal` 在三库未追平或副本记录验证 digest 不一致时拒绝上链。
- seal 后插入大量正常外观日志时，完整性校验只把 `node1` 标记为异常，`node2/node3` 作为可信参考副本。

为避免重复 `batch_id` 或重复 `log_id` 干扰，每个验收场景都使用不同的 60 秒窗口。

## 1. 批次窗口约定

下面手册使用 4 个互不重复的窗口：

| 场景 | 日志时间，北京时间 | UTC seal start_time | batch_id |
|---|---|---|---|
| 正常链路 | `2026-04-22 10:30:xx +0800` | `2026-04-22T02:30:00.000Z` | `bch_v1_tomcat-cve-2017-12615_20260422T023000Z` |
| node2 离线 | `2026-04-22 10:31:xx +0800` | `2026-04-22T02:31:00.000Z` | `bch_v1_tomcat-cve-2017-12615_20260422T023100Z` |
| seal 前篡改 | `2026-04-22 10:32:xx +0800` | `2026-04-22T02:32:00.000Z` | `bch_v1_tomcat-cve-2017-12615_20260422T023200Z` |
| seal 后插入日志 | `2026-04-22 10:33:xx +0800` | `2026-04-22T02:33:00.000Z` | `bch_v1_tomcat-cve-2017-12615_20260422T023300Z` |

如果你的链上已经存在这些批次，就把所有命令里的分钟整体换成新的未使用窗口，例如 `10:20`、`10:21`、`10:22`、`10:23`。

## 2. 重跑前清理策略

如果已经按旧版 Stage 9.5 手册执行过一次，不建议直接复用旧批次窗口。推荐做法是：

- MySQL 中的测试批次可以清理。
- Fabric 链上批次不要尝试单条删除；链码设计保证同一 `batch_id` 不可被静默覆盖。
- 避免重复批次的常规方式是使用新的未上链时间窗口，并在 `agent.md` 的“已用批次登记”中记录。
- 如果必须清理链上信息，只能重置 Fabric 账本/容器卷并重新执行阶段 8、阶段 9；这会破坏当前 Fabric 验收基线，本手册不建议这样做。

在 `node1` 执行下面命令，清理本手册当前窗口和旧版 Stage 9.5 默认窗口在三台 MySQL 中留下的测试数据。该命令不会影响 Fabric 链上状态。

```bash
STAGE95_BATCHES="'bch_v1_tomcat-cve-2017-12615_20260422T021000Z',\
'bch_v1_tomcat-cve-2017-12615_20260422T021100Z',\
'bch_v1_tomcat-cve-2017-12615_20260422T021200Z',\
'bch_v1_tomcat-cve-2017-12615_20260422T021300Z',\
'bch_v1_tomcat-cve-2017-12615_20260422T023000Z',\
'bch_v1_tomcat-cve-2017-12615_20260422T023100Z',\
'bch_v1_tomcat-cve-2017-12615_20260422T023200Z',\
'bch_v1_tomcat-cve-2017-12615_20260422T023300Z'"

mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "DELETE FROM replica_sync_tasks WHERE batch_id IN ($STAGE95_BATCHES);
      DELETE FROM replica_write_audit WHERE batch_id IN ($STAGE95_BATCHES);
      DELETE FROM log_batches WHERE batch_id IN ($STAGE95_BATCHES);
      DELETE FROM log_records WHERE batch_id IN ($STAGE95_BATCHES);"

mysql -u"$LOGTRACE_NODE2_JDBC_USERNAME" -p"$LOGTRACE_NODE2_JDBC_PASSWORD" \
  -h192.168.88.102 -Dlogtrace_node2 \
  -e "DELETE FROM log_batches WHERE batch_id IN ($STAGE95_BATCHES);
      DELETE FROM log_records WHERE batch_id IN ($STAGE95_BATCHES);"

mysql -u"$LOGTRACE_NODE3_JDBC_USERNAME" -p"$LOGTRACE_NODE3_JDBC_PASSWORD" \
  -h192.168.88.103 -Dlogtrace_node3 \
  -e "DELETE FROM log_batches WHERE batch_id IN ($STAGE95_BATCHES);
      DELETE FROM log_records WHERE batch_id IN ($STAGE95_BATCHES);"
```

清理后确认三库没有这些批次的明文和本地批次记录：

```bash
mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "SELECT 'node1_logs' AS item, COUNT(*) FROM log_records WHERE batch_id IN ($STAGE95_BATCHES)
      UNION ALL
      SELECT 'node1_batches', COUNT(*) FROM log_batches WHERE batch_id IN ($STAGE95_BATCHES)
      UNION ALL
      SELECT 'node1_tasks', COUNT(*) FROM replica_sync_tasks WHERE batch_id IN ($STAGE95_BATCHES);"

mysql -u"$LOGTRACE_NODE2_JDBC_USERNAME" -p"$LOGTRACE_NODE2_JDBC_PASSWORD" \
  -h192.168.88.102 -Dlogtrace_node2 \
  -e "SELECT 'node2_logs' AS item, COUNT(*) FROM log_records WHERE batch_id IN ($STAGE95_BATCHES)
      UNION ALL
      SELECT 'node2_batches', COUNT(*) FROM log_batches WHERE batch_id IN ($STAGE95_BATCHES);"

mysql -u"$LOGTRACE_NODE3_JDBC_USERNAME" -p"$LOGTRACE_NODE3_JDBC_PASSWORD" \
  -h192.168.88.103 -Dlogtrace_node3 \
  -e "SELECT 'node3_logs' AS item, COUNT(*) FROM log_records WHERE batch_id IN ($STAGE95_BATCHES)
      UNION ALL
      SELECT 'node3_batches', COUNT(*) FROM log_batches WHERE batch_id IN ($STAGE95_BATCHES);"
```

预期所有 `COUNT(*)` 都为 `0`。如果链上已经存在当前手册的 `02:30` 到 `02:33` 四个批次，则 MySQL 清理后仍会在 seal 时遇到 `batch evidence already exists`；此时应整体换一组新分钟窗口，并把新批次登记到 `agent.md`。

## 3. Xftp 上传

在 Windows 中用 Xftp 上传到 `node1`，推荐目录：

```text
/home/yangli/Documents/logtrace/
```

至少上传：

```text
backend/
docs/
ops/stage9.5/node1-sync-migration.sql
ops/stage9.5/README.md
ops/backend-runtime.env.example
```

如果不确定哪些文件变更过，直接上传整个项目目录覆盖 `backend`、`docs`、`ops`。

## 4. node1 执行迁移

在 Xshell 登录 `node1`：

```bash
cd /home/yangli/Documents/logtrace
sudo mysql < ops/stage9.5/node1-sync-migration.sql
```

确认 outbox 表存在：

```bash
mysql -ulogtrace_app -p -h127.0.0.1 -Dlogtrace_node1 \
  -e "SHOW TABLES LIKE 'replica_sync_tasks';"
```

预期输出包含：

```text
replica_sync_tasks
```

## 5. 配置后端环境

在后端目录创建或更新 env 文件：

```bash
cd /home/yangli/Documents/logtrace/backend
cp ../ops/backend-runtime.env.example ./backend-stage95.env
vim backend-stage95.env
```

必须把 `CHANGE_ME_*` 改成真实值，并追加或确认以下配置：

```bash
LOGTRACE_LEDGER_MODE=fabric
LOGTRACE_REPLICA_SYNC_SECRET='stage95-change-me-to-a-long-random-secret'
LOGTRACE_REPLICA_SYNC_SCHEDULER_ENABLED=true
LOGTRACE_REPLICA_SYNC_POLL_INTERVAL_MILLIS=5000
LOGTRACE_REPLICA_SYNC_DRAIN_TIMEOUT_MILLIS=10000
```

加载环境变量时必须使用 `set -a`：

```bash
cd /home/yangli/Documents/logtrace/backend
set -a
source ./backend-stage95.env
set +a

echo "$LOGTRACE_NODE1_JDBC_USERNAME"
echo "$LOGTRACE_NODE1_JDBC_URL"
```

三条 JDBC URL 必须保留单引号，因为 URL 中有 `&`。

## 6. 启动后端

仍在刚才加载 env 的同一个 Xshell 窗口：

```bash
cd /home/yangli/Documents/logtrace/backend
mvn spring-boot:run
```

如果看到 `replica sync task table is unavailable`，说明第 3 节迁移没有执行成功，或 env 没有加载到正确的 `node1` 数据库。

## 7. 获取 JWT

如果没有账号，先注册：

```bash
curl -s -X POST http://127.0.0.1:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"Admin@123456","display_name":"Stage95 Admin"}'
```

登录获取 JWT：

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"Admin@123456"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "$TOKEN"
```

如果 `echo "$TOKEN"` 有输出，后续命令可以直接复制执行。

## 8. 正常链路验收

本节使用窗口：

```text
batch_id = bch_v1_tomcat-cve-2017-12615_20260422T023000Z
seal start_time = 2026-04-22T02:30:00.000Z
```

执行 ingest：

```bash
curl -s -X POST http://127.0.0.1:8080/api/logs/ingest \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "source":"tomcat-cve-2017-12615",
    "hostname":"node1",
    "app_name":"tomcat",
    "file_path":"/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.stage95-normal.txt",
    "records":[
      {"raw_message":"172.18.0.1 - - [22/Apr/2026:10:30:01 +0800] \"GET /stage95-normal-1 HTTP/1.1\" 200 11230","file_offset":103000},
      {"raw_message":"172.18.0.1 - - [22/Apr/2026:10:30:18 +0800] \"PUT /stage95-normal-shell.jsp/ HTTP/1.1\" 201 32","file_offset":103082}
    ]
  }'
```

预期响应包含：

```json
"replica_sync_status":"PENDING"
```

等待 5 到 10 秒后查询任务：

```bash
mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "SELECT task_type,target_source_node,status,COUNT(*)
      FROM replica_sync_tasks
      WHERE batch_id='bch_v1_tomcat-cve-2017-12615_20260422T023000Z'
      GROUP BY task_type,target_source_node,status;"
```

预期 `node2/node3` 的 `LOG_RECORD` 都是 `SUCCEEDED`。

执行 seal：

```bash
curl -s -X POST http://127.0.0.1:8080/api/batches/seal \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"source":"tomcat-cve-2017-12615","start_time":"2026-04-22T02:30:00.000Z"}'
```

预期返回：

```json
"seal_status":"CHAIN_COMMITTED"
```

如果 seal 长时间无响应，不要在原请求还未结束时再次执行同一批次的 seal。旧版后端没有 Fabric 调用 deadline，首次请求可能已经提交了 Fabric 交易但还在等待 commit status；此时重复提交同一 `batch_id` 可能触发 Fabric `MVCC_READ_CONFLICT`。遇到这种情况，先按第 12 节诊断命令确认 `log_batches.seal_status`、链上 evidence 和三库完整性，再决定是否继续。

## 9. node2 离线验收

本节保留为诊断与回归参考。本次最小收口不要求重新证明 `IN_PROGRESS` 卡住重置能力；如果执行本节，只需确认离线时 seal 会因副本未追平而拒绝，恢复后任务可重试成功。

本节使用窗口：

```text
batch_id = bch_v1_tomcat-cve-2017-12615_20260422T023100Z
seal start_time = 2026-04-22T02:31:00.000Z
```

在 `node2` 停止 MySQL：

```bash
sudo systemctl stop mysql
sudo systemctl status mysql --no-pager
```

回到 `node1`，确认 node2 连不上：

```bash
mysql -u"$LOGTRACE_NODE2_JDBC_USERNAME" -p"$LOGTRACE_NODE2_JDBC_PASSWORD" \
  -h192.168.88.102 -Dlogtrace_node2 -e "SELECT 1;"
```

预期该命令失败。

执行本节专用 ingest：

```bash
curl -s -X POST http://127.0.0.1:8080/api/logs/ingest \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "source":"tomcat-cve-2017-12615",
    "hostname":"node1",
    "app_name":"tomcat",
    "file_path":"/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.stage95-node2-down.txt",
    "records":[
      {"raw_message":"172.18.0.1 - - [22/Apr/2026:10:31:01 +0800] \"GET /stage95-node2-down HTTP/1.1\" 200 11230","file_offset":113100}
    ]
  }'
```

等待 5 到 10 秒后查询任务：

```bash
mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "SELECT task_type,target_source_node,status,attempt_count,last_error
      FROM replica_sync_tasks
      WHERE batch_id='bch_v1_tomcat-cve-2017-12615_20260422T023100Z'
      ORDER BY target_source_node,status;"
```

预期：

- `node3` 为 `SUCCEEDED`
- `node2` 为 `FAILED` 或短暂 `PENDING`
- 如果短暂出现 `IN_PROGRESS`，可使用第 12 节诊断命令观察或手动重置；该能力已确认稳定，不作为本次必测门禁。

执行 seal：

```bash
curl -s -X POST http://127.0.0.1:8080/api/batches/seal \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"source":"tomcat-cve-2017-12615","start_time":"2026-04-22T02:31:00.000Z"}'
```

预期返回 400，detail 类似：

```text
replica sync incomplete for batch ...
```

恢复 node2：

```bash
sudo systemctl start mysql
sudo systemctl status mysql --no-pager
```

在 `node1` 将失败任务改为立即重试：

```bash
mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "UPDATE replica_sync_tasks
      SET next_retry_at=NOW(3)
      WHERE batch_id='bch_v1_tomcat-cve-2017-12615_20260422T023100Z'
        AND target_source_node='node2'
        AND status='FAILED';"
```

等待 5 到 10 秒，再查任务，应变为 `SUCCEEDED`。此时再次执行本节 seal 命令，应成功。

## 10. seal 前篡改防污染验收

本节使用窗口：

```text
batch_id = bch_v1_tomcat-cve-2017-12615_20260422T023200Z
seal start_time = 2026-04-22T02:32:00.000Z
```

确保 node2 MySQL 已恢复：

```bash
mysql -u"$LOGTRACE_NODE2_JDBC_USERNAME" -p"$LOGTRACE_NODE2_JDBC_PASSWORD" \
  -h192.168.88.102 -Dlogtrace_node2 -e "SELECT 1;"
```

执行本节专用 ingest：

```bash
curl -s -X POST http://127.0.0.1:8080/api/logs/ingest \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "source":"tomcat-cve-2017-12615",
    "hostname":"node1",
    "app_name":"tomcat",
    "file_path":"/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.stage95-before-seal-tamper.txt",
    "records":[
      {"raw_message":"172.18.0.1 - - [22/Apr/2026:10:32:01 +0800] \"GET /stage95-before-seal-original HTTP/1.1\" 200 11230","file_offset":123200}
    ]
  }'
```

等待任务成功：

```bash
mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "SELECT target_source_node,status,COUNT(*)
      FROM replica_sync_tasks
      WHERE batch_id='bch_v1_tomcat-cve-2017-12615_20260422T023200Z'
      GROUP BY target_source_node,status;"
```

确认 `node2/node3` 都是 `SUCCEEDED` 后，在 `node1` 篡改明文日志：

```bash
mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "UPDATE log_records
      SET request_uri='/tampered-before-seal',
          raw_message='tampered-before-seal',
          updated_at=CURRENT_TIMESTAMP(3)
      WHERE batch_id='bch_v1_tomcat-cve-2017-12615_20260422T023200Z'
      LIMIT 1;"
```

查询三库内容，验证 node2/node3 没有被污染：

```bash
mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "SELECT source_node,request_uri,raw_message
      FROM log_records
      WHERE batch_id='bch_v1_tomcat-cve-2017-12615_20260422T023200Z';"

mysql -u"$LOGTRACE_NODE2_JDBC_USERNAME" -p"$LOGTRACE_NODE2_JDBC_PASSWORD" \
  -h192.168.88.102 -Dlogtrace_node2 \
  -e "SELECT source_node,request_uri,raw_message
      FROM log_records
      WHERE batch_id='bch_v1_tomcat-cve-2017-12615_20260422T023200Z';"

mysql -u"$LOGTRACE_NODE3_JDBC_USERNAME" -p"$LOGTRACE_NODE3_JDBC_PASSWORD" \
  -h192.168.88.103 -Dlogtrace_node3 \
  -e "SELECT source_node,request_uri,raw_message
      FROM log_records
      WHERE batch_id='bch_v1_tomcat-cve-2017-12615_20260422T023200Z';"
```

预期：

- node1 显示 `/tampered-before-seal`
- node2/node3 仍显示 `/stage95-before-seal-original`

执行 seal：

```bash
curl -s -X POST http://127.0.0.1:8080/api/batches/seal \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"source":"tomcat-cve-2017-12615","start_time":"2026-04-22T02:32:00.000Z"}'
```

预期返回 400，因为三库不一致。常见 detail：

```text
stored leaf_hash does not match normalized_message
```

或：

```text
replica leaf_hash mismatch
```

或：

```text
replica record digest mismatch
```

说明：本节 SQL 只改 `request_uri/raw_message`，不改 `leaf_hash`。Stage 9.5 的 seal 门禁会对同一 `log_id` 的稳定业务字段计算副本记录验证 digest；只要明文字段、结构化字段、`raw_message`、`normalized_message`、`leaf_hash`、文件 offset 等任一稳定字段不一致，就会拒绝 seal。

## 11. seal 后添加大量正常日志验收

本节使用窗口：

```text
batch_id = bch_v1_tomcat-cve-2017-12615_20260422T023300Z
seal start_time = 2026-04-22T02:33:00.000Z
```

先执行本节专用 ingest：

```bash
curl -s -X POST http://127.0.0.1:8080/api/logs/ingest \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "source":"tomcat-cve-2017-12615",
    "hostname":"node1",
    "app_name":"tomcat",
    "file_path":"/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.stage95-after-seal-noise.txt",
    "records":[
      {"raw_message":"172.18.0.1 - - [22/Apr/2026:10:33:01 +0800] \"GET /stage95-after-seal-baseline HTTP/1.1\" 200 11230","file_offset":133300}
    ]
  }'
```

等待任务成功后执行 seal：

```bash
curl -s -X POST http://127.0.0.1:8080/api/batches/seal \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"source":"tomcat-cve-2017-12615","start_time":"2026-04-22T02:33:00.000Z"}'
```

预期返回 `CHAIN_COMMITTED`。

然后在 `node1` 插入大量正常外观日志：

```bash
sudo mysql -Dlogtrace_node1 \
  -e "CALL sp_tamper_insert_noise(
        'bch_v1_tomcat-cve-2017-12615_20260422T023300Z',
        50,
        '/normal-looking'
      );"
```

说明：Ubuntu 上 MySQL `root` 账号通常使用 `auth_socket` 插件，只允许本机 `sudo mysql` 登录；`mysql -uroot -p -h127.0.0.1` 会走 TCP 密码认证，容易出现 `Access denied for user 'root'@'127.0.0.1'`。

执行完整性校验：

```bash
curl -s -X POST http://127.0.0.1:8080/api/integrity/check \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T023300Z"}'
```

预期：

- `abnormal_nodes` 只能包含 `node1`
- `abnormal_nodes` 不应包含 `node2` 或 `node3`
- `differences` 包含 `BATCH_ROOT_MISMATCH`，节点为 `node1`
- 新增日志必须显示为 `EXTRA_LOG`，节点为 `node1`
- 不应出现针对 `node2/node3` 的 `MISSING_LOG`

## 12. 常用诊断命令

查看最近 20 条同步任务：

```bash
mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "SELECT task_type,target_source_node,batch_id,status,attempt_count,last_error,updated_at
      FROM replica_sync_tasks
      ORDER BY updated_at DESC
      LIMIT 20;"
```

手动重置卡住的 `IN_PROGRESS`：

```bash
mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "UPDATE replica_sync_tasks
      SET status='FAILED',
          next_retry_at=NOW(3),
          last_error='manual reset stale IN_PROGRESS',
          updated_at=NOW(3)
      WHERE status='IN_PROGRESS';"
```

立即重试失败任务：

```bash
mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "UPDATE replica_sync_tasks
      SET next_retry_at=NOW(3)
      WHERE status='FAILED';"
```

查看某个批次的本地封存状态：

```bash
mysql -u"$LOGTRACE_NODE1_JDBC_USERNAME" -p"$LOGTRACE_NODE1_JDBC_PASSWORD" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "SELECT batch_id,seal_status,chain_tx_id,chain_committed_at
      FROM log_batches
      WHERE batch_id='bch_v1_tomcat-cve-2017-12615_20260422T023000Z';"
```

如果返回 `CHAIN_COMMITTED` 且 `chain_tx_id` 非空，不要再重复 seal 该批次；继续执行账本查询和完整性校验。

## 13. 批次登记要求

每完成一次阶段验收后，把实际用过的批次同步写入仓库根目录的 `agent.md`：

- 如果使用了本手册默认窗口，登记 `02:30` 到 `02:33` 四个批次。
- 如果因为链上已存在而整体换了新窗口，登记实际使用的新批次。
- 登记内容至少包括阶段、场景、`batch_id`、状态、备注。

## 14. 答辩口径

如果老师问“node1 被攻击后 DELETE/UPDATE 会不会同步到副本”：

> 不会。Stage 9.5 不使用 MySQL 主从复制，也不从 node1 当前日志表复制。副本同步只消费 ingest 当时生成的冻结 payload，并校验 hash 和 HMAC。node1 后续修改不会改变 outbox payload，也不会被同步到 node2/node3。

如果老师问“黑客添加大量正常日志怎么办”：

> 如果添加发生在 seal 后，链上 `merkle_root` 和 `log_count` 已固定，新增日志会让 node1 的重新计算 Root 偏离链上 Root。Stage 9.5 中 seal 通过后的 node2/node3 被视为可信参考副本，因此只存在于 node1 的新增日志会被归类为 `EXTRA_LOG(node1)`，node2/node3 不会被误判为异常。如果添加发生在 seal 前并通过合法采集链路进入系统，它属于输入源可信性问题，系统通过来源限制、鉴权、确定性 log_id、offset 去重、审计和 seal 门禁降低风险，但不宣称能自动判断日志内容真假。

如果老师问“seal 前只改明文字段但不改 leaf 怎么办”：

> seal 前门禁不只看 leaf。后端会对同一 `log_id` 的稳定字段计算副本记录验证 digest，覆盖 `request_uri`、`raw_message`、`normalized_message`、`leaf_hash`、文件路径和 offset 等字段，排除 `source_node` 这类物理副本字段。node1 明文字段被改而 node2/node3 保持原样时，三库 digest 不一致，seal 会被拒绝，数据不会上链。

如果老师问“为什么不做分布式事务”：

> 本系统的可信边界是批次 seal，不是单次 ingest。日志采集要优先保证可用性，副本允许短暂落后；seal 前必须三库一致，否则不上链。这比伪装成强一致三库事务更符合实际工程边界。
