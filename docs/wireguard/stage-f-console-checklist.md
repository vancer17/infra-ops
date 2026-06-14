# Hub / Dev 共用安全组 — 阶段 F 前控制台核对

## 为何共用 id 有影响

Hub-01、dev-01、dev-02 当前均绑定 **`sg-bp122tjy3h95um8kv4f9`（sg-dev-ecs-bootstrap）**。

阿里云安全组规则按**绑定实例**生效，因此：

- `IN-WG-UDP-*`（UDP 51820）会对**所有**绑定该组的 ECS 开放入站，不仅是 Hub。
- **仅 Hub 应运行 `wg listen 51820`**；Dev 实例勿安装 WG Server。
- 阶段 F 稳定后建议 Hub 迁移独立 **`sg-hub-wg`**（见 `hub-01.yaml` security_groups.target）。

## 阶段 F 前控制台核对（人工）

在阿里云 ECS → 安全组 `sg-bp122tjy3h95um8kv4f9` 确认已存在：

| 规则 id | 协议 | 端口 | 源 | 用途 |
|---------|------|------|-----|------|
| IN-WG-UDP-OFFICE | UDP | 51820 | 115.195.216.251/32 | 办公网 Peer |
| IN-WG-UDP-CI | UDP | 51820 | 121.41.58.20/32 | ci-01 Peer |

权威定义：[dev-ecs-bootstrap.rules.yaml](dev-ecs-bootstrap.rules.yaml)

## 从 ci-01 快速探测（可选）

```bash
# 从 ci-01 向 Hub 公网发 UDP（需安全组已放行 ci 源 IP）
nc -zvu -w 3 121.43.49.58 51820
```

Hub 尚未监听 51820 时可能仍显示 open/refused 因环境而异；**阶段 F apply 后**应能完成 WG handshake。

核对完成后更新 `docs/assets/hub-01.yaml` → `wireguard_keys.pending_stage_f` 中 `console_udp_51820_verified`。
