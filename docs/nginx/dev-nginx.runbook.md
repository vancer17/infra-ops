# Dev 业务 Nginx 与占位 API（阶段 3）

dev-01 业务 API 出口：**宿主机 Nginx**（`nginx.runtime: host`）或 **Compose 网关**（`nginx.runtime: compose`）。

**状态（2026-06-16）**：`nginx.status: operational`（host 模式验收）。迁移 Compose 见 [Dev Gateway Runbook](../docker/dev-gateway.runbook.md)。

## 架构（host 模式 — 历史）

```text
WG / 公网  →  dev-01 Nginx :443  →  127.0.0.1:8080  →  dev-app-placeholder（或真实业务容器）
```

| 访问方 | 入口 |
|--------|------|
| WG 开发机 | `https://dev-app.internal`（DNS → `10.200.0.2`） |
| 公网 / 小程序联调 | `https://121.41.58.20` |
| 本机调试 | `http://127.0.0.1:8080`（不经 Nginx） |

8080 **不对公网开放**（安全组无 8080 入站）。

## Compose 网关（推荐 — 小程序 LE 证书）

| 项 | 说明 |
|----|------|
| Playbook | `ansible/playbooks/gateway-compose.yml` |
| Runbook | [docs/docker/dev-gateway.runbook.md](../docker/dev-gateway.runbook.md) |
| Inventory | `gateway.yml`、`nginx.runtime: compose` |

```bash
make stage-gateway-compose-preflight
ansible-playbook ansible/playbooks/gateway-compose.yml \
  -i ansible/inventories/dev/ --limit dev-01 --vault-password-file .vault_pass
```

## 架构（host 模式）

| 文件 | 内容 |
|------|------|
| `ansible/inventories/dev/group_vars/all/nginx.yml` | Nginx 80/443、server_name、SSL、upstream |
| `ansible/inventories/dev/group_vars/all/app.yml` | 占位 API / Compose / 镜像 |
| `ansible/inventories/dev/group_vars/all/network.yml` | `dev_hosts.dev-01` 业务状态 |

## Playbook

```bash
export ANSIBLE_PRIVATE_KEY_FILE=~/infra-ops/ansible/keys/infra-ci-deploy

# 顺序：先应用，后 Nginx
make stage-dev-app-preflight
ansible-playbook ansible/playbooks/dev-app.yml \
  -i ansible/inventories/dev/ --limit dev-01

make stage-dev-nginx-preflight
ansible-playbook ansible/playbooks/nginx-dev.yml \
  -i ansible/inventories/dev/ --limit dev-01
```

首次 apply 前若 `become` 报 sudo 错误：

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventories/dev/ --limit dev-01 --tags sudo
```

## 验收

```bash
# dev-01 本机
curl -sf http://127.0.0.1:8080/
curl -sk https://127.0.0.1/health

# WG 笔记本
curl -sk https://dev-app.internal/health

# 公网
curl -sk https://121.41.58.20/health
curl -sI http://121.41.58.20/health   # 期望 301
```

## 安全组（dev-01 / ci-01 同机）

见 `logs/remark.log` / `network.yml` → `security_group_ingress`：

- `IN-HTTP-WG` / `IN-HTTPS-WG` ← `10.200.0.0/16`
- `IN-HTTP-PUBLIC-DEV` / `IN-HTTPS-PUBLIC-DEV` ← `0.0.0.0/0`

## 相关 Role / 模板

- `ansible/roles/app_deploy/` — Compose、`.env`、占位容器
- `ansible/roles/nginx/tasks/dev-app.yml` — 业务 Nginx vhost
