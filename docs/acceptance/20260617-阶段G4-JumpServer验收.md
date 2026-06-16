# 阶段 G4：Hub JumpServer Compose — 验收清单

> **控制机**：ci-01（yax / deploy）  
> **目标主机**：hub-01（`10.200.0.1` WG）  
> **Playbook**：`ansible/playbooks/hub-g4-jumpserver.yml`  
> **前提**：阶段 F + G1 + G2 + G3 已 operational  
> **验收日期**：2026-06-17  
> **结论**：**通过**

## 一、目标

| 项 | 说明 |
|----|------|
| 容器 | `jms_all` @ `/opt/mgmt/jumpserver` |
| 镜像 | `5yrqsf19ms2mh4.xuanyuan.run/jumpserver/jms_all:v4.10.16` |
| 监听 | `127.0.0.1:8080`（HTTP）、`127.0.0.1:2222`（SSH/Koko） |
| Nginx | `jms.internal` 由 503 维护页切换为反代 |
| 状态 JSON | `/jms/status` → `deploy_status: ready` |

## 二、执行前

```bash
make stage-g4-jumpserver-preflight
```

确认：

- [x] `hub_docker.status=operational`
- [x] `nginx.status=operational`
- [x] `internal_dns.status=operational`
- [x] `jumpserver_vault.yml` 可解密
- [x] `deploy@10.200.0.1` 可 `sudo -n true`

## 三、执行

```bash
ansible-playbook ansible/playbooks/hub-g4-jumpserver.yml \
  -i ansible/inventories/mgmt/ \
  --limit hub-01 \
  --vault-password-file .vault_pass
```

## 四、验收命令

```bash
./scripts/mgmt/verify-hub-jumpserver-remote.sh
curl -k -s https://jms.internal/jms/status | python3 -m json.tool
curl -k -o /dev/null -w "%{http_code}\n" https://jms.internal/
dig +short @10.200.0.1 jms.internal
```

| # | 检查项 | 通过标准 | 结果 |
|---|--------|----------|------|
| 1 | compose ps | `jms_all` Up，`8080:80` / `2222:2222` | OK |
| 2 | Hub loopback | `curl http://127.0.0.1:8080/` → 200 | 200 |
| 3 | Hub Nginx | `curl -k -H Host:jms.internal https://127.0.0.1/` → 200 | 200 |
| 4 | status JSON | `deploy_status: ready` | ready |
| 5 | ci-01 WG | `curl -k https://jms.internal/jms/status` | ready |
| 6 | ci-01 根路径 | `curl -k https://jms.internal/` | 200 |
| 7 | ci-01 DNS | `dig @10.200.0.1 jms.internal` | 10.200.0.1 |
| 8 | 办公笔记本 WG | `curl -k https://jms.internal/jms/status` | ready |
| 9 | 办公笔记本根路径 | `curl -k https://jms.internal/` | 200 |
| 10 | inventory | `jumpserver.status=operational` | operational |
| 11 | inventory | `nginx.jumpserver.deploy_status=ready` | ready |

原始日志：`logs/console-acceptance.log`（G4 段，ci-01 + 办公笔记本）。

## 五、台账

已更新：

- `ansible/inventories/mgmt/group_vars/all/jumpserver.yml` → `status: operational`
- `ansible/inventories/mgmt/group_vars/all/nginx.yml` → `jumpserver.deploy_status: ready`
- `docs/assets/hub-01.yaml` → `lifecycle.jumpserver_status`、`stage_g4_hub_jumpserver`
- `docs/assets/registry.yaml` → `hub_jumpserver_status: operational`
- `logs/console-acceptance.log` → G4 验收记录

## 六、下一步

- [ ] 浏览器登录 `https://jms.internal/`，修改 `admin` / `ChangeMe` 默认密码
- [ ] JumpServer 资产纳管（Dev ECS 等）
- [ ] 评估关公网 SSH / 安全组收口（`steady_in_ssh_wg`）
- [ ] 可选：Self-hosted Runner、dev-02 Bootstrap

## 参考

- Runbook：[hub-jumpserver.runbook.md](../jumpserver/hub-jumpserver.runbook.md)
- Playbook：`ansible/playbooks/hub-g4-jumpserver.yml`
