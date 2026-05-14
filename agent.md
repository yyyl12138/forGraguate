# Agent 指南

> 用途：给 AI 协作者快速建立项目上下文。优先保留事实、边界、契约和当前状态；避免重复叙述。

## 1. 项目定位

本项目是基于 Hyperledger Fabric 的网络日志存证与溯源系统，面向安全事件日志的采集、处理、存储、上链存证与后续溯源分析。

核心设计不是把完整日志写入链上，而是分层存储：

- 链下：`node1`、`node2`、`node3` 三台 MySQL 保存同一批日志明文副本，支持检索、分析、追溯和交叉校验。
- 后端：对批次日志计算叶子哈希，构建 Merkle Tree。
- 链上：仅写入 Merkle Root Hash 与批次元数据。
- Fabric 状态库：`node2`、`node3` 上 Peer 挂载的 CouchDB。

安全目标：不阻止攻击本身，而是在攻击者事后删除、修改或插入日志时，发现被篡改的批次、节点和日志记录。

## 2. 当前总状态

### 2.1 策略

Windows 11 宿主机与 VMware 三节点环境已恢复可用。项目策略已从“本地 mock 优先”切换为“真实三节点环境分层验收优先”。

推进顺序固定为：

`基础设施 -> MySQL -> Fabric/链码 -> 后端 -> Filebeat/Vulhub -> 前端 -> 演示`

要求：

- 下层验收未通过，不进入上层。
- 本地 mock ledger 与单机三 schema 保留为回归和故障隔离基线。
- 后续真实联调优先修实现、配置和部署脚本问题，不主动变更后端 OpenAPI、链码 ABI、哈希契约和 MySQL schema。

### 2.2 阶段进度

| 阶段 | 状态 | 要点 |
|---|---|---|
| 1 | 已完成 | `docs/ledger-state-model.md`、`docs/hash-batch-contract.md`、`docs/canonical-log.schema.json` 已冻结；批次 ID、Root Hash、CanonicalLog、Merkle 规则固定。 |
| 2 | 已完成 | `docs/mysql-schema.sql`、`docs/mysql-replica-strategy.md`、`docs/mysql-mock-data.sql` 已完成；三副本写入策略为 `A. 严格同步`。 |
| 3 | 已完成 | `chaincode/` Go 链码实现 `CreateBatchEvidence`、`GetBatchEvidence`、`QueryBatchEvidenceByTimeRange`、`QueryBatchEvidenceBySource`、`VerifyBatchRoot`；`go test ./...` 已通过。 |
| 4 | 已完成 | `backend/` Spring Boot 后端本地闭环完成：三数据源、MyBatis、BCrypt、JWT、refresh token、角色权限、审计、三库严格写入、批次封存、日志搜索、批次详情、账本 mock 查询、完整性校验差异定位。 |
| 4 验证 | 已完成 | 本地验证基座为 `127.0.0.1:3306` 下 `logtrace_node1`、`logtrace_node2`、`logtrace_node3`，支持环境变量覆盖；`backend` 下 `mvn test` 3 个测试全部通过；用户已启动后端并完成注册功能测试。 |
| 5 | 已完成 | `frontend/` 使用 Vue 3、Vite、TypeScript、Pinia、Vue Router、Element Plus；已实现登录、注册、数据录入、批次管理、批次详情、账本存证、日志检索、完整性校验、审计查询页面。 |
| 5 边界 | 已确认 | 前端只调用真实后端接口，不使用 mock 数据；不封装、不展示、不调用废弃的 `POST /api/demo/attack`；后端仍使用 `MockLedgerGatewayClient` 作为阶段 5 合法替代层。 |
| 6 | 已完成 | 截至 `2026-05-08`，用户已在真实环境手动完成三节点基础设施健康检查；IP、主机名解析、SSH、Docker、Docker Compose、Go、Fabric 二进制、代理绕过、`fabric_net` 均可用。 |
| 7 | 已完成 | 截至 `2026-05-08`，用户已按 `ops/stage7/` 在三节点以宿主机方式部署 MySQL，并完成数据库层验收。 |
| 8 | 已完成 | 截至 `2026-05-09`，用户已按 `ops/stage8/README.md` 在真实三节点环境完成 Fabric 网络与链码真实验收；`log-evidence` 链码已以版本 `1.0`、sequence `1` 提交到 `mychannel`；CLI 已验证创建、查询、按时间查询、按来源查询、Root 校验、重复批次拒绝和 CouchDB 状态。 |
| 9 | 已完成 | 截至 `2026-05-09`，用户已按 `ops/stage9/README.md` 完成后端真实 Fabric Gateway 与三库联调；注册、登录、日志接收、三库写入、链上查询、Root 校验、完整性校验和负向场景响应均符合预期。 |
| 9.5 | 已完成 | 截至 `2026-05-11`，阶段 9.5 已通过：完成异步副本同步、防污染 seal 门禁、副本记录验证 digest、完整性差异分类修复、Fabric Gateway 超时与诊断日志、最小回归测试和 `ops/stage9.5/README.md` 手工验收。 |
| 10 | 已完成 | 截至 `2026-05-11`，阶段 10 已通过真实三虚拟机手工验收：Vulhub Tomcat `access.log` 已挂载到 `node1` 宿主机目录，Filebeat + 本地中继可将正常 `GET /` 与攻击 `PUT /shell.jsp/` 自动送入后端，三库副本、90 秒缓冲自动 seal 与 Fabric 自动上链链路均通过。 |
| 11 | 已完成 | 截至 `2026-05-12`，阶段 11 已通过真实三虚拟机环境黑盒篡改验收：`ops/stage11/run-stage11.sh all` 已完成删除、修改、插入噪声三类场景，完整性校验均能在篡改前确认三库一致，并在篡改后定位 `node1` 与对应差异类型。 |
| 12 | 已完成 | 截至 `2026-05-14`，阶段 12 已完成：`ops/stage12/README.md`、`run-stage12-preflight.sh`、`run-normal-traffic.sh`、`run-attack-and-tamper.sh` 已固化；前端复制按钮、分钟级时间筛选、日志筛选、账本/完整性边界和 `/data-entry` 导航边界已修复；`frontend npm run build` 已通过。 |

