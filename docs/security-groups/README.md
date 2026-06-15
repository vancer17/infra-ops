# Dev / Hub ECS 安全组策略

## 阶段对照 — Dev（dev-01 / dev-02）

| 阶段 | 安全组 | SSH 来源 | 应用端口来源 | 公网 22 |
|------|--------|----------|--------------|---------|
| bootstrap | sg-dev-ecs-bootstrap | CI 公网 `121.41.58.20/32` + 公司 IP + CI 私网 `172.21.226.38/32` | 公司 IP + CI 公网 IP | 临时开放 |
| wireguard | sg-dev-ecs-wg | 10.200.0.1 (Hub) / 10.200.0.0/16 | 10.200.1.0/24 + 公司 WG | 关闭 |

## 阶段对照 — Hub（hub-01）

| 阶段 | 安全组 | SSH 来源 | WG UDP 51820 | 80/443 |
|------|--------|----------|--------------|--------|
| bootstrap（历史） | sg-dev-ecs-bootstrap | CI 私网 + 公网 + 公司 IP | 公司 + CI `/32` | — |
| **wireguard / G0（当前）** | **sg-hub-wg** | Workbench + 临时 `/32` +（规划）`10.200.0.0/16` | **`0.0.0.0/0`**（密钥认证） | **443 ← WG**；80 待添加 |

**2026-06-15**：Hub 已切换为**独占规则集**（[hub-wg.rules.yaml](hub-wg.rules.yaml)），验收见 [阶段 G0 报告](../acceptance/20260615-阶段G0-Hub安全组与Nginx前置验收.md)。控制台 id：`sg-bp122tjy3h95um8kv4f9`（与历史 bootstrap 共用 id 时，以实例绑定与规则内容为准）。

**家用动态 IP**：UDP 51820 对 `0.0.0.0/0` 开放；**禁止**对公网开放 TCP 22/80/443。当前家用 SSH 临时 `/32`：`125.121.146.255`。

**共用安全组注意**：Dev/ci 实例**不应**再绑定 Hub 独占规则集；仅 hub-01 运行 WG Server。

规则文件：

- Hub 当前：[hub-wg.rules.yaml](hub-wg.rules.yaml)
- Hub 历史 bootstrap：[hub-bootstrap.rules.yaml](hub-bootstrap.rules.yaml)
- Dev bootstrap：[dev-ecs-bootstrap.rules.yaml](dev-ecs-bootstrap.rules.yaml)

## 维护规则

1. 规则变更必须同步更新 `*-bootstrap.rules.yaml` / `hub-wg.rules.yaml` 与对应主机 `docs/assets/*.yaml`。
2. 禁止在控制台直接改规则而不落库。
3. **2026-06-15 起** hub-01 使用 [hub-wg.rules.yaml](hub-wg.rules.yaml)；Dev 仍用 [dev-ecs-bootstrap.rules.yaml](dev-ecs-bootstrap.rules.yaml)（勿与 Hub 规则混绑）。
4. Bootstrap 完成后：`bootstrap_status` 为 `bootstrap_done`（仅 1.2）或 `ssh_done`（含 1.3 steady）。
5. **2026-06-08 起** CI 替代机（`121.41.58.20`）与 Dev/Hub 在**同一 VPC**：Ansible 优先 **私网 IP**；Hub Ansible 经 WG `10.200.0.1`。
6. 原 CI `47.98.161.33` 已退役，安全组与 `network.yml` 均不再引用。
7. Inventory：`ansible/inventories/dev/`、`ansible/inventories/mgmt/`。
8. 资产台账：`docs/assets/registry.yaml` 为总览。

## 相关文档

- Hub Bootstrap：[hub-01-bootstrap.runbook.md](../bootstrap/hub-01-bootstrap.runbook.md)
- 部署计划：`docs/plan/20260608-开发环境（Dev）部署计划.md` §1.1
- 企业模板：`docs/20260608-ECS 企业环境实施方案.md` §4.4
