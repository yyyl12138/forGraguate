# 阶段12：前端真实演示验收手册

本手册用于在真实三虚拟机环境中完成最终前端演示验收：

- 浏览器完成登录、批次管理、批次详情、账本存证、日志检索、完整性校验和审计查询。
- 正常流量与攻击/篡改流量拆成两个脚本，便于答辩时先展示“稳定业务流量”，再展示“攻击后毁痕被发现”。
- 默认演示数据使用本阶段新生成的实时批次，不复用阶段 11 旧批次。阶段 11 批次只作为故障时备用样本。

## 1. 阶段边界

本阶段做：

- 从前端消费真实后端 API，不使用 mock 数据。
- 使用 `run-normal-traffic.sh` 长期产生正常 Tomcat 访问日志。
- 使用 `run-attack-and-tamper.sh` 触发 `PUT /shell.jsp/`，等待批次上链后调用 node1 MySQL 存储过程篡改。
- 用浏览器验收新批次的链上存证、日志检索、三库重算 Root 和审计记录。

本阶段不做：

- 不新增前端篡改入口。
- 不修改 OpenAPI、链码 ABI、MySQL schema 或哈希契约。
- 不让前端直连 Fabric 或 MySQL。
- 不把候选 Root 校验当作数据库完整性校验。

## 2. 固定参数

| 项 | 值 |
|---|---|
| 后端 | `http://127.0.0.1:8080` |
| 前端 dev server | `http://192.168.88.101:5173` |
| Vulhub Tomcat | `http://127.0.0.1:18080` |
| source | `tomcat-cve-2017-12615` |
| 自动 seal 缓冲 | `90` 秒 |
| 前端 API 访问方式 | Vite `/api` 代理到 `127.0.0.1:8080` |
| 默认演示账号 | `admin` / `Admin@123456` |

## 3. 上传文件

在 Windows 使用 Xftp 将项目上传到 `node1`：

```text
/home/yangli/Documents/logtrace
```

至少包含：

```text
backend/
frontend/
docs/
ops/
```

确认阶段 12 文件存在：

```bash
cd /home/yangli/Documents/logtrace
ls -l ops/stage12
bash -n ops/stage12/run-stage12-preflight.sh ops/stage12/run-normal-traffic.sh ops/stage12/run-attack-and-tamper.sh
```

预期包含：

```text
README.md
run-stage12-preflight.sh
run-normal-traffic.sh
run-attack-and-tamper.sh
```

## 4. 启动真实链路

按阶段 11 的方式启动真实后端链路：

```bash
cd /home/yangli/Documents/logtrace
chmod +x ops/start-vm-stack.sh ops/stage12/*.sh
bash ops/start-vm-stack.sh
```

成功时应看到：

```text
backend-up: http://127.0.0.1:8080
tomcat url: http://127.0.0.1:18080
```

快速确认：

```bash
curl -s http://127.0.0.1:8080/swagger-ui.html >/dev/null && echo backend-up
curl -i http://127.0.0.1:18080/
sudo systemctl is-active filebeat
sudo systemctl is-active log-relay.service
```

预期：

```text
backend-up
active
active
```

## 5. 安装前端依赖并构建

在 `node1` 执行：

```bash
cd /home/yangli/Documents/logtrace/frontend
npm ci
npm run build
```

说明：

- Windows 工作区曾出现 `.bin` 缺少 `vue-tsc.cmd/.ps1` 的问题，执行 `npm ci` 可重建依赖。
- 阶段 12 必须先通过 `npm run build`，再启动浏览器演示。

## 6. 启动前端

继续在 `node1` 执行：

```bash
cd /home/yangli/Documents/logtrace/frontend
npm run dev -- --host 0.0.0.0
```

浏览器访问：

```text
http://192.168.88.101:5173
```

不要在前端设置 `VITE_API_BASE_URL`。保持空值时，前端请求 `/api/...`，由 Vite 代理转发到 `http://localhost:8080`。

