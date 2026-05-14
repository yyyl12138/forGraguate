# Stage 11 VM 一键启动与篡改完整性验收手册

本手册用于在真实三虚拟机环境中使用新增文件完成两件事：

- 启动真实后端链路：Fabric、Vulhub Tomcat、已部署的 Filebeat、已部署的中继 relay、Spring Boot 后端。
- 执行阶段 11 黑盒验收：生成真实攻击批次后，只通过 `node1` MySQL 存储过程模拟毁痕，再用完整性校验观察 `MISSING_LOG`、`MODIFIED_LOG`、`EXTRA_LOG`。

宿主机中的 `backend/src/main/resources/application-vm.yml` 上传到虚拟机后文件名为 `backend/src/main/resources/application.yml`，替换虚拟机内原配置。虚拟机后端启动时不再额外指定 Spring profile。

## 1. 新增文件

| 文件 | 用途 |
|---|---|
| `backend/src/main/resources/application-vm.yml` | 宿主机侧真实环境配置；上传到虚拟机后改名/覆盖为 `backend/src/main/resources/application.yml`。 |
| `ops/vm-runtime.env.example` | node1 运行时环境变量模板，真实密码、令牌和路径都在这里填。 |
| `ops/start-vm-stack.sh` | 一键启动 Fabric、Vulhub、Filebeat、relay 和后端，并打印排错信息。 |
| `ops/stage11/run-stage11.sh` | 阶段 11 独立验收脚本，支持 `missing`、`modified`、`extra`、`all`。 |
| `ops/stage10/filebeat.yml.example` | 仅作参考；你已完整执行 Stage 10 手册，虚拟机中 `filebeat.yml` 已部署，启动脚本不会覆盖它。 |

## 2. 上传项目

在 Windows 使用 Xftp 将项目上传到 `node1`，推荐目录：

```text
/home/yangli/Documents/logtrace
```

至少需要包含：

```text
backend/
docs/
ops/
```

如果你只上传增量文件，必须确认以下文件已经在 `node1` 上存在：

```text
/home/yangli/Documents/logtrace/backend/src/main/resources/application.yml
/home/yangli/Documents/logtrace/ops/vm-runtime.env.example
/home/yangli/Documents/logtrace/ops/start-vm-stack.sh
/home/yangli/Documents/logtrace/ops/stage10/filebeat.yml.example
/home/yangli/Documents/logtrace/ops/stage10/log-relay.py
/home/yangli/Documents/logtrace/ops/stage11/run-stage11.sh
```

## 3. 填写运行时配置

在 `node1` 执行：

```bash
cd /home/yangli/Documents/logtrace
cp ops/vm-runtime.env.example ops/vm-runtime.env
vim ops/vm-runtime.env
```

必须替换所有 `CHANGE_ME_*`：

```bash
LOGTRACE_NODE1_JDBC_PASSWORD=...
LOGTRACE_NODE2_JDBC_PASSWORD=...
LOGTRACE_NODE3_JDBC_PASSWORD=...
LOGTRACE_JWT_SECRET=...
LOGTRACE_INTERNAL_INGEST_SHARED_TOKEN=...
LOGTRACE_REPLICA_SYNC_SECRET=...
LOGTRACE_RELAY_SHARED_TOKEN=...
```

要求：

- `LOGTRACE_INTERNAL_INGEST_SHARED_TOKEN` 和 `LOGTRACE_RELAY_SHARED_TOKEN` 必须一致。
- `LOGTRACE_JWT_SECRET` 至少 32 字节。
- JDBC URL 保持单引号包裹，因为其中包含 `&`。
- 如果虚拟机路径不同，只改 `ops/vm-runtime.env`，不要改脚本。

Filebeat 默认按以下顺序自动探测：

```text
LOGTRACE_FILEBEAT_BIN
/usr/local/filebeat/filebeat
/usr/local/filebeat-*/filebeat
command -v filebeat
```

你已说明 Filebeat 在 `/usr/local`，因此通常只需要保持：

```bash
LOGTRACE_FILEBEAT_BIN=/usr/local/filebeat/filebeat
```

如果真实二进制不是这个路径，改成实际路径。

## 4. 一键启动真实链路

在 `node1` 执行：

```bash
cd /home/yangli/Documents/logtrace
chmod +x ops/start-vm-stack.sh ops/stage11/run-stage11.sh
bash ops/start-vm-stack.sh
```

