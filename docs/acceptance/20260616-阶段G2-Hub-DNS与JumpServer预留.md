# 阶段 G2 验收报告 — Hub 内网 DNS + JumpServer upstream 细化

| 项 | 内容 |
|----|------|
| **日期** | 2026-06-16 |
| **范围** | hub-01 dnsmasq、`*.internal` 解析、Nginx `jms.internal` 维护页与 `/jms/status` |
| **Playbook** | `ansible/playbooks/hub-g2.yml` |
| **Runbook** | [docs/dns/hub-internal-dns.runbook.md](../dns/hub-internal-dns.runbook.md) |
| **日志** | `logs/console-acceptance.log`（G2 节，apply 后填写） |

---

## 一、目标

| 目标 | 说明 |
|------|------|
| 内网 DNS | Hub `10.200.0.1:53` 解析 `hub.internal`、`jms.internal`、`ci.internal` 等 |
| WG Client DNS | ci-01 / 笔记本 `DNS=10.200.0.1` |
| JumpServer 预留细化 | `/jms/status` JSON；根路径 503 维护页（非裸 502） |

---

## 二、验收项

| # | 项 | 命令 / 方法 | 通过标准 |
|---|-----|-------------|----------|
| 1 | 安全组 | 控制台 IN-DNS-WG | UDP 53 ← 10.200.0.0/16 |
| 2 | dnsmasq | Hub `systemctl is-active dnsmasq` | active |
| 3 | DNS 解析 | `dig @10.200.0.1 jms.internal +short` | `10.200.0.1` |
| 4 | ci.internal | `dig @10.200.0.1 ci.internal +short` | `10.200.0.2` |
| 5 | jms/status | `curl -k https://jms.internal/jms/status` | HTTP 200，JSON `deploy_status: pending` |
| 6 | jms 根路径 | `curl -k -o /dev/null -w '%{http_code}\n' https://jms.internal/` | **503**（JumpServer 未部署） |
| 7 | hub 导航 | `curl -k https://hub.internal/health` | `ok` |
| 8 | WG DNS ci-01 | `resolvectl dns wg0` 或 `grep DNS /etc/wireguard/wg0.conf` | `10.200.0.1` |
| 9 | inventory | `make inventory-mgmt` | 绿；`internal_dns.status=operational` |
| 10 | 静态 | `make ci` | 绿 |

---

## 三、与 G1 的差异

| 项 | G1 | G2 |
|----|----|----|
| `curl https://jms.internal/` | 502 | **503** 维护页 |
| 域名解析 | 需 `--resolve` 或 `/etc/hosts` | **dig @10.200.0.1** |
| `/jms/status` | 无 | **JSON** |

---

## 四、后续（G3）

- Hub 启用 Docker，部署 JumpServer `127.0.0.1:8080`
- `nginx.jumpserver.deploy_status: ready`，重跑 `hub-g2.yml`
- `curl https://jms.internal/` → JumpServer 登录页（200）

---

## 五、实机记录（apply 后填写）

```
# CI 机
dig @10.200.0.1 jms.internal +short
curl -k https://jms.internal/jms/status
curl -k -w "%{http_code}\n" -o /dev/null https://jms.internal/

# 笔记本
dig @10.200.0.1 hub.internal +short
curl -k https://jms.internal/jms/status
```