## 7. 可选预检

你已经能正常启动前后端时，可以跳过预检。需要快速确认环境时执行：

```bash
cd /home/yangli/Documents/logtrace
bash ops/stage12/run-stage12-preflight.sh --check-only
```

需要让预检生成一个干净的新实时批次时执行：

```bash
bash ops/stage12/run-stage12-preflight.sh
```

预检成功会输出 `batch_id`、`attack_log_id`、`ledger_root`、`chain_tx_id`，并保存临时 API 证据到 `/tmp/logtrace-stage12-*.json`。

## 8. 持续正常流量

另开一个 Xshell 窗口，在 `node1` 执行：

```bash
cd /home/yangli/Documents/logtrace
bash ops/stage12/run-normal-traffic.sh
```

脚本会持续：

- 随机访问 `/`、`/index.jsp`、`/docs`、`/health`、`/search` 等 URI。
- 随机追加查询参数、User-Agent、请求间隔和突发请求数。
- 通过 `X-Forwarded-For` 模拟随机来源 IP。

注意：当前 Tomcat access log 解析只读取日志行首 IP，因此随机 IP 只作为请求头/模拟元数据，不承诺写入数据库 `source_ip` 字段。真实 `source_ip` 可能仍是 Docker 网关地址。

可调环境变量：

```bash
LOGTRACE_STAGE12_NORMAL_MIN_SLEEP=1
LOGTRACE_STAGE12_NORMAL_MAX_SLEEP=5
LOGTRACE_STAGE12_NORMAL_BURST_MIN=1
LOGTRACE_STAGE12_NORMAL_BURST_MAX=4
```

停止脚本按 `Ctrl+C`。

## 9. 攻击并篡改

保持正常流量脚本运行，另开窗口执行：

```bash
cd /home/yangli/Documents/logtrace
bash ops/stage12/run-attack-and-tamper.sh
```

脚本会：

1. 让你选择篡改方式。
2. 等待进入新的 UTC 分钟窗口。
3. 触发 `PUT /shell.jsp/` 攻击流量。
4. 等待攻击日志进入 `node1.log_records`。
5. 攻击后至少等待 `60` 秒。
6. 继续等待目标批次达到 `CHAIN_COMMITTED`。
7. 调用 node1 MySQL 现有 `sp_tamper_*` 存储过程执行篡改。
8. 输出 `batch_id`、`attack_log_id`、`tamper_mode`、`chain_tx_id` 和前端链接。

交互选择：

```text
1) missing  - 删除攻击日志，预期 MISSING_LOG
2) modified - 修改攻击 URI，预期 MODIFIED_LOG
3) extra    - 插入大量正常外观噪声日志，预期 EXTRA_LOG
```

也可以用环境变量免交互：

```bash
LOGTRACE_STAGE12_TAMPER_MODE=missing bash ops/stage12/run-attack-and-tamper.sh
LOGTRACE_STAGE12_TAMPER_MODE=modified bash ops/stage12/run-attack-and-tamper.sh
LOGTRACE_STAGE12_TAMPER_MODE=extra LOGTRACE_STAGE12_NOISE_COUNT=30 bash ops/stage12/run-attack-and-tamper.sh
```

输出示例：

```text
Stage 12 attack/tamper completed

batch_id=bch_v1_tomcat-cve-2017-12615_20260513T020500Z
attack_log_id=log_v1_xxx
tamper_mode=missing
chain_tx_id=<fabric-tx-id>

Open in browser:
  http://192.168.88.101:5173/integrity?batch_id=<batch_id>
  http://192.168.88.101:5173/logs
  http://192.168.88.101:5173/batches/<batch_id>
```

把这四项记录到答辩材料：

```text
batch_id=
attack_log_id=
tamper_mode=
chain_tx_id=
```

## 10. 浏览器验收流程

### 10.1 登录

