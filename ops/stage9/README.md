# 阶段9：后端真实 Fabric Gateway 与三库联调操作手册

本手册用于手工完成阶段9验收：在 `node1` 启动 Spring Boot 后端，连接三台真实 MySQL，并通过 Fabric Gateway 调用 `mychannel` 上的 `log-evidence` 链码。

执行方式：使用 Xshell 登录虚拟机，使用 Xftp 传输文件。本文不提供自动部署脚本。

## 0. 阶段边界

本阶段只做：

- 启用后端真实 Fabric Gateway 客户端。
- 后端 datasource 指向三台真实 MySQL。
- 使用 Org1 Admin 身份材料在 `node1` 连接 `peer0.org1.example.com:7051`。
- 验证注册、登录、日志入库、三库写入、批次封存、链码提交、账本查询、完整性校验。

本阶段不做：

- 不修改 OpenAPI。
- 不修改链码 ABI。
- 不修改 MySQL schema。
- 不重建 Fabric 网络、通道或 CouchDB。
- 不执行 `docker compose down -v`。
- 不接入 Vulhub/Filebeat；阶段9使用手工 HTTP 请求模拟日志进入后端。

如果任一步预期不一致，先停止并定位，不要继续下一节。

## 1. 固定参数

| 项 | 值 |
|---|---|
| 后端运行节点 | `node1` |
| 后端端口 | `8080` |
| Fabric 通道 | `mychannel` |
| 链码名 | `log-evidence` |
| 链码版本 | `1.0` |
| 链码 sequence | `1` |
| Gateway 身份 | Org1 Admin |
| MSP ID | `Org1MSP` |
| Gateway Peer | `peer0.org1.example.com:7051` |
| Override authority | `peer0.org1.example.com` |
| 测试 source | `tomcat-cve-2017-12615` |
| 测试 batch_id | `bch_v1_tomcat-cve-2017-12615_20260422T020500Z` |
| 测试 merkle_root | `36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f` |

## 2. node1 前置检查

在 `node1` 执行：

```bash
getent hosts orderer.example.com
getent hosts peer0.org1.example.com
getent hosts peer0.org2.example.com
java -version
mvn -version
```

预期：

- 三个 Fabric 域名解析到 `192.168.88.101/102/103`。
- Java 至少为 `21`。
- Maven 可用。

如果 Java 低于 `21`，不要启动后端，先安装或切换 JDK 21+。

## 3. 准备 Gateway 身份材料

只复制 Org1 Admin 身份到 `node1` 的独立 gateway 目录，不直接操作 Fabric 网络原始目录。

### 3.1 用 Xftp 复制文件

从 `node2` 下载以下目录和文件：

```text
/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/signcerts
/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore
/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
```

上传到 `node1`：

```text
/home/yangli/Documents/fabric-workspace/gateway/org1/users/Admin@org1.example.com/msp/signcerts
/home/yangli/Documents/fabric-workspace/gateway/org1/users/Admin@org1.example.com/msp/keystore
/home/yangli/Documents/fabric-workspace/gateway/org1/peer0.org1.example.com/tls/ca.crt
```

### 3.2 在 node1 检查

```bash
ls -l /home/yangli/Documents/fabric-workspace/gateway/org1/users/Admin@org1.example.com/msp/signcerts
ls -l /home/yangli/Documents/fabric-workspace/gateway/org1/users/Admin@org1.example.com/msp/keystore
ls -l /home/yangli/Documents/fabric-workspace/gateway/org1/peer0.org1.example.com/tls/ca.crt
```

预期：

- `signcerts` 目录中有 `Admin@org1.example.com-cert.pem`。
- `keystore` 目录中有且只有一个私钥文件，或第一个按文件名排序的文件就是 Admin 私钥。
- `ca.crt` 存在。

## 4. 准备后端代码与环境变量

### 4.1 上传后端代码

用 Xftp 将仓库中的 `backend/` 上传到 `node1`，建议目标目录：

```text
/home/yangli/Documents/logtrace/backend
```

