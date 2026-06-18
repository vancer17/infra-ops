# 资产台账（Asset Registry）

本目录记录 **阿里云 ECS 及相关云资源的结构化台账**，是运维、安全组、Inventory、WireGuard 规划的**人工权威来源（Human SSOT）**。

## 设计原则

| 原则 | 说明 |
|------|------|
| **一处登记、多处引用** | 主机级细节在 `docs/assets/<host>.yaml`；总览与角色映射在 `registry.yaml` |
| **与 Ansible 对齐** | `inventories/dev/`、`inventories/mgmt/` 的 `network.yml` 须与本目录 IP、WG、bootstrap_status 一致 |
| **与安全组对齐** | `docs/security-groups/*.rules.yaml` 中的源 IP 须与 `security_whitelist` / 各主机 `access_whitelist` 一致 |
| **原规划 vs 当前现实** | 企业方案中的 10 台规划 IP 可能不可用；`registry.yaml` 的 `replacements` 记录**谁替代谁** |
| **控制台变更必须回写** | 在阿里云改了 IP、安全组、实例规格后，先更新本目录，再改 Inventory |

## 文件索引

| 文件 | 内容 |
|------|------|
| [registry.yaml](./registry.yaml) | **总台账**：全部可用/不可用机器、VPC 拓扑、角色分配、WG IP 规划、替代关系 |
| [wireguard-clients.yaml](./wireguard-clients.yaml) | **人员 WG Client 池**（`10.200.10.0/24`，五人 Peer） |
| [hub-01.yaml](./hub-01.yaml) | 临时 Hub / WG Server（原 `47.97.19.58` 不可用后的替代） |
| [ci-01.yaml](./ci-01.yaml) | 临时 CI / Ansible 控制机（原 `47.98.161.33` 不可用后的替代） |
| [dev-01.yaml](./dev-01.yaml) | Dev 主应用节点（与 ci-01 **同机**，见 registry） |
| [dev-02.yaml](./dev-02.yaml) | Dev Worker 替代节点（原 `121.40.245.68` 不可用后的替代） |
| [test-01.yaml](./test-01.yaml) | Test 预留节点（本期 WG 可选纳入） |
| [RDS MySQL 实例现状与 Dev 规划](../rds/20260615-RDS-MySQL-实例现状与Dev规划.md) | **云数据库**：实例规格、已有库表、连接地址、白名单、Dev 规划 |
| [OSS 实例现状与 Dev 规划](../oss/20260616-OSS-实例现状与Dev规划.md) | **对象存储**：Bucket 现状、RAM/前缀规划、阶段 H 验收清单 |
| [阶段 G RDS 验收](../acceptance/20260615-阶段G-Dev-RDS-app_dev验收.md) | `app_dev` 内网连通与 prod 隔离验收 |
| [阶段 G5 Hub 资产纳管验收](../acceptance/20260617-阶段G5-JumpServer资产纳管-Hub验收.md) | JumpServer Hub-01 `jump_ops` + 账号推送 |
| [阶段 G5 Dev 资产纳管验收](../acceptance/20260618-阶段G5-JumpServer资产纳管-Dev验收.md) | JumpServer Dev-01（CI-DEV-01）`jump_ops` + Web 终端 |
| [阶段 3 Dev 业务 Nginx 验收](../acceptance/20260616-阶段3-Dev业务Nginx与占位API验收.md) | dev-01 占位 API + 宿主机 Nginx（历史 host 模式） |
| [阶段 4 Dev Gateway Compose 验收](../acceptance/20260617-阶段4-Dev-Gateway-Compose-LE验收.md) | Compose LE 网关 + Docker 网段修复 + 微信 TLS |
| [Dev Gateway Runbook](../docker/dev-gateway.runbook.md) | `gateway-compose.yml` / Compose 运维 |
| [Dev 业务 Nginx Runbook](../nginx/dev-nginx.runbook.md) | 业务出口总览（Compose 当前 / host 历史） |
| [阶段 F6 WG Client 池验收](../acceptance/20260616-阶段F6-WireGuard人员Client池验收.md) | 五人笔记本 Hub 登记 + zhengyaoyuan Client 验收 |

## 与 Inventory 的分工

```
docs/assets/*.yaml          ← 人工台账（含实例 ID、控制台名称、备注）
        │ 同步 IP / 角色 / WG
        ▼
network.yml (group_vars)    ← Ansible 运行时 SSOT（dev_hosts / mgmt_hosts / platform_hosts）
        │ Jinja2 计算
        ▼
host_vars/*.yml             ← 每台主机的 ansible_host 表达式
```

- **dev** 应用节点：`ansible/inventories/dev/`（dev-01、dev-02）
- **mgmt** 管理面：`ansible/inventories/mgmt/`（hub-01）
- ci-01 与 dev-01 同机：mgmt `wireguard_peers` 组管理 ci-01 WG Client；dev inventory 管 dev-01 应用

## Bootstrap / 数据层 / 业务层进度（2026-06-18）

