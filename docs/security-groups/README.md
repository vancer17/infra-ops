# Dev ECS 安全组策略

## 阶段对照

| 阶段 | 安全组 | SSH 来源 | 应用端口来源 | 公网 22 |
|------|--------|----------|--------------|---------|
| bootstrap | sg-dev-ecs-bootstrap | CI 公网 `121.41.58.20/32` + 公司 IP +（同 VPC）CI 私网 `172.21.226.38/32` | 公司 IP + CI 公网 IP | 临时开放 |
| wireguard | sg-dev-ecs-wg | 10.200.0.1 (Hub) / 10.200.0.0/16 | 10.200.1.0/24 + 公司 WG | 关闭 |

## 维护规则

1. 规则变更必须同步更新 `dev-ecs-bootstrap.rules.yaml` 与对应主机 `docs/assets/*.yaml`。
2. 禁止在控制台直接改规则而不落库。
3. Dev-01 / Dev-02 共用 `sg-dev-ecs-bootstrap`，不 per-host 建组（减少漂移）。
4. Bootstrap 完成后，`bootstrap_status` 改为 `sg_done`。
5. **2026-06-08 起** CI 替代机（`121.41.58.20`）与 Dev 在**同一 VPC**：Ansible 优先 Dev **私网 IP**；`IN-SSH-CI-PRIVATE` 已启用。
6. 原 CI `47.98.161.33` 已退役，安全组与 `network.yml` 均不再引用。
7. Inventory 入口：`ansible/inventories/dev/`。
8. CI Runner 健康检查须为 `121.41.58.20/32` 放行 80/443/8080（见 `IN-*-CI` 规则）。
9. 资产台账：`docs/assets/registry.yaml` 为总览；变更须同步 `dev-ecs-bootstrap.rules.yaml`。

## 相关文档

- 部署计划：`docs/plan/20260608-开发环境（Dev）部署计划.md` §1.1
- 企业模板：`docs/20260608-ECS 企业环境实施方案.md` §4.4