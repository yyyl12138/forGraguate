# 阶段8：Fabric 网络与链码真实验收操作手册

本手册用于手工完成阶段8验收：恢复或确认 Fabric 网络，部署 `log-evidence` 链码，使用 CLI 验证全部链码方法，并确认 CouchDB 中存在链上状态。

执行方式：使用 Xshell 登录虚拟机，使用 Xftp 传输文件。本文不提供自动部署脚本。

## 0. 阶段边界

本阶段只做：

- Fabric 容器、通道、Peer、CouchDB 状态检查。
- 链码生命周期：`package`、`install`、`approveformyorg`、`checkcommitreadiness`、`commit`、`querycommitted`。
- CLI 验证链码 ABI。
- CouchDB 验证链码状态落库。

本阶段不做：

- 不接入 Spring Boot 真实 Fabric Gateway。
- 不修改后端 OpenAPI、MySQL schema、链码 ABI、哈希契约或前端页面。
- 不执行 `docker compose down -v`。
- 不删除 ledger volume。
- 不重建通道。
- 不清空 CouchDB。

若任一步预期不一致，先停止，不要继续下一节。

## 1. 固定参数

| 项 | 值 |
|---|---|
| Fabric 工作区 | `/home/yangli/Documents/fabric-workspace` |
| Fabric 网络目录 | `/home/yangli/Documents/fabric-workspace/network` |
| 链码源码目标目录 | `/home/yangli/Documents/fabric-workspace/chaincode/log-evidence` |
| Docker Compose 文件 | `/home/yangli/Documents/fabric-workspace/network/docker/docker-compose.yaml` |
| 通道 | `mychannel` |
| 链码名 | `log-evidence` |
| 链码版本 | `1.0` |
| 链码 sequence | `1` |
| 链码 package label | `log-evidence_1.0` |
| 链码包文件 | `log-evidence.tar.gz` |
| 背书策略 | `OR('Org1MSP.peer','Org2MSP.peer')` |
| Orderer | `orderer.example.com:7050` |
| Org1 Peer | `peer0.org1.example.com:7051` |
| Org2 Peer | `peer0.org2.example.com:7051` |

测试批次数据：

```text
BATCH_ID=bch_v1_tomcat-cve-2017-12615_20260422T020500Z
MERKLE_ROOT=36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f
WRONG_ROOT=0972d52b9c5a49a54287486521fc89f52a15fc1313f153daea8afd8b9cf05660
START_TIME=2026-04-22T02:05:00.000Z
END_TIME=2026-04-22T02:06:00.000Z
SOURCE=tomcat-cve-2017-12615
```

## 2. Xftp 文件传输

### 2.1 上传链码源码到 node2

在 Windows 上使用 Xftp：

1. 连接 `node2`。
2. 创建目录：

```text
/home/yangli/Documents/fabric-workspace/chaincode/log-evidence
```

3. 将本仓库的 `chaincode/` 目录内容上传到该目录。

上传后，`node2` 上应存在：

```text
/home/yangli/Documents/fabric-workspace/chaincode/log-evidence/go.mod
/home/yangli/Documents/fabric-workspace/chaincode/log-evidence/main.go
/home/yangli/Documents/fabric-workspace/chaincode/log-evidence/evidence_chaincode.go
/home/yangli/Documents/fabric-workspace/chaincode/log-evidence/model.go
/home/yangli/Documents/fabric-workspace/chaincode/log-evidence/validation.go
```

不要上传 `frontend/`、`backend/target/` 或无关目录。

### 2.2 node2 检查上传结果

在 Xshell 登录 `node2`：

```bash
cd /home/yangli/Documents/fabric-workspace/chaincode/log-evidence
ls -la
sed -n '1,5p' go.mod
```

预期：

- `ls` 能看到 `go.mod`、`go.sum`、`main.go`、`evidence_chaincode.go`、`model.go`、`validation.go`。
- `go.mod` 第一行是：

```text
module log-evidence-chaincode
```

## 3. Go 版本门禁

链码 `go.mod` 声明：

```text
go 1.23
```

