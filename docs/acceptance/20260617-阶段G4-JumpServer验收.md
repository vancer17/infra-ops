# 阶段 G4 — Hub JumpServer Compose 验收

**状态**：待 apply（代码与 playbook 已就绪）  
**目标主机**：hub-01（10.200.0.1）  
**控制机**：ci-01（yax / deploy）

## 范围

- 部署 `jms_all` 单容器至 `/opt/mgmt/jumpserver`
- 镜像：`5yrqsf19ms2mh4.xuanyuan.run/jumpserver/jms_all:v4.10.16`
- 监听 `127.0.0.1:8080`（HTTP）、`127.0.0.1:2222`（SSH/Koko）
- Nginx `jms.internal` 从 503 维护页切换为反代模式
- `/jms/status` → `deploy_status: ready`

## 前置条件

| 项 | 要求 |
|----|------|
| G3 Hub Docker | `hub_docker.status=operational` |
| G2 内网 DNS | `internal_dns.status=operational` |
| G1 Nginx | `nginx.status=operational` |
| WireGuard | `wireguard.status=operational` |
| Vault | `jumpserver_vault.yml` 已加密提交 |

## 执行步骤

```bash
cd ~/infra-ops
./scripts/mgmt/jumpserver-vault-init.sh   # 首次
make stage-g4-jumpserver-preflight

ansible-playbook ansible/playbooks/hub-g4-jumpserver.yml \
  -i ansible/inventories/mgmt/ --limit hub-01 \
  --vault-password-file .vault_pass

./scripts/mgmt/verify-hub-jumpserver-remote.sh
```

## 验收检查清单

### Hub 本机（verify-hub-jumpserver-remote.sh）

- [ ] `docker compose ps` 显示 `jms_all` running
- [ ] `curl http://127.0.0.1:8080/` → 200/302/401
- [ ] `curl -k -H Host:jms.internal https://127.0.0.1/` → 200/302（非 503）
- [ ] `/jms/status` JSON 中 `deploy_status` 为 `ready`

### ci-01 / 办公笔记本（WG 已连）

- [ ] `curl -k https://jms.internal/jms/status` → `deploy_status: ready`
- [ ] `curl -k -o /dev/null -w '%{http_code}\n' https://jms.internal/` → 200 或 302
- [ ] 浏览器打开 `https://jms.internal/` 可见登录页
- [ ] `admin` / `ChangeMe` 可登录（**登录后立即改密**）

### Inventory / CI

- [ ] `jumpserver.status=operational`
- [ ] `nginx.jumpserver.deploy_status=ready`
- [ ] `docs/assets/hub-01.yaml` → `jumpserver_status: operational`
- [ ] `make inventory-mgmt` 与 `make ci` 通过

## 回滚

```bash
ssh deploy@10.200.0.1 'cd /opt/mgmt/jumpserver && docker compose down'
# 将 nginx.jumpserver.deploy_status 改回 pending 并重跑 nginx-hub.yml 或 hub-g2.yml
```

## 参考

- Runbook：[hub-jumpserver.runbook.md](../jumpserver/hub-jumpserver.runbook.md)
- Playbook：`ansible/playbooks/hub-g4-jumpserver.yml`
