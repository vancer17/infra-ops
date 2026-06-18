# 阶段 3：Dev 业务 Nginx 与占位 API 验收

| 项 | 说明 |
|----|------|
| **日期** | 2026-06-16 |
| **范围** | dev-01 占位 API（`dev-app.yml`）+ 业务 Nginx（`nginx-dev.yml`） |
| **控制机** | ci-01（yax，与 dev-01 同机） |
| **验收日志** | [logs/console-acceptance.log](../../logs/console-acceptance.log) |
| **Playbook** | `ansible/playbooks/dev-app.yml`、`ansible/playbooks/nginx-dev.yml` |
| **Runbook** | [docs/nginx/dev-nginx.runbook.md](../nginx/dev-nginx.runbook.md) |
| **后续** | 公网 HTTPS 已迁移至 [阶段 4 Compose LE 网关](../acceptance/20260617-阶段4-Dev-Gateway-Compose-LE验收.md) |
| **前置** | Bootstrap、WireGuard、RDS `app_dev`、Hub 内网 DNS（`dev-app.internal` → `10.200.0.2`） |

---

## 一、结论

**Dev 业务统一出口（Nginx 80/443 → 127.0.0.1:8080）与占位 API 已部署并通过实机验收。**

- 本机：`http://127.0.0.1:8080/` 返回占位文案
- WG：`https://dev-app.internal/health` → 200；`/` 反代占位 API
- 公网：`https://121.41.58.20/health` → 200；HTTP 80 → 301 HTTPS

当前为 **占位 API**（`deploy_status: placeholder`）；真实业务镜像待 app-repo 与 CI 接通后替换。

---

## 二、部署内容

| 组件 | 位置 | 状态 |
|------|------|------|
| 占位容器 | `dev-app-placeholder` @ `127.0.0.1:8080` | operational |
| 业务 Nginx | dev-01 宿主机 80/443 | operational |
| `/health` | Nginx 直接 `return 200` | 不依赖容器 |
| TLS | 自签（`dev-app.internal` / `121.41.58.20` / `10.200.0.2` SAN） | Dev 联调用 `-k` |

占位镜像：`5yrqsf19ms2mh4.xuanyuan.run/hashicorp/http-echo:0.2.3`

---

## 三、功能验收

### 3.1 dev-01 本机（ci-01 Ansible）

| 检查 | 结果 |
|------|------|
| `curl -sf http://127.0.0.1:8080/` | `infra-ops dev placeholder api` |
| `docker ps --filter name=dev-app-placeholder` | Up，`127.0.0.1:8080->8080/tcp` |

### 3.2 办公笔记本（WG Client）

| 检查 | 结果 |
|------|------|
| `ping dev-app.internal` | → `10.200.0.2`，0% 丢包 |
| `curl -sk https://dev-app.internal/health` | 200 |
| `curl -sk https://dev-app.internal/` | 占位 API 文案 |
| `nslookup dev-app.internal` | 超时（Windows 常见；HTTP 访问正常，见 Clash bypass 文档） |

### 3.3 公网

| 检查 | 结果 |
|------|------|
| `curl -sI http://121.41.58.20/health` | 301 → `https://121.41.58.20/health` |
| `curl -sk https://121.41.58.20/health` | 200 |
| `curl -sk https://121.41.58.20/` | 占位 API 文案 |

---

## 四、与台账同步项

- [x] `ansible/inventories/dev/group_vars/all/app.yml` → `enabled: true`，`deploy_status: placeholder`
- [x] `ansible/inventories/dev/group_vars/all/nginx.yml` → `enabled: true`，`status: operational`
- [x] `ansible/inventories/dev/group_vars/all/network.yml` → `nginx_app_status: operational`，`app_deploy_status: placeholder`
- [x] `docs/assets/dev-01.yaml` → `app` / `nginx_app`
- [x] `docs/assets/registry.yaml` → `stage_dev_app_acceptance`、`hosts.dev-01`
- [x] `internal_dns.yml` / DNS runbook → `dev-app.internal` operational
- [x] `docs/dev/开发环境介绍-业务部署指南.md`

---

## 五、下一步

1. 注册 GitHub Self-hosted Runner，接通 `deploy.yml` + `dev-app.yml` 流水线
2. dev-02 Bootstrap → Redis / Worker
3. 业务栈确定后：`app.deploy_status: operational`，替换占位镜像
4. 小程序正式环境：备案域名 + 受信 CA（当前自签仅 Dev 联调）
5. JumpServer 纳管 dev-01 资产（G5 扩展）

---

## 六、关联文档

- Hub 管理面 Nginx（对比）：[20260615-阶段G1-Hub-Nginx验收.md](20260615-阶段G1-Hub-Nginx验收.md)
- 内网 DNS：[20260616-阶段G2-Hub-DNS与JumpServer预留.md](20260616-阶段G2-Hub-DNS与JumpServer预留.md)
- 业务部署指南：[docs/dev/开发环境介绍-业务部署指南.md](../dev/开发环境介绍-业务部署指南.md)
