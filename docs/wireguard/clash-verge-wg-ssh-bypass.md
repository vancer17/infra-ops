# Clash Verge 与 WireGuard / SSH 共存配置指南

| 项 | 说明 |
|----|------|
| **适用对象** | 办公笔记本同时使用 **Clash Verge**（跨境访问）与 **公司 WireGuard**（Dev 内网）的同事 |
| **文档版本** | 2026-06-16 |
| **维护** | infra / 运维团队 |
| **前置阅读** | [办公笔记本 WG Client 接入指南](./办公笔记本-WG-Client-接入指南.md) |

---

## 一、为什么需要配置

许多同事使用 **Clash Verge**（Mihomo 内核）访问境外网站。若同时开启 **TUN 模式** 或 **系统代理**，Clash 可能拦截下列流量，导致 WireGuard 或 SSH 异常：

| 流量 | 典型现象 | 原因 |
|------|----------|------|
| WireGuard → Hub UDP | `0 B received`、无 `latest handshake` | WG 握手包被送进代理节点 |
| SSH → `10.200.x.x` | 连接超时或中断 | 内网地址被错误代理 |
| SSH → 公网 `:22` | 会话不稳定 | 代理链路不适合长连接 |
| `*.internal` 解析 | `jms.internal` 无法访问 | DNS 覆写与 Hub dnsmasq 冲突 |

**目标**：在 Clash 中增加 **前置 DIRECT 规则**，并在 TUN 中 **排除内网路由**，使跨境代理不影响公司内网通道。

```text
本机流量
    │
    ├─ WG / SSH / 10.200.x.x ──→ DIRECT（绕过代理）
    │
    └─ 其他流量 ──→ 订阅规则 ──→ 代理节点
```

---

## 二、公司内网相关参数（规则中须使用）

以下值来自 infra 标准配置，写入 Clash 规则时 **请原样使用**（若 infra 变更 Endpoint，以你收到的 `wg0.conf` 为准）：

| 项 | 值 | 用途 |
|----|-----|------|
| Hub 公网 IP | `121.43.49.58` | WG Endpoint |
| Hub UDP 端口 | `51820` | WG 握手 |
| 内网网段 | `10.200.0.0/16` | 覆盖 Hub / CI / Dev / Test |
| Hub 内网 DNS | `10.200.0.1` | 解析 `*.internal` |
| 内网域名后缀 | `internal` | `jms.internal`、`ci.internal` 等 |

开发角色 `AllowedIPs` 仅为 `10.200.0.0/24`、`10.200.1.0/24`、`10.200.2.0/24`，但 Clash 规则建议使用 **`10.200.0.0/16`** 统一排除，避免漏网。

---

## 三、配置总览（三步）

| 步骤 | 位置 | 作用 |
|------|------|------|
| 1 | **编辑规则** → 添加 **前置规则** | 让 WG / SSH / 内网流量走 DIRECT |
| 2 | **Merge 覆写** | TUN 路由排除内网；可选 DNS 策略 |
| 3 | **日志 / 命令行** 验收 | 确认规则生效 |

**关键原则**：

- 规则必须 **前置**（排在订阅规则 **最上面**），不要点「添加后置规则」。
- **推荐启动顺序**：先开 Clash → 再激活 WireGuard → 再 SSH / 访问内网。
- Windows / macOS / Linux 的 **进程名规则不同**（见第五节），IP 与端口规则三端通用。

---

## 四、通用配置代码（Merge 推荐）

在 Clash Verge 中：**配置** → 选中当前订阅 → **编辑** → **Merge**（合并 / 覆写）。

将下列内容粘贴到 Merge 文件（若已有内容，合并 `tun`、`prepend-rules`、`dns` 段，勿重复定义冲突字段）：

