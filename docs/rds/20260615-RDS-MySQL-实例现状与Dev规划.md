# RDS MySQL 实例现状与 Dev 规划

> **文档性质**：云数据库（RDS）人工权威台账，供 Dev/Test/Prod 分库、白名单、应用连接与后续 Ansible 扩展引用。  
> **归档日期**：2026-06-15（初版）；**2026-06-15 更新**：方案 A `app_dev` 验收通过，台账与 `network.yml` 已同步内网 host。  
> **前提上下文**：阶段 F（WireGuard）已完成；**阶段 G（Dev RDS `app_dev`）实机已验收**；JumpServer 与业务应用尚未开始。  
> **机器可读副本**：`docs/assets/registry.yaml` → `shared_cloud_dependencies.rds`；`ansible/inventories/dev/group_vars/all/network.yml` → `rds` / `rds_whitelist`

---

## 一、文档用途与维护规则

| 原则 | 说明 |
|------|------|
| 控制台变更须回写 | 在阿里云修改白名单、库、账号、连接地址后，同步更新本文档与 `registry.yaml`、`network.yml` |
| ECS 走内网、不走 WG | RDS 白名单填 **ECS VPC 私网 IP**，不填 WireGuard 地址 `10.200.x.x` |
| 应用连内网域名 | Dev ECS 应使用 **内网连接地址**，不使用外网地址（除非临时救急且须收紧白名单） |
| 与 prod 库隔离 | 本实例为多业务共享；Dev 必须 **分库 + 分账号 + 最小权限**，禁止 Dev 账号访问生产库 |

**维护流程**：

1. 阿里云 RDS 控制台确认变更  
2. 更新本文档对应章节  
3. 同步 `docs/assets/registry.yaml`、`ansible/inventories/dev/group_vars/all/network.yml`  
4. 本地执行 `make inventory`

---

## 二、RDS 实例总览

| 项 | 值 |
|----|-----|
| 实例 ID | `rm-bp1wjjf373l7t331v` |
| 实例名称 | `rm-bp1wjjf373l7t331v`（与 ID 相同） |
| 运行状态 | **运行中** |
| 数据库引擎 | **MySQL 8.0** |
| 实例规格 | 通用型，`mysql.n2.large.1` — **4 核 / 8 GB** |
| 最大连接数 | 6000 |
| 最大 IOPS | 4750 |
| 存储类型 | ESSD PL1 云盘，**50 GB**（已用约 **16.83 GB**） |
| 备份空间 | 数据备份约 56.86 GB，日志约 35.19 MB（100 GB 内免费额度） |
| 存储自动扩容 | **未开启**（扩容上限 50 GB） |
| 计费方式 | 包年包月（自动续费未开启） |
| 创建时间 | 2022-05-05 12:50:17 |
| 到期时间 | 2026-11-07 00:00:00 |
| 可维护时段 | 02:00–06:00（Asia/Shanghai UTC+8） |
| 小版本 | 当前 `rds_20230620`（可升级至 `rds_20240228`，已开自动升级） |
| 地域 / 可用区 | 华东 1（杭州）**可用区 G** |
| 网络类型 | **专有网络 VPC** |
| VPC ID | `vpc-bp1jmugctnhj97dbjyx31` |
| 网段 | `172.16.0.0/12`（VPC 级；ECS 子网为 `172.21.x.x`） |
| 实例系列 | 常规实例（基础系列） |

**与 ECS 的位置关系**：Dev ECS 位于同 VPC 的可用区 I/K（如 dev-01 在 K 区），RDS 在 G 区 — **同 VPC 跨可用区访问正常**，无需迁移 ECS。

---

## 三、连接地址（重要）

| 类型 | 域名 | 端口 | 用途 | 当前状态 |
|------|------|------|------|----------|
| **内网** | `rm-bp1wjjf373l7t331v.mysql.rds.aliyuncs.com` | 3306 | **Dev/Test/Prod ECS 应用连接（推荐）** | 已开启 |
| **外网** | `rm-bp1wjjf373l7t331vno.mysql.rds.aliyuncs.com` | 3306 | 仅临时运维/救急；**不应作为应用默认连接串** | **已开启**（待收口） |

### 3.1 与 infra-ops 仓库变量对照

| 来源 | 当前记录的 host | 说明 |
|------|-----------------|------|
| `network.yml` → `rds.host` | `rm-bp1wjjf373l7t331v.mysql.rds.aliyuncs.com` | **内网**（2026-06-15 验收后已同步） |
| `registry.yaml` → `shared_cloud_dependencies.rds.endpoint_internal` | 同上 | 应用默认连接串 |
| 外网（救急） | `rm-bp1wjjf373l7t331vno.mysql.rds.aliyuncs.com` | **勿作应用默认**；待控制台关闭（§八） |

> **待办**：关闭 RDS 外网地址（内网已验收稳定，见 [阶段 G 验收报告](../acceptance/20260615-阶段G-Dev-RDS-app_dev验收.md)）。

