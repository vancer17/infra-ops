# Dev 业务 API 出口（阶段 3 / 阶段 4 / 阶段 J）

dev-01 业务 API 与 MQTT 公网出口：**Compose 网关**（当前）或 **宿主机 Nginx**（历史）。

**状态（2026-06-22）**：`nginx.runtime: compose`，`gateway.status: operational`。API **Let's Encrypt** + `backend.yizuxing.com`；MQTT 路线 A **`mqtt.yizuxing.com:8883`**。验收见 [阶段 J](../acceptance/20260622-阶段J-Dev-MQTT-MQTTS与域名迁移验收.md)。

## 架构（Compose — 当前）

```text
小程序 / 公网 API  →  backend.yizuxing.com:443（LE）→ 127.0.0.1:8080（petintelli-backend）
设备 / 公网 MQTT   →  mqtt.yizuxing.com:8883（stream TLS）→ 127.0.0.1:1883（Broker）
WG 内网            →  dev-app.internal:80（HTTP）→ 127.0.0.1:8080
```

| 访问方 | 入口 |
|--------|------|
| 微信小程序 / 公网 API | `https://backend.yizuxing.com` |
| 硬件 / 设备 MQTT | `mqtts://mqtt.yizuxing.com:8883` |
| WG 开发机 | `http://dev-app.internal`（DNS → `10.200.0.2`） |
| 本机调试 | `http://127.0.0.1:8080/healthz`（不经 Nginx） |

8080、1883 **不对公网开放**（安全组无公网入站；1883 仅 `127.0.0.1`）。

## Compose 网关（SSOT）

| 项 | 说明 |
|----|------|
| Runbook | [docs/docker/dev-gateway.runbook.md](../docker/dev-gateway.runbook.md) |
| Playbook | `ansible/playbooks/gateway-compose.yml` |
| Inventory | `gateway.yml`、`nginx.yml`、`network.yml` |
| Ansible 路径 | `/opt/gateway/compose` |
| 手工路径 | `~/infra-ops/docker/dev-gateway` |

```bash
cd /opt/gateway/compose
./scripts/verify-gateway.sh
```

## 架构（host 模式 — 历史，2026-06-16）

```text
WG / 公网  →  dev-01 宿主机 Nginx :443（自签）→  127.0.0.1:8080
```

仅作回滚参考；**勿与 Compose 同时占用 80/443**。验收：[阶段 3](../acceptance/20260616-阶段3-Dev业务Nginx与占位API验收.md)。

## 变量 SSOT

| 文件 | 内容 |
|------|------|
| `gateway.yml` | Compose、LE DNS-01、镜像、MQTT、`gateway.mqtt.*` |
| `nginx.yml` | `runtime`、server_name 语义、upstream |
| `network.yml` | `app_ports.mqtt_tls`、安全组 `IN-MQTT-TLS-PUBLIC-DEV` |
| `app.yml` | PetIntelli / Compose @ 8080 |

## 验收（Compose）

```bash
curl -sS https://backend.yizuxing.com/healthz
curl -sS --max-time 15 https://backend.yizuxing.com/readyz
echo | openssl s_client -connect backend.yizuxing.com:443 -servername backend.yizuxing.com 2>&1 | grep "Verify return code"
echo | openssl s_client -connect mqtt.yizuxing.com:8883 -servername mqtt.yizuxing.com 2>&1 | grep "Verify return code"
```

## 安全组（dev-01 / ci-01 同机）

见 `network.yml` → `security_group_ingress`：

- `IN-HTTP-WG` / `IN-HTTPS-WG` ← `10.200.0.0/16`
- `IN-HTTP-PUBLIC-DEV` / `IN-HTTPS-PUBLIC-DEV` ← `0.0.0.0/0`
- `IN-MQTT-TLS-PUBLIC-DEV` ← TCP `8883` / `0.0.0.0/0`
- **不暴露** 公网 `1883`、`8080`

## 域名说明

| 域名 | 状态 |
|------|------|
| `backend.yizuxing.com` | **当前** API；已备案；外网 HTTPS 200 |
| `mqtt.yizuxing.com` | **当前** MQTTS |
| `backend.jxqydw.com` | **废弃**；外网 Beaver 403（未备案） |

## 相关

- `ansible/roles/gateway_compose/` — Ansible 部署
- `docker/dev-gateway/` — Compose 项目与 `verify-gateway.sh`
- `docker/nginx/stream-templates/` — MQTTS stream 模板（勿放入 `templates/`）