因此 node2 和 node3 至少需要 Go `1.23.x`。不通过降低 `go.mod` 规避版本问题。

### 3.1 node2 检查 Go 版本

在 `node2`：

```bash
go version
```

预期示例：

```text
go version go1.23.x linux/amd64
```

如果看到 `go1.21.x` 或 `go: command not found`，先升级 Go。

### 3.2 node3 检查 Go 版本

在 `node3`：

```bash
go version
```

预期示例：

```text
go version go1.23.x linux/amd64
```

### 3.3 Go 版本不足时的升级命令

只在 Go 版本低于 `1.23` 时执行。以下命令需分别在 `node2` 和 `node3` 执行：

```bash
cd /tmp
wget https://go.dev/dl/go1.23.6.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.23.6.linux-amd64.tar.gz
grep -q '/usr/local/go/bin' ~/.profile || echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.profile
export PATH=/usr/local/go/bin:$PATH
go version
```

预期：

```text
go version go1.23.6 linux/amd64
```

如果下载失败，先检查虚拟机网络或代理。不要继续部署链码。

### 3.4 node2 离线测试链码

在 `node2`：

```bash
cd /home/yangli/Documents/fabric-workspace/chaincode/log-evidence
go env -w GOPROXY=https://goproxy.cn,direct
go mod download
go mod vendor
go test ./...
```

预期：

```text
ok  	log-evidence-chaincode	...
```

确认 `vendor/` 已生成：

```bash
ls -d vendor
```

预期：

```text
vendor
```

必须生成 `vendor/` 后再打包链码。Fabric 的 Go 链码构建容器默认会尝试访问 `proxy.golang.org` 下载依赖；当前环境中该地址可能被拒绝，导致 `peer lifecycle chaincode install` 长时间等待后失败。链码包内包含 `vendor/` 后，Fabric 构建脚本会使用 `-mod=vendor`，避免构建阶段联网下载依赖。

若 `go mod download` 失败，先检查网络或 Go proxy。若 `go test ./...` 失败，不要继续阶段8。

## 4. 网络状态检查与恢复

本节从“不确定网络是否已运行”开始检查。只恢复容器，不删除卷。

### 4.1 node1 检查 Orderer

在 `node1`：

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'orderer.example.com|NAMES'
```

预期包含：

```text
orderer.example.com   Up ...   0.0.0.0:7050->7050/tcp
```

如果没有 `orderer.example.com` 或状态不是 `Up`：

```bash
cd /home/yangli/Documents/fabric-workspace/network/docker
docker compose -f docker-compose.yaml up -d orderer.example.com
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'orderer.example.com|NAMES'
```

预期 `orderer.example.com` 变为 `Up`。

### 4.2 node2 检查 Org1 Peer、CouchDB、CLI

在 `node2`：

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'peer0.org1.example.com|couchdb0|cli|NAMES'
```

预期包含：

```text
peer0.org1.example.com   Up ...   0.0.0.0:7051->7051/tcp
couchdb0                 Up ...   0.0.0.0:5984->5984/tcp
cli                      Up ...
```

如果缺少容器或状态不是 `Up`：

```bash
cd /home/yangli/Documents/fabric-workspace/network/docker
docker compose -f docker-compose.yaml up -d couchdb0 peer0.org1.example.com cli
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'peer0.org1.example.com|couchdb0|cli|NAMES'
```

预期三个容器均为 `Up`。

### 4.3 node3 检查 Org2 Peer、CouchDB

