# Dev Inventory（`inventories/dev/`）

应用环境主机清单与变量，与 `inventories/mgmt/`（Hub 管理面）分离。

## 主机分组

| 分组 | 主机 | 职责 |
|------|------|------|
| `dev_app` | dev-01 | 业务 Nginx 统一出口 + 应用/占位 API |
| `dev_worker` | dev-02 | Redis / Worker（无业务 Nginx） |
| `jumpserver_assets` | dev-01、dev-02 | JumpServer 纳管元数据 |

## `group_vars/all/` 文件分工

| 文件 | 说明 |
|------|------|
| `bootstrap.yml` | Bootstrap、Docker |
| `main.yml` | `env_name`、时区、OSS |
| `network.yml` | IP 台账、RDS、安全组入站摘要 |
| `app.yml` | 占位 API、Compose 路径、客户端类型 |
| `nginx.yml` | 业务 Nginx 语义；`nginx.runtime`：`host` 或 `compose` |
| `gateway.yml` | Compose 网关（LE DNS-01、镜像 tag、项目路径、.env 非敏感键） |
| `secrets.yml.example` | Vault 明文结构（`app_secrets`、`gateway_secrets`） |
| `ssh.yml` | SSH 密钥 |

## `host_vars/`

| 文件 | 关键变量 |
|------|----------|
| `dev-01.yml` | `nginx_app_gateway`、`gateway_compose_host`、`app_deploy_host` |
| `dev-02.yml` | 无业务 Nginx 网关 |

## 常用命令

```bash
make inventory
ansible-inventory -i ansible/inventories/dev/ --graph
ansible dev-01 -i ansible/inventories/dev/ -m debug -a var=nginx -c local
```

## 资产同步

修改 IP、域名、安全组后同步：

1. `docs/assets/dev-01.yaml`
2. `group_vars/all/network.yml`、`nginx.yml`、`app.yml`
3. `make inventory`

## 阶段 2 → 阶段 3（2026-06-16 已验收）

| 变量 | apply 后状态 |
|------|--------------|
| `app.enabled` | `true` |
| `app.deploy_status` | `operational`（PetIntelli） |
| `nginx.enabled` | `true` |
| `nginx.runtime` | `compose` |
| `nginx.status` | `operational` |
| `gateway.status` | `operational` |
| `dev_hosts.dev-01.nginx_app_status` | `operational` |
| `dev_hosts.dev-01.gateway_compose_status` | `operational` |

验收（Compose LE）：[docs/acceptance/20260617-阶段4-Dev-Gateway-Compose-LE验收.md](../../docs/acceptance/20260617-阶段4-Dev-Gateway-Compose-LE验收.md)

历史（host 自签）：[docs/acceptance/20260616-阶段3-Dev业务Nginx与占位API验收.md](../../docs/acceptance/20260616-阶段3-Dev业务Nginx与占位API验收.md)

## 阶段 3 Playbook

| Playbook | Role | 目标 |
|----------|------|------|
| `ansible/playbooks/dev-app.yml` | `app_deploy` | 占位 API / 业务 Compose @ `127.0.0.1:8080` |
| `ansible/playbooks/nginx-dev.yml` | `nginx`（`tasks_from: dev-app`） | **仅 `nginx.runtime: host`**：宿主机 80/443 |
| `ansible/playbooks/gateway-compose.yml` | `gateway_compose` | **`nginx.runtime: compose`**：LE + 容器 Nginx |

**推荐顺序（Compose 网关）**：`make build-gateway-images` → `dev-app.yml` → `gateway-compose.yml`（`delivery=local` 时在 dev-01 构建；跨机用 `save-gateway-images` + `delivery=bundle`）

```bash
make stage-dev-app-preflight
ansible-playbook ansible/playbooks/dev-app.yml -i ansible/inventories/dev/ --limit dev-01

make stage-gateway-compose-preflight
ansible-playbook ansible/playbooks/gateway-compose.yml \
  -i ansible/inventories/dev/ --limit dev-01 --vault-password-file .vault_pass
```

割接成功后更新 inventory：`nginx.runtime: compose`、`gateway.status: operational`。

**宿主机 Nginx（回滚/未迁移）**：`nginx.runtime: host` 时 `dev-app.yml` → `nginx-dev.yml`

```bash
make stage-dev-nginx-preflight
ansible-playbook ansible/playbooks/nginx-dev.yml -i ansible/inventories/dev/ --limit dev-01
```

若 `become` 报 sudo 密码错误，在 dev-01 重新应用 bootstrap users（写入 `deploy-app-host` sudoers）：

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventories/dev/ --limit dev-01 --tags sudo
```