## 3. 基础设施事实

### 3.1 Fabric 基线

- Fabric Core：`2.5.4`
- 通道：`mychannel`
- 网络结构：双组织、单 Orderer、双 Peer、双 CouchDB
- Orderer：`orderer.example.com`，`OrdererMSP`，单节点 `etcdraft`
- Org1：`peer0.org1.example.com`，`Org1MSP`，节点 `node2`
- Org2：`peer0.org2.example.com`，`Org2MSP`，节点 `node3`
- 背书策略：`OR('Org1MSP.peer','Org2MSP.peer')`
- Peer 状态库：CouchDB
- CLI 主控台：`node2`
- Fabric 工作区：`/home/yangli/Documents/fabric-workspace/network`
- `crypto-config.yaml`、`configtx.yaml`、`docker-compose.yaml` 已完成
- 通道创建、Peer 加入、Anchor Peer 设置已完成

### 3.2 三节点

- 宿主环境：Windows 11 + VMware Workstation 16 Pro
- 虚拟机：Ubuntu 24.04 × 3
- `node1`：`192.168.88.101`
  - `orderer.example.com`
  - `Vulhub`
  - `Filebeat`
  - `Spring Boot` 后端
  - 前端
  - `MySQL-node1`
  - 可作为控制节点
- `node2`：`192.168.88.102`
  - `peer0.org1.example.com`
  - `couchdb0`
  - `MySQL-node2`
  - `cli`
- `node3`：`192.168.88.103`
  - `peer0.org2.example.com`
  - `couchdb1`
  - `MySQL-node3`

### 3.3 阶段 6 已确认基线

- `node1` 可 SSH 到 `node2`、`node3`
- `orderer.example.com` -> `192.168.88.101`
- `peer0.org1.example.com` -> `192.168.88.102`
- `peer0.org2.example.com` -> `192.168.88.103`
- `NO_PROXY/no_proxy` 已覆盖三节点 IP、三节点主机名、Fabric 域名、`192.168.88.0/24`
- `docker`、`docker compose`、`go`、`peer`、`orderer`、`configtxgen`、`cryptogen` 可用
- `fabric_net` 已存在

### 3.4 阶段 7 MySQL 基线

- 三节点均以宿主机方式安装 `MySQL 8.0.45-0ubuntu0.24.04.1`
- 三台 MySQL 的 `@@time_zone` 均为 `+00:00`
- 三台 MySQL 的 `@@character_set_server` 均为 `utf8mb4`
- 三台 MySQL 的 `@@collation_server` 均为 `utf8mb4_bin`
- `logtrace_app` 最小权限账号已创建
- 已从 `node1` 通过 TCP 成功连接：
  - `127.0.0.1:3306/logtrace_node1`
  - `192.168.88.102:3306/logtrace_node2`
  - `192.168.88.103:3306/logtrace_node3`

MySQL 分工：

- `node1.logtrace_node1`：主业务库，包含 `app_users`、`user_login_audit`、`user_refresh_tokens`、`system_operation_audit`、`log_records`、`log_batches`、`replica_write_audit`，并部署 `sp_tamper_delete_by_pattern`、`sp_tamper_update_by_pattern`、`sp_tamper_insert_noise`。
- `node2.logtrace_node2`：副本库，仅包含 `log_records`、`log_batches`。
- `node3.logtrace_node3`：副本库，仅包含 `log_records`、`log_batches`。

### 3.5 阶段 8 Fabric/链码基线

截至 `2026-05-09`，阶段 8 已通过。

- 链码名：`log-evidence`
- 链码版本：`1.0`
- 链码 sequence：`1`
- 通道：`mychannel`
- 背书策略：`OR('Org1MSP.peer','Org2MSP.peer')`
- 测试批次：`bch_v1_tomcat-cve-2017-12615_20260422T020500Z`
- 测试 Root：`36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f`
- 链码函数已通过真实 CLI 验收：
  - `CreateBatchEvidence`
  - `GetBatchEvidence`
  - `QueryBatchEvidenceByTimeRange`
  - `QueryBatchEvidenceBySource`
  - `VerifyBatchRoot`
- 负向验收已通过：
  - 重复 `batch_id` 返回 `batch evidence already exists`
  - 错误 Root 校验返回成功响应且 `matched=false`
- `node2` 的 `couchdb0` 和 `node3` 的 `couchdb1` 均可查询到测试批次状态。

阶段 8 实际排障结论：

- `node2`、`node3` 曾出现 Fabric 域名 `getent hosts` 无输出，原因是本机 `/etc/hosts` 缺少 `orderer.example.com`、`peer0.org1.example.com`、`peer0.org2.example.com` 映射；补齐后继续。
- `node1` 的 Go 版本为 `1.21` 不阻断阶段 8；链码构建发生在 `node2`/`node3` 和 Fabric 构建环境侧，阶段 8 不要求同步升级 `node1`。
- 链码安装前需要 `hyperledger/fabric-ccenv:2.5` 镜像。
- Fabric 安装链码时出现 `Cannot connect to the Docker daemon at unix:///host/var/run/docker.sock` 可能是误导性包装错误；本次真实根因是链码构建容器访问 `proxy.golang.org` 被拒绝，依赖下载失败。
- 已采用 `go env -w GOPROXY=https://goproxy.cn,direct`、`go mod download`、`go mod vendor` 后重新打包链码，Fabric 构建脚本检测到 `vendor/` 后使用 `-mod=vendor`，避免构建阶段联网下载依赖。
- Org2 `approveformyorg` 曾返回 `timed out waiting for txid on all peers`；该错误不一定表示批准失败，应先用 `peer lifecycle chaincode queryapproved --channelID mychannel --name log-evidence --sequence 1` 验证是否已落账。
- CouchDB `_find` 返回目标 `docs` 的同时出现 `No matching index found` warning 可接受；阶段 8 只要求能查到批次状态，索引优化不作为门禁。

