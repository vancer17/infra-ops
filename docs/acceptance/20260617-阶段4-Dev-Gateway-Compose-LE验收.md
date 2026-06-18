# 阶段 4：Dev Gateway Compose（LE DNS-01）验收

| 项 | 说明 |
|----|------|
| **日期** | 2026-06-17 |
| **范围** | dev-01 业务网关由 **Compose** 接管（`dev-gateway` 栈）；LE 证书 + 容器 Nginx；Docker 网段修复 |
| **控制机** | ci-01 / dev-01 同机（yax） |
| **验收日志** | [logs/console-acceptance.log](../../logs/console-acceptance.log) |
| **故障报告** | [logs/remark.log](../../logs/remark.log)（Docker 172.20/16 遮挡 RDS，已修复） |
| **Playbook** | 手工 `docker compose`（`~/infra-ops/docker/dev-gateway`）；Ansible：`gateway-compose.yml` |
| **Runbook** | [docs/docker/dev-gateway.runbook.md](../docker/dev-gateway.runbook.md) |
| **前置** | 阶段 3 业务出口、RDS `app_dev`、PetIntelli @ `127.0.0.1:8080` |

---

## 一、结论

**Dev 公网 API 出口已迁移至 Compose 网关：Let's Encrypt（DNS-01）+ Nginx host 网络，域名 `backend.jxqydw.com`，满足微信小程序 HTTPS 证书链要求。**

- TLS：`Verify return code: 0 (ok)`；`curl` 严格校验 `ssl_verify=0`
- 探针：`/healthz`、`/readyz` 本机与公网 HTTPS 均为 **200**
- Docker：`certbot-internal` 子网 **172.30.0.0/24**；RDS 路由走 **eth0**（非 docker 网桥）
- 宿主机 `systemd nginx` 已停用，由 `dev-gateway-nginx` 占用 80/443

阶段 3（宿主机自签 Nginx + 占位 API）由本阶段 **取代** 公网 HTTPS 路径；阶段 3 验收仍作历史记录。

---

## 二、部署内容

| 组件 | 容器/服务 | 说明 |
|------|-----------|------|
| 首次签发 | `dev-gateway-certbot-init` | DNS-01，`Exited (0)` |
| 续期 | `dev-gateway-certbot-renew` | healthy；卷 `dev-gateway-letsencrypt` |
| 网关 | `dev-gateway-nginx` | `network_mode: host`；`fullchain.pem` |
| 应用 | `petintelli-backend` | `127.0.0.1:8080→8000` |
| 域名 | `backend.jxqydw.com` | A → `121.41.58.20` |
| 证书 | Let's Encrypt（issuer YE2） | 有效期至 2026-09-15 |

镜像 tag：`infra-ops/*:1.0.0`

---

## 三、功能验收

### 3.1 Compose 与证书

| 检查 | 结果 |
|------|------|
| `docker compose ps` | init exit 0；renew、nginx healthy |
| LE fullchain + SAN | `DNS:backend.jxqydw.com` |
| `openssl s_client` | `Verify return code: 0 (ok)`；TLS 1.2/1.3 |
| `curl` 无 `-k` healthz/readyz | HTTP 200，`ssl_verify=0` |

### 3.2 Docker 网段与 RDS（修复项）

| 检查 | 结果 |
|------|------|
| `dev-gateway-certbot-internal` 子网 | `172.30.0.0/24`（非 172.20/16） |
| `ip route get 172.20.211.167` | `via ... dev eth0` |
| `/dev/tcp/172.20.211.167/3306` | OK |
| `/readyz`（修复前曾超时/500） | 200 `{"status":"ready"}` |

根因：`certbot-internal` 曾自动分配到 `172.20.0.0/16`，与 RDS 私网 IP 冲突。修复：compose 显式 `ipam` +（可选）docker `default-address-pools`。

### 3.3 公网路径

| 路径 | HTTPS 结果 |
|------|------------|
| `/healthz` | 200 |
| `/readyz` | 200 |
| `/docs` | 200 |
| `/api/v1/health` | 404（后端无此路由，非 TLS 问题） |

### 3.4 外网抽样

| 客户端 | 结果 |
|--------|------|
| 浏览器 `https://backend.jxqydw.com/healthz` | 无证书告警；JSON 正常 |
| Windows `curl.exe` | 个别环境可能出现 connection reset；以浏览器/微信为准 |

---

## 四、Inventory / 台账同步

| 变量 | 值 |
|------|-----|
| `gateway.status` | `operational` |
| `nginx.runtime` | `compose` |
| `app.deploy_status` | `operational` |
| `dev_hosts.dev-01.gateway_compose_status` | `operational` |

文档：`docs/assets/dev-01.yaml`、`docs/assets/registry.yaml` → `stage_gateway_compose_acceptance`

---

## 五、待办（非阻断）

| 项 | 说明 |
|----|------|
| 微信公众平台 | request 合法域名配置 `backend.jxqydw.com` |
| 小程序真机 | 关闭「不校验合法域名/TLS」复测 |
| Ansible 正式路径 | `/opt/gateway/compose` 与 `gateway-compose.yml` 收敛 |
| docker daemon | `default-address-pools` 低峰 `bootstrap --tags docker` |
| 清理 | 旧容器 `nice_mcnulty`（试验 certbot）可移除 |
| 应用 env | `healthz` 返回 `env: staging`，按规范可改为 `development` |

---

## 六、回滚（仅应急）

```bash
cd ~/infra-ops/docker/dev-gateway
docker compose down
sudo systemctl enable --now nginx   # 仅当宿主机自签配置仍存在
```

回滚后微信小程序 TLS 将回到自签/不可用状态，不建议长期使用。
