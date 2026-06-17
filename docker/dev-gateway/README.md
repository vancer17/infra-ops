# Dev 业务网关（Compose）

在 **dev-01** 上以 Docker Compose 运行公网 API 出口：**DNS-01 签发 Let's Encrypt 证书** + **Nginx（host 网络）** 反代宿主机 `127.0.0.1:8080`。

替代原宿主机 Ansible 管理的自签 Nginx（迁移时须先 `systemctl disable --now nginx`）。

## 架构

```text
certbot-init (一次性)  →  写入 letsencrypt 卷
certbot-renew (常驻)   →  就绪门控 + 续期 + reload nginx
nginx (host 网络)      →  :80 / :443  →  127.0.0.1:8080
```

| 组件 | 容器名 | 说明 |
|------|--------|------|
| 首次签发 | `dev-gateway-certbot-init` | DNS-01，`restart: no` |
| 续期 | `dev-gateway-certbot-renew` | 默认每 12h 检查 renew |
| 网关 | `dev-gateway-nginx` | `network_mode: host` |

证书保存在 Docker 卷 `dev-gateway-letsencrypt`，由 init/renew/nginx 共享。

## Docker 网段与 VPC（必读）

阿里云 VPC 内 **RDS 使用 172.20.x**、**ECS 使用 172.21.x**。若 Docker 自动为 `certbot-internal` 分配到 `172.20.0.0/16`，宿主机访问 RDS 会被错误路由到 docker 网桥，导致 `/readyz` 连库失败而 `/healthz` 仍 200。

- Compose 已将 `certbot-internal` **钉死为 `172.30.0.0/24`**
- Dev `bootstrap.yml` 配置 `docker_daemon_default_address_pools`（172.30/10.244），避免其它新网络再撞 VPC
- 修改 `daemon.json` 后需 `systemctl restart docker`（会短暂影响容器）

若曾用旧配置创建过冲突网络，须重建：

```bash
docker compose down
docker network rm dev-gateway-certbot-internal 2>/dev/null || true
docker compose up -d

ip route get 172.20.211.167   # 应 via eth0，而非 dev br-xxx
make verify
```

## 目录与同步

建议部署路径：`/opt/gateway/docker/dev-gateway`（Ansible `gateway-compose.yml` 同步整个 `docker/` 到 `/opt/gateway/docker/`）。

需同步的仓库路径（构建上下文为 `docker/`，compose 在 `docker/dev-gateway/`）：

```text
docker/dev-gateway/          # compose.yml、.env、Makefile
docker/nginx/
docker/certbot-init/
docker/certbot-renew/
docker/certbot-common/
```

## 快速开始

```bash
cd /opt/gateway/docker/dev-gateway   # 或仓库内 docker/dev-gateway

cp .env.example .env
# 编辑 .env：CERTBOT_EMAIL、CERTBOT_DOMAINS、阿里云 DNS RAM 密钥

# 迁移前释放 80/443
sudo systemctl disable --now nginx

make build
make up
make verify
```

## 环境变量要点

| 变量 | 说明 |
|------|------|
| `CERTBOT_DOMAINS` | 空格分隔，首个为主域名 |
| `CERTBOT_STAGING` | `1` = LE 测试环境（微信不信任） |
| `CERTBOT_FORCE_ISSUE` | `1` = 忽略已有证强制重签 |
| `ALIYUN_DNS_*` | 阿里云 DNS API（DNS-01 必填） |
| `NGINX_SERVER_NAMES` | 公网 HTTPS `server_name` |
| `NGINX_INTERNAL_SERVER_NAMES` | 可选 WG 内网 HTTP，不强制 HTTPS |

## 常用命令

```bash
make ps
make logs
make logs-init          # 查看首次签发日志
docker compose logs certbot-init

# 强制重新签发（保留卷）
CERTBOT_FORCE_ISSUE=1 docker compose run --rm certbot-init
docker compose up -d certbot-renew nginx

# Staging 演练
make issue-staging
```

## 验收

```bash
make verify

# 公网（勿使用 -k）
curl -s "https://backend.jxqydw.com/healthz"
curl -s "https://backend.jxqydw.com/readyz"
```

微信小程序另须在公众平台配置 **request 合法域名**。

## 相关文档

- [Dev Gateway Runbook](../../docs/docker/dev-gateway.runbook.md)
- [后端 API 探针](../../docs/api/backend.md)