---

## 四、访问控制现状

### 4.1 ECS 安全组（RDS 控制台 → 安全组 Tab）

| 项 | 状态 |
|----|------|
| 已关联 ECS 安全组 | **无**（列表为空） |

说明：RDS 可通过 **白名单** 或 **关联 ECS 安全组** 两种方式授权；当前未使用安全组关联方式。

### 4.2 IP 白名单（RDS 控制台 → 白名单设置）

| 项 | 状态 |
|----|------|
| 控制台详情 | **dev-01 已确认**（2026-06-15：`172.21.226.38/32` 可连通） |
| infra-ops 规划分组名 | `dev-ecs`（见 `network.yml` → `rds_whitelist.group_name`） |

**ECS 私网 IP 白名单**（仅内网，不加公网、不加 WG 网段）：

| 主机 | 角色 | 私网 IP | 白名单状态 |
|------|------|---------|------------|
| dev-01 / ci-01（同机 yax） | Dev 应用 / CI | `172.21.226.38/32` | **confirmed**（2026-06-15） |
| dev-02（launch-advisor-20260425） | Dev Worker 替代 | `172.21.127.124/32` | pending_bootstrap |
| hub-01 | 管理面 | `172.21.127.123/32` | 一般**不需要**（除非 DBA 从 Hub 连库） |
| test-01（显物） | Test 预留 | `172.21.127.122/32` | Test 阶段再议 |

**禁止加入白名单**：

- `0.0.0.0/0`  
- WireGuard 网段 `10.200.0.0/16`  
- ECS **公网 IP**（应走 VPC 内网连 RDS）

---

## 五、已有数据库与账号（实例内现状）

实例内约有 **20+ 个数据库**（含历史生产/测试库）。**Dev 专用库已按方案 A 新增**（2026-06-15）。

### 5.0 Dev 专用库（infra-ops 方案 A — 已实施）

| 库名 | 字符集 | 账号 | 权限 | 状态 |
|------|--------|------|------|------|
| **`app_dev`** | **utf8mb4** | **`app_dev`** | 仅 `app_dev.*` | **operational**（2026-06-15 验收） |

验收摘要（ci-01 / dev-01）：

- 内网 `nc` / `mysql` 登录成功（MySQL **8.0.28**）
- `USE yzx`、`USE risk` → Access denied（prod 隔离）
- 读写 smoke 表 `_infra_smoke` 通过

详见：[阶段 G 验收报告](../acceptance/20260615-阶段G-Dev-RDS-app_dev验收.md)、`logs/console-acceptance.log`。

### 5.1 历史库（实例内其他库，节选）

| 库名 | 字符集 | 绑定账号（控制台显示） | 备注/用途倾向 |
|------|--------|------------------------|---------------|
| `yzx` | utf8 | prod yzx | 生产 |
| `risk` | utf8 | prod risk | 生产（风控中心） |
| `yzxzj` | utf8 | prod yzxzj | 生产 |
| `zuxiaoka` | utf8 | prod zuxiaoka | 生产 |
| `wzb` | utf8 | jiyouzu / prod wzb | 生产 |
| `nacos` | utf8 | nacos | 配置中心 |
| `nacos_test` | utf8 | yzx_test | 配置中心测试 |
| `yzx_test` | **utf8mb4** | yzx_test | **测试环境**（现有体系） |
| `lkz` | utf8 | jiyouzu / lkz / yzx_test | 业务/测试 |
| `zjjyw` | utf8 | yzx_test | 业务/测试 |
| … | … | … | 另有约 10 个库未在初版截图中列出 |

### 5.2 策略选择（已决策）

| 方案 | 说明 | 结论 |
|------|------|------|
| **A. 新建 `app_dev`**（推荐，对齐 infra-ops） | 新库 utf8mb4 + 新账号 `app_dev`，仅授权 `app_dev.*` | **已采用**（2026-06-15） |
| B. 沿用 `yzx_test` | 不新建库，Dev 应用连现有测试库 | 未采用 |
| C. 新建其他 Dev 库名 | 如 `yzx_dev` | 未采用 |

仓库中 `rds.database: app_dev` / `rds.user: app_dev` 已与实机一致。

---

## 六、Dev 环境连接参数（当前）

以下与 `ansible/inventories/dev/group_vars/all/network.yml` 对齐；**密码不进 Git**。

| 变量 | 当前值 | 备注 |
|------|--------|------|
| `rds.host` | `rm-bp1wjjf373l7t331v.mysql.rds.aliyuncs.com` | **内网**；应用 JDBC/DSN |
| `rds.port` | `3306` | |
| `rds.database` | `app_dev` | 已创建 |
| `rds.user` | `app_dev` | 已创建 |
| `rds.status` | `operational` | 2026-06-15 验收 |
| 密码 | GitHub Secret `DB_PASSWORD` / ansible-vault `secrets.yml` | **运维配置**；不进 Git 明文 |

**MySQL 8.0 注意**：

