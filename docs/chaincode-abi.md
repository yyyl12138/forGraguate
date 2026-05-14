# Chaincode ABI And Test Checklist

## 目标与边界

本文档冻结阶段 3 的 Go 链码 ABI 与离线测试清单。链码只负责批次级存证锚点管理，不负责日志采集、日志规范化、Merkle Tree 构建、MySQL 明文比对或攻击演示。

链码运行环境沿用现有 Fabric 基线：

- Fabric Core: `2.5.4`
- Channel: `mychannel`
- Chaincode language: `Go`
- State database: CouchDB
- Organizations: `Org1MSP`, `Org2MSP`
- Endorsement policy: `OR('Org1MSP.peer','Org2MSP.peer')`
- State key: `batch:{batch_id}`

## 数据模型

链上状态值为 `BatchEvidence` JSON。公开字段与 `docs/ledger-state-model.md` 保持一致：

```json
{
  "doc_type": "BatchEvidence",
  "batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z",
  "merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f",
  "log_count": 3,
  "start_time": "2026-04-22T02:05:00.000Z",
  "end_time": "2026-04-22T02:06:00.000Z",
  "source": "tomcat-cve-2017-12615",
  "schema_version": 1,
  "hash_algorithm": "SHA-256",
  "canonicalization_version": "clog-v1",
  "created_at": "2026-04-22T02:06:01.000Z",
  "tx_id": "fabric_transaction_id"
}
```

`doc_type` 是 CouchDB 富查询辅助字段，固定为 `BatchEvidence`。它不改变后端和前端依赖的核心字段。

`created_at` 和 `tx_id` 必须由链码从 Fabric stub 获取：

- `created_at`: 使用 `GetTxTimestamp()` 转换为 UTC 毫秒格式。
- `tx_id`: 使用 `GetTxID()`。

客户端不得提交可信的 `created_at` 或 `tx_id`。如果 ABI 输入中出现这些字段，链码实现应忽略或拒绝；推荐拒绝，避免调用方误解边界。

## 通用约定

所有函数名区分大小写。所有时间字符串使用 UTC 毫秒格式：

```text
YYYY-MM-DDTHH:mm:ss.SSSZ
```

哈希字段使用 64 位小写 hex，不带 `0x`。

错误返回必须使用明确错误信息，至少包含失败字段名或失败原因。Go 链码中推荐使用 `fmt.Errorf("invalid merkle_root: ...")` 这类可诊断文本。

## ABI

### CreateBatchEvidence

创建批次存证记录。重复 `batch_id` 必须失败，禁止覆盖。

调用形式：

```text
CreateBatchEvidence(batchEvidenceInputJson)
```

输入 JSON：

```json
{
  "batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z",
  "merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f",
  "log_count": 3,
  "start_time": "2026-04-22T02:05:00.000Z",
  "end_time": "2026-04-22T02:06:00.000Z",
  "source": "tomcat-cve-2017-12615",
  "schema_version": 1,
  "hash_algorithm": "SHA-256",
  "canonicalization_version": "clog-v1"
}
```

链码写入状态：

```text
key = batch:{batch_id}
value = BatchEvidence JSON
```

返回 JSON：

```json
{
  "batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z",
  "tx_id": "fabric_transaction_id",
  "created_at": "2026-04-22T02:06:01.000Z"
}
```

写入校验：

- `batch_id` 匹配 `^bch_v1_[a-z0-9][a-z0-9-]*_[0-9]{8}T[0-9]{6}Z$`。
- 状态键必须为 `batch:{batch_id}`。
- `GetState(batch:{batch_id})` 已存在时返回错误。
- `merkle_root` 匹配 `^[a-f0-9]{64}$`。
- `log_count > 0`。
- `start_time < end_time`。
- `end_time - start_time = 60s`。
- `source` 非空，且等于 `batch_id` 中的 source 段。
- `schema_version = 1`。
- `hash_algorithm = SHA-256`。
- `canonicalization_version = clog-v1`。
- 输入 JSON 不允许携带 `created_at`、`tx_id`、`raw_message`、`leaf_hash`、`source_node` 或 MySQL 字段。

### GetBatchEvidence

按批次 ID 查询链上存证记录。

调用形式：

```text
GetBatchEvidence(batchId)
```

输入：

```text
bch_v1_tomcat-cve-2017-12615_20260422T020500Z
```

返回 JSON：

```json
{
  "doc_type": "BatchEvidence",
  "batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z",
  "merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f",
  "log_count": 3,
  "start_time": "2026-04-22T02:05:00.000Z",
  "end_time": "2026-04-22T02:06:00.000Z",
  "source": "tomcat-cve-2017-12615",
  "schema_version": 1,
  "hash_algorithm": "SHA-256",
  "canonicalization_version": "clog-v1",
  "created_at": "2026-04-22T02:06:01.000Z",
  "tx_id": "fabric_transaction_id"
}
```

错误：

- `batchId` 格式非法。
- `batch:{batchId}` 不存在。

### QueryBatchEvidenceByTimeRange

按批次时间窗口查询链上存证摘要。查询条件使用批次窗口与目标时间范围有交集的记录：

