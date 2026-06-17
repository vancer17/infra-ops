# Dev 业务网关 Compose（Nginx + LE DNS-01）

在 **dev-01** 上用 Compose 接管业务 API 公网出口，替代宿主机 Ansible Nginx + 自签证书。

## 镜像与镜像站说明

| 类型 | 示例 | 用途 |
|------|------|------|
| **公网基础镜像** | `certbot/certbot`、`nginx` | 构建时经 Docker 镜像加速拉取（如轩辕 `5yrqsf19ms2mh4.xuanyuan.run`） |
| **自建网关镜像** | `infra-ops/certbot-init:1.0.0` | 本地 `docker build` 打 tag，**不向轩辕 push** |
| **真实私有仓库（可选）** | 阿里云 ACR | `gateway.images.delivery=registry` + `registry_url` |

## 架构

```text
小程序 / 公网 → dev-01 :443（Compose nginx, LE）→ 127.0.0.1:8080
certbot-init → letsencrypt 卷 → certbot-renew → nginx reload
```

## 镜像分发（gateway.yml `images.delivery`）

| delivery | 说明 |
|----------|------|
| `local` | 在 **dev-01 本机** `make build-gateway-images` 后 compose / Ansible up |
| `bundle` | 控制机 `build` + `save`，Ansible 同步 `bundles/*.tar` 并 `docker load` |
| `registry` | 推送到 **阿里云 ACR 等真实仓库** 后 Ansible pull（非轩辕） |

镜像引用：`{{ namespace }}/{{ name }}:{{ tag }}` → 默认 `infra-ops/certbot-init:1.0.0`。

## 职责分工

| 环节 | 位置 | 命令 |
|------|------|------|
| 构建 | 有 Docker 的机器 | `make build-gateway-images` |
| 跨机分发 | 控制机 | `make save-gateway-images` |
| 部署 | dev-01 | `gateway-compose.yml` 或 `docker compose up` |

## 部署目录

| 路径 | 说明 |
|------|------|
| `/opt/gateway/compose/` | Compose 项目（Ansible 同步） |
| `docker/dev-gateway/bundles/` | `save` 生成的 tar（不提交 Git） |

## 发布新镜像

```bash
export GATEWAY_IMAGE_TAG=1.0.1
make build-gateway-images

# 同机部署（delivery=local）
# 更新 gateway.yml images.tag → ansible-playbook gateway-compose.yml

# 跨机部署（delivery=bundle）
make save-gateway-images
# gateway.yml: delivery=bundle, bundle_filename=infra-ops-gateway-1.0.1.tar
```

## 手工在 dev-01 测试

```bash
cd ~/infra-ops/docker/dev-gateway
cp .env.example .env   # 镜像名用 infra-ops/*:1.0.0
make -C ~/infra-ops build-gateway-images

sudo systemctl disable --now nginx
docker compose up -d
./scripts/verify-gateway.sh
```

## 故障排查

| 现象 | 排查 |
|------|------|
| 镜像不存在 | `delivery=local` 时先 `make build-gateway-images` |
| bundle 缺失 | `make save-gateway-images`，检查 `bundles/` 路径 |
| 误用轩辕 push | 轩辕仅加速公网镜像 pull，不能 `docker push infra-ops/*` 到轩辕 |
| init DNS 失败 | RAM 权限、TXT 传播时间 |
| `/readyz` 超时、`/healthz` 200 | `ip route get <RDS_IP>` 是否走 `br-*`；检查 `certbot-internal` 子网是否为 172.20/172.21；`compose down` 后重建网络 |
| 502 | `curl http://127.0.0.1:8080/healthz` |

## 相关路径

- `scripts/docker/build-gateway-images.sh` — build / save / list
- `ansible/inventories/dev/group_vars/all/gateway.yml` — SSOT
- `ansible/playbooks/gateway-compose.yml` — 部署