不要上传旧的 `target/` 目录；在 `node1` 重新构建。

同时用 Xftp 上传本仓库的：

```text
ops/stage9/backend-stage9.env.example
```

建议上传到：

```text
/home/yangli/Documents/logtrace/backend/backend-stage9.env.example
```

### 4.2 创建环境变量文件

在 `node1`：

```bash
cd /home/yangli/Documents/logtrace/backend
cp ./backend-stage9.env.example ./backend-stage9.env
```

如果没有上传样例文件，手工创建 `backend-stage9.env`，内容参考本目录的 `backend-stage9.env.example`。

根据实际密码调整：

```bash
vim backend-stage9.env
```

加载环境变量：

```bash
set -a
source ./backend-stage9.env
set +a
```

注意：`backend-stage9.env` 中的 JDBC URL 必须带引号，因为 URL 含有 `&`。如果未加引号，Bash 会把 `characterEncoding=utf8`、`connectionTimeZone=UTC` 当成后台命令，终端会出现类似：

```text
[6]+  已完成               characterEncoding=utf8
```

出现该提示时，说明环境变量已被错误加载。请先修正 env 文件，再重新 `source ./backend-stage9.env`。

确认关键变量：

```bash
printf '%s\n' "$LOGTRACE_NODE1_JDBC_URL"
echo "$LOGTRACE_NODE1_JDBC_USERNAME"
echo "$LOGTRACE_LEDGER_MODE"
echo "$LOGTRACE_LEDGER_PEER_ENDPOINT"
echo "$LOGTRACE_LEDGER_TLS_CERT_PATH"
```

预期：

```text
jdbc:mysql://127.0.0.1:3306/logtrace_node1?useUnicode=true&characterEncoding=utf8&connectionTimeZone=UTC
logtrace_app
fabric
peer0.org1.example.com:7051
/home/yangli/Documents/fabric-workspace/gateway/org1/peer0.org1.example.com/tls/ca.crt
```

## 5. 构建并启动后端

在 `node1`：

```bash
cd /home/yangli/Documents/logtrace/backend
LOGTRACE_LEDGER_MODE=mock mvn test
mvn spring-boot:run
```

说明：`mvn test` 使用 `mock` ledger 验证后端本地回归，避免测试阶段提前连接真实 Fabric。真实 Fabric Gateway 在 `mvn spring-boot:run` 启动和后续 HTTP 联调中验收。

`mvn spring-boot:run` 必须在已经 `source ./backend-stage9.env` 的同一个 Xshell 窗口执行。若换了新窗口、重新登录或使用 `sudo`，需要重新加载环境变量，否则后端会回退到 `application.yml` 默认数据库账号。

后端启动成功后，另开一个 Xshell 窗口执行：

```bash
curl -s http://127.0.0.1:8080/swagger-ui.html >/dev/null && echo backend-up
```

预期：

```text
backend-up
```

如果启动时报 Fabric 连接失败，优先检查：

- `peer0.org1.example.com` 是否能在 `node1` 解析。
- `node2` 的 `peer0.org1.example.com` 容器是否 `Up`。
- `LOGTRACE_LEDGER_TLS_CERT_PATH` 是否是 Org1 peer TLS CA。
- `LOGTRACE_LEDGER_CLIENT_CERT_PATH` 和 `LOGTRACE_LEDGER_CLIENT_KEY_DIR` 是否存在。
- `LOGTRACE_LEDGER_OVERRIDE_AUTHORITY` 是否为 `peer0.org1.example.com`。

## 6. 注册和登录验收

在 `node1` 新窗口：

```bash
curl -s -X POST http://127.0.0.1:8080/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"Admin@123456","display_name":"Stage9 Admin"}'
```

预期返回中包含：

```json
"role":"ADMIN"
```