### 3.6 阶段 9 后端真实联调基线

截至 `2026-05-09`，阶段 9 已通过。用户在 `node1` 手工执行 `ops/stage9/README.md`，使用 Xshell/Xftp 上传代码和配置，后端以 `LOGTRACE_LEDGER_MODE=fabric` 连接真实 Fabric Gateway，并连接三台真实 MySQL。

阶段 9 已确认：

- `mvn test` 可通过。
- 后端真实模式可启动。
- 首个用户注册为 `ADMIN`，登录可获取 JWT。
- `/api/logs/ingest` 可接收三条 Tomcat access log，并写入 `node1/node2/node3` 三库。
- 三台 MySQL 的 `log_records` 可按固定 batch 查询到一致记录，且 `source_node` 分别为 `node1/node2/node3`。
- 固定测试批次 `bch_v1_tomcat-cve-2017-12615_20260422T020500Z` 在链上已存在，链上 Root 为 `36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f`。
- `/api/ledger/batches/{batchId}`、按 source 查询、`verify-root` 正确和错误 Root、`/api/integrity/check` 后续响应均符合阶段 9 手册预期。
- 重复封存同一 `batch_id` 时，链码通过 Fabric Gateway 返回 `batch evidence already exists`，后端能展开 Fabric details。

阶段 9 期间代码修改：

- `backend/pom.xml`：对齐 Fabric Gateway 运行时依赖，`grpc-netty-shaded` 调整为 `1.78.0`，显式引入 `protobuf-java:4.31.1`，解决 `RuntimeVersion$RuntimeDomain` 类缺失。
- `FabricLedgerGatewayClient`：实现真实 Gateway 调用，并增强 Fabric `GatewayException` / `GatewayRuntimeException` 的 status、transaction id 和 peer error details 输出。
- `DataSourceConfig`：为每个 `SqlSessionFactory` 显式注册 `com.logtrace.persistence.mapper`，解决 `node2/node3` 通过 `SqlSessionTemplate.getMapper()` 时 mapper 未注册。
- `ReplicaWriteService`：日志写入审计改为每条日志、每个节点一次写入尝试生成独立 `write_id`，避免批量 ingest 时 `replica_write_audit` 主键冲突。
- `LogRecordMapper`、`BatchMapper`、`AuditMapper`：修正 MyBatis 注解 SQL 中普通 SQL 与 `<script>` 动态 SQL 对 `<`、`>=` 的不同转义要求。
- `HashingService`、`BatchService`、`IntegrityService`：从 MySQL `JSON` 类型取回 `normalized_message` 后先反序列化再 canonical 序列化，避免数据库 JSON 格式化导致 leaf hash 误判。
- `HashingServiceTests`：补充 MySQL JSON 格式变化后 leaf hash 仍可复现的回归测试。
- `ops/stage9/README.md` 与 env 示例：补充阶段 9 手工验收、JDBC URL 引号、protobuf/gRPC 依赖错误等排障说明。

阶段 9 实际阻碍记录：

- `mvn test` 曾因 Bash `source` 未引用 JDBC URL 中的 `&` 导致环境变量被拆分；解决方式是在 env 文件中用单引号包住 JDBC URL。
- 后端注册接口曾回退到默认 `root` 账号并报 `Access denied for user 'root'@'127.0.0.1'`；原因是启动后端的 shell 未加载 `backend-stage9.env`。
- Fabric TLS CA 初始路径不存在；通过 Xftp 将 Org1 peer TLS CA 复制到 `node1` gateway 目录解决。
- Spring Boot 启动曾报 `NoClassDefFoundError: com/google/protobuf/RuntimeVersion$RuntimeDomain`；根因是 Fabric Gateway/gRPC 与 protobuf 运行库版本不匹配。
- `/api/logs/ingest` 曾报 `LogRecordMapper is not known to the MapperRegistry`；根因是多数据源下 mapper 只绑定到 `node1SqlSessionTemplate`。
- 批量 ingest 曾报 `replica_write_audit.PRIMARY` 重复；根因是整批日志复用同一 `write_id`。
- 重复执行同一 ingest 请求曾报 `log_records.PRIMARY` 重复；根因是前一次失败已留下部分 `log_records`，同一 raw log 会生成同一 `log_id`。
- 清理测试数据时误尝试删除 `node2/node3.replica_write_audit`；实际该表只存在于 `node1` 主业务库。
- `/api/batches/seal` 曾因普通注解 SQL 中保留 `&gt;=` / `&lt;` 导致 MySQL 语法错误；后续明确 `<script>` 动态 SQL 与普通注解 SQL 的转义边界。
- 封存时曾误报 `stored leaf_hash does not match normalized_message`；根因是 MySQL `JSON` 类型取回文本格式与入库前 canonical JSON 字符串不同。
- Fabric 背书失败最初只显示 `ABORTED: failed to endorse transaction`；增强后确认真实原因为链码拒绝重复 `batch_id`：`batch evidence already exists`。

## 4. 业务演示链路

### 4.1 固定场景

- 项目主题：网络日志存证与溯源
- 靶机环境：`Vulhub`
- 演示漏洞：优先使用 `tomcat/CVE-2017-12615`
- 漏洞服务：Apache Tomcat 8.5.19
- 访问端口：`8080`
- 正常请求：`GET / HTTP/1.1`
- 攻击请求：利用 Tomcat PUT 任意写文件漏洞向 Web 根目录写入 JSP 文件
- 后端技术栈：`Spring Boot`
- 链码语言：`Go`

