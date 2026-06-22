# 阶段 I：Dev Redis（云实例 `r-bp10kgwdml4kqgssoz`）验收报告

> **验收日期**：2026-06-22  
> **执行位置**：dev-01 / ci-01 同机（`121.41.58.20` / `172.21.226.38`）  
> **原始日志**：`logs/console-acceptance.log`（Redis 段落，约 L1–L34）  
> **策略**：阿里云托管 Redis 7.0 标准版 + 独立账号 `petintelli_app`（授权 **DB 0**）+ 键前缀 `petintelli:app:`

---

## 一、验收结论

| 项 | 结果 |
|----|------|
| 总体 | **通过** — Dev 缓存层可用于 `petintelli-backend` 接入 |
| 实例 | `r-bp10kgwdml4kqgssoz`（控制台名 `20260622-183920`） |
| 连接地址 | 内网 `r-bp10kgwdml4kqgssoz.redis.rds.aliyuncs.com:6379` |
| 解析 IP | `172.23.160.90`（验收时） |
| 账号 / DB | `petintelli_app` / **0** |
| 引擎版本 | Redis **7.0.15**（`INFO server`） |

---

## 二、检查项明细

| # | 检查 | 命令/方式 | 结果 |
|---|------|-----------|------|
| 1 | 网络连通 | `nc -zv $REDIS_HOST 6379` | succeeded → `172.23.160.90` |
| 2 | 路由 | `ip route get 172.23.160.90` | `via 172.21.239.253 dev eth0 src 172.21.226.38` |
| 3 | 认证 | `redis-cli --user petintelli_app PING` | `PONG` |
| 4 | DB 0 读写 | `SELECT 0` → SET/GET/DEL `petintelli:app:_infra_smoke` | ok |
| 5 | 版本 | `INFO server` | `redis_version:7.0.15` |

---

## 三、架构要点（相对初版规划之变更）

| 项 | 初版（dev-02 Docker） | 当前实机（2026-06-22） |
|----|----------------------|------------------------|
| 部署 | dev-02 容器 Redis | **云 Redis** 托管实例 |
| `REDIS_HOST` | `172.21.127.124` | 内网域名 `r-bp10kgwdml4kqgssoz.redis.rds.aliyuncs.com` |
| 账号 | 单密码 | 控制台账号 **`petintelli_app`** |
| dev-02 依赖 | Bootstrap 后才能用 Redis | **不阻塞**；Redis 已独立于 dev-02 |

---

## 四、台账同步（本验收后须一致）

| 文件 | 变更要点 |
|------|----------|
| `ansible/inventories/dev/group_vars/all/network.yml` | 新增 `redis`、`redis_whitelist` |
| `docs/assets/registry.yaml` | `shared_cloud_dependencies.redis` |
| `docs/assets/dev-01.yaml` | `dependencies.redis`；`redis_dev` |
| `docs/redis/20260622-Redis-实例现状与Dev规划.md` | 本文档姊妹篇（实例台账） |
| `docs/dev/开发环境介绍-业务部署指南.md` | 第七节 Redis、环境变量、路线图 |
| `docs/assets/dev-02.yaml` | 说明 Redis 已迁至云实例 |
| `ansible/.../secrets.yml.example` | `redis_password` 注释更新 |

---

## 五、待办（不阻塞本验收）

| 项 | 说明 |
|----|------|
| GitHub `REDIS_PASSWORD` | 写入 Environment `dev` |
| 应用 `.env` | `petintelli-backend` 配置 `REDIS_*` 后重启容器 |
| dev-02 白名单 | Bootstrap 后加 `172.21.127.124/32`（Worker 连同一 Redis） |
| 第二账号（可选） | 若视频生成需 DB 隔离，再建 `petintelli_video` + DB 1 |

---

## 六、相关文档

- [Redis 实例现状与 Dev 规划](../redis/20260622-Redis-实例现状与Dev规划.md)
- [开发环境业务部署指南](../dev/开发环境介绍-业务部署指南.md)
- [阶段 G RDS 验收](./20260615-阶段G-Dev-RDS-app_dev验收.md)
