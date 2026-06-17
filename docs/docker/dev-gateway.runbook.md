# Dev 业务网关 Compose（Nginx + LE DNS-01）

在 **dev-01** 上用 Compose 接管业务 API 公网出口，替代宿主机 Ansible Nginx + 自签证书。

**状态**：镜像预构建 + Ansible pull 部署；生产割接前须完成 Staging 演练与宿主机 Nginx 停用。

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
| 镜像 | apt 安装 nginx | **控制机 build+push，目标机 pull** |

Hub 管理面 Nginx（`jms.internal`）**不在本栈**，仍由 hub-01 Ansible 管理。

## 职责分工

| 环节 | 在哪里做 | 做什么 |
|------|----------|--------|
| **构建镜像** | 开发机 / CI | `make build-gateway-images` |
| **推送镜像** | 开发机 / CI | `make push-gateway-images`（需 `docker login`） |
| **部署栈** | dev-01 via Ansible | `gateway-compose.yml`：同步 compose 项目、渲染 `.env`、pull、up |
| **不在目标机做** | dev-01 | `docker build`、同步 Dockerfile 构建树 |

镜像版本由 `ansible/inventories/dev/group_vars/all/gateway.yml` → `gateway.images.tag` 锁定，须与 push 的 tag 一致。

## 前提

- `backend.jxqydw.com` A 记录 → dev-01 公网 IP（如 `121.41.58.20`）
- 域名备案完成（小程序长期依赖）
- 安全组入站 **TCP 80、443** 对公网开放；**8080 不对公网**
- 阿里云 RAM 子账号 + DNS API 密钥（`_acme-challenge` TXT）
- 宿主机应用监听 `127.0.0.1:8080`（PetIntelli）
- **已停用**宿主机 `nginx.service`，释放 80/443
- 目标机已安装 Docker CE 与 Compose 插件
- 镜像已 push 至 `gateway.images.registry`（默认 `5yrqsf19ms2mh4.xuanyuan.run/infra-ops`）

## 部署目录

Ansible 与手工部署统一使用：

| 路径 | 说明 |
|------|------|
| `/opt/gateway/compose/` | Compose 项目（`docker-compose.yml`、`.env`、验收脚本） |

Ansible **仅同步** `docker/dev-gateway/` 目录，不同步 `docker/certbot-*` Dockerfile 到目标机。

## 发布新镜像（控制机 / CI）

```bash
# 1. 修改 docker/ 下 Dockerfile 或脚本后
export GATEWAY_IMAGE_TAG=1.0.1   # 新版本
make build-gateway-images
make push-gateway-images

# 2. 更新 gateway.yml
#    gateway.images.tag: "1.0.1"

# 3. 部署
make stage-gateway-compose-preflight
ansible-playbook ansible/playbooks/gateway-compose.yml \
  -i ansible/inventories/dev/ --limit dev-01 --vault-password-file .vault_pass
```

查看当前 inventory 引用的镜像名：

```bash
./scripts/docker/build-gateway-images.sh list
# 将 GATEWAY_IMAGE_TAG 设为与 gateway.yml images.tag 相同
```

## 首次部署（Ansible 推荐）

### 1. 构建并推送镜像

```bash
make build-gateway-images
make push-gateway-images
```

### 2. 配置 Vault 与 inventory

- `gateway.certbot.email` 改为真实邮箱
- `secrets.yml`：`gateway_secrets.aliyun_dns_*`
- `gateway.images.tag` 与已 push 的 tag 一致

### 3. Staging 演练（可选，在 dev-01 手工）

将 inventory 或 `.env` 中 `CERTBOT_STAGING=1`，`ansible-playbook gateway-compose.yml` 或目标机 `make issue-staging`。

Staging 证书**不受微信信任**，仅验证 DNS-01。

### 4. 执行 playbook

```bash
make stage-gateway-compose-preflight
ansible-playbook ansible/playbooks/gateway-compose.yml \
  -i ansible/inventories/dev/ --limit dev-01 --vault-password-file .vault_pass
```

Playbook 会：停用宿主机 nginx → 同步 `/opt/gateway/compose` → 渲染 `.env` → **pull 三镜像** → `compose up`（`build: never`）。

### 5. 公网与微信验收

```bash
curl -s "https://backend.jxqydw.com/healthz"
curl -s "https://backend.jxqydw.com/readyz"
```

- 勿使用 `curl -k` 作为最终验收
- 微信公众平台配置 request 合法域名：`backend.jxqydw.com`

## 手工在目标机运维（应急）

```bash
cd /opt/gateway/compose
docker compose pull
docker compose up -d
make -C /opt/gateway/compose verify   # 若已同步 scripts
```

## 运维

### 查看状态与日志

```bash
cd /opt/gateway/compose
docker compose ps -a
docker compose logs -f certbot-renew nginx
docker compose logs certbot-init
docker compose exec nginx nginx -t
```

### 强制重新签发

```bash
CERTBOT_FORCE_ISSUE=1 docker compose run --rm certbot-init
docker compose up -d certbot-renew nginx
```

### 续期

`certbot-renew` 默认每 12 小时执行 `certbot renew`；成功时通过 docker.sock 向 `dev-gateway-nginx` 发送 SIGHUP。

### WireGuard 内网（可选）

`.env` 中 `NGINX_INTERNAL_SERVER_NAMES=dev-app.internal 10.200.0.2` 时，额外提供 **HTTP** 反代。

## 故障排查

| 现象 | 排查 |
|------|------|
| pull 失败 | 镜像未 push、`gateway.images.tag` 不一致、registry 未 login |
| init 失败 | `docker compose logs certbot-init`；RAM 权限、DNS 传播 |
| renew 不健康 | ready 文件与证书路径 |
| nginx 未启动 | renew 未 healthy |
| 502 | 上游 `127.0.0.1:8080` |
| 80/443 冲突 | 宿主机 nginx 未停 |

## 回滚（应急）

```bash
docker compose down
sudo systemctl enable --now nginx
```

保留 `dev-gateway-letsencrypt` 卷。

## 相关路径

| 路径 | 说明 |
|------|------|
| `scripts/docker/build-gateway-images.sh` | 手工 build / push |
| `docker/dev-gateway/docker-compose.yml` | Compose（image 来自 .env） |
| `ansible/inventories/dev/group_vars/all/gateway.yml` | 镜像 tag、compose 路径 SSOT |
| `ansible/playbooks/gateway-compose.yml` | 部署 playbook |