登录并保存 token：

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"Admin@123456"}' \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
echo "$TOKEN"
```

预期输出非空 JWT。

如果注册返回用户名已存在，可直接登录；但阶段9首次验收建议使用空库确认第一个用户为 `ADMIN`。

## 7. 手工日志入库

```bash
curl -s -X POST http://127.0.0.1:8080/api/logs/ingest \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "source":"tomcat-cve-2017-12615",
    "hostname":"node1",
    "app_name":"tomcat",
    "file_path":"/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.2026-04-22.txt",
    "records":[
      {"raw_message":"172.18.0.1 - - [22/Apr/2026:10:05:01 +0800] \"GET / HTTP/1.1\" 200 11230","file_offset":0},
      {"raw_message":"172.18.0.1 - - [22/Apr/2026:10:05:18 +0800] \"GET /docs/ HTTP/1.1\" 200 2147","file_offset":82},
      {"raw_message":"172.18.0.1 - - [22/Apr/2026:10:05:42 +0800] \"PUT /shell.jsp/ HTTP/1.1\" 201 32","file_offset":164}
    ]
  }'
```

预期：

- `accepted_count` 为 `3`。
- 三条 summary 的 `batch_id` 都是 `bch_v1_tomcat-cve-2017-12615_20260422T020500Z`。

## 8. 三库写入检查

在 `node1` 查询三台 MySQL：

```bash
mysql -h127.0.0.1 -ulogtrace_app -p -Dlogtrace_node1 -e "select source_node,count(*) from log_records where batch_id='bch_v1_tomcat-cve-2017-12615_20260422T020500Z' group by source_node;"
mysql -h192.168.88.102 -ulogtrace_app -p -Dlogtrace_node2 -e "select source_node,count(*) from log_records where batch_id='bch_v1_tomcat-cve-2017-12615_20260422T020500Z' group by source_node;"
mysql -h192.168.88.103 -ulogtrace_app -p -Dlogtrace_node3 -e "select source_node,count(*) from log_records where batch_id='bch_v1_tomcat-cve-2017-12615_20260422T020500Z' group by source_node;"
```

预期：

- node1 返回 `node1 3`。
- node2 返回 `node2 3`。
- node3 返回 `node3 3`。

## 9. 封存并上链

```bash
curl -s -X POST http://127.0.0.1:8080/api/batches/seal \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"source":"tomcat-cve-2017-12615","start_time":"2026-04-22T02:05:00.000Z"}'
```

预期返回：

```json
"batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z"
"merkle_root":"36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f"
"seal_status":"CHAIN_COMMITTED"
```

`chain_tx_id` 必须非空，且不应是 `mock_tx_` 前缀。

如果返回 `batch evidence already exists`，说明链上已有同 batch_id。阶段9重新验收时需要换一个未使用时间窗口，或清空三库并使用新链上 batch_id；不要尝试覆盖链上旧存证。

## 10. 账本查询验收

按 batch ID 查询：

```bash
curl -s http://127.0.0.1:8080/api/ledger/batches/bch_v1_tomcat-cve-2017-12615_20260422T020500Z \
  -H "Authorization: Bearer $TOKEN"
```

预期包含：

```json
"doc_type":"BatchEvidence"
"tx_id":"..."
```

按 source 查询：

```bash
curl -s "http://127.0.0.1:8080/api/ledger/batches?source=tomcat-cve-2017-12615" \
  -H "Authorization: Bearer $TOKEN"
```

Root 正确校验：

```bash
curl -s -X POST http://127.0.0.1:8080/api/ledger/batches/bch_v1_tomcat-cve-2017-12615_20260422T020500Z/verify-root \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"merkle_root":"36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f"}'
```

预期：

```json
"matched":true
```

Root 错误校验：

```bash
curl -s -X POST http://127.0.0.1:8080/api/ledger/batches/bch_v1_tomcat-cve-2017-12615_20260422T020500Z/verify-root \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"merkle_root":"0972d52b9c5a49a54287486521fc89f52a15fc1313f153daea8afd8b9cf05660"}'
```

预期：

```json
"matched":false
```

## 11. 完整性校验

```bash
curl -s -X POST http://127.0.0.1:8080/api/integrity/check \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z"}'
```

预期：

- `ledger_root` 为 `36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f`。
- `replica_roots.node1/node2/node3` 均等于链上 root。
- `abnormal_nodes` 为空。
- `differences` 为空。

## 12. CouchDB 辅助确认

在 `node2`：

```bash
curl -s -u admin:adminpw \
  -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:5984/mychannel_log-evidence/_find \
  -d '{"selector":{"doc_type":"BatchEvidence","batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z"}}'
