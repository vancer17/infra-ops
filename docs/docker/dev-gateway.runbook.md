# Dev 业务网关 Compose（Nginx + LE DNS-01）

在 **dev-01** 上用 Compose 接管业务 API 公网出口，替代宿主机 Ansible Nginx + 自签证书。

**状态**：仓库内实现就绪；生产割接前须完成 Staging 演练与宿主机 Nginx 停用。

## 架构

```text
小程序 / 公网
    → dev-01 :443（Compose nginx, host 网络, LE 证书）
    → 127.0.0.1:8080（PetIntelli / 占位 API，宿主机容器）

certbot-init  ──一次性 DNS-01──►  dev-gateway-letsencrypt 卷
certbot-renew ◄──续期 + reload──►  dev-gateway-nginx
```

| 与旧方案对比 | 宿主机 Ansible Nginx | Compose dev-gateway |
|--------------|----------------------|---------------------|
| 证书 | 自签（`dev-app.crt`） | Let's Encrypt（DNS-01） |
| 验证方式 | — | 阿里云 DNS TXT，不占用 80 验证 |
| 续期 | 无 | `certbot-renew` 轮询 + reload |
| 80/443 | systemd nginx | 容器 nginx（host 网络） |

Hub 管理面 Nginx（`jms.internal`）**不在本栈**，仍由 hub-01 Ansible 管理。

## 前提

- `backend.jxqydw.com` A 记录 → dev-01 公网 IP（如 `121.41.58.20`）
- 域名备案完成（小程序长期依赖）
- 安全组入站 **TCP 80、443** 对公网开放；**8080 不对公网**
- 阿里云 RAM 子账号 + DNS API 密钥（`_acme-challenge` TXT）
- 宿主机应用监听 `127.0.0.1:8080`（PetIntelli）
- **已停用**宿主机 `nginx.service`，释放 80/443
- 目标机已安装 Docker CE 与 Compose 插件

## 部署目录

Ansible 与手工部署统一使用：

| 路径 | 说明 |
|------|------|
| `/opt/gateway/docker/` | 从仓库同步的完整 `docker/` 构建树 |
| `/opt/gateway/docker/dev-gateway/` | Compose 项目目录（`.env`、`docker-compose.yml`） |

从 `infra-ops` 同步：

- `docker/dev-gateway/`
- `docker/nginx/`、`docker/certbot-*`、`docker/certbot-common/`

## 首次部署

### 1. 配置环境

```bash
cd /opt/gateway/docker/dev-gateway
cp .env.example .env
chmod 600 .env
```

填写：

- `CERTBOT_EMAIL`、`CERTBOT_DOMAINS`、`CERTBOT_PRIMARY_DOMAIN`
- `ALIYUN_DNS_ACCESS_KEY`、`ALIYUN_DNS_ACCESS_KEY_SECRET`
- `NGINX_SERVER_NAMES`（含备案域名与过渡期 IP）

### 2. Staging 演练（推荐）

`.env` 中设置 `CERTBOT_STAGING=1`，然后：

```bash
make issue-staging
docker compose up -d certbot-renew
# 确认 init / renew 日志无 DNS API 错误后，改回 CERTBOT_STAGING=0
```

Staging 证书**不受微信信任**，仅验证 DNS-01 流程。

### 3. 停用宿主机 Nginx

```bash
sudo systemctl disable --now nginx
ss -tlnp | grep -E ':80|:443'   # 确认无冲突
```

### 4. 启动全栈

```bash
make build
make up
make verify
```

启动顺序由 Compose 保证：`certbot-init` 成功 → `certbot-renew` healthy → `nginx` 启动。

### 5. 公网与微信验收

```bash
curl -s "https://backend.jxqydw.com/healthz"
curl -s "https://backend.jxqydw.com/readyz"
```

- 勿使用 `curl -k` 作为最终验收
- 微信公众平台配置 request 合法域名：`backend.jxqydw.com`
- 小程序 `baseURL` 使用 `https://backend.jxqydw.com`

## 运维

### 查看状态与日志

```bash
make ps
make logs
make logs-init
docker compose exec nginx nginx -t
```

Nginx 访问日志：卷 `dev-gateway-nginx-logs` → 容器内 `/var/log/nginx/dev-app.access.log`

### 强制重新签发

```bash
CERTBOT_FORCE_ISSUE=1 docker compose run --rm certbot-init
docker compose up -d certbot-renew nginx
```

### 续期

`certbot-renew` 默认每 12 小时执行 `certbot renew`；成功时通过 docker.sock 向 `dev-gateway-nginx` 发送 SIGHUP。

建议每月检查：

```bash
docker compose logs --tail=100 certbot-renew
make verify
```

### WireGuard 内网（可选）

`.env` 中设置 `NGINX_INTERNAL_SERVER_NAMES=dev-app.internal 10.200.0.2` 时，额外提供 **HTTP** 反代（不跳转 HTTPS），便于 WG 内网联调。

公网域名仍走 HTTPS + LE 证书。

## 故障排查

| 现象 | 排查 |
|------|------|
| init 失败 | `make logs-init`；检查 RAM 权限、DNS 传播时间、`CERTBOT_DNS_PROPAGATION_SECONDS` |
| renew 不健康 | `docker compose logs certbot-renew`；检查 ready 文件与证书路径 |
| nginx 未启动 | renew 未 healthy；先修证书再 `docker compose up -d nginx` |
| 502 Bad Gateway | 上游 `127.0.0.1:8080` 未监听；`curl http://127.0.0.1:8080/healthz` |
| 微信 TLS 错误 | 确认非 Staging 证、`NGINX_SERVER_NAMES` 含域名、公众平台合法域名已配 |
| 80/443 冲突 | 宿主机 nginx 未停或其他进程占用 |

## 回滚（应急）

```bash
docker compose down
sudo systemctl enable --now nginx   # 恢复宿主机自签 Nginx（微信仍可能失败）
```

保留 `dev-gateway-letsencrypt` 卷以便再次割接。

## 相关路径

| 路径 | 说明 |
|------|------|
| `docker/dev-gateway/docker-compose.yml` | Compose 定义 |
| `docker/dev-gateway/.env.example` | 环境变量模板 |
| `docker/nginx/templates/dev-app.conf.template` | 公网 HTTPS 模板 |
| `docker/certbot-common/certbot-dns-lib.sh` | DNS-01 共用逻辑 |

## 下一步（非本 Runbook）

- Ansible：同步 compose 到目标机、确保 `nginx.service` disabled（另文）
- `app.yml` / 应用 Compose 与网关解耦发布
- 证书到期告警接入监控