本项目不做通用主机日志采集，也不做多源补充采集。演示阶段只采集 Vulhub 漏洞服务自身的 `access.log`。

### 4.2 目标处理链路

1. 在 `node1` 拉起 `Vulhub` 的 `tomcat/CVE-2017-12615`。
2. 正常流量脚本持续访问漏洞环境，产生稳定 `access.log`。
3. 演示时运行攻击脚本，发起利用请求并产生攻击访问日志。
4. `Filebeat` 只采集漏洞环境的 `access.log`，发送到后端。
5. `Spring Boot` 后端接收、解析、规范化并处理日志。
6. 日志明文严格写入 `node1`、`node2`、`node3` 的 MySQL。
7. 后端对批次日志计算哈希并构建 Merkle Tree。
8. 后端将 Root Hash 和批次元数据写入 Fabric 网络。
9. 链上状态最终落入 `node2`、`node3` Peer 对应的 CouchDB。
10. 校验时先通过链上 Root Hash 锁定批次，再比对三台 MySQL 中该批次日志，识别被修改节点和具体差异。

### 4.3 Vulhub 日志挂载

- 容器内 Tomcat 日志目录：`/usr/local/tomcat/logs`
- 虚拟机本地目录：`/opt/log-trace/vulhub-logs/tomcat`
- Filebeat 采集路径：`/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.*.txt`

建议将 Tomcat `AccessLogValve` 设置为尽快落盘，例如 `buffered="false"`，避免 Filebeat 采集延迟影响演示。

典型正常访问日志：

```text
172.18.0.1 - - [22/Apr/2026:10:05:01 +0800] "GET / HTTP/1.1" 200 11230
```

正常请求只用于制造可校验日志基线；攻击请求应在演示第二幕单独触发，并带有可识别 URI、User-Agent 或攻击标记，例如 `PUT /shell.jsp/ HTTP/1.1`。

## 5. 日志规范

后端归一化日志参考 `RFC 5424`。`Filebeat` 负责采集，`Spring Boot` 负责标准化与补齐字段。

标准输出字段：

- `PRI`
- `VERSION`
- `TIMESTAMP`
- `HOSTNAME`
- `APP-NAME`
- `PROCID`
- `MSGID`
- `STRUCTURED-DATA`
- `MSG`

字段映射：

- `TIMESTAMP`：日志事件时间，使用带时区的 ISO 8601。
- `HOSTNAME`：`node1` 或实际源主机名。
- `APP-NAME`：漏洞环境服务名，如 `nginx`、`apache`、`tomcat`、`mysql`。
- `PROCID`：进程号；若拿不到，使用 `-`。
- `MSGID`：事件类型，如 `WEB_ACCESS`、`WEB_ERROR`、`AUTH_FAIL`、`EXPLOIT_ATTEMPT`。
- `STRUCTURED-DATA`：结构化字段。
- `MSG`：原始日志正文或规范化摘要。

建议 `STRUCTURED-DATA` 字段：

- `source_ip`
- `source_port`
- `dest_ip`
- `dest_port`
- `container_id`
- `container_name`
- `service_name`
- `request_method`
- `request_uri`
- `status_code`
- `log_type`
- `batch_id`

## 6. 攻击与篡改模型

演示拆成两个独立阶段，不能混为一个安全边界：

1. 攻击漏洞环境
   - 攻击脚本利用 `CVE-2017-12615` 向 Tomcat 写入 JSP 文件。
   - 该动作在 Tomcat `access.log` 留下异常请求记录。
   - 攻击脚本直接作用域通常是漏洞环境容器，不应假设能直接修改宿主机 MySQL。
2. 篡改项目数据
   - 独立黑客模拟脚本在“已获得数据库最高权限”的假设下连接 `node1` MySQL。
   - 仅篡改 `node1` 的 MySQL 明文日志表。
   - `node2`、`node3` 不被篡改，作为交叉比对来源。
   - 篡改方式通过 `node1` MySQL 存储过程执行，包括删除攻击日志、修改攻击 URI、修改来源 IP、修改状态码、插入大量无关虚假日志。

结论：

- `CVE-2017-12615` 攻击脚本负责制造攻击日志。
- 黑客模拟脚本负责调用 `node1` MySQL 存储过程抹除痕迹。
- 除非额外设计容器逃逸、数据库弱口令或横向移动，否则 Tomcat 漏洞攻击不应被描述为天然获得宿主机 MySQL 修改权限。
- 攻击脚本应可配置请求方法、URL、请求头、请求体和攻击标记，便于未来切换 Vulhub 场景。
- 后端和前端均不提供修改数据库的演示篡改接口。

MySQL 篡改存储过程只部署在 `MySQL-node1`：

- `sp_tamper_delete_by_pattern`
- `sp_tamper_update_by_pattern`
- `sp_tamper_insert_noise`

能力边界：

- 按 `batch_id` 限定范围。
- 按 URI、来源 IP、HTTP 方法、User-Agent、原始日志正文等字段匹配攻击日志。
- 删除匹配日志。
- 修改匹配日志的 URI、IP、状态码、原始日志或规范化日志。
- 插入大量无关虚假日志。
- 修改日志时同步更新 `leaf_hash`，模拟攻击者具备数据库最高权限后的强篡改能力。
- 不同 Vulhub 场景通过不同匹配字段、匹配值和篡改动作复用同一组存储过程。

## 7. 完整性校验模型

演示阶段按固定批次窗口生成 Merkle Root，例如每 60 秒一个批次。

正常流程：

