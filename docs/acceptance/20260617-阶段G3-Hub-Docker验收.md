# 阶段 G3：Hub 启用 Docker — 验收清单

> **控制机**：ci-01（yax）  
> **目标主机**：hub-01（`10.200.0.1` WG / `172.21.127.123` 私网）  
> **Playbook**：`ansible/playbooks/hub-g3-docker.yml`  
> **前提**：阶段 F + G1 + G2 已 operational  
> **验收日期**：2026-06-17  
> **结论**：**通过**

## 一、目标

| 项 | 说明 |
|----|------|
| Docker CE | 官方 apt 源安装，含 compose 插件 |
| deploy 用户 | 加入 `docker` 组 |
| 目录 | `/opt/mgmt/jumpserver/{data,static}` |
| 验收 | `docker run` smoke 成功；**不**部署 JumpServer 容器 |

## 二、执行前

```bash
make stage-g3-docker-preflight
```

确认：

- [x] `wireguard.status=operational`
- [x] `nginx.status=operational`
- [x] `internal_dns.status=operational`
- [x] `hub_docker.enabled=true`
- [x] `deploy@10.200.0.1` 可 `sudo -n true`

## 三、执行

预览（可选，`--check` 下 apt 装包会跳过，见 runbook）：

```bash
ansible-playbook ansible/playbooks/hub-g3-docker.yml \
  -i ansible/inventories/mgmt/ \
  --limit hub-01 \
  --vault-password-file .vault_pass \
  --check --diff
```

正式 apply：

```bash
ansible-playbook ansible/playbooks/hub-g3-docker.yml \
  -i ansible/inventories/mgmt/ \
  --limit hub-01 \
  --vault-password-file .vault_pass
```

## 四、验收命令

```bash
./scripts/mgmt/verify-hub-docker-remote.sh
```

| # | 检查项 | 通过标准 | 结果 |
|---|--------|----------|------|
| 1 | docker 命令 | `docker --version` 成功 | Docker 29.5.3 |
| 2 | compose 插件 | `docker compose version` 成功 | v5.1.4 |
| 3 | deploy 组 | `id deploy` 含 `docker` | groups 含 docker(993) |
| 4 | 目录 | `/opt/mgmt/jumpserver/data` 存在 | OK |
| 5 | smoke | `deploy` 用户 `docker run --rm` hello-world 成功 | smoke OK |
| 6 | 服务 | `systemctl is-active docker` → active | active |
| 7 | Nginx 未变 | `curl -k https://jms.internal/jms/status` 仍为 `deploy_status: pending` | pending |
| 8 | inventory | `hub_docker.status` 更新为 `operational` | operational |

## 五、台账

已更新：

- `ansible/inventories/mgmt/group_vars/all/docker.yml` → `hub_docker.status: operational`
- `docs/assets/hub-01.yaml` → `lifecycle.docker_status: operational`、`stage_g3_hub_docker`
- `docs/assets/registry.yaml` → `hub_docker_status: operational`
- `logs/console-acceptance.log` → G3 验收记录

## 六、下一步

JumpServer Compose 部署（G3+1）→ `nginx.jumpserver.deploy_status: ready`
