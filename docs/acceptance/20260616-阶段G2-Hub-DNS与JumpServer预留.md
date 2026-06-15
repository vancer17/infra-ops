# 阶段 G2 验收报告 — Hub 内网 DNS + JumpServer upstream 细化

| 项 | 内容 |
|----|------|
| **日期** | 2026-06-16 |
| **结论** | **验收通过** |
| **范围** | hub-01 dnsmasq、`*.internal` 解析、Nginx `jms.internal` 维护页与 `/jms/status` |
| **Playbook** | `ansible/playbooks/hub-g2.yml` |
| **Runbook** | [docs/dns/hub-internal-dns.runbook.md](../dns/hub-internal-dns.runbook.md) |
| **日志** | [logs/console-acceptance.log](../../logs/console-acceptance.log)（G2 节） |

---

## 一、目标

| 目标 | 说明 | 结果 |
|------|------|------|
| 内网 DNS | Hub `10.200.0.1:53` 解析 `hub.internal`、`jms.internal`、`ci.internal` 等 | 通过 |
| WG Client DNS | ci-01 / 笔记本 `DNS=10.200.0.1` | 通过 |
| JumpServer 预留细化 | `/jms/status` JSON；根路径 503 维护页（非裸 502） | 通过 |

---

## 二、验收项

| # | 项 | 通过标准 | 结果 |
|---|-----|----------|------|
| 1 | 安全组 IN-DNS-WG | UDP 53 ← 10.200.0.0/16 | 通过（dig 跨 WG 成功） |
| 2 | DNS 解析 ci-01 | `dig @10.200.0.1 jms.internal` → `10.200.0.1` | 通过 |
| 3 | DNS 解析 ci-01 | `dig @10.200.0.1 ci.internal` → `10.200.0.2` | 通过 |
| 4 | DNS 解析 ci-01 | `dig @10.200.0.1 hub.internal` → `10.200.0.1` | 通过 |
| 5 | hub 健康 | `curl -k https://hub.internal/health` → `ok` | 通过 |
| 6 | jms/status | JSON `deploy_status: pending` | 通过 |
| 7 | jms 根路径 | `curl -k https://jms.internal/` → **503** | 通过 |
| 8 | WG DNS ci-01 | `grep DNS /etc/wireguard/wg0.conf` → `10.200.0.1` | 通过 |
| 9 | 笔记本 DNS | `dig @10.200.0.1 jms.internal` → `10.200.0.1` | 通过 |
| 10 | 笔记本 jms | `/jms/status` JSON + 根路径 503 | 通过 |
| 11 | inventory | `internal_dns.status=operational` | 通过 |

---

## 三、与 G1 的差异

| 项 | G1 | G2 |
|----|----|----|
| `curl https://jms.internal/` | 502 | **503** 维护页 |
| 域名解析 | 需 `--resolve` 或 `/etc/hosts` | **dig @10.200.0.1** / WG Client DNS |
| `/jms/status` | 无 | **JSON** |

---

## 四、实机记录（2026-06-16）

摘自 `logs/console-acceptance.log`：

**ci-01**

```
dig @10.200.0.1 jms.internal +short   → 10.200.0.1
dig @10.200.0.1 ci.internal +short    → 10.200.0.2
dig @10.200.0.1 hub.internal +short   → 10.200.0.1
curl -k https://hub.internal/health   → ok
curl -k https://jms.internal/jms/status → JSON deploy_status=pending
curl -k https://jms.internal/         → 503
grep DNS /etc/wireguard/wg0.conf      → DNS = 10.200.0.1
```

**办公笔记本（developer-laptop）**

```
dig @10.200.0.1 jms.internal +short   → 10.200.0.1
curl -k https://jms.internal/jms/status → JSON deploy_status=pending
curl -k https://jms.internal/         → 503
```

---

## 五、后续（G3）

- Hub 启用 Docker，部署 JumpServer `127.0.0.1:8080`
- `nginx.jumpserver.deploy_status: ready`，重跑 `hub-g2.yml`
- `curl https://jms.internal/` → JumpServer 登录页（200）