在 `node3`：

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'peer0.org2.example.com|couchdb1|NAMES'
```

预期包含：

```text
peer0.org2.example.com   Up ...   0.0.0.0:7051->7051/tcp
couchdb1                 Up ...   0.0.0.0:6984->5984/tcp
```

如果缺少容器或状态不是 `Up`：

```bash
cd /home/yangli/Documents/fabric-workspace/network/docker
docker compose -f docker-compose.yaml up -d couchdb1 peer0.org2.example.com
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'peer0.org2.example.com|couchdb1|NAMES'
```

预期两个容器均为 `Up`。

### 4.4 三节点网络解析检查

分别在 `node1`、`node2`、`node3` 执行：

```bash
getent hosts orderer.example.com
getent hosts peer0.org1.example.com
getent hosts peer0.org2.example.com
```

预期：

```text
192.168.88.101 orderer.example.com
192.168.88.102 peer0.org1.example.com
192.168.88.103 peer0.org2.example.com
```

如果解析不一致，先修复 `/etc/hosts`，不要继续。

实际执行中，`node2`、`node3` 曾出现本命令无输出。处理方式是在对应节点补齐 hosts：

```bash
sudo cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d-%H%M%S)

sudo tee -a /etc/hosts >/dev/null <<'EOF'
192.168.88.101 node1 orderer.example.com
192.168.88.102 node2 peer0.org1.example.com
192.168.88.103 node3 peer0.org2.example.com
EOF
```

补齐后重新执行 `getent hosts`。如果 `node1` 返回重复行但 IP 正确，不阻断阶段8。

### 4.5 通道加入状态检查

在 `node2` 设置 Org1 环境变量：

```bash
export FABRIC_CFG_PATH=/home/yangli/Documents/fabric-workspace/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
export CORE_PEER_MSPCONFIGPATH=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
peer channel list
```

预期包含：

```text
Channels peers has joined:
mychannel
```

在 `node3` 设置 Org2 环境变量：

```bash
export FABRIC_CFG_PATH=/home/yangli/Documents/fabric-workspace/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_ADDRESS=peer0.org2.example.com:7051
export CORE_PEER_MSPCONFIGPATH=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
peer channel list
```

预期同样包含：

```text
Channels peers has joined:
mychannel
```

如果任一节点未加入 `mychannel`，不要继续。本阶段不重建通道，需要先对话定位。

## 5. 准备跨组织公开 TLS 证书

提交链码定义时通常需要同时指定 Org1 和 Org2 Peer 地址及 TLS 根证书。只复制公开 TLS CA 证书，不复制 Admin 私钥。

### 5.1 从 node3 复制 Org2 Peer TLS CA 到 node2

推荐使用 Xftp：

1. 从 `node3` 下载：

```text
/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
```

2. 上传到 `node2`：

```text
/home/yangli/Documents/fabric-workspace/network/peer-tls-cas/org2/peer0.org2.ca.crt
```

如果使用命令行中转，只依赖阶段6已确认的 `node1 -> node2/node3` SSH。先在 `node1`：

```bash
mkdir -p /tmp/stage8-tls
scp yangli@node3:/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt /tmp/stage8-tls/peer0.org2.ca.crt
ssh yangli@node2 'mkdir -p /home/yangli/Documents/fabric-workspace/network/peer-tls-cas/org2'
scp /tmp/stage8-tls/peer0.org2.ca.crt yangli@node2:/home/yangli/Documents/fabric-workspace/network/peer-tls-cas/org2/peer0.org2.ca.crt
```

然后在 `node2`：

```bash
ls -l /home/yangli/Documents/fabric-workspace/network/peer-tls-cas/org2/peer0.org2.ca.crt
```

预期：

```text
-rw-r--r-- ... peer0.org2.ca.crt
```

### 5.2 从 node2 复制 Org1 Peer TLS CA 到 node3

推荐使用 Xftp：

1. 从 `node2` 下载：

```text
/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
```

2. 上传到 `node3`：

```text
/home/yangli/Documents/fabric-workspace/network/peer-tls-cas/org1/peer0.org1.ca.crt
```

如果使用命令行中转，先在 `node1`：

```bash
mkdir -p /tmp/stage8-tls
scp yangli@node2:/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt /tmp/stage8-tls/peer0.org1.ca.crt
ssh yangli@node3 'mkdir -p /home/yangli/Documents/fabric-workspace/network/peer-tls-cas/org1'
scp /tmp/stage8-tls/peer0.org1.ca.crt yangli@node3:/home/yangli/Documents/fabric-workspace/network/peer-tls-cas/org1/peer0.org1.ca.crt
```

然后在 `node3`：

```bash
ls -l /home/yangli/Documents/fabric-workspace/network/peer-tls-cas/org1/peer0.org1.ca.crt
```

预期：

```text
-rw-r--r-- ... peer0.org1.ca.crt
```

## 6. 打包链码

只在 `node2` 打包一次，再把同一个包复制到 `node3`，保证两个组织安装同一个 package ID。

### 6.1 node2 打包

在 `node2`：

```bash
export FABRIC_CFG_PATH=/home/yangli/Documents/fabric-workspace/config
cd /home/yangli/Documents/fabric-workspace
peer lifecycle chaincode package log-evidence.tar.gz \
  --path /home/yangli/Documents/fabric-workspace/chaincode/log-evidence \
  --lang golang \
  --label log-evidence_1.0
