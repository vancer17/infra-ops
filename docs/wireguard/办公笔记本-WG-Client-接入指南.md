# 办公笔记本 WireGuard Client 接入指南

| 项 | 说明 |
|----|------|
| **适用对象** | 需要经 VPN 访问 Dev 内网（Hub、CI、开发环境）的同事 |
| **文档版本** | 2026-06-16 |
| **维护** | infra / 运维团队 |
| **技术索引** | 仓库内 [`developer-laptop-client.md`](developer-laptop-client.md)（运维简版） |

---

## 一、这是什么

公司通过 **WireGuard** 建立加密隧道，让你的笔记本接入内网地址段 `10.200.x.x`，从而：

- 访问 **Hub** 管理节点（`10.200.0.1`）
- 访问 **CI / 开发机**（如 `10.200.0.2`）
- 解析 **`*.internal`** 内网域名（如 `jms.internal` 堡垒机、`ci.internal`）
- 经内网 SSH、调试 Dev 环境（无需 Hub 公网 SSH）

```text
你的笔记本 (10.200.10.x，每人独立)
        │  加密 UDP
        ▼
Hub (121.43.49.58 → 内网 10.200.0.1)
        │  dnsmasq：*.internal
        ├── JumpServer @ jms.internal（Nginx 反代）
        ├── CI 控制机 (10.200.0.2 / ci.internal)
        └── Dev 网段 (10.200.1.x) / Test (10.200.2.x)
```

**说明**：开发角色笔记本默认路由 **管理 + Dev + Test** 网段，**不包含**生产环境（`10.200.3.x`）。具体以 infra 交付的 `wg0.conf` 中 `AllowedIPs` 为准。

---

## 二、接入前准备

### 2.1 向 infra 同事申请

每位同事应使用 **独立的 Peer**（独立 IP + 密钥对），**请勿多人共用同一私钥**。

当前团队 Client 池为 `10.200.10.1`–`10.200.10.5`（见台账 [wireguard-clients.yaml](../assets/wireguard-clients.yaml)）。**新成员**向 infra 申请；已登记 Peer 的同事由 infra 经安全渠道发放个人配置。

申请时 infra 会通过安全渠道（勿用微信/邮件明文）提供：

| 交付物 | 说明 |
|--------|------|
| `wg0.conf` 或配置片段 | 已填好 **PrivateKey** 的 WireGuard 配置 |
| 本机 WG 地址 | `10.200.10.x/32`（每人不同，infra 分配；见台账） |
| （可选）SSH 私钥 | 访问 `deploy@10.200.0.x` 等主机时使用，与 WG 密钥不同 |
| （可选）JumpServer 账号 | 访问 `https://jms.internal/` 须另向 infra 申请平台授权 |

若你自行从 Git 克隆 `infra-ops` 仓库，**不要**把 `*.private` 提交到 Git。

### 2.2 本机要求

- 操作系统：Windows 10+、macOS、或 Linux（Debian/Ubuntu 等）
- 能访问公网 UDP（家庭宽带、公司网络均可；**家庭网络 IP 常变动，已由 infra 在 Hub 侧放行 WG 端口**）
- 管理员权限（安装 WireGuard、写 `/etc/wireguard` 或 Windows 导入隧道）

### 2.3 连接参数（默认值，以 infra 交付的配置为准）

| 项 | 值 |
|----|-----|
| Hub 公网地址 | `121.43.49.58` |
| Hub 端口 | `51820`（UDP） |
| Hub 公钥 | `MNczHi1IQ4l8zkEPIQL1sPxSEPputkPdo2neaZWkFj8=` |
| 本机地址示例 | `10.200.10.x/32`（每人不同，见 `docs/assets/wireguard-clients.yaml`） |
| 内网 DNS（阶段 G2 后） | `10.200.0.1`（Hub dnsmasq，解析 `*.internal`） |
| 可访问网段 | 开发：`10.200.0.0/24`、`10.200.1.0/24`、`10.200.2.0/24`；运维另含全网段 |
| 保活间隔 | `25` 秒 |

配置由 infra 通过 `./scripts/wireguard/render-laptop-conf.sh <peer_name>` 生成后经安全渠道交付。模板参考：

