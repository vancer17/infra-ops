# Dev ECS 安全组策略

## 阶段对照

| 阶段 | 安全组 | SSH 来源 | 应用端口来源 | 公网 22 |
|------|--------|----------|--------------|---------|
| bootstrap | sg-dev-ecs-bootstrap | CI 公网 IP + 公司 IP（跨 VPC 不走私网） | 公司 IP + CI 公网 IP（若 Runner 验应用） | 临时开放 |
| wireguard | sg-dev-ecs-wg | 10.200.0.1 (Hub) / 10.200.0.0/16 | 10.200.1.0/24 + 公司 WG | 关闭 |

## 维护规则

1. 规则变更必须同步更新 `dev-ecs-bootstrap.rules.yaml` 与对应主机 `docs/assets/*.yaml`。
2. 禁止在控制台直接改规则而不落库。
3. Dev-01 / Dev-02 共用 `sg-dev-ecs-bootstrap`，不 per-host 建组（减少漂移）。
4. Bootstrap 完成后，`bootstrap_status` 改为 `sg_done`。
5. CI 与 Dev **不在同一 VPC** 时：Ansible/`hosts.yml` 必须使用 Dev **公网 IP**；`IN-SSH-CI-PRIVATE` 不启用。
6. Inventory 入口：`ansible/inventories/dev/`（`inventory/` 为同名 symlink）。
7. CI Runner 需从本机 curl 应用健康检查时，须为 `47.98.161.33/32` 放行 80/443/8080（见 `IN-*-CI` 规则）。

## 相关文档

- 部署计划：`docs/plan/20260608-开发环境（Dev）部署计划.md` §1.1
- 企业模板：`docs/20260608-ECS 企业环境实施方案.md` §4.4