脚本会按顺序执行：

1. 读取 `ops/vm-runtime.env`。
2. 创建运行目录：
   - `/opt/log-trace/vulhub-logs/tomcat`
   - `/var/spool/logtrace-stage10`
   - `/var/lib/logtrace-stage10`
   - `/var/log/logtrace`
   - `/var/run/logtrace`
3. 检查 Java、Maven、Docker、Docker Compose、MySQL client、Fabric 证书、三个 MySQL、Vulhub 目录和 Filebeat。
4. 启动 Fabric 容器：`node1` 只启动 `orderer.example.com`，通过 SSH 到 `node2` 启动 `couchdb0 peer0.org1.example.com cli`，通过 SSH 到 `node3` 启动 `couchdb1 peer0.org2.example.com`。
5. 启动 Vulhub Tomcat compose。
6. 检查已部署的 Filebeat 配置，不覆盖 `filebeat.yml`。
7. 检查已部署的 `log-relay.service`，不重写 relay env 或 systemd service。
8. 使用虚拟机中的 `backend/src/main/resources/application.yml` 启动后端：

```bash
mvn spring-boot:run
```

9. 等待 `http://127.0.0.1:8080/swagger-ui.html` 可访问。
10. 重启 Filebeat 和 relay。

成功时会看到类似信息：

```text
backend-up: http://127.0.0.1:8080
backend pid: <pid>
backend log: /var/log/logtrace/backend.log
tomcat url: http://127.0.0.1:18080
filebeat: /usr/local/...
Next: run bash /home/yangli/Documents/logtrace/ops/stage11/run-stage11.sh all
```

## 5. 快速确认 Stage 10 链路

一键启动后先做最小确认：

```bash
curl -s http://127.0.0.1:8080/swagger-ui.html >/dev/null && echo backend-up
curl -i http://127.0.0.1:18080/
sudo systemctl is-active filebeat
sudo systemctl is-active log-relay.service
ls -lh /var/spool/logtrace-stage10
tail -n 20 /opt/log-trace/vulhub-logs/tomcat/localhost_access_log.*.txt
```

预期：

```text
backend-up
active
active
```

`tail` 中应能看到 Tomcat access log。若 Filebeat spool 暂时为空，先访问几次 Tomcat：

```bash
for i in 1 2 3; do curl -s http://127.0.0.1:18080/ >/dev/null; sleep 1; done
```

然后再次查看 `/var/spool/logtrace-stage10`。

## 6. 执行 Stage 11 独立验收

在 `node1` 执行全部三类场景：

```bash
cd /home/yangli/Documents/logtrace
bash ops/stage11/run-stage11.sh all
```

也可以单独执行：

```bash
bash ops/stage11/run-stage11.sh missing
bash ops/stage11/run-stage11.sh modified
bash ops/stage11/run-stage11.sh extra
```

脚本行为：

- 每个场景等待进入新的 UTC 分钟窗口。
- 触发正常流量 `GET /`。
- 触发攻击流量 `PUT /shell.jsp/`。
- 先等待攻击日志进入 `node1.log_records`；如果 90 秒内未入库，脚本会打印 Tomcat、Filebeat、relay、spool、dead-letter 和后端日志诊断，而不是继续空等上链。
- 等待后端自动 seal 到 `CHAIN_COMMITTED`。
- 篡改前先调用 `/api/integrity/check`，确保批次是干净的。
- 只通过 `node1` MySQL 存储过程篡改：
  - `missing`：调用 `sp_tamper_delete_by_pattern` 删除攻击日志。
  - `modified`：调用 `sp_tamper_update_by_pattern` 修改攻击 URI。
  - `extra`：调用 `sp_tamper_insert_noise` 插入噪声日志。
- 篡改后再次调用 `/api/integrity/check`。
- 将报告写入：

```text
ops/stage11/reports/stage11-<timestamp>.md
```

## 7. 验收通过标准

`missing` 场景预期：

```text
SCENARIO_RESULT missing PASS
```

完整性结果应包含：

```text
abnormal_nodes = ["node1"]
difference type includes MISSING_LOG
difference type includes BATCH_ROOT_MISMATCH
```

`modified` 场景预期：

```text
SCENARIO_RESULT modified PASS
```

完整性结果应包含：

```text
abnormal_nodes = ["node1"]
difference type includes MODIFIED_LOG
difference type includes BATCH_ROOT_MISMATCH
```