1. `Filebeat` 采集 Tomcat `access.log`。
2. 后端解析并同时写入三台 MySQL。
3. 后端按批次读取规范化日志，按固定规则生成叶子哈希。
4. 后端构建 Merkle Tree，得到 Root Hash。
5. 后端调用 Fabric 链码，将批次 ID 与 Root Hash 上链。

篡改后校验流程：

1. 管理员点击“账本完整性校验”。
2. 后端从 Fabric 查询批次存证记录，锁定 `batch_id`、时间窗口、Root Hash、日志数量和来源。
3. 后端分别读取 `node1`、`node2`、`node3` 的该批次日志。
4. 后端分别计算三份数据的 Root Hash。
5. 节点 Root Hash 与链上 Root Hash 不一致时，判定该节点该批次日志被篡改。
6. 后端继续比对三份数据库的 `log_id`、规范化日志、叶子哈希，定位删除、修改或插入的日志记录。

定位能力：

- 链上 Root Hash 先定位异常批次。
- 三台 MySQL 明文副本交叉比对再定位具体记录。
- 链上不保存日志明文、叶子哈希清单或 Merkle Proof。
- 被修改内容由未被篡改的 MySQL 副本提供参考，不由区块链直接恢复。
- 多数副本一致时，可作为演示阶段可信参考。
- 多个副本同时被篡改或发生分歧时，标记为多副本不一致，不能自动断言哪一份是真实日志。

数据保存要求：

- MySQL 日志表：`log_id`、`batch_id`、`raw_message`、`normalized_message`、`leaf_hash`、`source_node`
- MySQL 批次表：`batch_id`、`start_time`、`end_time`、`log_count`、`merkle_root`、`chain_tx_id`、`source_node`
- 链上最小字段：`batch_id`、`log_count`、`merkle_root`、`start_time`、`end_time`、`source`
- 后端批次校验接口返回：链上批次信息、三库 Root Hash、异常节点、差异日志列表

## 8. 证据边界

本系统能提供“完整性证明”和“篡改告警”，不是“法律结论”。

可证明：

- 某个时间窗口内的日志集合在上链后发生过删除、修改或新增。
- 哪些时间窗口的日志仍可信。
- 哪些系统日志可能被事后篡改。
- 事故调查所依赖的数据是否保持完整。
- 向监管、审计、保险或司法程序提交的日志是否具备可验证完整性。

不能宣称：

- 系统能阻止攻击。
- 系统能直接定位攻击者身份。
- 区块链存证天然产生法律上必然有效的证据。

生产系统若要提升证据效力，还需要：

- 日志采集、传输、入库、上链全流程审计记录。
- 对采集端、后端、数据库、链码调用身份做签名或身份认证。
- 可信时间源或可信时间戳。
- 系统运行状态、配置版本、操作人、交易 ID 等元数据。
- 证明上链前数据生成环境可靠、取证流程清洁、数据流转过程可追溯。

可参考叙事：类似 MGM Resorts 2023 年网络攻击事件中的大规模业务中断，企业事后需要判断日志可信窗口、篡改范围和调查数据完整性。

## 9. 链码职责

链码只负责存证和校验锚点管理，不是日志处理器或全文检索引擎。

应承担：

- 接收后端提交的日志批次存证数据。
- 将批次 ID、默克尔根、日志数量、时间范围、来源标识写入账本。
- 按批次 ID、时间范围、来源标识查询批次存证记录。
- 提供 Root 校验接口，核对某批日志摘要是否与链上记录一致。
- 保证同一批次存证记录不可被静默覆盖。
- 为后续溯源和司法取证提供可验证链上锚点。

不承担：

- 不直接存储完整明文日志。
- 不查询 MySQL 日志明文。
- 不负责三台 MySQL 明文日志比对。
- 不负责日志采集、解析、清洗、去重、分类。
- 不负责构建 Merkle Tree。
- 不负责复杂全文检索和分析。

链码开发约束：

- 使用 `Go`。
- 数据模型围绕“日志批次存证记录”，不是“单条日志全文记录”。
- 输入参数稳定、可校验、可重放。
- 写入前做基础字段校验，避免无效批次上链。
- 查询接口只查询链上批次存证记录。
- 查询接口优先支持：
  - 按 `batch_id` 查询链上 Root Hash、日志数量、时间范围、来源服务、交易 ID。
  - 按时间范围查询多个批次的链上存证摘要。
  - 按来源系统或服务查询对应批次的链上存证摘要。
- 校验接口接收后端对某一节点 MySQL 重新计算出的 Root Hash，并与链上 Root Hash 比对。
- 若使用 CouchDB 富查询，链码 JSON 字段命名必须稳定且语义明确。

## 10. 后端接口契约

后端负责正常业务链路和完整性校验，不提供直接修改数据库的演示篡改接口。

阶段 4 已在 `docs/openapi.yaml` 和 `backend/` Controller 中固定主要接口：

- `POST /api/auth/register`：用户注册，只写 `node1`
- `POST /api/auth/login`：用户登录，成功和失败均记录登录审计
- `POST /api/auth/refresh`：刷新访问令牌，数据库只保存 refresh token 摘要
- `POST /api/auth/logout`：撤销 refresh token
- `GET /api/auth/me`：查询当前用户
- `POST /api/logs/ingest`：接收 Filebeat 或中间转发器提交的日志
- `GET /api/logs/search`：按 `log_id`、`batch_id`、`source_ip`、`request_uri`、`request_method`、`status_code`、`msgid`、时间范围、关键字检索日志，默认查询 `node1`
- `POST /api/batches/seal`：对指定时间窗口生成批次、写入三台 MySQL、计算 Root Hash 并上链
- `GET /api/batches`：查询批次列表
- `GET /api/batches/{batchId}`：查询批次信息，包括 MySQL 批次记录和链上存证摘要
- `POST /api/integrity/check`：根据 `batch_id` 执行链上 Root Hash 校验和三库明文比对
- `GET /api/ledger/batches`：查询链上批次摘要
- `GET /api/ledger/batches/{batchId}`：按批次 ID 查询链上存证
- `POST /api/ledger/batches/{batchId}/verify-root`：校验候选 Root 是否匹配链上 Root
- `GET /api/audits/operations`：查询系统操作审计
- `GET /api/audits/logins`：查询登录审计

