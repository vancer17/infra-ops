# Dev / Hub ECS 安全组策略

## 阶段对照 — Dev（dev-01 / dev-02）

| 阶段 | 安全组 | SSH 来源 | 应用端口来源 | 公网 22 |
|------|--------|----------|--------------|---------|
| bootstrap | sg-dev-ecs-bootstrap | CI 公网 `121.41.58.20/32` + 公司 IP + CI 私网 `172.21.226.38/32` | 公司 IP + CI 公网 IP | 临时开放 |
| wireguard | sg-dev-ecs-wg | 10.200.0.1 (Hub) / 10.200.0.0/16 | 10.200.1.0/24 + 公司 WG | 关闭 |

## 阶段对照 — Hub（hub-01）

| 阶段 | 安全组 | SSH 来源 | WG UDP 51820 | 公网 22 |
|------|--------|----------|--------------|---------|
| bootstrap | sg-dev-ecs-bootstrap (`sg-bp122tjy3h95um8kv4f9`) | CI 私网 + 公网 + 公司 IP | 可预置（公司 + CI 公网） | 临时开放 |

**2026-06-14**：Hub 控制台当前绑定 **与 Dev 相同** 的安全组 id；UDP 51820 规则以 [dev-ecs-bootstrap.rules.yaml](dev-ecs-bootstrap.rules.yaml) 中 `IN-WG-*` 为准（须在阿里云控制台手动添加）。
| wireguard | sg-hub-wg | 10.200.0.0/16 | 公司 IP + 已知 Peer | 关闭 |

规则文件：[hub-bootstrap.rules.yaml](hub-bootstrap.rules.yaml)

## 维护规则

1. 规则变更必须同步更新 `*-bootstrap.rules.yaml` 与对应主机 `docs/assets/*.yaml`。
2. 禁止在控制台直接改规则而不落库。
3. Dev-01 / Dev-02 / Hub-01 当前共用 `sg-bp122tjy3h95um8kv4f9`（`sg-dev-ecs-bootstrap`）；Hub 专用组为二期可选项。
4. Bootstrap 完成后：`bootstrap_status` 为 `bootstrap_done`（仅 1.2）或 `ssh_done`（含 1.3 steady）。
5. ~~Hub 使用独立 sg-hub-bootstrap~~ → 见上条共用 id 说明。
6. **2026-06-08 起** CI 替代机（`121.41.58.20`）与 Dev/Hub 在**同一 VPC**：Ansible 优先 **私网 IP**。
7. 原 CI `47.98.161.33` 已退役，安全组与 `network.yml` 均不再引用。
8. Inventory：`ansible/inventories/dev/`、`ansible/inventories/mgmt/`。
9. 资产台账：`docs/assets/registry.yaml` 为总览。

## 相关文档

- Hub Bootstrap：[hub-01-bootstrap.runbook.md](../bootstrap/hub-01-bootstrap.runbook.md)
- 部署计划：`docs/plan/20260608-开发环境（Dev）部署计划.md` §1.1
- 企业模板：`docs/20260608-ECS 企业环境实施方案.md` §4.4