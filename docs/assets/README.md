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
| [hub-01.yaml](./hub-01.yaml) | 临时 Hub / WG Server（原 `47.97.19.58` 不可用后的替代） |
| [ci-01.yaml](./ci-01.yaml) | 临时 CI / Ansible 控制机（原 `47.98.161.33` 不可用后的替代） |
| [dev-01.yaml](./dev-01.yaml) | Dev 主应用节点（与 ci-01 **同机**，见 registry） |
| [dev-02.yaml](./dev-02.yaml) | Dev Worker 替代节点（原 `121.40.245.68` 不可用后的替代） |
| [test-01.yaml](./test-01.yaml) | Test 预留节点（本期 WG 可选纳入） |

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
- ci-01 与 dev-01 同机，不在 mgmt hosts 列表中（见 `control_plane_hosts`）

## Bootstrap 进度（2026-06-14）

| 主机 | bootstrap_status | Inventory |
|------|------------------|-----------|
| ci-01 / dev-01 | `bootstrap_done` | dev / 同机 |
| hub-01 | `ssh_done` | mgmt |
| dev-02 | `pending` | dev |
| test-01 | `pending` | 未纳入 |

## 维护流程

1. 阿里云控制台确认：公网 IP、私网 IP、实例 ID、安全组 ID、可用区。
2. 更新对应 `docs/assets/<host>.yaml` 与 `registry.yaml`。
3. 同步 `ansible/inventories/dev/group_vars/all/network.yml` 与（Hub 时）`ansible/inventories/mgmt/group_vars/all/network.yml`。
4. 若涉及 SSH 白名单：同步 `docs/security-groups/*-bootstrap.rules.yaml`。
5. 本地执行 `make inventory` / `make inventory-mgmt` 与 `make ci`。

## 当前网络阶段

见 `registry.yaml` → `network_phase: bootstrap`。

- **同一 VPC**：4 台可用 ECS 均在 `vpc-bp1jmugctnhj97dbjyx31`（杭州）。
- **CI 替代机与 Dev-01 同机**：Ansible 从 `121.41.58.20` 部署时，访问 dev-01 等价于 SSH 本机私网地址。
- **WireGuard**：地址已规划（`10.200.x.x`），隧道**尚未实施**；`ci_access_mode` 仍为 `public`（Bootstrap 期公网 SSH）。

## 相关文档

- [安全组策略](../security-groups/README.md)
- [Dev Bootstrap Runbook](../bootstrap/dev-01-bootstrap.runbook.md)
- [Hub Bootstrap Runbook](../bootstrap/hub-01-bootstrap.runbook.md)（hub-01：`ssh_done`，2026-06-14）
- [企业环境实施方案](../20260608-ECS%20企业环境实施方案.md) §4 网络与 WireGuard