接口要求：

- 攻击接口不能写死 Tomcat 场景，应通过配置描述漏洞环境 URL、HTTP 方法、请求头、请求体和攻击标记。
- 数据库毁痕由独立黑客模拟脚本调用 `node1` MySQL 存储过程完成，不经过后端 API。
- 校验接口返回 `batch_id`、链上 Root Hash、三库 Root Hash、异常节点、差异日志和判断依据。

## 11. 存储与目录

### 11.1 存储分工

- `MySQL-node1`：项目实际运行节点上的日志明文副本；演示中模拟黑客仅篡改该数据库。
- `MySQL-node2`：日志明文副本，用于跨节点比对。
- `MySQL-node3`：日志明文副本，用于跨节点比对。
- `Fabric + CouchDB`：批次 Root Hash、时间戳、批次标识、日志数量、来源标识等存证数据。

原则：

- 链下三节点保存日志明文副本。
- 用户、审计、写入诊断和演示篡改能力只存在于 `node1` 主业务库。
- 链上只保存防篡改校验和批次级溯源证明的最小必要数据。
- 校验时先用链上 Root Hash 锁定异常批次，再用三台 MySQL 副本比对锁定具体差异。

### 11.2 目录约定

虚拟机 `fabric-workspace`：

- `config/`：通道与组织配置
- `network/crypto-config.yaml`：证书生成拓扑
- `network/crypto-config/`：证书与私钥
- `network/channel-artifacts/`：创世区块、通道交易、Anchor 交易等
- `network/docker/docker-compose.yaml`：容器编排
- `network/scripts/`：网络部署与运维脚本

当前仓库：

- `chaincode/`：链码源码与单元测试
- `docs/`：接口、流程、部署说明与阶段契约
- `backend/`：Spring Boot 后端
- `frontend/`：前端
- `ops/`：分阶段运维与验收材料

## 12. 当前开发重点

阶段 12 已于 `2026-05-14` 由用户确认完成。真实三节点链路、阶段 11 黑盒篡改验收、阶段 12 前端真实演示验收与演示材料固化均已完成。阶段 12 操作材料位于 `ops/stage12/`，并拆分为持续正常流量脚本与一次性攻击/篡改脚本。

### 12.1 阶段 9.5 已完成的主要改造

截至 `2026-05-11`，阶段 9.5 已完成并通过真实三节点手工验收，主要改造为：

- `node1` 主写：`/api/logs/ingest` 只要 `node1` 本地事务成功即可返回。
- 冻结 outbox：`node1.replica_sync_tasks` 保存同步到 `node2/node3` 的冻结 payload、payload hash 和 HMAC signature。
- 异步副本：后台任务只消费冻结 payload 追加写 `node2/node3`，不从 `node1.log_records` 当前状态复制，避免 `node1` 后续 `DELETE/UPDATE` 被传播到副本。
- seal 门禁：`/api/batches/seal` 会先 drain 当前批次同步任务，再检查三库日志集合、日志数量、`log_id`、`leaf_hash` 和副本记录验证 digest；任一稳定字段不一致则拒绝上链。
- 重复批次处理：当 Fabric 链上已有相同 `batch_id` 且 Root/日志数一致时，后端可复用链上 evidence 完成本地状态收尾；若不一致仍拒绝。
- node2/node3 离线处理：已降低 Hikari 连接超时，并增加 stale `IN_PROGRESS` 任务重置，避免 seal 长时间无响应。
- Fabric Gateway 超时与诊断：Fabric evaluate/endorse/submit/commit status 已设置 deadline，seal 流程增加关键步骤日志，避免长时间无提示等待。
- 完整性分类：seal 通过后 `node2/node3` 作为可信参考副本；只存在于 `node1` 的新增日志归类为 `EXTRA_LOG(node1)`，不会误把 `node2/node3` 列入异常节点。
- 操作手册：新增 `ops/stage9.5/README.md`，按 Xshell/Xftp 手动操作流程给出独立批次、ingest、seal、故障注入和完整性校验命令。

### 12.2 阶段 9.5 验收结论

阶段 9.5 已通过，已确认：

- 正常链路可完成 ingest、异步副本同步、seal、Fabric 上链和完整性校验。
- seal 前只修改 `node1` 明文字段但不改 leaf 时，副本记录 digest 不一致，seal 会拒绝上链。
- seal 后向 `node1` 插入正常外观日志时，完整性校验只标记 `node1` 异常，新增日志归类为 `EXTRA_LOG`，`node2/node3` 不被误判。
- 本地后端 `mvn test` 通过，当前为 10 个测试，覆盖 seal 门禁、digest 漏检、`EXTRA_LOG`、`MISSING_LOG`、`MODIFIED_LOG` 分类。
- 手册已补充 MySQL 重跑清理、批次登记、root 使用 `sudo mysql` 调用毁痕存储过程、seal 重复提交导致 `MVCC_READ_CONFLICT` 的处理说明。

### 12.3 阶段 10 真实环境验收与排错记录

截至 `2026-05-11`，阶段 10 已在真实三虚拟机环境通过。验收与排错中实际落地的关键调整为：

