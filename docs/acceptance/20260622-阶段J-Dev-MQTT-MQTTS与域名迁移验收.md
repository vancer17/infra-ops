# 阶段 J — Dev MQTT MQTTS（路线 A）与 API 域名迁移验收

**完成日期**：2026-06-22  
**控制机**：ci-01（与 dev-01 同 ECS）  
**目标主机**：dev-01  
**验收日志**：`logs/console-acceptance.log`、`logs/console-check.log`

---

## 结论

**Dev 公网 API 域名已迁移至已备案主域 `yizuxing.com`；MQTT 采用路线 A（公网 MQTTS 8883，明文 1883 仅本机回环）；Compose 网关镜像升至 `1.0.2`（修复 stream 模板路径）。**

| 项 | 状态 |
|----|------|
| API 域名 | `backend.yizuxing.com`（替代 `backend.jxqydw.com`，后者外网 Beaver 403） |
| MQTT 域名 | `mqtt.yizuxing.com` |
| LE 证书 | 一张证 SAN：`backend.yizuxing.com` + `mqtt.yizuxing.com`；到期 2026-09-20 |
| 网关镜像 | `infra-ops/*:1.0.2` |
| Ansible 部署路径 | `/opt/gateway/compose` |
| MQTT 路线 | A — Nginx `stream` TLS 终止 `:8883` → `127.0.0.1:1883` |

---

## 背景

1. **域名备案**：`backend.jxqydw.com` 外网 HTTP 返回 403（Server: Beaver，未备案）；`backend.yizuxing.com` 外网 HTTP 301 / HTTPS 200。
2. **MQTT**：原生 MQTT 不能走 HTTP `location` 反代；无 1883→8883 协议跳转。公网仅开放 **8883 MQTTS**，**1883 不对公网暴露**。
3. **镜像 1.0.1 缺陷**：`mqtt-stream.conf.template` 置于 `/etc/nginx/templates/` 时被官方 `20-envsubst-on-templates.sh` 误渲染到 `conf.d/`（http 上下文），nginx 启动失败；**1.0.2** 移至 `stream-templates/` 并清理 stray 文件。

---

## 架构（当前）

```text
小程序 / 公网 API  →  backend.yizuxing.com:443 (LE, http)
                   →  127.0.0.1:8080 (petintelli-backend)

设备 / 公网 MQTT   →  mqtt.yizuxing.com:8883 (LE, stream TLS)
                   →  127.0.0.1:1883 (Broker 明文，仅回环)

certbot-init / renew (DNS-01) → dev-gateway-letsencrypt 卷
nginx (network_mode: host)    → 80 / 443 / 8883 直接监听宿主机
```

---

## 变更摘要

| 类别 | 内容 |
|------|------|
| Inventory | `gateway.yml`：`mqtt.*`、`certbot.domains` 含 mqtt；`images.tag: 1.0.2` |
| Inventory | `network.yml`：`app_ports.mqtt_tls: 8883`；`IN-MQTT-TLS-PUBLIC-DEV` |
| Nginx 镜像 | `stream.d/mqtt-stream.conf`；`host` 网络；`PORTS` 列为空属正常 |
| 部署 | `ansible-playbook gateway-compose.yml --limit dev-01` |

---

## 验收检查项

| 检查 | 结果 | 说明 |
|------|------|------|
| `dev-gateway-nginx` | healthy | `infra-ops/dev-nginx:1.0.2` |
| `dev-gateway-certbot-renew` | healthy | |
| `conf.d` 无 `mqtt-stream.conf` | ok | 1.0.2 修复 |
| `stream.d/mqtt-stream.conf` | ok | 8883 → 127.0.0.1:1883 |
| `nginx -t` | ok | |
| LE SAN | ok | `DNS:backend.yizuxing.com, DNS:mqtt.yizuxing.com` |
| `ss -tln :8883` | ok | 宿主机监听（host 模式） |
| `ss -tln :1883` | ok | 仅 `127.0.0.1:1883` |
| MQTTS SNI verify | ok | `mqtt.yizuxing.com:8883` verify=0 |
| HTTPS `/healthz` | 200 | `ssl_verify=0` |
| HTTPS `/readyz` | 200 | RDS 就绪 |
| HTTP → HTTPS | 301 | 无 Beaver 403 |
| RDS 路由 | ok | `eth0`，非 docker 网桥 |
| Docker `certbot-internal` | ok | `172.30.0.0/24` |

---

## 命令摘录

```bash
# Ansible apply 后
cd /opt/gateway/compose && ./scripts/verify-gateway.sh

curl -sS -o /dev/null -w 'healthz: %{http_code} ssl=%{ssl_verify_result}\n' \
  https://backend.yizuxing.com/healthz

echo | openssl s_client -connect mqtt.yizuxing.com:8883 \
  -servername mqtt.yizuxing.com 2>&1 | grep 'Verify return code'
```

---

## 待办（非阻塞）

| 项 | 说明 |
|----|------|
| 微信公众平台 | request 合法域名改为 `backend.yizuxing.com` |
| 安全组控制台 | 确认入站 TCP 8883 已放行；1883 未对公网开放 |
| MQTT Broker | 生产级 EMQX/Mosquitto compose 纳入 infra-ops（当前验收期可有临时 Broker） |
| 旧域 `jxqydw.com` | 文档与客户端配置逐步去除引用 |

---

## 相关文档

- [Dev Gateway Runbook](../docker/dev-gateway.runbook.md)
- [阶段 4 Compose LE 验收](./20260617-阶段4-Dev-Gateway-Compose-LE验收.md)（历史；域名仍为 jxqydw）
- `ansible/inventories/dev/group_vars/all/gateway.yml`
- `docs/assets/dev-01.yaml`