```

在 `node3`：

```bash
curl -s -u admin:adminpw \
  -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:6984/mychannel_log-evidence/_find \
  -d '{"selector":{"doc_type":"BatchEvidence","batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z"}}'
```

预期两个节点都能查到同一批次。`No matching index found` warning 可接受。

## 13. 阶段9通过标准

全部满足才算通过：

- 后端以 `LOGTRACE_LEDGER_MODE=fabric` 启动成功。
- 注册首个用户为 `ADMIN`。
- 登录能获取 JWT。
- 手工 `/api/logs/ingest` 接收三条 Tomcat 日志。
- 三台 MySQL 的 `log_records` 均有三条记录，且 `source_node` 分别为 `node1/node2/node3`。
- `/api/batches/seal` 返回 `CHAIN_COMMITTED` 和真实 `chain_tx_id`。
- `/api/ledger/batches/{batchId}` 返回链上 `BatchEvidence`。
- `/api/ledger/batches/{batchId}/verify-root` 正确 root 返回 `matched=true`，错误 root 返回 `matched=false`。
- `/api/integrity/check` 正常批次无异常节点和差异。
- node2 与 node3 CouchDB 均可查到该批次。

## 14. 常见异常与停止点

| 异常 | 处理 |
|---|---|
| `mvn test` 在 surefire 阶段失败，且终端出现 `[n]+ 已完成 characterEncoding=utf8` | JDBC URL 未加引号导致 `source backend-stage9.env` 被 Bash 拆分。修正 env 中三条 JDBC URL 的单引号，重新 `source`，再执行 `LOGTRACE_LEDGER_MODE=mock mvn test`。 |
| 注册或登录时报 `Access denied for user 'root'@'127.0.0.1'` | 后端启动进程没有读到 `LOGTRACE_NODE1_JDBC_USERNAME=logtrace_app`。停止后端，在同一窗口重新 `source ./backend-stage9.env`，确认 `echo "$LOGTRACE_NODE1_JDBC_USERNAME"` 输出 `logtrace_app`，再启动。 |
| 后端启动失败且提示证书或私钥路径不存在 | 检查第 3 节 Xftp 上传路径和环境变量。 |
| `UNAVAILABLE` 或 `connection refused` | 检查 `node2` 的 `peer0.org1.example.com` 容器、端口 7051、hosts 解析和防火墙。 |
| `x509` 或 TLS authority 错误 | 检查 `LOGTRACE_LEDGER_TLS_CERT_PATH` 和 `LOGTRACE_LEDGER_OVERRIDE_AUTHORITY`。 |
| `access denied`、MSP、signature 相关错误 | 检查 client cert/key 是否属于 Org1 Admin，`LOGTRACE_LEDGER_MSP_ID` 是否为 `Org1MSP`。 |
| 启动时出现 `NoClassDefFoundError: com/google/protobuf/RuntimeVersion$RuntimeDomain` | 这是 protobuf 运行库版本不匹配。确认 `backend/pom.xml` 已显式引入 `com.google.protobuf:protobuf-java:4.31.1`，且 `io.grpc:grpc-netty-shaded` 与 `fabric-gateway` 都对齐到 `1.78.0`，然后在 `node1` 上重新 `mvn -U clean test` 再启动。 |
| `batch evidence already exists` | 链上已经存在该 batch_id，不能覆盖；换新时间窗口或停止对话确认清理策略。 |
| 三库写入部分成功后失败 | 记录失败信息，先不要封存；检查对应 MySQL 账号、网络和 schema。 |
| `/api/integrity/check` root 不一致 | 先确认三库 `log_id`、`timestamp`、`leaf_hash` 是否一致，再检查是否误用了旧数据。 |