- `backend/src/main/java/com/logtrace/persistence/mapper/BatchMapper.java`：`listUnsealedWindows` 查询改为兼容 MySQL `ONLY_FULL_GROUP_BY` 的聚合写法，避免 auto-seal 定时任务在真实 MySQL 上报 `BadSqlGrammarException`。
- MySQL 清理：已从三台数据库删除两个确认“未上链”的历史脏批次 `bch_v1_tomcat-cve-2017-12615_20260422T022200Z`、`bch_v1_tomcat-cve-2017-12615_20260422T023200Z`，同时清理 `node1.replica_sync_tasks` 与 `node1.replica_write_audit` 中对应记录，避免 auto-seal 反复重试旧窗口。
- Vulhub `docker-compose.yml`：将 Tomcat 日志卷挂载从相对目录 `./tomcat_log` 调整为宿主机固定目录 `/opt/log-trace/vulhub-logs/tomcat`，并保留宿主机端口映射 `18080:8080`，避免与后端 `8080` 冲突。
- `filebeat.yml`：在 `filestream` input 下新增 `prospector.scanner.fingerprint.length: 64`，使小文件 access log 能更早进入采集；同时将 `output.file.permissions` 调整为 `0644`，解决 `log-relay.service` 以 `yangli` 用户运行时无法读取 spool 文件的问题。
- 真实环境根因确认：宿主机 `/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.*.txt` 已能实时看到 `2026-05-11` 的 `GET /`、`PUT /shell.jsp/`；排除系统时间问题后，最终定位为 Filebeat spool 权限与日志挂载路径不一致导致阶段 10 初次联调未入库。

### 12.4 阶段 11 黑盒篡改验收记录

截至 `2026-05-12`，阶段 11 已通过。验收报告位于 `ops/stage11/reports/stage11-20260512-225850.md`，脚本为 `ops/stage11/run-stage11.sh`，执行模式为 `all`。

- 删除攻击日志场景通过：批次 `bch_v1_tomcat-cve-2017-12615_20260512T145900Z`，攻击日志 `log_v1_fade232869c2cb24cf3760048d4263b4`；篡改前 `abnormal_nodes=[]`、`differences=[]`，篡改后定位 `node1`，差异包含 `BATCH_ROOT_MISMATCH` 与 `MISSING_LOG`。
- 修改攻击 URI 场景通过：批次 `bch_v1_tomcat-cve-2017-12615_20260512T150200Z`，攻击日志 `log_v1_69b1adf21394c3f1e8d592a3a6f5dc70`；篡改前干净，篡改后定位 `node1`，差异包含 `BATCH_ROOT_MISMATCH` 与 `MODIFIED_LOG`。
- 插入噪声日志场景通过：批次 `bch_v1_tomcat-cve-2017-12615_20260512T150500Z`，攻击日志 `log_v1_d983540ef1734e644025bb45b04f7606`；`node1` 插入噪声 20 条、`node2/node3` 为 0，篡改后定位 `node1`，差异包含 `BATCH_ROOT_MISMATCH` 与 `EXTRA_LOG`。
- 运行期排错结论：若 `log-relay.service` 返回 403，应优先核对 relay token 与后端 internal ingest secret；手工测试 internal ingest 返回 202 后，可以继续执行阶段 11 脚本。Tomcat 当天 access log 可能需要 `sudo` 才能读取。

### 12.5 阶段 12 完成记录

- `ops/stage12/README.md` 已更新为最终演示手册：覆盖真实链路启动、前端启动、持续正常流量、攻击并篡改、浏览器逐页验收和答辩截图清单。
- `ops/stage12/run-normal-traffic.sh` 已固化为持续正常流量脚本：随机 URI、查询参数、User-Agent、间隔和请求组合；随机 IP 仅作为请求头模拟，不改变 Tomcat access log 行首 IP 解析边界。
- `ops/stage12/run-attack-and-tamper.sh` 已固化为一次性攻击并篡改脚本：触发 `PUT /shell.jsp/`，等待至少 60 秒且批次达到 `CHAIN_COMMITTED` 后，再按 `missing`、`modified` 或 `extra` 调用 node1 MySQL 的 `sp_tamper_*` 存储过程。
- 前端修复已完成：复制按钮支持 Clipboard API 失败后的 textarea 回退；批次、账本、日志、审计页面支持分钟级时间选择和快捷按钮；`/logs` 的方法、状态码、MsgID 改为友好选项；`/ledger` 明确只负责链上存证查询，数据库完整性检测跳转 `/integrity`；`/data-entry` 保留路由但从主导航隐藏。
- 本地验证：`frontend` 下 `npm run build` 已通过。Windows 本地无可用 Bash/WSL 发行版，`bash -n` 语法检查需在 `node1` Ubuntu 执行；三个阶段 12 shell 脚本已确认使用 LF 行尾。
- 阶段 12 具体新实时 `batch_id` 未在当前文档中登记；后续如需重跑或补交材料，应使用新的 UTC 分钟窗口并补充登记。

后续任务清单：

1. 整理答辩材料：阶段 10/11/12 截图、日志样本、Fabric 查询记录、完整性校验结果和脚本输出摘要。
2. 如需重跑阶段 11 或阶段 12，必须使用新的分钟窗口，避免复用已登记的真实上链批次。

## 13. Agent 工作准则

- 先读现有配置和目录，再改动。
- 不随意修改已生成的证书、区块、MSP 或现有网络拓扑。
- 仅修改与当前任务直接相关的文件。
- 涉及链路设计时，明确区分链下数据与链上数据。
- 涉及日志字段时，优先保证可追溯性、一致性和可校验性。
- 生成脚本、配置、链码或后端代码后，附带可执行验证步骤。
- 若关键业务规则未定义清楚，先提问，不自行发明结论。

## 14. 敏感点与风险