- 运维：`ansible/keys/wireguard/laptop-zhengyaoyuan.conf.example`
- 开发：`ansible/keys/wireguard/laptop-client-dev.conf.example`

---

## 三、安装 WireGuard

### Windows

1. 下载并安装 [WireGuard 官方客户端](https://www.wireguard.com/install/)
2. 打开 **WireGuard** → **添加隧道** → **从文件导入** 或 **手动输入**
3. 粘贴 infra 提供的配置（见第四节格式）
4. 保存后点击 **激活**

### macOS

**方式 A — 图形客户端（推荐）**

1. 从 App Store 安装 **WireGuard**
2. 导入 infra 提供的 `.conf` 文件或粘贴配置
3. 点击 **Activate**

**方式 B — 命令行**

```bash
brew install wireguard-tools
```

### Linux（Debian / Ubuntu）

```bash
sudo apt update
sudo apt install -y wireguard-tools
wg --version
```

---

## 四、配置 WireGuard

### 4.1 配置文件格式

infra 提供的配置与下列结构一致（**PrivateKey、Address、AllowedIPs 每人不同**；以下为**开发角色**示例）：

```ini
[Interface]
PrivateKey = <你的私钥，单行 Base64，由 infra 提供>
Address = 10.200.10.x/32
# 须保留：经 Hub dnsmasq 解析 hub.internal / jms.internal / ci.internal
DNS = 10.200.0.1

[Peer]
# hub-01
PublicKey = MNczHi1IQ4l8zkEPIQL1sPxSEPputkPdo2neaZWkFj8=
Endpoint = 121.43.49.58:51820
AllowedIPs = 10.200.0.0/24, 10.200.1.0/24, 10.200.2.0/24
PersistentKeepalive = 25
```

> **注意**：上式 `Address` 与 `AllowedIPs` 须使用 infra 交付文件中的实际值，**不要**自行改成他人的 `10.200.10.x` 或添加 `10.200.3.0/24`（生产网段）。

### 4.2 Linux 保存配置

```bash
sudo mkdir -p /etc/wireguard
sudo nano /etc/wireguard/wg0.conf
# 粘贴 infra 提供的完整配置

sudo chmod 600 /etc/wireguard/wg0.conf
```

### 4.3 Windows / macOS

使用图形客户端导入上述内容即可，无需手动指定路径。

---

### 4.4 内网 DNS 与 JumpServer

Hub 在 `10.200.0.1` 运行 **dnsmasq**，为 WG 内网提供 `*.internal` 解析。配置中须包含 `DNS = 10.200.0.1`，激活隧道后可直接用域名访问管理面服务：

| 域名 | 指向 | 用途 |
|------|------|------|
| `hub.internal` | 10.200.0.1 | Hub 导航 / Nginx |
| `jms.internal` | 10.200.0.1 | **JumpServer**（HTTPS，经 Nginx 反代） |
| `ci.internal` | 10.200.0.2 | CI 控制机 |

验收示例：

```bash
dig @10.200.0.1 jms.internal +short
# 期望：10.200.0.1

ping -c 1 jms.internal
# 期望：64 bytes from 10.200.0.1

curl -sk -o /dev/null -w '%{http_code}\n' https://jms.internal/
# 期望：200（JumpServer 已上线；登录须 infra 开通平台账号）
```

修改 `DNS` 或 `AllowedIPs` 后须重载隧道：`sudo wg-quick down wg0 && sudo wg-quick up wg0`（Linux）。

Runbook：`docs/dns/hub-internal-dns.runbook.md`

---

## 五、启动与停止

### Linux

```bash
# 启动
sudo wg-quick up wg0

# 停止
sudo wg-quick down wg0

# 开机自启（可选）
sudo systemctl enable wg-quick@wg0
```

### Windows / macOS

在 WireGuard 客户端中 **激活 / 停用** 隧道。

---

## 六、验收（必做）

连接成功后，按操作系统执行下列检查。

### 6.1 查看隧道状态

**Linux / macOS：**

```bash
sudo wg show wg0
```

**通过标准：**

- 出现 **`latest handshake: xx seconds ago`**（1～2 分钟内）
- `transfer` 中 **received** 大于 0（不全是 0 B received）

若只有 `sent`、无 `received`、无 handshake → 见 [第八节 常见问题](#八常见问题)。

### 6.2 连通性测试

```bash
ping -c 4 10.200.0.1
ping -c 4 10.200.0.2
```

两条均应 **0% 丢包**（延迟通常几毫秒～几十毫秒）。

### 6.3 内网 DNS 与 JumpServer（推荐）

```bash
ping -c 2 jms.internal
curl -sk -o /dev/null -w '%{http_code}\n' https://jms.internal/
```

- `ping` 应解析到 `10.200.0.1` 且可达
- `curl` 应返回 **200**（表示经 WG 可访问 Hub 上 JumpServer 反代）

登录 JumpServer Web 须 infra 已开通账号；仅 HTTP 200 不代表已有登录权限。

### 6.4 SSH 登录（若 infra 已发放 SSH 密钥）

```bash
chmod 600 ~/.ssh/infra-ci-deploy
ssh -i ~/.ssh/infra-ci-deploy deploy@10.200.0.1 hostname
```

成功则输出 Hub 主机名（如 `iZbp13...`）。

访问 **CI / Dev 同机** 示例：

```bash
ssh -i ~/.ssh/infra-ci-deploy deploy@10.200.0.2 hostname
```

### 6.5 验收结果反馈

请将以下信息发给 infra（截图或文字均可）：

- `wg show` 中含 `latest handshake` 的截图
- `ping 10.200.0.1` 与 `ping 10.200.0.2` 成功
- `curl -sk https://jms.internal/` 返回 200（可选但推荐）
- 当前公网 IP（可选）：`curl -s ifconfig.me`

---

## 七、日常使用

| 场景 | 操作 |
|------|------|
| 开始办公 | 激活 WireGuard 隧道 |
| 结束办公 | 停用隧道（可选，视安全策略） |
| 更换 Wi-Fi / 宽带 | 一般 **无需改配置**；若长期无法 handshake，联系 infra |
| 访问 Dev 应用 | 先连 WG，再访问 `10.200.0.2:8080` 或未来内网域名 |
| 访问 JumpServer | 先连 WG，浏览器打开 `https://jms.internal/` |
| 同时使用 Clash Verge 翻墙 | 须配置 bypass 规则，见 [Clash Verge 与 WG/SSH 共存指南](./clash-verge-wg-ssh-bypass.md) |

**注意**：未连接 WG 时，无法访问 `10.200.x.x` 内网地址。

---

## 八、常见问题

### Q1：`transfer: 0 B received`，没有 `latest handshake`

**含义**：本机已发包，Hub 未回应，隧道未建立。

**常见原因与处理：**

| 原因 | 处理 |
|------|------|
| Hub 安全组未放行你的出口 IP（历史情况） | 联系 infra；家庭网络 IP 变动时 infra 可能已改为 UDP 51820 对公网开放 |
| 私钥与 Hub 登记公钥不匹配 | 确认使用的是 infra **本次分配**的私钥，不要自己重新 `wg genkey` 后不告知 infra |
| 本地防火墙拦截 UDP 出站 | 关闭或放行 WireGuard / UDP 出站 |
| Hub Endpoint 写错 | 确认为 `121.43.49.58:51820` |
| **Clash Verge 等代理客户端抢占路由** | 按 [Clash Verge 与 WG/SSH 共存指南](./clash-verge-wg-ssh-bypass.md) 配置 DIRECT 与 TUN 排除；或临时关闭 TUN |

自检公网 IP：

```bash
curl -s ifconfig.me
```

将结果告知 infra 以便核对安全组。

### Q2：ping 不通 10.200.0.1，但 handshake 正常

- 检查 `AllowedIPs` 是否包含 `10.200.0.0/24`（开发角色完整值为三段：`.0` / `.1` / `.2` 网段）
- 确认配置含 `DNS = 10.200.0.1`（访问 `jms.internal` 需要）
- 联系 infra 检查 Hub / 对端路由

### Q3：SSH `Permission denied`

- WireGuard 与 SSH 是两套密钥；WG 只解决「能到达内网」
- 确认 infra 是否已发放 `infra-ci-deploy` 私钥，且用户为 `deploy`

### Q4：能否自己改 `AllowedIPs` 访问更多网段？

**不要**自行添加 `10.200.3.0/24`（生产网段）或其他未授权网段；需变更请联系 infra。

### Q5：同时使用 Clash Verge，WG 或 SSH 异常

**含义**：跨境代理（尤其 **TUN 模式**）可能拦截 WireGuard UDP 或内网 `10.200.x.x` 流量。

**处理**：按 **[Clash Verge 与 WG/SSH 共存指南](./clash-verge-wg-ssh-bypass.md)** 添加前置 DIRECT 规则与 Merge 配置。快速自检：Clash 日志中 `121.43.49.58` 须为 `DIRECT`。

### Q6：笔记本丢失或私钥泄露

**立即联系 infra**：吊销对应 Peer、轮换密钥、重新 apply Hub 配置。

---

## 九、安全须知

1. **私钥（PrivateKey）** 仅保存在你的笔记本，勿上传 Git、网盘、聊天工具。
2. **一人一对密钥**，不要与同事共用配置文件。
3. 丢失设备或怀疑泄露时，**第一时间**报告 infra。
4. 公司设备建议启用磁盘加密与屏幕锁。
5. 仅在需要访问内网时开启 WG，降低暴露面。

---

## 十、infra 同事：为新成员开通 Peer（内部）

> 本节供运维分发文档时参考；普通接入用户可跳过。

1. 在 **ci-01** 上从台账分配 `10.200.10.x`（[wireguard-clients.yaml](../assets/wireguard-clients.yaml) → `client_pool` `10.200.10.0/24`）。
2. 生成密钥并登记 Hub（单人或批量）：

   ```bash
   cd ~/infra-ops
   # 单人
   ./scripts/wireguard/wg-keys.sh generate-peer <peer-name>
   # 或批量（跳过已有公钥）
   ./scripts/wireguard/generate-team-laptop-peers.sh
   ./scripts/wireguard/wg-keys.sh sync-inventory
   export ANSIBLE_VAULT_PASSWORD_FILE=~/infra-ops/.vault_pass
   ansible-playbook ansible/playbooks/wireguard-hub.yml \
     -i ansible/inventories/mgmt/ --limit hub-01 \
     --vault-password-file .vault_pass
   ```

3. 执行 `./scripts/wireguard/render-laptop-conf.sh <peer-name> /tmp/wg0.conf`，经 **安全渠道** 发送给同事（勿通过普通聊天工具发私钥）。
4. 家庭宽带无固定 IP 时，Hub 安全组 UDP **51820** 可对 `0.0.0.0/0` 放行（仅 WG 端口；SSH 仍限源）。详见 `stage-f-console-checklist.md`。
5. 用户验收通过后，更新 [wireguard-clients.yaml](../assets/wireguard-clients.yaml) 与 [F6 验收记录](../acceptance/20260616-阶段F6-WireGuard人员Client池验收.md)。

---

## 附录：相关链接

| 资源 | 路径 |
|------|------|
| 人员台账 | [wireguard-clients.yaml](../assets/wireguard-clients.yaml) |
| F6 验收报告 | [20260616-阶段F6-WireGuard人员Client池验收.md](../acceptance/20260616-阶段F6-WireGuard人员Client池验收.md) |
| 开发环境总览 | [开发环境介绍-业务部署指南.md](../dev/开发环境介绍-业务部署指南.md) |
| 配置模板（运维） | `ansible/keys/wireguard/laptop-zhengyaoyuan.conf.example` |
| 配置模板（开发） | `ansible/keys/wireguard/laptop-client-dev.conf.example` |
| 运维简版 | [`developer-laptop-client.md`](developer-laptop-client.md) |
| Clash Verge 共存配置 | [clash-verge-wg-ssh-bypass.md](./clash-verge-wg-ssh-bypass.md) |
| Hub 公钥文件 | `ansible/keys/wireguard/hub.pub` |
| WireGuard 官方安装 | https://www.wireguard.com/install/ |

---

**文档结束。** 接入问题请联系 infra 团队，并提供第六节要求的验收信息。