| 主机 / 资源 | 状态 | 备注 |
|-------------|------|------|
| ci-01 / dev-01 | `ssh_done` | WG operational；RDS + PetIntelli + Compose LE 网关；**G5 Dev 堡垒机纳管 onboarded** |
| hub-01 | `ssh_done` | WG Server operational；G4 JumpServer + G5 Hub 资产纳管 onboarded；F6 Client 池 Hub 已登记 |
| WG Client 池 | `hub_registered` | zhengyaoyuan operational；四人待 Client 握手（见 wireguard-clients.yaml） |
| dev-02 | `pending` | RDS 白名单 pending_bootstrap |
| test-01 | `pending` | 未纳入 |
| RDS `app_dev` | **operational** | 内网 host；见 [阶段 G 验收](../acceptance/20260615-阶段G-Dev-RDS-app_dev验收.md) |
| dev-01 业务网关 | **operational（compose）** | LE + `backend.jxqydw.com`；见 [阶段 4 验收](../acceptance/20260617-阶段4-Dev-Gateway-Compose-LE验收.md) |
| dev-01 应用 | **operational** | `petintelli-backend` @ 8080 |

## 维护流程

1. 阿里云控制台确认：公网 IP、私网 IP、实例 ID、安全组 ID、可用区。
2. 更新对应 `docs/assets/<host>.yaml` 与 `registry.yaml`。
3. 同步 `ansible/inventories/dev/group_vars/all/network.yml` 与（Hub 时）`ansible/inventories/mgmt/group_vars/all/network.yml`。
4. 若涉及 SSH 白名单：同步 `docs/security-groups/*-bootstrap.rules.yaml`。
5. 本地执行 `make inventory` / `make inventory-mgmt` 与 `make ci`。

## WireGuard / 网络阶段（2026-06-14）

见 `registry.yaml` → **`network_phase: wireguard`**。

| 项 | 当前状态 |
|----|----------|
| **Hub↔ci-01 隧道** | `wireguard.status: operational`（F1 Server + F2 Client 握手已验收） |
| **Ansible 连 Hub** | mgmt `access_mode: wireguard` → `ansible_host` = **`10.200.0.1`**（**已验收**，`logs/console-check.log`） |
| **F3-1 自动化** | **已通过**（`make stage-f-preflight`、`secret-scan`；`logs/console-acceptance.log`） |
| **GitHub VAULT** | **`ANSIBLE_VAULT_PASSWORD` 已配**（dev Environment）；`wireguard-hub.yml --check --diff` 通过 |
| **Dev inventory** | `ci_access_mode: wireguard`（阶段标记）；dev-01 同机仍用 VPC 私网 |
| **GitHub Runner** | 可选；见 `ci-01.yaml` → `github_runner.status` |
| **下一里程碑** | 四人 `wg0.conf` 分发与握手；JumpServer **平台授权/MFA**；删 JMS 多余 `deploy`；`network_phase: steady` |

- **同一 VPC**：4 台可用 ECS 均在 `vpc-bp1jmugctnhj97dbjyx31`（杭州）。
- **CI 与 Dev-01 同机**：访问 dev-01 仍等价于本机私网 `172.21.226.38`；连 Hub 走 WG `10.200.0.1`。
- **验收日志**：F2 隧道 + F3-1 `logs/console-acceptance.log`；F2-5 收口 `logs/console-check.log`。
- **验收报告**：[阶段 F WireGuard](../acceptance/20260614-阶段F-WireGuard验收报告.md)、[阶段 F6 Client 池](../acceptance/20260616-阶段F6-WireGuard人员Client池验收.md)、[阶段 G RDS `app_dev`](../acceptance/20260615-阶段G-Dev-RDS-app_dev验收.md)、[阶段 G5 Hub 资产纳管](../acceptance/20260617-阶段G5-JumpServer资产纳管-Hub验收.md)、[阶段 G5 Dev 资产纳管](../acceptance/20260618-阶段G5-JumpServer资产纳管-Dev验收.md)、[阶段 3 Dev 业务 Nginx](../acceptance/20260616-阶段3-Dev业务Nginx与占位API验收.md)

## 相关文档

- [RDS MySQL 实例现状与 Dev 规划](../rds/20260615-RDS-MySQL-实例现状与Dev规划.md)
- [安全组策略](../security-groups/README.md)
- [Dev Bootstrap Runbook](../bootstrap/dev-01-bootstrap.runbook.md)
- [Hub Bootstrap Runbook](../bootstrap/hub-01-bootstrap.runbook.md)（hub-01：`ssh_done`，2026-06-14）
- [WireGuard F3 验收](../wireguard/stage-f3-acceptance-runbook.md)
- [WireGuard F2-5 收口](../wireguard/stage-f2-5-runbook.md)
- [办公笔记本 WG Client 接入指南（分发给同事）](../wireguard/办公笔记本-WG-Client-接入指南.md)
- [人员笔记本 WG 台账（wireguard-clients.yaml）](wireguard-clients.yaml)
- [运维笔记本 WG Client（简版）](../wireguard/developer-laptop-client.md)
- [企业环境实施方案](../20260608-ECS%20企业环境实施方案.md) §4 网络与 WireGuard