`extra` 场景预期：

```text
SCENARIO_RESULT extra PASS
```

完整性结果应包含：

```text
abnormal_nodes = ["node1"]
difference type includes EXTRA_LOG
difference type includes BATCH_ROOT_MISMATCH
```

验收结束后，把报告中的实际 `batch_id` 登记到根目录 `agent.md` 的“已用批次登记”，避免后续重复使用同一链上批次。

## 8. 常用排错入口

后端日志：

```bash
tail -n 120 /var/log/logtrace/backend.log
cat /var/run/logtrace/backend.pid
```

Filebeat：

```bash
sudo systemctl status filebeat --no-pager
source ops/vm-runtime.env
sudo "$LOGTRACE_FILEBEAT_BIN" test config -c "$LOGTRACE_FILEBEAT_CONFIG"
ls -lh /var/spool/logtrace-stage10
```

如果 Filebeat 实际路径不是 `/usr/local/filebeat/filebeat`，使用：

```bash
grep '^LOGTRACE_FILEBEAT_BIN=' ops/vm-runtime.env
```

relay：

```bash
sudo systemctl status log-relay.service --no-pager
journalctl -u log-relay.service -n 80 --no-pager
cat /home/yangli/Documents/logtrace/ops/stage10/relay.env
tail -n 50 /var/lib/logtrace-stage10/dead-letter.ndjson
```

Tomcat access log：

```bash
curl -i http://127.0.0.1:18080/
tail -n 50 /opt/log-trace/vulhub-logs/tomcat/localhost_access_log.*.txt
```

最近批次：

```bash
source ops/vm-runtime.env
MYSQL_PWD="$LOGTRACE_NODE1_JDBC_PASSWORD" mysql -h127.0.0.1 -u"$LOGTRACE_NODE1_JDBC_USERNAME" -Dlogtrace_node1 \
  -e "SELECT batch_id, source, log_count, seal_status, chain_tx_id
      FROM log_batches
      ORDER BY start_time DESC
      LIMIT 10;"
```

最近入库日志：

```bash
source ops/vm-runtime.env
MYSQL_PWD="$LOGTRACE_NODE1_JDBC_PASSWORD" mysql -h127.0.0.1 -u"$LOGTRACE_NODE1_JDBC_USERNAME" -Dlogtrace_node1 \
  -e "SELECT batch_id, request_method, request_uri, event_time, inserted_at
      FROM log_records
      WHERE source='tomcat-cve-2017-12615'
      ORDER BY inserted_at DESC
      LIMIT 20;"
```

三库攻击日志对比：

```bash
source ops/vm-runtime.env
MYSQL_PWD="$LOGTRACE_NODE1_JDBC_PASSWORD" mysql -h127.0.0.1 -u"$LOGTRACE_NODE1_JDBC_USERNAME" -Dlogtrace_node1 \
  -e "SELECT batch_id, log_id, request_method, request_uri, source_node
      FROM log_records
      WHERE source='tomcat-cve-2017-12615'
      ORDER BY event_time DESC
      LIMIT 10;"
```

## 9. 注意事项

- 不要用后端或前端提供篡改入口；阶段 11 模拟的是攻击者已拿到 `node1` MySQL 高权限后的事后毁痕。
- 不要执行 `docker compose down -v`，避免破坏 Fabric ledger 和 CouchDB 状态。
- 不要在 `node1` 启动完整 Fabric compose；`node1` 只承载 Orderer，否则可能和远端 peer 暴露端口产生 `7051 already allocated` 一类冲突。
- 不要让启动脚本覆盖 Filebeat 或 relay 配置；Stage 10 手册已经部署完成，脚本只做检查和启动。
- 如果 `ops/start-vm-stack.sh` 报 `CHANGE_ME`，先补完 `ops/vm-runtime.env`，不要绕过检查。
- 如果阶段 11 篡改前完整性校验已经异常，停止当前场景，换新分钟窗口重新生成批次。
- 如果 `run-stage11.sh all` 时间较长，这是正常的；每个场景都要等待“分钟窗口结束 + 90 秒缓冲 + 自动上链”。
- 如果 `sudo mysql -Dlogtrace_node1` 不能免密调用存储过程，在 `ops/vm-runtime.env` 中覆盖 `LOGTRACE_STAGE11_TAMPER_MYSQL_CLI`，例如 `mysql -uroot -p -Dlogtrace_node1`。
