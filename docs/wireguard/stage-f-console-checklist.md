# Hub / Dev 共用安全组 — UDP 51820 控制台核对

> **状态（2026-06-14）**：阶段 F 已完成，Hub↔ci-01 隧道 `operational`。本文档保留作安全组审计与 steady 阶段迁移参考。

## 为何共用 id 有影响

Hub-01、dev-01、dev-02 当前均绑定 **`sg-bp122tjy3h95um8kv4f9`（sg-dev-ecs-bootstrap）**。

阿里云安全组规则按**绑定实例**生效，因此：

- `IN-WG-UDP-*`（UDP 51820）会对**所有**绑定该组的 ECS 开放入站，不仅是 Hub。
- **仅 Hub 应运行 `wg listen 51820`**；Dev 实例勿安装 WG Server。
- steady 阶段建议 Hub 迁移独立 **`sg-hub-wg`**（见 `hub-01.yaml` security_groups.target）。

## 控制台核对（人工）

在阿里云 ECS → 安全组 `sg-bp122tjy3h95um8kv4f9` 确认已存在：

| 规则 id | 协议 | 端口 | 源 | 用途 |
|---------|------|------|-----|------|
| IN-WG-UDP-OFFICE | UDP | 51820 | 115.195.216.251/32 | 办公网 Peer |
| IN-WG-UDP-CI | UDP | 51820 | 121.41.58.20/32 | ci-01 Peer |

权威定义：[dev-ecs-bootstrap.rules.yaml](../security-groups/dev-ecs-bootstrap.rules.yaml)

**F 阶段验收**：隧道已 handshake（`logs/console-acceptance.log`）；`stage-f-preflight` 默认不跑 UDP probe，实机以 `wg show` 为准。

## 从 ci-01 快速探测（可选）

```bash
# 从 ci-01 向 Hub 公网发 UDP（需安全组已放行 ci 源 IP）
nc -zvu -w 3 121.43.49.58 51820

# 或经隧道验证（推荐）
sudo wg show wg0
ping -c 3 10.200.0.1
```

## 台账字段

`docs/assets/hub-01.yaml` → `wireguard_keys` / `wireguard_server` 已标记 `operational`；`console_udp_51820_verified` 以实机握手为准。