ls -lh log-evidence.tar.gz
```

预期：

```text
-rw-r--r-- ... log-evidence.tar.gz
```

如果提示 `go.mod requires go >= 1.23`，说明当前链码构建环境仍不满足 Go 版本要求，先停止对话。

如果后续 `install` 阶段长时间等待后失败，且 peer 日志包含：

```text
Get "https://proxy.golang.org/...": connect: connection refused
```

说明链码包没有带上可用的 `vendor/`，或重新打包前没有执行 `go mod vendor`。回到第 3.4 节生成 `vendor/`，然后删除旧包并重新打包。

### 6.2 复制链码包到 node3

推荐使用 Xftp：

1. 从 `node2` 下载：

```text
/home/yangli/Documents/fabric-workspace/log-evidence.tar.gz
```

2. 上传到 `node3`：

```text
/home/yangli/Documents/fabric-workspace/log-evidence.tar.gz
```

如果使用命令行中转，先在 `node1`：

```bash
scp yangli@node2:/home/yangli/Documents/fabric-workspace/log-evidence.tar.gz /tmp/log-evidence.tar.gz
scp /tmp/log-evidence.tar.gz yangli@node3:/home/yangli/Documents/fabric-workspace/log-evidence.tar.gz
```

在 `node3`：

```bash
ls -lh /home/yangli/Documents/fabric-workspace/log-evidence.tar.gz
```

预期：

```text
-rw-r--r-- ... log-evidence.tar.gz
```

## 7. 安装链码

### 7.1 Org1 在 node2 安装

在 `node2`：

```bash
export FABRIC_CFG_PATH=/home/yangli/Documents/fabric-workspace/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
export CORE_PEER_MSPCONFIGPATH=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt

cd /home/yangli/Documents/fabric-workspace
peer lifecycle chaincode install log-evidence.tar.gz
peer lifecycle chaincode queryinstalled
```

预期安装输出包含：

```text
Chaincode code package identifier: log-evidence_1.0:<hash>
```

`queryinstalled` 也应包含同一个 `Package ID`。

记录 package ID：

```bash
export PACKAGE_ID="$(peer lifecycle chaincode calculatepackageid log-evidence.tar.gz)"
echo "$PACKAGE_ID"
```

预期：

```text
log-evidence_1.0:<hash>
```

如果报：

```text
No such image: hyperledger/fabric-ccenv:2.5
```

先拉取 Fabric 链码构建镜像：

```bash
docker pull hyperledger/fabric-ccenv:2.5
docker image inspect hyperledger/fabric-ccenv:2.5 --format '{{.RepoTags}}'
```

预期：

```text
[hyperledger/fabric-ccenv:2.5]
```

如果报：

```text
Cannot connect to the Docker daemon at unix:///host/var/run/docker.sock
```

不要只看 CLI 报错，先查看 peer 日志：

```bash
docker logs --tail 120 peer0.org1.example.com
```

本项目实际遇到过该报错，但真实根因是 Fabric 构建容器访问 `proxy.golang.org` 被拒绝。日志中若出现 `Get "https://proxy.golang.org/...": connect: connection refused`，按第 3.4 节生成 `vendor/` 后重新打包。若日志只显示 Docker socket 权限问题，再检查 `/var/run/docker.sock` 挂载和权限。

### 7.2 Org2 在 node3 安装

在 `node3`：

```bash
export FABRIC_CFG_PATH=/home/yangli/Documents/fabric-workspace/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_ADDRESS=peer0.org2.example.com:7051
export CORE_PEER_MSPCONFIGPATH=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