```yaml
# merge.yaml — Clash Verge + 公司 WireGuard / SSH  bypass
# 适用：Mihomo 内核（Clash Verge 2.x）

tun:
  enable: true
  stack: system
  auto-route: true
  auto-detect-interface: true
  strict-route: false
  route-exclude-address:
    - 10.200.0.0/16
    - 10.0.0.0/8
    - 172.16.0.0/12
    - 192.168.0.0/16

prepend-rules:
  # WireGuard Hub
  - IP-CIDR,121.43.49.58/32,DIRECT,no-resolve
  - DST-PORT,51820,DIRECT

  # SSH（全平台通用）
  - DST-PORT,22,DIRECT

  # 公司内网（经 WG）
  - IP-CIDR,10.200.0.0/16,DIRECT,no-resolve
  - IP-CIDR,10.200.0.1/32,DIRECT,no-resolve
  - DOMAIN-SUFFIX,internal,DIRECT

  # 进程名规则：按操作系统取消注释对应行（见第五节）
  # Windows
  - PROCESS-NAME,WireGuard.exe,DIRECT
  - PROCESS-NAME,ssh.exe,DIRECT
  # macOS
  # - PROCESS-NAME,WireGuard,DIRECT
  # - PROCESS-NAME,ssh,DIRECT
  # Linux
  # - PROCESS-NAME,wireguard,DIRECT
  # - PROCESS-NAME,wg,DIRECT
  # - PROCESS-NAME,ssh,DIRECT

dns:
  nameserver-policy:
    '+.internal': 10.200.0.1
  fake-ip-filter:
    - '+.internal'
    - '+.lan'
```

保存后 **重新加载** 当前配置。

> **语法说明**：部分 Clash Verge 版本 Merge 使用 `+rules:` 代替 `prepend-rules:`。若保存报错，将 `prepend-rules:` 改为 `+rules:` 后重试；并在 **规则** 页确认 DIRECT 规则位于列表顶部。

### 4.1 最小可用规则（快速试通）

若暂不想改 Merge，仅在 **编辑规则 → 高级** 中粘贴：

```yaml
prepend-rules:
  - IP-CIDR,121.43.49.58/32,DIRECT,no-resolve
  - DST-PORT,51820,DIRECT
  - IP-CIDR,10.200.0.0/16,DIRECT,no-resolve
  - DST-PORT,22,DIRECT
```

仍建议补上第四节完整 Merge 中的 `tun.route-exclude-address`，否则 TUN 模式下 WG 仍可能异常。

---

## 五、分操作系统说明

### 5.1 Windows

#### 界面操作（编辑规则）

路径：**配置** → 当前订阅 → **编辑规则**

对每一条：选择规则类型 → 填写内容 → 代理策略选 **直接连接 (DIRECT)** → 点 **添加前置规则**。

| 顺序 | 规则类型 | 规则内容 |
|------|----------|----------|
| 1 | `IP-CIDR` | `121.43.49.58/32` |
| 2 | `DST-PORT` 或 `PORT` | `51820` |
| 3 | `PROCESS-NAME` | `WireGuard.exe` |
| 4 | `PROCESS-NAME` | `ssh.exe` |
| 5 | `IP-CIDR` | `10.200.0.0/16` |
| 6 | `IP-CIDR` | `10.200.0.1/32` |
| 7 | `DOMAIN-SUFFIX` | `internal` |
| 8 | `DST-PORT` 或 `PORT` | `22` |

也可点 **高级**，直接粘贴第四节 `prepend-rules` 中 Windows 相关段落。

#### 验收（PowerShell）

```powershell
# 先：Clash 已开 → WireGuard 已激活

ping 10.200.0.1
nslookup jms.internal 10.200.0.1
ssh -o ConnectTimeout=5 deploy@10.200.0.2 echo ok
```

在 Clash **日志** 中确认 `121.43.49.58`、`10.200.0.x` 显示为 `DIRECT`。

---

### 5.2 macOS

#### 进程名

| 应用 | `PROCESS-NAME` 建议值 |
|------|----------------------|
| App Store WireGuard | `WireGuard` |
| OpenSSH | `ssh` |

在 Merge 中 **注释掉 Windows 行**，启用 macOS 的 `PROCESS-NAME` 行。

#### 验收（终端）

```bash
# 先：Clash 已开 → WireGuard 已 Activate

ping -c 2 10.200.0.1
dig @10.200.0.1 jms.internal +short    # 期望 10.200.0.1
ssh -o ConnectTimeout=5 deploy@10.200.0.2 hostname
```

若使用命令行 WG（`brew install wireguard-tools`），可额外添加 `PROCESS-NAME,wg,DIRECT`。

---

### 5.3 Linux（Debian / Ubuntu 等）

Linux 内核态 WireGuard **常无独立用户态进程**，因此 **IP-CIDR + DST-PORT 规则比进程名更重要**。进程名规则作为补充。

| 场景 | `PROCESS-NAME` 建议值 |
|------|----------------------|
| OpenSSH 客户端 | `ssh` |
| `wg-quick` / `wg` 命令 | `wg` |
| userspace wireguard-go | `wireguard` |

#### 验收

