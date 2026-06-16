# 阶段 G5：JumpServer 资产纳管 — Hub-01 验收清单

> **控制机**：ci-01（yax / deploy）  
> **目标主机**：hub-01（`10.200.0.1` WG / `172.21.127.123` VPC）  
> **Ansible Playbook**：`ansible/playbooks/jumpserver-asset-prep.yml`  
> **前提**：阶段 G4 JumpServer `operational`；Hub `ssh_phase=steady`  
> **验收日期**：2026-06-17  
> **结论**：**通过**（Hub-01 资产账户推送与测试连接）

## 一、目标

| 项 | 说明 |
|----|------|
| Linux 用户 | `jump_ops` 可登录（Ansible `jump_ops` role） |
| JumpServer 节点 | `Mgmt/Hub`（另建 `Dev/ECS` 等预留节点） |
| 资产 | 控制台 **Hub-01**，IP `10.200.0.1`（回退 `172.21.127.123`） |
| 账户模板 | `linux-jump-ops` → 用户 `jump_ops` |
| 账号推送 | JumpServer 写入 `jump_ops` SSH 公钥 |
| 测试连接 | 控制台「测试连接」成功 |
| 隔离 | **未**录入 `deploy` 账户；**未**建 `ci-01` 重复资产 |

## 二、Ansible 执行与验收

```bash
make stage-jumpserver-asset-preflight LIMIT=hub-01
make jumpserver-asset-prep LIMIT=hub-01
./scripts/mgmt/verify-jumpserver-asset-remote.sh hub-01
```

| # | 检查项 | 通过标准 | 结果 |
|---|--------|----------|------|
| 1 | jump_ops shell | `getent passwd jump_ops` → `/bin/bash` | OK |
| 2 | .ssh 目录 | mode `700`，owner `jump_ops` | OK |
| 3 | sshd AllowUsers | 含 `deploy jump_ops` | OK |
| 4 | sudoers | `/etc/sudoers.d/jump_ops` 存在（ops profile） | OK |
| 5 | inventory | `make inventory-mgmt` 通过 | OK |
| 6 | secret-scan | `make secret-scan` 无泄漏 | OK |

原始日志：`logs/console-acceptance.log`（`verify-jumpserver-asset-remote` 段）、`logs/console-check.log`。

## 三、JumpServer 控制台配置（Hub-01）

### 3.1 节点树

| 节点路径 | 用途 | 本期资产 |
|----------|------|----------|
| `Mgmt/Hub` | 管理面 Hub | **Hub-01** |
| `Dev/ECS` | 开发 ECS | 预留（Dev-01 待纳管） |
| `Test/ECS` | 测试预留 | 空 |
| `Prod/ECS` | 生产预留 | 空 |

### 3.2 资产 Hub-01

| 字段 | 值 |
|------|-----|
| 名称 | `Hub-01` |
| IP/主机 | `10.200.0.1`（不通时 `172.21.127.123`） |
| 平台 | Linux |
| 节点 | `Mgmt/Hub` |
| 协议 | SSH 22、SFTP 22 |
| 账户 | 从模板 `linux-jump-ops`（`jump_ops`） |
| 推送 / 测试连接 | **已完成** |

与 inventory 对齐：`ansible/inventories/mgmt/host_vars/hub-01.yml` → `jumpserver_asset_console`。

## 四、运维备注（paramiko / 容器重启）

Hub 上排查 JumpServer 连通性时曾记录：

- 容器内 `python3` 与 `/opt/py3` 的 paramiko 版本不一致（5.0.0 vs 3.2.0）；`remote_client` 导入使用 5.0.0。
- 容器重启后若「测试连接」失败，可执行 `/opt/mgmt/jumpserver/install-paramiko.sh`（Hub 本地维护脚本）。
- Hub 经 `ssh deploy@10.200.0.1` 自连可能出现 **Broken pipe**；以 JumpServer 控制台测试连接为准。

## 五、台账

已更新：

- `docs/assets/hub-01.yaml` → `stage_g5_jumpserver_asset_hub`、`lifecycle.jumpserver_asset_hub_status`
- `docs/assets/registry.yaml` → `hub_jumpserver_asset_hub_status`
- `docs/jumpserver/asset-prep.runbook.md` → Hub-01 完成标记
- `ansible/inventories/mgmt/group_vars/all/jumpserver_asset.yml` → 控制台节点 SSOT

## 六、下一步

- [ ] **资产授权**：用户组 ↔ `Mgmt/Hub`（+ 后续 `Dev/ECS`）+ 账户 `jump_ops`；平台用户 MFA
- [ ] **端到端**：非管理员经 Web 终端登录 Hub-01，确认录像/命令记录
- [ ] Dev-01：`jumpserver-asset-prep` → 资产挂 `Dev/ECS`（**勿**重复建 ci-01）
- [ ] 修改 JumpServer `admin` 默认密码（若尚未完成）
- [ ] 评估关公网 SSH / `network_phase: steady`
- [ ] 可选：将 `install-paramiko.sh` 纳入 infra-ops 或容器启动后检查

## 参考

- Runbook：[asset-prep.runbook.md](../jumpserver/asset-prep.runbook.md)
- Playbook：`ansible/playbooks/jumpserver-asset-prep.yml`
- 前置验收：[20260617-阶段G4-JumpServer验收.md](./20260617-阶段G4-JumpServer验收.md)