- `node1` 同时承载 `Orderer` 与 `Vulhub`，需提前检查资源竞争和端口冲突。
- `Filebeat` 到后端的传输格式需先统一，避免反复改解析逻辑。
- 三台 MySQL 写入必须保持同一 `log_id`、`batch_id`、`leaf_hash`，否则跨库比对失效。
- Merkle Tree 构建规则必须固定：单条日志哈希算法、字段拼接顺序、批次划分方式、空节点补齐策略。
- MySQL 明文数据与链上批次存证记录必须稳定关联，不能只存 Root Hash 而缺少 `batch_id`、时间范围和来源。
- MySQL 毁痕存储过程只应存在于演示数据库或演示 schema，避免误用于正常数据。
- 代理、TLS、多机通信、容器挂载路径仍是基础设施敏感项。
- 背书策略为 `OR`，可信叙事弱于多组织共同背书；论文中需说明该策略边界。
- Fabric 链码安装阶段如果报 Docker daemon 连接失败，需先查 peer 日志中的真实 `docker build` 错误；本项目已确认过一次根因是 Go 依赖下载被拒绝，应优先检查 `vendor/` 是否随链码包重新打入。
- 阶段 9.5 已收口敏感点：seal 门禁已使用统一副本记录验证 digest 覆盖完整稳定字段，避免“普通明文字段被改但 leaf 未变”的漏检风险。
- 阶段 9.5 已收口敏感点：完整性校验已以 seal 后可信的 `node2/node3` 为参考副本，`node1` 新增日志归类为 `EXTRA_LOG`，不再误判可信副本。

## 15. 维护要求

如果项目目标、节点职责、采集链路、存储策略或目录结构变化，必须同步更新本文件。`agent.md` 应始终作为新协作者进入项目时的第一份说明。

## 16. 已用批次登记

用途：记录真实环境手工验收中已经使用过的 `batch_id`，避免后续重复 seal 时遇到链码预期拒绝 `batch evidence already exists`。每完成一个阶段或一组手工验收后，都应同步更新本节。

链上清理原则：

- Fabric 链码不提供单条删除批次能力，同一 `batch_id` 不可被静默覆盖。
- MySQL 测试数据可以按 `batch_id` 删除；链上旧批次默认保留。
- 避免重复批次的常规做法是使用新的 60 秒窗口，并在本节登记。
- 若必须清理链上状态，只能重置 Fabric 账本/容器卷并重做阶段 8、阶段 9；这会破坏当前验收基线，默认不建议。

| 阶段 | 场景 | batch_id | 状态 | 备注 |
|---|---|---|---|---|
| 8/9 | 固定 Fabric/后端联调批次 | `bch_v1_tomcat-cve-2017-12615_20260422T020500Z` | 已使用，链上已存在 | Root 为 `36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f`。 |
| 9.5 旧手册 | 正常链路 | `bch_v1_tomcat-cve-2017-12615_20260422T021000Z` | 已执行过，可能链上已存在 | 用户已按修改前 `ops/stage9.5/README.md` 完整执行过一次；重跑前可清 MySQL，但链上批次保留。 |
| 9.5 旧手册 | node2 离线 | `bch_v1_tomcat-cve-2017-12615_20260422T021100Z` | 已执行过，可能链上已存在 | 同上。 |
| 9.5 旧手册 | seal 前篡改 | `bch_v1_tomcat-cve-2017-12615_20260422T021200Z` | 已执行过，可能链上已存在 | 该场景预期 seal 拒绝；若未成功上链，链上可能不存在。 |
| 9.5 旧手册 | seal 后插入日志 | `bch_v1_tomcat-cve-2017-12615_20260422T021300Z` | 已执行过，可能链上已存在 | 同上；用于完整性校验噪声插入。 |
| 9.5 当前手册 | 正常链路 | `bch_v1_tomcat-cve-2017-12615_20260422T023000Z` | 已通过，链上已存在 | 首次 seal 长时间等待后完成本地收尾；重复 seal 曾触发 Fabric `MVCC_READ_CONFLICT`，后续按 `CHAIN_COMMITTED` 处理。 |
| 9.5 当前手册 | node2 离线 | `bch_v1_tomcat-cve-2017-12615_20260422T023100Z` | 未执行/非门禁 | 诊断与回归参考场景，不影响阶段 9.5 通过结论。 |
| 9.5 当前手册 | seal 前篡改 | `bch_v1_tomcat-cve-2017-12615_20260422T023200Z` | 已通过，seal 拒绝 | 副本记录 digest 不一致，链上不应新增该批次。 |
| 9.5 当前手册 | seal 后插入日志 | `bch_v1_tomcat-cve-2017-12615_20260422T023300Z` | 已通过，链上已存在 | `sudo mysql` 调用 `sp_tamper_insert_noise` 插入噪声后，完整性校验只标记 `node1` 的 `EXTRA_LOG`。 |
| 11 | 删除攻击日志 | `bch_v1_tomcat-cve-2017-12615_20260512T145900Z` | 已通过，链上已存在 | `ops/stage11/run-stage11.sh all` 生成；攻击日志 `log_v1_fade232869c2cb24cf3760048d4263b4`，篡改后定位 `node1`，差异为 `BATCH_ROOT_MISMATCH` + `MISSING_LOG`。 |
| 11 | 修改攻击 URI | `bch_v1_tomcat-cve-2017-12615_20260512T150200Z` | 已通过，链上已存在 | 攻击日志 `log_v1_69b1adf21394c3f1e8d592a3a6f5dc70`，篡改后定位 `node1`，差异为 `BATCH_ROOT_MISMATCH` + `MODIFIED_LOG`。 |
| 11 | 插入噪声日志 | `bch_v1_tomcat-cve-2017-12615_20260512T150500Z` | 已通过，链上已存在 | 攻击日志 `log_v1_d983540ef1734e644025bb45b04f7606`，`node1` 插入噪声 20 条、`node2/node3` 为 0，差异为 `BATCH_ROOT_MISMATCH` + `EXTRA_LOG`。 |
