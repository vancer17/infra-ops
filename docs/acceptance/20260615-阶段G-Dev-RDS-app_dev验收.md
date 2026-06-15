# 阶段 G：Dev RDS（`app_dev`）验收报告

> **验收日期**：2026-06-15  
> **执行位置**：ci-01 / dev-01 同机（`121.41.58.20` / `172.21.226.38`）  
> **原始日志**：`logs/console-acceptance.log`（RDS 段落）  
> **策略**：方案 A — 新建库 `app_dev` + 账号 `app_dev`（utf8mb4，仅单库权限）

---

## 一、验收结论

| 项 | 结果 |
|----|------|
| 总体 | **通过** — Dev MySQL 数据层可用于后续应用接入 |
| 连接地址 | 内网 `rm-bp1wjjf373l7t331v.mysql.rds.aliyuncs.com:3306` |
| 解析 IP（验收时） | `172.20.211.167` |
| 库 / 账号 | `app_dev` / `app_dev` |
| 与 prod 隔离 | `USE yzx`、`USE risk` → Access denied（1044） |

---

## 二、检查项明细

| # | 检查 | 命令/方式 | 结果 |
|---|------|-----------|------|
| 1 | 网络连通 | `nc -zv $RDS_HOST 3306` | succeeded |
| 2 | 登录与库 | `mysql ... SELECT VERSION(); SELECT DATABASE();` | 8.0.28，`app_dev` |
| 3 | 基本查询 | `SELECT 1` | ok |
| 4 | prod 隔离 | `USE yzx` / `USE risk` | Access denied |
| 5 | 读写 DDL | `_infra_smoke` 建表/插入/查询/删除 | 通过 |

---

## 三、台账同步（本验收后须一致）

| 文件 | 变更要点 |
|------|----------|
| `ansible/inventories/dev/group_vars/all/network.yml` | `rds.host` → 内网域名；`rds.status: operational` |
| `docs/assets/registry.yaml` | `shared_cloud_dependencies.rds` |
| `docs/assets/dev-01.yaml` | `dependencies.rds` |
| `docs/rds/20260615-RDS-MySQL-实例现状与Dev规划.md` | §四～§十 更新 |

---

## 四、待办（不阻塞本验收）

| 项 | 说明 |
|----|------|
| GitHub `DB_PASSWORD` | 写入 Environment `dev`（密码不进 Git） |
| `secrets.yml`（vault） | 可选；与 `DB_PASSWORD` 二选一或并存 |
| RDS 外网地址 | 控制台关闭或严格限制（内网已可用） |
| dev-02 白名单 | Bootstrap 后加 `172.21.127.124/32` |
| Schema 迁移 | 等业务栈（Flyway/Liquibase） |

---

## 五、相关文档

- [RDS MySQL 实例现状与 Dev 规划](../rds/20260615-RDS-MySQL-实例现状与Dev规划.md)
- [开发环境部署计划](../plan/20260608-开发环境（Dev）部署计划.md)
