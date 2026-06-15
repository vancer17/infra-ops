# Hub 管理面 Docker（阶段 G3）

在 **hub-01** 上启用 Docker CE，为 JumpServer Compose 部署做准备。

## 与 Dev Docker 的分工

| 主机 | 时机 | 用途 |
|------|------|------|
| dev-01 | Bootstrap 1.2 | 业务应用容器 |
| hub-01 | 阶段 G3（G2 之后） | JumpServer / 管理面 Compose |

Hub Bootstrap 刻意 `docker_install: false`；G3 通过 `group_vars/all/docker.yml` 覆盖为 `true`。

## 前提

- 阶段 F：`wireguard.status=operational`
- 阶段 G1：`nginx.status=operational`
- 阶段 G2：`internal_dns.status=operational`
- `deploy@hub-01` steady + 免密 sudo

## 在 ci-01 上执行

```bash
cd ~/infra-ops
source .venv/bin/activate
export ANSIBLE_PRIVATE_KEY_FILE=~/infra-ops/ansible/keys/infra-ci-deploy
export ANSIBLE_VAULT_PASSWORD_FILE=~/infra-ops/.vault_pass

chmod +x scripts/mgmt/stage-g3-docker-preflight.sh
chmod +x scripts/mgmt/verify-hub-docker-remote.sh

make stage-g3-docker-preflight

# 预览
ansible-playbook ansible/playbooks/hub-g3-docker.yml \
  -i ansible/inventories/mgmt/ \
  --limit hub-01 \
  --vault-password-file .vault_pass \
  --check --diff

# 正式执行
ansible-playbook ansible/playbooks/hub-g3-docker.yml \
  -i ansible/inventories/mgmt/ \
  --limit hub-01 \
  --vault-password-file .vault_pass

./scripts/mgmt/verify-hub-docker-remote.sh
```

## apply 后须更新 inventory

`ansible/inventories/mgmt/group_vars/all/docker.yml`：

```yaml
hub_docker:
  status: operational
```

同步 `docs/assets/hub-01.yaml` → `lifecycle.docker_status: operational`。

## 目录规划

| 路径 | 用途 |
|------|------|
| `/opt/mgmt/jumpserver` | Compose 项目根（下一阶段） |
| `/opt/mgmt/jumpserver/data` | JumpServer 数据卷 |
| `/opt/mgmt/jumpserver/static` | 静态资源 |

JumpServer 应监听 `127.0.0.1:8080`，与 `nginx.jumpserver_upstream` 一致。

## 下一步（非本阶段）

1. 在 `/opt/mgmt/jumpserver` 部署 JumpServer 官方 Compose  
2. `nginx.jumpserver.deploy_status: ready` + 重跑 `hub-g2.yml` 或 `nginx-hub.yml`  
3. `https://jms.internal/` 由 503 变为 JumpServer 登录页  

## 相关文档

- [docs/acceptance/20260617-阶段G3-Hub-Docker验收.md](../acceptance/20260617-阶段G3-Hub-Docker验收.md)
- [hub-01-bootstrap.runbook.md](../bootstrap/hub-01-bootstrap.runbook.md)
