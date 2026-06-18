# Dev 业务 API 出口（阶段 3 / 阶段 4）

dev-01 业务 API 出口：**Compose 网关**（当前）或 **宿主机 Nginx**（历史）。

**状态（2026-06-17）**：`nginx.runtime: compose`，`gateway.status: operational`。公网 HTTPS 使用 **Let's Encrypt** + `backend.jxqydw.com`。验收见 [阶段 4](../acceptance/20260617-阶段4-Dev-Gateway-Compose-LE验收.md)。

## 架构（Compose — 当前）

```text
小程序 / 公网  →  backend.jxqydw.com:443（LE）→ 127.0.0.1:8080（petintelli-backend）
WG 内网        →  dev-app.internal:80（HTTP）→ 127.0.0.1:8080
```

| 访问方 | 入口 |
|--------|------|
| 微信小程序 / 公网 | `https://backend.jxqydw.com` |
| WG 开发机 | `http://dev-app.internal`（DNS → `10.200.0.2`） |
| 本机调试 | `http://127.0.0.1:8080/healthz`（不经 Nginx） |

8080 **不对公网开放**（安全组无 8080 入站）。

## Compose 网关（SSOT）

| 项 | 说明 |
|----|------|
| Runbook | [docs/docker/dev-gateway.runbook.md](../docker/dev-gateway.runbook.md) |
| Playbook | `ansible/playbooks/gateway-compose.yml` |
| Inventory | `gateway.yml`、`nginx.runtime: compose` |
| 手工路径 | `~/infra-ops/docker/dev-gateway` |

```bash
cd ~/infra-ops/docker/dev-gateway
./scripts/verify-gateway.sh
```

## 架构（host 模式 — 历史，2026-06-16）

```text
WG / 公网  →  dev-01 宿主机 Nginx :443（自签）→  127.0.0.1:8080
```

仅作回滚参考；**勿与 Compose 同时占用 80/443**。验收：[阶段 3](../acceptance/20260616-阶段3-Dev业务Nginx与占位API验收.md)。

```bash
# 仅 nginx.runtime: host 时
make stage-dev-nginx-preflight
ansible-playbook ansible/playbooks/nginx-dev.yml \
  -i ansible/inventories/dev/ --limit dev-01
```

## 变量 SSOT

| 文件 | 内容 |
|------|------|
| `gateway.yml` | Compose、LE DNS-01、镜像、Docker 网段 |
| `nginx.yml` | `runtime`、server_name 语义、upstream |
| `app.yml` | PetIntelli / Compose @ 8080 |

## 验收（Compose）

```bash
curl -sS https://backend.jxqydw.com/healthz
curl -sS --max-time 15 https://backend.jxqydw.com/readyz
echo | openssl s_client -connect backend.jxqydw.com:443 -servername backend.jxqydw.com 2>&1 | grep "Verify return code"
```

## 安全组（dev-01 / ci-01 同机）

见 `network.yml` → `security_group_ingress`：

- `IN-HTTP-WG` / `IN-HTTPS-WG` ← `10.200.0.0/16`
- `IN-HTTP-PUBLIC-DEV` / `IN-HTTPS-PUBLIC-DEV` ← `0.0.0.0/0`

## 相关

- `ansible/roles/gateway_compose/` — Ansible 部署
- `docker/dev-gateway/` — Compose 项目与 `verify-gateway.sh`