打开：

```text
http://192.168.88.101:5173/login
```

使用管理员账号登录。

通过标准：

- 登录成功后进入 `/batches`。
- 不出现 401 循环。
- DevTools Console 没有红色运行错误。

### 10.2 批次管理

打开：

```text
http://192.168.88.101:5173/batches
```

操作：

- 来源输入 `tomcat-cve-2017-12615`。
- 时间范围可用“当前分钟”“上一分钟”“最近 10 分钟”等快捷按钮。
- 找到攻击脚本输出的 `batch_id`。

通过标准：

- 新批次存在。
- 状态为 `CHAIN_COMMITTED`。
- 日志数大于 0。
- 可点击“详情”“校验”“账本”。

### 10.3 批次详情

从批次列表点击“详情”，或直接打开：

```text
http://192.168.88.101:5173/batches/<batch_id>
```

通过标准：

- “链上存证”展示批次 ID、来源、Root 和交易 ID。
- “三库批次元数据”展示 `node1/node2/node3`。
- “批次日志”中可看到 `PUT /shell.jsp/`。如果选择 `missing` 篡改，node1 的攻击日志会被删除，此时用 `/logs` 切换 node2/node3 可查到未被篡改副本。

### 10.4 账本存证

打开：

```text
http://192.168.88.101:5173/ledger?batch_id=<batch_id>
```

通过标准：

- 页面展示链上批次详情、Root、交易 ID、时间窗和算法。
- 页面文案明确：账本负责链上存证查询，数据库完整性检测由 `/integrity` 负责。
- 点击“执行数据库完整性校验”会跳转到 `/integrity?batch_id=<batch_id>`。

说明：`POST /api/ledger/batches/{batchId}/verify-root` 只校验“提交的候选 Root 是否等于链上 Root”，不读取 MySQL，也不重算三库日志。因此阶段 12 主流程不再把它作为普通用户操作。

### 10.5 日志检索

打开：

```text
http://192.168.88.101:5173/logs
```

操作：

- 批次 ID 输入攻击脚本输出的 `batch_id`。
- 方法选择 `PUT`。
- URI 输入 `/shell.jsp/`。
- MsgID 可选择 `EXPLOIT_ATTEMPT`。
- 如果 `missing` 场景下 node1 查不到攻击日志，切换副本节点到 `node2` 或 `node3` 查询。

通过标准：

- 未篡改副本能检索到攻击日志。
- `request_method` 为 `PUT`。
- `request_uri` 为 `/shell.jsp/`。
- 可点击“批次”跳回详情。

### 10.6 完整性校验

打开：

```text
http://192.168.88.101:5173/integrity?batch_id=<batch_id>
```

攻击并篡改后的通过标准：

- 显示发现异常节点 `node1`。
- 差异类型包含 `BATCH_ROOT_MISMATCH`。
- 选择 `missing` 时包含 `MISSING_LOG`。
- 选择 `modified` 时包含 `MODIFIED_LOG`。
- 选择 `extra` 时包含 `EXTRA_LOG`。
- `node2/node3` 可作为未篡改参考副本。

如果使用预检生成的未篡改新批次，正常通过标准是“三库 Root 与链上 Root 一致”，差异定位表为空。

### 10.7 审计查询

打开：

```text
http://192.168.88.101:5173/audits
```

操作：

- 查看“操作审计”。
- 切换到“登录审计”。
- 时间范围可用分钟级快捷按钮。

通过标准：

- 操作审计可加载。
- 登录审计可看到当前账号登录记录。
- 当前账号为 `ADMIN` 或 `AUDITOR`，不会被 403 拒绝。

## 11. 前端体验验收门禁

阶段 12 前端验收必须同时满足：