```text
record.start_time >= startTime AND record.start_time < endTime
```

调用形式：

```text
QueryBatchEvidenceByTimeRange(startTime, endTime)
```

输入示例：

```text
startTime = 2026-04-22T02:00:00.000Z
endTime   = 2026-04-22T03:00:00.000Z
```

返回 JSON 数组，按 `start_time ASC, batch_id ASC` 排序：

```json
[
  {
    "batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z",
    "merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f",
    "log_count": 3,
    "start_time": "2026-04-22T02:05:00.000Z",
    "end_time": "2026-04-22T02:06:00.000Z",
    "source": "tomcat-cve-2017-12615",
    "schema_version": 1,
    "hash_algorithm": "SHA-256",
    "canonicalization_version": "clog-v1",
    "created_at": "2026-04-22T02:06:01.000Z",
    "tx_id": "fabric_transaction_id"
  }
]
```

错误：

- `startTime` 或 `endTime` 格式非法。
- `startTime >= endTime`。

实现要求：

- 使用 CouchDB rich query 时 selector 必须包含 `doc_type = BatchEvidence`。
- 如果 CouchDB 查询结果不保证顺序，链码实现必须在返回前排序。
- 空结果返回 `[]`，不是错误。

### QueryBatchEvidenceBySource

按来源查询链上存证摘要。

调用形式：

```text
QueryBatchEvidenceBySource(source)
```

输入示例：

```text
tomcat-cve-2017-12615
```

返回 JSON 数组，按 `start_time ASC, batch_id ASC` 排序：

```json
[
  {
    "batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z",
    "merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f",
    "log_count": 3,
    "start_time": "2026-04-22T02:05:00.000Z",
    "end_time": "2026-04-22T02:06:00.000Z",
    "source": "tomcat-cve-2017-12615",
    "schema_version": 1,
    "hash_algorithm": "SHA-256",
    "canonicalization_version": "clog-v1",
    "created_at": "2026-04-22T02:06:01.000Z",
    "tx_id": "fabric_transaction_id"
  }
]
```

错误：

- `source` 为空。
- `source` 不匹配 `^[a-z0-9][a-z0-9-]*$`。

实现要求：

- 空结果返回 `[]`，不是错误。
- 查询只返回链上批次存证，不返回日志明文。

### VerifyBatchRoot

校验后端提交的某个重算 Root 是否与链上 Root 一致。该函数不访问 MySQL，不重算 Merkle Tree。

调用形式：

```text
VerifyBatchRoot(batchId, merkleRoot)
```

输入示例：

```text
batchId    = bch_v1_tomcat-cve-2017-12615_20260422T020500Z
merkleRoot = 36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f
```

返回 JSON：

```json
{
  "batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z",
  "expected_merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f",
  "actual_merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f",
  "matched": true,
  "tx_id": "fabric_transaction_id"
}
```

Root 不一致时仍返回成功响应，`matched = false`：

```json
{
  "batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z",
  "expected_merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f",
  "actual_merkle_root": "0972d52b9c5a49a54287486521fc89f52a15fc1313f153daea8afd8b9cf05660",
  "matched": false,
  "tx_id": "fabric_transaction_id"
}
```

错误：

- `batchId` 格式非法。
- `merkleRoot` 格式非法。
- `batch:{batchId}` 不存在。

## CouchDB 查询建议

建议链码保存 `doc_type`，并为真实联调准备 CouchDB 索引：

```json
{
  "index": {
    "fields": ["doc_type", "source", "start_time", "batch_id"]
  },
  "ddoc": "indexBatchEvidenceBySourceTime",
  "name": "indexBatchEvidenceBySourceTime",
  "type": "json"
}
```

时间范围查询 selector：

```json
{
  "selector": {
    "doc_type": "BatchEvidence",
    "start_time": { "$gte": "2026-04-22T02:00:00.000Z", "$lt": "2026-04-22T03:00:00.000Z" }
  }
}
```

来源查询 selector：

```json
{
  "selector": {
    "doc_type": "BatchEvidence",
    "source": "tomcat-cve-2017-12615"
  }
}
```

## CLI 调用示例

真实环境部署后，可在 `node2` 的 CLI 容器中按既有 `mychannel` 调用。具体 peer/orderer/TLS 参数以后续部署脚本为准。

创建批次：

```bash
peer chaincode invoke -C mychannel -n log-evidence -c '{"Args":["CreateBatchEvidence","{\"batch_id\":\"bch_v1_tomcat-cve-2017-12615_20260422T020500Z\",\"merkle_root\":\"36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f\",\"log_count\":3,\"start_time\":\"2026-04-22T02:05:00.000Z\",\"end_time\":\"2026-04-22T02:06:00.000Z\",\"source\":\"tomcat-cve-2017-12615\",\"schema_version\":1,\"hash_algorithm\":\"SHA-256\",\"canonicalization_version\":\"clog-v1\"}"]}'
```

查询批次：

```bash
peer chaincode query -C mychannel -n log-evidence -c '{"Args":["GetBatchEvidence","bch_v1_tomcat-cve-2017-12615_20260422T020500Z"]}'
```

