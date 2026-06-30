# Dev Gateway device-management 路径隔离验收

| 项 | 说明 |
|----|------|
| 日期 | 2026-06-30 |
| 范围 | dev-01 业务面 Compose Nginx 新增 `/device-management` 路径隔离 |
| 网关镜像 | `infra-ops/dev-nginx:1.0.3` |
| 后端 upstream | `127.0.0.1:18080` |
| 前端目录 | `/home/deploy/device-management-system/frontend` |
| 部署路径 | `/opt/gateway/compose` |

## 结论

device-management-system 已通过业务面 Compose Nginx 对外暴露：

```text
/device-management/              -> 前端静态文件
/device-management/api/*          -> 127.0.0.1:18080/api/*
/device-management/healthz        -> 127.0.0.1:18080/healthz
/device-management/readyz         -> 127.0.0.1:18080/readyz
```

该入口不占用根路径 `/`，不改变后端监听端口，不使用 Hub 管理面 Nginx。

## 验收结果

| 检查项 | 结果 | 备注 |
|--------|------|------|
| `dev-gateway-nginx` | healthy | 镜像 `infra-ops/dev-nginx:1.0.3` |
| `nginx -t` | ok | 配置语法通过 |
| LE 证书 | ok | issuer: Let's Encrypt YE2 |
| Docker 网络 | ok | `dev-gateway-certbot-internal` = `172.30.0.0/24` |
| RDS 路由 | ok | `172.20.211.167` 走 `eth0`，非 Docker 网桥 |
| 旧业务 upstream | ok | `127.0.0.1:8080/healthz`、`/readyz` 均 200 |
| device-management upstream | ok | `127.0.0.1:18080/healthz`、`/readyz` 均 200 |
| 公网 `/device-management/healthz` | ok | HTTPS 200 |
| 公网 `/device-management/readyz` | ok | HTTPS 200 |
| 公网 `/device-management/api/auth/me` | ok | Bearer test 返回 401，说明已到达后端鉴权 |
| 公网 `/device-management/` | ok | 200 `text/html` |
| WG `/device-management/healthz` | ok | HTTP 200 |
| WG `/device-management/` | ok | 200 `text/html` |
| MQTTS | ok | `mqtt.yizuxing.com:8883` 保持正常 |

## 验收命令

```bash
cd /opt/gateway/compose
./scripts/verify-gateway.sh

curl -sS -i http://127.0.0.1:18080/healthz
curl -sS -i http://127.0.0.1:18080/readyz

curl -sS -i https://backend.yizuxing.com/device-management/healthz
curl -sS -i https://backend.yizuxing.com/device-management/readyz
curl -sS -i https://backend.yizuxing.com/device-management/api/auth/me \
  -H 'Authorization: Bearer test'
curl -sS -I https://backend.yizuxing.com/device-management/

curl -sS -i http://dev-app.internal/device-management/healthz
curl -sS -I http://dev-app.internal/device-management/
```

## 相关文件

- `ansible/inventories/dev/group_vars/all/gateway.yml`
- `ansible/playbooks/gateway-compose.yml`
- `docker/dev-gateway/docker-compose.yml`
- `docker/nginx/templates/dev-app.conf.template`
- `docker/nginx/templates/internal-http.conf.template`
- `docs/docker/dev-gateway.runbook.md`