cd /home/yangli/Documents/fabric-workspace
peer lifecycle chaincode install log-evidence.tar.gz
peer lifecycle chaincode queryinstalled
export PACKAGE_ID="$(peer lifecycle chaincode calculatepackageid log-evidence.tar.gz)"
echo "$PACKAGE_ID"
```

预期：

- 安装输出包含 `Chaincode code package identifier: log-evidence_1.0:<hash>`。
- `echo "$PACKAGE_ID"` 与 node2 的 package ID 完全一致。

如果两个 package ID 不一致，不要继续。

## 8. 批准链码定义

### 8.1 Org1 在 node2 批准

在 `node2`：

```bash
export FABRIC_CFG_PATH=/home/yangli/Documents/fabric-workspace/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
export CORE_PEER_MSPCONFIGPATH=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export ORDERER_CA=/home/yangli/Documents/fabric-workspace/network/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt
export PACKAGE_ID="$(peer lifecycle chaincode calculatepackageid /home/yangli/Documents/fabric-workspace/log-evidence.tar.gz)"

peer lifecycle chaincode approveformyorg \
  -o orderer.example.com:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --tls \
  --cafile "$ORDERER_CA" \
  --channelID mychannel \
  --name log-evidence \
  --version 1.0 \
  --package-id "$PACKAGE_ID" \
  --sequence 1 \
  --signature-policy "OR('Org1MSP.peer','Org2MSP.peer')"
```

预期输出通常为空，或包含交易提交成功信息。若命令退出码为 `0`，继续。

### 8.2 Org2 在 node3 批准

在 `node3`：

```bash
export FABRIC_CFG_PATH=/home/yangli/Documents/fabric-workspace/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_ADDRESS=peer0.org2.example.com:7051
export CORE_PEER_MSPCONFIGPATH=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
export ORDERER_CA=/home/yangli/Documents/fabric-workspace/network/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt
export PACKAGE_ID="$(peer lifecycle chaincode calculatepackageid /home/yangli/Documents/fabric-workspace/log-evidence.tar.gz)"

peer lifecycle chaincode approveformyorg \
  -o orderer.example.com:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --tls \
  --cafile "$ORDERER_CA" \
  --channelID mychannel \
  --name log-evidence \
  --version 1.0 \
  --package-id "$PACKAGE_ID" \
  --sequence 1 \
  --signature-policy "OR('Org1MSP.peer','Org2MSP.peer')"
```

预期同 Org1：命令退出码为 `0`。

实际执行中，Org2 曾返回：

```text
Error: timed out waiting for txid on all peers
```

该错误不一定表示批准失败。先查询批准是否已落账：

```bash
peer lifecycle chaincode queryapproved \
  --channelID mychannel \
  --name log-evidence \
  --sequence 1
```

若输出包含 `Approved chaincode definition`、`sequence: 1`、`version: 1.0`，说明批准已成功，可继续第 9 节。

若未批准，再补齐代理绕过后重试：

```bash
export NO_PROXY=localhost,127.0.0.1,::1,192.168.88.101,192.168.88.102,192.168.88.103,node1,node2,node3,orderer.example.com,peer0.org1.example.com,peer0.org2.example.com
export no_proxy=$NO_PROXY
```

## 9. 检查提交就绪

在 `node2`：

```bash
export FABRIC_CFG_PATH=/home/yangli/Documents/fabric-workspace/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
export CORE_PEER_MSPCONFIGPATH=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export ORDERER_CA=/home/yangli/Documents/fabric-workspace/network/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt

peer lifecycle chaincode checkcommitreadiness \
  --channelID mychannel \
  --name log-evidence \
  --version 1.0 \
  --sequence 1 \
  --signature-policy "OR('Org1MSP.peer','Org2MSP.peer')" \
  --output json
