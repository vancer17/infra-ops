# 阶段 G5：JumpServer 资产纳管 — Dev-01（CI-DEV-01）验收清单

> **控制机**：ci-01（yax / deploy）  
> **目标主机**：dev-01（与 ci-01 **同 ECS**；`10.200.0.2` WG / `172.21.226.38` VPC）  
> **Ansible Playbook**：`ansible/playbooks/jumpserver-asset-prep.yml`  
> **前提**：阶段 G4 JumpServer `operational`；dev-01 `ssh_phase=steady`；Hub G5 已完成  
> **验收日期**：2026-06-18  
> **结论**：**通过**（Ansible `jump_ops` 准备 + JumpServer Web 终端登录）

## 一、目标

| 项 | 说明 |
|----|------|
| Linux 用户 | `jump_ops` 可登录（`/bin/bash` + `AllowUsers deploy jump_ops`） |
| JumpServer 节点 | `Dev/ECS` |
| 资产 | 控制台 **CI-DEV-01**（台账逻辑名 dev-01），IP **`10.200.0.2`** |
| 账户模板 | `linux-jump-ops` → 用户 `jump_ops` |
| Web 终端 | `linux-jump-ops(jump_ops)@10.200.0.2` 登录成功 |
| 隔离 | **勿**将 `deploy` 作为日常堡垒机账户；CI/Ansible 走 `infra-ci-deploy` |

## 二、Ansible 执行与验收

```bash
cd ~/infra-ops
export ANSIBLE_PRIVATE_KEY_FILE=~/infra-ops/ansible/keys/infra-ci-deploy
export ANSIBLE_VAULT_PASSWORD_FILE=~/infra-ops/.vault_pass

make stage-jumpserver-asset-preflight JUMPSERVER_ASSET_LIMIT=dev-01
make jumpserver-asset-prep JUMPSERVER_ASSET_LIMIT=dev-01
./scripts/mgmt/verify-jumpserver-asset-remote.sh dev-01
```

> **注意**：Make 变量为 **`JUMPSERVER_ASSET_LIMIT`**，不是 `LIMIT`。误用 `LIMIT=dev-01` 会默认跑在 `hub-01` 上。

| # | 检查项 | 通过标准 | 结果 |
|---|--------|----------|------|
| 1 | jump_ops shell | `getent passwd jump_ops` → `/bin/bash` | OK |
| 2 | sshd AllowUsers | 含 `deploy jump_ops` | OK |
| 3 | .ssh 目录 | mode `700`（ansible -b 验收） | OK |
| 4 | sudoers | `/etc/sudoers.d/jump_ops` ops profile | OK |
| 5 | verify script | `verify-jumpserver-asset-remote.sh dev-01` | OK |
| 6 | inventory | `make inventory` | OK |
| 7 | JMS Web 终端 | `jump_ops@10.200.0.2` shell 提示符 | OK |

原始日志：`logs/console-acceptance.log`（2026-06-18 段）、`logs/network.log`。

## 三、JumpServer 控制台配置

| 字段 | 值 |
|------|-----|
| 名称（控制台） | `CI-DEV-01` |
| 台账 / inventory 建议名 | `Dev-01`（`host_vars` → `jumpserver_asset_console.name`） |
| IP/主机 | `10.200.0.2`（WG；勿用公网 IP） |
| 节点 | `Dev/ECS` |
| 协议 | SSH 22、SFTP 22 |
| 账户 | `linux-jump-ops`（`jump_ops`） |

### 账号推送说明

- 首次推送在 asset-prep **之前**已完成，`authorized_keys` 保留 1 行。
- asset-prep 后再次点「推送」可能显示 **「未找到待处理帐户」**（无新推送任务）；**不影响** Web 终端登录。
- Hub 上已执行 `/opt/mgmt/jumpserver/install-paramiko.sh`（`python3: 5.0.0` / `/opt/py3: 3.2.0`），缓解 JMS「测试连接」paramiko 校验问题。

## 四、已知问题 / 待办

| 项 | 状态 |
|----|------|
| `make secret-scan` | **待处理**：历史提交中 `jumpserver/.env.example` 触发 gitleaks（与本次纳管无关） |
| JMS 资产上的 `deploy` 账户 | **建议删除**（不符合「deploy 不进堡垒机」） |
| 平台授权 + MFA | 待办（与 Hub G5 相同） |
| `network_phase: steady` | 待办（关公网 SSH 等） |

## 五、台账

已更新：

- `docs/assets/dev-01.yaml` → `jumpserver_asset`
- `docs/assets/registry.yaml` → `stage_g5_dev_acceptance`、`hosts.dev-01.jumpserver_asset_*`
- `docs/jumpserver/asset-prep.runbook.md` → Dev-01 完成标记

## 参考

- Hub G5：[20260617-阶段G5-JumpServer资产纳管-Hub验收.md](./20260617-阶段G5-JumpServer资产纳管-Hub验收.md)
- Runbook：[asset-prep.runbook.md](../jumpserver/asset-prep.runbook.md)
- Playbook：`ansible/playbooks/jumpserver-asset-prep.yml`