- 复制按钮在 `http://192.168.88.101:5173` 下可用；浏览器 Clipboard API 不可用时会自动回退。
- 批次、账本、日志、审计页面的时间筛选支持分钟级选择和快捷按钮。
- `/logs` 的“方法”“状态码”“MsgID”为可选项，MsgID 有含义提示。
- `/ledger` 不再引导用户手填 Root 做主流程校验，而是跳转 `/integrity` 执行三库重算。
- 主导航不显示 `/data-entry`；该路由保留为备用手工工具。
- DevTools Console 无红色运行错误。
- 页面无明显表格、按钮、长 hash 溢出遮挡。

## 12. 备用演示样本

如果当天新实时批次因 Filebeat、relay 或 Fabric 临时故障无法生成，可临时使用阶段 11 已登记批次展示完整性页面能力：

| 场景 | batch_id | 预期差异 |
|---|---|---|
| 删除攻击日志 | `bch_v1_tomcat-cve-2017-12615_20260512T145900Z` | `BATCH_ROOT_MISMATCH` + `MISSING_LOG` |
| 修改攻击 URI | `bch_v1_tomcat-cve-2017-12615_20260512T150200Z` | `BATCH_ROOT_MISMATCH` + `MODIFIED_LOG` |
| 插入噪声日志 | `bch_v1_tomcat-cve-2017-12615_20260512T150500Z` | `BATCH_ROOT_MISMATCH` + `EXTRA_LOG` |

注意：备用样本不能替代阶段 12 通过标准。阶段 12 仍要求最终跑通新实时批次。

## 13. 常用排错入口

后端：

```bash
tail -n 120 /var/log/logtrace/backend.log
curl -s http://127.0.0.1:8080/swagger-ui.html >/dev/null && echo backend-up
```

前端：

```bash
cd /home/yangli/Documents/logtrace/frontend
npm ci
npm run build
npm run dev -- --host 0.0.0.0
```

Tomcat：

```bash
curl -i http://127.0.0.1:18080/
tail -n 50 /opt/log-trace/vulhub-logs/tomcat/localhost_access_log.*.txt
```

Filebeat 与 relay：

```bash
sudo systemctl status filebeat --no-pager
sudo systemctl status log-relay.service --no-pager
ls -lh /var/spool/logtrace-stage10
tail -n 50 /var/lib/logtrace-stage10/dead-letter.ndjson
```

最近批次：

```bash
source ops/vm-runtime.env
MYSQL_PWD="$LOGTRACE_NODE1_JDBC_PASSWORD" mysql -h127.0.0.1 -u"$LOGTRACE_NODE1_JDBC_USERNAME" -Dlogtrace_node1 \
  -e "SELECT batch_id, source, log_count, seal_status, chain_tx_id
      FROM log_batches
      WHERE source='tomcat-cve-2017-12615'
      ORDER BY start_time DESC
      LIMIT 10;"
```

最近攻击日志：

```bash
source ops/vm-runtime.env
MYSQL_PWD="$LOGTRACE_NODE1_JDBC_PASSWORD" mysql -h127.0.0.1 -u"$LOGTRACE_NODE1_JDBC_USERNAME" -Dlogtrace_node1 \
  -e "SELECT batch_id, log_id, request_method, request_uri, event_time, inserted_at
      FROM log_records
      WHERE source='tomcat-cve-2017-12615' AND request_uri LIKE '%shell.jsp%'
      ORDER BY inserted_at DESC
      LIMIT 10;"
```

## 14. 答辩材料清单

建议最终保存以下截图或摘录：

- 前端登录成功与用户角色。
- 正常流量脚本运行中的输出。
- 攻击篡改脚本输出的 `batch_id`、`attack_log_id`、`tamper_mode`、`chain_tx_id`。
- 新实时批次列表行。
- 批次详情的链上存证与三库元数据。
- `PUT /shell.jsp/` 攻击日志检索结果。
- 账本页面的链上存证详情和“执行数据库完整性校验”入口。
- 完整性校验中的异常节点、Root 对比和差异类型。
- 审计查询中的登录与操作记录。