Root 校验：

```bash
peer chaincode query -C mychannel -n log-evidence -c '{"Args":["VerifyBatchRoot","bch_v1_tomcat-cve-2017-12615_20260422T020500Z","36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f"]}'
```

## 离线测试清单

### ABI 稳定性

- `CreateBatchEvidence` 只接受一个 JSON 字符串参数。
- `GetBatchEvidence` 只接受一个 `batchId` 参数。
- `QueryBatchEvidenceByTimeRange` 只接受 `startTime`、`endTime` 两个参数。
- `QueryBatchEvidenceBySource` 只接受一个 `source` 参数。
- `VerifyBatchRoot` 只接受 `batchId`、`merkleRoot` 两个参数。
- 参数数量错误必须返回错误。
- 返回 JSON 字段名必须与本文档一致。

### CreateBatchEvidence 成功路径

- 使用 Tomcat 测试向量创建批次成功。
- 状态键等于 `batch:bch_v1_tomcat-cve-2017-12615_20260422T020500Z`。
- 状态值包含 `doc_type = BatchEvidence`。
- 状态值包含链码生成的 `created_at` 和 `tx_id`。
- 写入后 `GetBatchEvidence` 能返回同一记录。

### CreateBatchEvidence 失败路径

- 重复 `batch_id` 写入失败，不能覆盖旧状态。
- 空 `batch_id` 失败。
- 非法 `batch_id` 格式失败。
- `batch_id` 与 `source` 不一致失败。
- 空 `merkle_root` 失败。
- 大写 hex Root 失败。
- 带 `0x` 前缀 Root 失败。
- Root 长度不是 64 失败。
- `log_count = 0` 失败。
- `log_count < 0` 失败。
- `start_time` 等于 `end_time` 失败。
- `start_time` 晚于 `end_time` 失败。
- 批次窗口不是 60 秒失败。
- 时间缺少毫秒失败。
- 时间不是 UTC `Z` 结尾失败。
- `schema_version != 1` 失败。
- `hash_algorithm != SHA-256` 失败。
- `canonicalization_version != clog-v1` 失败。
- 输入携带 `tx_id` 失败。
- 输入携带 `created_at` 失败。
- 输入携带 `raw_message`、`leaf_hash` 或 `source_node` 失败。

### GetBatchEvidence

- 已存在批次查询成功。
- 不存在批次返回错误。
- 非法 `batchId` 格式返回错误。
- 返回记录不包含 MySQL 明文日志字段。

### QueryBatchEvidenceByTimeRange

- 查询包含目标窗口时返回对应批次。
- 查询边界使用 `start_time >= startTime AND start_time < endTime`。
- 空结果返回 `[]`。
- 多条结果按 `start_time ASC, batch_id ASC` 排序。
- `startTime >= endTime` 返回错误。
- 非 UTC 毫秒时间返回错误。

### QueryBatchEvidenceBySource

- 已存在来源返回对应批次列表。
- 不存在来源返回 `[]`。
- 多条结果按 `start_time ASC, batch_id ASC` 排序。
- 空 source 返回错误。
- 非法 source 格式返回错误。
- 返回记录不包含日志明文。

### VerifyBatchRoot

- 与链上 Root 一致时返回 `matched = true`。
- 与链上 Root 不一致时返回 `matched = false`，不返回链码错误。
- 不存在批次返回错误。
- 非法 `batchId` 返回错误。
- 非法 `merkleRoot` 返回错误。
- 函数不尝试重算 Merkle Tree。

### 序列化与确定性

- JSON marshal/unmarshal 后字段值保持一致。
- 相同输入在不同 peer 背书时生成相同状态值，除 Fabric 交易上下文本身提供的确定性 `tx_id` 和 `GetTxTimestamp` 外不使用本地时间。
- 不使用随机数。
- 不读取外部网络、文件系统、MySQL 或环境变量。

### 状态键碰撞

- `batch:{batch_id}` 是唯一状态键。
- `batch_id` 中不允许冒号、斜杠、空格或大写字符。
- 不允许通过构造特殊 `batch_id` 覆盖其他状态前缀。

### CouchDB 富查询

- 查询 selector 包含 `doc_type = BatchEvidence`。
- 富查询结果能反序列化为 `BatchEvidence`。
- 无索引时单元测试仍能通过；真实部署可增加索引优化性能。

## 后续实现提示

Go 链码建议使用清晰分层：

- `BatchEvidenceInput`: 客户端输入 DTO，不包含 `created_at`、`tx_id`、`doc_type`。
- `BatchEvidence`: 链上状态 DTO，包含完整链上字段。
- `VerifyBatchRootResult`: Root 校验返回 DTO。
- `validateBatchEvidenceInput`: 写入前校验。
- `stateKey(batchID string) string`: 统一生成 `batch:{batch_id}`。
- `formatTxTimestamp`: 将 Fabric protobuf timestamp 转为 UTC 毫秒字符串。

链码实现时不要引用 MySQL Schema，不要导入后端代码，不要实现 Merkle Tree。
