# Hub 管理面 Nginx 网关（阶段 G1）

在 **hub-01** 安装宿主机 Nginx，为 JumpServer 等管理面服务提供 **WireGuard 内网统一 HTTPS 入口**。

**状态（2026-06-15）**：已部署并验收通过（`nginx.status: operational`）。验收报告：[docs/acceptance/20260615-阶段G1-Hub-Nginx验收.md](../acceptance/20260615-阶段G1-Hub-Nginx验收.md)。

## 前提

- 阶段 F：WireGuard `operational`（`ping`/`ssh deploy@10.200.0.1` 正常）
- 阶段 G0/G1：安全组 `IN-HTTPS-WG`、`IN-HTTP-WG`（`10.200.0.0/16` → TCP 443/80）已添加并验收
- `deploy@hub-01` 免密 sudo（`stage-g1-nginx-preflight.sh` 会自动检测）

## 在 ci-01 上执行

```bash
cd ~/infra-ops
export ANSIBLE_PRIVATE_KEY_FILE=~/infra-ops/ansible/keys/infra-ci-deploy

chmod +x scripts/mgmt/stage-g1-nginx-preflight.sh
./scripts/mgmt/stage-g1-nginx-preflight.sh

# 预览（仅看 diff；handler reload、post_tasks 验收在 check mode 下跳过）
ansible-playbook ansible/playbooks/nginx-hub.yml \
  -i ansible/inventories/mgmt/ \
  --limit hub-01 \
  --check --diff

# 正式部署
ansible-playbook ansible/playbooks/nginx-hub.yml \
  -i ansible/inventories/mgmt/ \
  --limit hub-01
```

## 部署内容

| vhost | 地址 | 说明 |
|-------|------|------|
| 默认 | `hub.internal`、`10.200.0.1` | 导航页 + `/health` |
| JumpServer 预留 | `jms.internal` | 反代 `127.0.0.1:8080`（`deploy_status=pending` 时 **503** + `/jms/status`） |

TLS：内网自签证书（`hub.internal` / `jms.internal` SAN），浏览器需 `-k` 或信任自签。

> **与 G2 的分工**：`nginx-hub.yml` 仅刷新 Nginx（role `nginx/tasks/hub.yml` 含 G2 维护页模板）。
> 完整 G2（dnsmasq + Nginx + 验收）请用 [`hub-g2.yml`](../dns/hub-internal-dns.runbook.md) 与 `make stage-g2-preflight`。

## 验收

```bash
# ci-01 或笔记本（已连 WG）— 默认 vhost 用 IP 即可
curl -k https://10.200.0.1/health
nc -zv 10.200.0.1 443

# jms.internal — G1 验收时为 502；G2 hub-g2.yml 后为 503 + /jms/status JSON
# 无内网 DNS 时可用 --resolve 指定 SNI：
curl -k --resolve jms.internal:443:10.200.0.1 \
  -o /dev/null -w "%{http_code}\n" https://jms.internal/
# G2 后期望 503（JumpServer 未部署）

curl -k --resolve jms.internal:443:10.200.0.1 https://jms.internal/jms/status
# G2 后期望 JSON deploy_status=pending

curl -k --resolve hub.internal:443:10.200.0.1 https://hub.internal/health
```

未添加 `IN-HTTP-WG` 时，从 WG 客户端访问 `10.200.0.1:80` 可能超时（安全组过滤）。**当前环境已添加并验收通过**（2026-06-15）。

部署成功后须更新 `ansible/inventories/mgmt/group_vars/all/nginx.yml`（**已完成**）：

```yaml
nginx:
  enabled: true
  status: operational
```

并运行 `make inventory-mgmt`。

## TLS 证书轮换

自签证书由 Ansible 在首次 apply 时生成（`creates` 保证幂等）。若需更新 SAN 或过期重签：

```bash
# 在 hub-01（经 Ansible 或 SSH）
sudo rm -f /etc/nginx/ssl/hub-internal.crt /etc/nginx/ssl/hub-internal.key

# 在 ci-01 重新 apply
ansible-playbook ansible/playbooks/nginx-hub.yml \
  -i ansible/inventories/mgmt/ --limit hub-01
```

## Ansible 组件

| 路径 | 说明 |
|------|------|
| `ansible/playbooks/nginx-hub.yml` | Playbook |
| `ansible/roles/nginx/` | Role |
| `ansible/inventories/mgmt/group_vars/all/nginx.yml` | 变量 |