```bash
# 先：Clash 已开
sudo wg-quick up wg0

sudo wg show wg0          # 应有 latest handshake
ping -c 2 10.200.0.1
ping -c 2 10.200.0.2
dig @10.200.0.1 jms.internal +short
ssh -o ConnectTimeout=5 -i ~/.ssh/infra-ci-deploy deploy@10.200.0.2 hostname
```

---

## 六、Clash Verge 设置建议

在 **设置** 页：

| 选项 | 建议 | 说明 |
|------|------|------|
| 虚拟网卡模式 (TUN) | 开启 | 配合 Merge 中 `route-exclude-address` |
| 系统代理 | 可开启 | 主要影响浏览器等；内网已由规则 DIRECT |
| DNS 覆写 | 可开启 | 配合 Merge 中 `nameserver-policy` 保留 `*.internal` |

---

## 七、验收清单（三端通用）

连接 WG 后逐项确认：

- [ ] `wg show`（或客户端状态）有 **`latest handshake`**，且 **received > 0**
- [ ] `ping 10.200.0.1`、`ping 10.200.0.2` 无丢包
- [ ] `jms.internal` 解析到 `10.200.0.1` 且 HTTPS 可访问（`curl -sk https://jms.internal/` 返回 200）
- [ ] `ssh deploy@10.200.0.x` 可登录（须 infra 已发放密钥）
- [ ] Clash **日志** 中内网 IP 与 Hub 公网 IP 为 **DIRECT**（非代理组名）

---

## 八、常见问题

### Q1：仍无 WG handshake（`0 B received`）

1. 确认 `121.43.49.58` 与 `51820` 规则为 **前置 DIRECT**
2. 确认 Merge 含 `tun.route-exclude-address` 且含 `10.200.0.0/16`
3. 核对 `wg0.conf` 中 `Endpoint` 端口是否为 `51820`（若不同，改规则端口）
4. 临时关闭 TUN，仅保留系统代理，验证 WG 是否恢复

### Q2：handshake 正常但 ping 不通 10.200.x.x

1. 检查 `AllowedIPs` 是否包含对应网段（见 [WG 接入指南](./办公笔记本-WG-Client-接入指南.md)）
2. 确认 Clash 规则含 `IP-CIDR,10.200.0.0/16,DIRECT`
3. 查看 Clash 日志该 IP 是否仍为代理

### Q3：`jms.internal` 解析错误

1. 确认 WG 配置含 `DNS = 10.200.0.1`
2. 确认 Merge 中 `dns.nameserver-policy` 与 `fake-ip-filter` 已配置
3. 手动测试：`nslookup jms.internal 10.200.0.1`（Windows）或 `dig @10.200.0.1 jms.internal`（Linux/macOS）

### Q4：SSH 公网服务器也受影响

`DST-PORT,22,DIRECT` 会使 **所有** SSH 走直连。若你希望仅内网 SSH 直连、公网 SSH 仍走代理，可 **删除** 端口 22 规则，仅保留：

```yaml
- IP-CIDR,10.200.0.0/16,DIRECT,no-resolve
- PROCESS-NAME,ssh.exe,DIRECT    # 或 ssh / ssh.exe 按系统
```

### Q5：订阅更新后规则丢失

规则应写在 **Merge / 编辑规则（前置）** 中，而非直接改订阅 YAML。订阅刷新后 Merge 仍会合并。

### Q6：运维临时兜底

| 方案 | 操作 |
|------|------|
| 关 TUN | 设置 → 关闭虚拟网卡模式；浏览器仍可用系统代理翻墙 |
| 先 WG 后 Clash | 先连 WireGuard，再开 Clash（部分环境更稳定） |
| 分时使用 | 访问内网时关 Clash；跨境时关 WG |

---

## 九、infra 分发说明（内部）

向新同事分发 WG 配置时，若对方使用 Clash Verge，一并发送本文档链接。验收除 [WG 接入指南第六节](./办公笔记本-WG-Client-接入指南.md#六验收必做) 外，可要求对方提供 Clash 日志截图（Hub IP 为 DIRECT）。

---

## 附录：相关链接

| 资源 | 路径 |
|------|------|
| WG 接入指南 | [办公笔记本-WG-Client-接入指南.md](./办公笔记本-WG-Client-接入指南.md) |
| 开发环境网络总览 | [开发环境介绍-业务部署指南.md](../dev/开发环境介绍-业务部署指南.md) |
| 人员 WG 台账 | [wireguard-clients.yaml](../assets/wireguard-clients.yaml) |
| Clash Verge 项目 | https://github.com/clash-verge-rev/clash-verge-rev |