```

预期：

```json
{
  "approvals": {
    "Org1MSP": true,
    "Org2MSP": true
  }
}
```

如果任一组织为 `false`，回到第 8 节检查对应组织批准命令。

## 10. 提交链码定义

在 `node2`：

```bash
export FABRIC_CFG_PATH=/home/yangli/Documents/fabric-workspace/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
export CORE_PEER_MSPCONFIGPATH=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export ORDERER_CA=/home/yangli/Documents/fabric-workspace/network/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt
export ORG1_PEER_TLS=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export ORG2_PEER_TLS=/home/yangli/Documents/fabric-workspace/network/peer-tls-cas/org2/peer0.org2.ca.crt

peer lifecycle chaincode commit \
  -o orderer.example.com:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --tls \
  --cafile "$ORDERER_CA" \
  --channelID mychannel \
  --name log-evidence \
  --version 1.0 \
  --sequence 1 \
  --signature-policy "OR('Org1MSP.peer','Org2MSP.peer')" \
  --peerAddresses peer0.org1.example.com:7051 \
  --tlsRootCertFiles "$ORG1_PEER_TLS" \
  --peerAddresses peer0.org2.example.com:7051 \
  --tlsRootCertFiles "$ORG2_PEER_TLS"
```

预期输出包含：

```text
Chaincode definition committed on channel 'mychannel'
```

或命令退出码为 `0` 且没有错误。

查询提交结果：

```bash
peer lifecycle chaincode querycommitted --channelID mychannel --name log-evidence
```

预期包含：

```text
Name: log-evidence, Version: 1.0, Sequence: 1
Endorsement Plugin: escc
Validation Plugin: vscc
```

如果提示已经 committed 且版本、sequence、策略一致，可继续功能验收；如果版本或 sequence 不一致，停止对话。

## 11. CLI 功能验收

以下命令在 `node2` 执行。

### 11.1 设置调用环境

```bash
export FABRIC_CFG_PATH=/home/yangli/Documents/fabric-workspace/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
export CORE_PEER_MSPCONFIGPATH=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export ORDERER_CA=/home/yangli/Documents/fabric-workspace/network/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt
export ORG1_PEER_TLS=/home/yangli/Documents/fabric-workspace/network/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export ORG2_PEER_TLS=/home/yangli/Documents/fabric-workspace/network/peer-tls-cas/org2/peer0.org2.ca.crt
```

### 11.2 创建批次存证

```bash
peer chaincode invoke \
  -o orderer.example.com:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --tls \
  --cafile "$ORDERER_CA" \
  -C mychannel \
  -n log-evidence \
  --peerAddresses peer0.org1.example.com:7051 \
  --tlsRootCertFiles "$ORG1_PEER_TLS" \
  --peerAddresses peer0.org2.example.com:7051 \
  --tlsRootCertFiles "$ORG2_PEER_TLS" \
  -c '{"Args":["CreateBatchEvidence","{\"batch_id\":\"bch_v1_tomcat-cve-2017-12615_20260422T020500Z\",\"merkle_root\":\"36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f\",\"log_count\":3,\"start_time\":\"2026-04-22T02:05:00.000Z\",\"end_time\":\"2026-04-22T02:06:00.000Z\",\"source\":\"tomcat-cve-2017-12615\",\"schema_version\":1,\"hash_algorithm\":\"SHA-256\",\"canonicalization_version\":\"clog-v1\"}"]}'
```

预期包含：

```text
Chaincode invoke successful
```

或：

```text
status:200
```

如果提示 `batch evidence already exists`，说明该测试批次已经写过。可跳过重复写入，继续查询验收。

### 11.3 查询批次

```bash
peer chaincode query \
  -C mychannel \
  -n log-evidence \
  -c '{"Args":["GetBatchEvidence","bch_v1_tomcat-cve-2017-12615_20260422T020500Z"]}'
