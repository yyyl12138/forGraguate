# 阶段6基础设施健康检查

该目录用于执行“阶段6：三节点基础设施健康检查”。

## 目的

在进入三节点 MySQL、Fabric 链码和后端真实联调前，先从 `node1` 对三节点基础设施做一次统一体检，尽早暴露以下问题：

- IP 或主机名不一致
- `/etc/hosts` 缺失
- `node1 -> node2/node3` SSH 不通
- Docker / Docker Compose / Go 缺失
- Fabric 工作区或二进制不存在
- `NO_PROXY/no_proxy` 配置缺口
- `fabric_net` 容器网络未创建或异常

## 文件

- `health-check.env.example`：环境模板
- `infrastructure-health-check.sh`：主检查脚本
- `reports/`：执行后生成的报告目录

## 使用方式

在 `node1` 上执行：

```bash
cd /path/to/forGraguate-main
cp ops/stage6/health-check.env.example ops/stage6/health-check.env
vim ops/stage6/health-check.env
bash ops/stage6/infrastructure-health-check.sh ops/stage6/health-check.env
```

## 结果判断

- 只要存在 `FAIL`，阶段6不通过，不能进入阶段7。
- `WARN` 表示存在风险但不一定阻断，比如 `fabric_net` 还没创建。
- 报告位置会在脚本结尾打印，格式为 Markdown。

## 建议执行顺序

1. 先在 `node1` 跑脚本。
2. 先消除 `FAIL`。
3. 再人工复核 `WARN` 是否可接受。
4. 确认通过后，再开始阶段7 MySQL 部署与验证。