- 默认认证插件多为 `caching_sha2_password`；老旧驱动可能需要 `mysql_native_password`（按业务栈确认）  
- 建议连接时区与应用统一为 `Asia/Shanghai`

---

## 七、与 ECS / WireGuard 的关系

```
dev-01 (172.21.226.38) ──VPC 内网──→ RDS 内网 endpoint:3306
         ↑
    不经过 wg0 (10.200.x.x)

ci-01 与 dev-01 同机 → 验收在 ci-01/dev-01 上执行 nc / mysql 即可
Hub / JumpServer     → 通常不需要 RDS 白名单
办公笔记本 + WG      → 不能替代 ECS 连 RDS（除非笔记本在 VPC 内或有专线）
```

| 组件 | 是否依赖 RDS | 说明 |
|------|--------------|------|
| WireGuard | 否 | 已完成；与 RDS 无关 |
| JumpServer（规划） | 否 | 堡垒机不依赖业务库 |
| Dev 应用（规划） | **是** | 需要可用库 + 白名单 + Secrets |
| Bootstrap verify | 部分 | `bootstrap.sh verify` 仅 `nc` 测 3306，**不能替代** mysql 登录 |

---

## 八、安全收口待办（企业方案对齐）

| 项 | 当前 | 目标 |
|----|------|------|
| RDS 外网地址 | **已开启** | **关闭**或严格限制（内网已验收） |
| 应用连接串 | **已改为内网域名**（`network.yml`） | 保持 |
| 白名单 | dev-01 **已确认** | dev-02 Bootstrap 后补 IP；禁止 `0.0.0.0/0` |
| Dev 账号权限 | **已验收**（不可访问 `yzx`/`risk`） | 定期复核 |
| 审计 | — | 人工 SQL 经 JumpServer（Test 前收口）；应用仅经 CI/CD |

---

## 九、推荐下一步（Dev 数据层）

**MySQL（`app_dev`）已完成**；后续建议：

1. **Secrets**：确认 GitHub `DB_PASSWORD` 与/或 vault `secrets.yml` 已配置。  
2. **（推荐）** 控制台关闭 RDS 外网地址。  
3. **dev-02**：Bootstrap 后白名单加 `172.21.127.124/32` 并验收。  
4. **OSS**：RAM 角色 + `dev/` 前缀 smoke 测试（见 [OSS 实例现状与 Dev 规划](../oss/20260616-OSS-实例现状与Dev规划.md) §九）。
5. **Redis**（若业务需要）：dev-02 Docker 部署。  
6. **（等业务栈）** Flyway/Liquibase schema 迁移。  
7. **并行**：JumpServer、Self-hosted Runner、`network_phase: steady`。

---

## 十、验收清单（Dev 数据库层完成标志）

- [x] 已确认白名单含 dev-01 私网 IP（`172.21.226.38/32`）  
- [x] Dev 专用库存在（`app_dev`），utf8mb4  
- [x] Dev 专用账号存在，且**不能**访问 prod 库（`yzx`、`risk` 已测）  
- [x] 从 dev-01/ci-01：内网 `nc` 3306 成功  
- [x] 从 dev-01/ci-01：`mysql` 登录并 `SELECT 1` 成功  
- [ ] 密码已入 Secrets/vault，未进 Git（**运维确认** GitHub `DB_PASSWORD` / vault）  
- [x] `network.yml` / 本文档 / `registry.yaml` 一致（2026-06-15 回写）  
- [ ] （推荐）RDS 外网地址已关闭或严格限制  

---

## 十一、相关文档与仓库引用

| 文档 / 路径 | 说明 |
|-------------|------|
| [docs/assets/registry.yaml](../assets/registry.yaml) | `shared_cloud_dependencies.rds` |
| [ansible/inventories/dev/group_vars/all/network.yml](../../ansible/inventories/dev/group_vars/all/network.yml) | `rds`、`rds_whitelist` |
| [docs/assets/dev-01.yaml](../assets/dev-01.yaml) | dev-01 对 RDS 的依赖声明 |
| [docs/plan/20260608-开发环境（Dev）部署计划.md](../plan/20260608-开发环境（Dev）部署计划.md) | 阶段 3 数据层 |
| [docs/20260608-ECS 企业开发环境（Dev）实施方案.md](../20260608-ECS%20企业开发环境（Dev）实施方案.md) | §3.1 RDS `app_dev` |
| [docs/assets/README.md](../assets/README.md) | 资产台账总索引 |

| [docs/acceptance/20260615-阶段G-Dev-RDS-app_dev验收.md](../acceptance/20260615-阶段G-Dev-RDS-app_dev验收.md) | 阶段 G 验收报告 |

---

## 修订历史

| 日期 | 作者 | 说明 |
|------|------|------|
| 2026-06-15 | infra-ops | 初版：汇总控制台截图、讨论结论与 infra-ops 规划差异 |
| 2026-06-15 | infra-ops | 方案 A `app_dev` 验收通过；同步内网 host、白名单、§十清单 |