```

预期返回 JSON，至少包含：

```json
{
  "doc_type": "BatchEvidence",
  "batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z",
  "merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f",
  "log_count": 3,
  "source": "tomcat-cve-2017-12615",
  "schema_version": 1,
  "hash_algorithm": "SHA-256",
  "canonicalization_version": "clog-v1",
  "created_at": "...",
  "tx_id": "..."
}
```

必须看到 `doc_type`、`created_at`、`tx_id`。

### 11.4 按时间范围查询

```bash
peer chaincode query \
  -C mychannel \
  -n log-evidence \
  -c '{"Args":["QueryBatchEvidenceByTimeRange","2026-04-22T02:00:00.000Z","2026-04-22T03:00:00.000Z"]}'
```

预期返回 JSON 数组，数组中包含测试批次：

```json
[
  {
    "batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z"
  }
]
```

空数组 `[]` 不符合预期。

### 11.5 按来源查询

```bash
peer chaincode query \
  -C mychannel \
  -n log-evidence \
  -c '{"Args":["QueryBatchEvidenceBySource","tomcat-cve-2017-12615"]}'
```

预期返回 JSON 数组，数组中包含测试批次。

### 11.6 Root 正确校验

```bash
peer chaincode query \
  -C mychannel \
  -n log-evidence \
  -c '{"Args":["VerifyBatchRoot","bch_v1_tomcat-cve-2017-12615_20260422T020500Z","36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f"]}'
```

预期：

```json
{
  "batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z",
  "expected_merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f",
  "actual_merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f",
  "matched": true,
  "tx_id": "..."
}
```

### 11.7 Root 错误校验

```bash
peer chaincode query \
  -C mychannel \
  -n log-evidence \
  -c '{"Args":["VerifyBatchRoot","bch_v1_tomcat-cve-2017-12615_20260422T020500Z","0972d52b9c5a49a54287486521fc89f52a15fc1313f153daea8afd8b9cf05660"]}'
```

预期命令成功返回 JSON，且：

```json
{
  "matched": false,
  "actual_merkle_root": "0972d52b9c5a49a54287486521fc89f52a15fc1313f153daea8afd8b9cf05660"
}
```

注意：Root 不一致不是链码错误，必须返回成功响应并显示 `matched=false`。

### 11.8 重复写入负向验收

再次执行第 11.2 节的 `CreateBatchEvidence` 命令。

预期失败，错误信息包含：

```text
batch evidence already exists
```

如果重复写入成功，阶段8不通过，因为链码覆盖了已有存证。

## 12. CouchDB 状态验收

### 12.1 node2 CouchDB 检查

在 `node2`：

```bash
curl -s -u admin:adminpw http://127.0.0.1:5984/_all_dbs
```

预期列表中包含：

```text
mychannel_log-evidence
```

查询批次状态：

```bash
curl -s -u admin:adminpw \
  -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:5984/mychannel_log-evidence/_find \
  -d '{"selector":{"doc_type":"BatchEvidence","batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z"}}'
```

预期返回 JSON 中 `docs` 数组至少有一条记录，且包含：

```json
"doc_type": "BatchEvidence"
"batch_id": "bch_v1_tomcat-cve-2017-12615_20260422T020500Z"
"merkle_root": "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f"
```

如果响应中同时出现：

```text
"warning": "No matching index found, create an index to optimize query time."
```

该 warning 可接受，不影响阶段8验收。阶段8只要求 `docs` 数组能查到目标批次；CouchDB 索引优化不作为本阶段门禁。

### 12.2 node3 CouchDB 检查

在 `node3`：

```bash
curl -s -u admin:adminpw http://127.0.0.1:6984/_all_dbs
```

预期列表中包含：

```text
mychannel_log-evidence
```

查询批次状态：

```bash
curl -s -u admin:adminpw \
  -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:6984/mychannel_log-evidence/_find \
  -d '{"selector":{"doc_type":"BatchEvidence","batch_id":"bch_v1_tomcat-cve-2017-12615_20260422T020500Z"}}'
