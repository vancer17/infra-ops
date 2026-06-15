# 阶段 F — WireGuard 最小组网验收报告

**验收日期**：2026-06-14  
**控制机**：ci-01（yax，`121.41.58.20` / `10.200.0.2`）  
**验收人**：infra-ops  
**分支**：`feat/wireguard-stage-e-keys`（及后续合并分支）

---

## 一、验收范围

| 子阶段 | 内容 | 状态 |
|--------|------|------|
| **F1** | Hub-01 WireGuard Server（`wireguard-hub.yml`） | 通过 |
| **F2** | ci-01 WireGuard Client（`wireguard-peer.yml`）+ Hub↔CI 握手 | 通过 |
| **F2-5** | `access_mode: wireguard`；Ansible 经 `10.200.0.1` 连 Hub | 通过 |
| **F3-1** | 自动化检查（`stage-f-preflight`、`inventory-mgmt`、`secret-scan`） | 通过 |

**不在本期验收范围**：JumpServer、关公网 SSH（`network_phase: steady`）、GitHub Self-hosted Runner 注册、运维笔记本 Client 实机接入、dev-02/test-01 纳入 WG。

---

## 二、拓扑与 Peer 模型

```
运维笔记本（可选，10.200.10.1）──┐
                                  │ UDP 51820
ci-01 / yax（10.200.0.2）─────────┼──→ Hub-01（10.200.0.1）
                                  │      121.43.49.58:51820
                                  └── WG Server（唯一监听 51820）
```

**Peer 模型（方案 A）**：ci-01 与 dev-01 同 ECS，Hub `wg0.conf` 仅登记 **ci-01**（`10.200.0.2/32`），不单独建 dev-01 Peer。见 `wireguard_peer_model.decision: single_peer_ci_01`。

---

## 三、实机验收（F2）

**日志**：`logs/console-acceptance.log`（ci-01 上）

| # | 检查项 | 命令/现象 | 结果 |
|---|--------|-----------|------|
| 1 | ci-01 wg0 握手 | `sudo wg show wg0` → latest handshake 数十秒内 | OK |
| 2 | 经 WG ping Hub | `ping -c 4 10.200.0.1` → 0% 丢包，~2.3ms | OK |
| 3 | 经 WG SSH Hub | `ssh deploy@10.200.0.1` → hostname `iZbp13i3ed90ieamwrb4kbZ` | OK |
| 4 | Hub 见 ci-01 Peer | Hub `wg show` → endpoint `121.41.58.20:36969`，有 handshake | OK |
| 5 | ci-01 路由 | `10.200.0.0/16 dev wg0` | OK |
| 6 | developer-laptop Peer | Hub 已登记公钥，**无 handshake**（笔记本未接入） | 预期 |

---

## 四、F2-5 收口验收

**日志**：`logs/console-check.log`

| # | 检查项 | 结果 |
|---|--------|------|
| 1 | `wireguard.status` | `operational` |
| 2 | `ci_connectivity.access_mode` | `wireguard` |
| 3 | `network_phase` | `wireguard` |
| 4 | hub-01 `ansible_host` | `10.200.0.1` |
| 5 | `ansible ping hub-01` | success |

---

## 五、F3-1 自动化验收

**日志**：`logs/console-acceptance.log`（`make stage-f-preflight` 及后续）

| # | 检查项 | 结果 |
|---|--------|------|
| 1 | `make inventory-mgmt` | OK（hub-01 + wireguard_peers/ci-01） |
| 2 | `wg-keys verify-hub` / `verify-peer ci-01` | OK |
| 3 | ci-01 `ci-01.private` 在控制机 | OK |
| 4 | `deploy-wireguard` limited sudo | OK |
| 5 | `vault-view`（`.vault_pass`） | OK |
| 6 | `make secret-scan`（gitleaks） | no leaks found |
| 7 | `stage-f-preflight` 总结 | `[stage-f-preflight] OK` |

**说明**：步骤 6/7 中 UDP 51820 probe 为 **SKIP**（未加 `--probe-udp`）；隧道已 handshake，UDP 路径实际可用。控制台规则仍以 [stage-f-console-checklist.md](../wireguard/stage-f-console-checklist.md) 为准。

---

## 六、Inventory / 台账对齐

| 文件 | 关键字段 |
|------|----------|
| `wireguard.yml` | `enabled: true`，`status: operational` |
| `network.yml` (mgmt) | `access_mode: wireguard` |
| `main.yml` (mgmt) | `network_phase: wireguard` |
| `registry.yaml` | `network_phase: wireguard` |
| `hub-01.yaml` | `wireguard_status: operational`，`wireguard_server_status: installed` |
| `ci-01.yaml` | `wireguard_status: operational`，`wireguard_client` 验收块 |

---

## 七、已知限制与后续项

| 项 | 说明 | 优先级 |
|----|------|--------|
| 公网 SSH 仍开放 | Bootstrap 安全组未收口；`network_phase` 仍为 `wireguard` 非 `steady` | 二期 |
| Hub 与 Dev 共用 `sg-bp122tjy3h95um8kv4f9` | 仅 Hub 应监听 51820；建议迁移 `sg-hub-wg` | 二期 |
| GitHub Runner | `runner_status: not_registered` | 握手后可选 |
| `ANSIBLE_VAULT_PASSWORD` | 手工 playbook 用 `.vault_pass`；`deploy.yml` 前须配 Secret | 上 Runner 前 |
| developer-laptop | Hub 已登记 Peer，笔记本 Client 未配置 | 可选 |
| dev-02 Bootstrap + WG | `bootstrap_status: pending` | 后续 |
| 应用层（dev-app） | 待业务栈确定 | 后续 |

---

## 八、相关文档

- [stage-f3-acceptance-runbook.md](../wireguard/stage-f3-acceptance-runbook.md) — F3-1 命令清单
- [stage-f2-5-runbook.md](../wireguard/stage-f2-5-runbook.md) — F2-5 收口
- [wg-keys.runbook.md](../wireguard/wg-keys.runbook.md) — 阶段 E 密钥
- [hub-01-bootstrap.runbook.md](../bootstrap/hub-01-bootstrap.runbook.md) — 阶段 C
- [资产总台账](../assets/registry.yaml)

---

## 九、签署

| 角色 | 结论 |
|------|------|
| 阶段 F 最小组网（Hub + ci-01） | **验收通过** |
| 可进入下一阶段 | JumpServer 规划 / dev-02 Bootstrap / 应用部署（业务栈确定后） |