```

预期与 node2 一致，`docs` 数组中能看到同一批次。

如果 node2 可见但 node3 不可见，先检查 Org2 Peer 是否已经加入通道、链码是否安装、commit 是否指定了 Org2 peer 地址。

## 13. 阶段8通过标准

全部满足才算通过：

- `node1` 的 `orderer.example.com` 为 `Up`。
- `node2` 的 `peer0.org1.example.com`、`couchdb0`、`cli` 为 `Up`。
- `node3` 的 `peer0.org2.example.com`、`couchdb1` 为 `Up`。
- Org1 与 Org2 Peer 均已加入 `mychannel`。
- Org1 与 Org2 安装的 package ID 完全一致。
- `checkcommitreadiness` 显示 `Org1MSP: true`、`Org2MSP: true`。
- `querycommitted` 显示 `Name: log-evidence, Version: 1.0, Sequence: 1`。
- `CreateBatchEvidence` 能成功写入测试批次。
- `GetBatchEvidence` 返回包含 `doc_type`、`created_at`、`tx_id` 的 JSON。
- `QueryBatchEvidenceByTimeRange` 能查到测试批次。
- `QueryBatchEvidenceBySource` 能查到测试批次。
- 正确 Root 校验返回 `matched=true`。
- 错误 Root 校验返回 `matched=false`。
- 重复写入返回 `batch evidence already exists`。
- node2 与 node3 的 CouchDB 均能查询到测试批次状态。

## 14. 常见异常与停止点

| 异常 | 处理 |
|---|---|
| `go.mod requires go >= 1.23` | Go 版本或 Fabric 链码构建环境不满足要求，停止对话。 |
| `No such image: hyperledger/fabric-ccenv:2.5` | 在对应节点执行 `docker pull hyperledger/fabric-ccenv:2.5`。 |
| `Cannot connect to the Docker daemon at unix:///host/var/run/docker.sock` | 先查 `docker logs --tail 120 peer0.org*.example.com`；本项目实际根因曾是 `proxy.golang.org` 依赖下载被拒绝，需要生成 `vendor/` 并重新打包。 |
| `Get "https://proxy.golang.org/...": connect: connection refused` | 在链码源码目录执行 `go env -w GOPROXY=https://goproxy.cn,direct`、`go mod download`、`go mod vendor`，重新打包并重新分发同一个链码包。 |
| `access denied` 或 MSP 相关错误 | 检查 `CORE_PEER_MSPCONFIGPATH` 是否指向对应组织 Admin MSP。 |
| `x509: certificate signed by unknown authority` | 检查 `ORDERER_CA`、`CORE_PEER_TLS_ROOTCERT_FILE`、跨组织公开 TLS CA 路径。 |
| `context deadline exceeded` | 检查主机名解析、端口、防火墙、容器状态和代理绕过。 |
| `timed out waiting for txid on all peers` | 不要直接判失败；先用 `queryapproved` 或 `querycommitted` 验证交易是否已落账。 |
| `chaincode definition not agreed to by this org` | 回到第 8 节，确认两个组织都执行了 `approveformyorg`。 |
| `requested sequence is X, but new definition must be sequence Y` | 说明通道上已有链码定义，不要自行改 sequence，先对话确认升级策略。 |
| CouchDB `_find` 返回 `docs: []` | 先确认 CLI 查询能查到批次；若 CLI 正常，检查 CouchDB DB 名和对应节点 Peer 状态。 |
| CouchDB `_find` 返回目标 `docs` 但带 `No matching index found` warning | 可接受；阶段8不要求建立索引。 |

## 15. 阶段8完成后记录

执行通过后，建议记录以下信息，供阶段9真实 Gateway 联调用：

```text
CHAINCODE_NAME=log-evidence
CHAINCODE_VERSION=1.0
CHAINCODE_SEQUENCE=1
PACKAGE_ID=log-evidence_1.0:<hash>
CHANNEL_NAME=mychannel
ORDERER=orderer.example.com:7050
ORG1_PEER=peer0.org1.example.com:7051
ORG2_PEER=peer0.org2.example.com:7051
TEST_BATCH_ID=bch_v1_tomcat-cve-2017-12615_20260422T020500Z
TEST_MERKLE_ROOT=36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f
```
