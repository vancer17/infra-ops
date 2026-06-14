# Hub-01 Bootstrap Runbook（阶段 C）

> 主机：hub-01 | 公网 121.43.49.58 | 私网 172.21.127.123  
> 控制机：ci-01（yax，121.41.58.20 / 172.21.226.38）  
> Inventory：`ansible/inventories/mgmt/`  
> **状态：已于 2026-06-14 完成**（`bootstrap_status: ssh_done`）

## 前置条件

- [x] 阶段 A：能以 **root + 实例密钥** SSH 登录 Hub（公网或私网）
- [x] 阶段 B：ci-01（dev-01 同机）已完成 Bootstrap（`bootstrap_status: bootstrap_done`）
- [x] Hub 安全组已按 [hub-bootstrap.rules.yaml](../security-groups/hub-bootstrap.rules.yaml) 配置并绑定实例
- [x] 从控制机验证：`ssh root@172.21.127.123`（优先私网；控制机 `~/.ssh/hub-root`）

## 执行用户（控制机）

在 **yax** 上以 **`deploy` 用户**跑 Ansible（无需控制机 sudo）：

```bash
cd ~/infra-ops
make setup
source .venv/bin/activate

export ANSIBLE_INVENTORY=ansible/inventories/mgmt/
export ANSIBLE_PRIVATE_KEY_FILE=~/.ssh/hub-root   # Bootstrap 1.2 期连接 Hub root
```

Playbook 对 **远程 Hub** 仍使用 `become: true`（装包、建用户等需 root）；仅在控制机读仓库公钥的 task 显式 `become: false`，避免 `sudo: a password is required`。

**steady 之后**：Ansible / CI 使用 `deploy` + `ansible/keys/infra-ci-deploy`（或 GitHub Secret `ANSIBLE_SSH_PRIVATE_KEY`）。

## Step 0 — 静态检查（控制机上）

```bash
cd ~/infra-ops
make inventory-mgmt
make ci
```

确认 playbook 能选中 hub-01：

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventories/mgmt/ \
  --limit hub-01 \
  --list-hosts
```

预期输出包含 `hub-01`（不应为 0 hosts）。

## Step 1 — Bootstrap（1.2）

```bash
export ANSIBLE_INVENTORY=ansible/inventories/mgmt/

./scripts/dev/bootstrap.sh preflight hub-01
./scripts/dev/bootstrap.sh apply hub-01
./scripts/dev/bootstrap.sh verify hub-01
# 或：./scripts/dev/bootstrap.sh all hub-01
```

Hub 特性（与 dev 差异）：

| 项 | Hub |
|----|-----|
| Docker | **不安装**（`docker_install: false`） |
| 目录 | `/opt/mgmt`、`/opt/wireguard`、`/var/log/mgmt` |
| RAM 角色 | 不验证（`ram_role_verify: false`） |
| RDS | **不探测**（`rds_verify: false`；Hub 无 `rds.host`） |
| verify | **不**要求 `docker hello-world` |

## Step 2 — SSH 密钥（1.3）

前提：`ansible/keys/infra-ci-deploy.pub` 已存在（阶段 B 已 generate）。

```bash
export ANSIBLE_INVENTORY=ansible/inventories/mgmt/

./scripts/dev/ssh-keys.sh all hub-01
./scripts/dev/ssh-keys.sh steady hub-01
```

verify 通过后：

```bash
ssh -i ansible/keys/infra-ci-deploy deploy@172.21.127.123 'whoami'
```

GitHub Environment Secrets（已配置）：

| Secret | 用途 |
|--------|------|
| `ANSIBLE_SSH_PRIVATE_KEY` | `infra-ci-deploy` 私钥 |
| `ANSIBLE_SSH_KNOWN_HOSTS` | Hub 私网 `172.21.127.123` 指纹 |

## Step 3 — 回填台账

- [x] `docs/assets/hub-01.yaml` → `bootstrap_status: ssh_done`
- [ ] `hub-01.yaml` → 安全组 `id`（控制台创建后填入 `sg-hub-bootstrap` 的 id）
- [x] `ansible/inventories/mgmt/group_vars/all/network.yml` → `mgmt_hosts.hub-01.bootstrap_status`
- [x] `ansible/inventories/mgmt/group_vars/all/ssh.yml` → `deploy` / `steady` / `ssh_keys_configured: true`

## 验收（2026-06-14 已通过）

| # | 项 | 结果 |
|---|-----|------|
| 1 | `id deploy`、`id jump_ops` 存在 | OK |
| 2 | `/opt/mgmt`、`/opt/wireguard` 存在 | OK（`/opt/wireguard` 为 root 0750，deploy 无 list 权限为预期） |
| 3 | `timedatectl` → Asia/Shanghai | OK |
| 4 | `deploy@172.21.127.123` SSH 成功 | OK（`infra-ci-deploy`） |
| 5 | 连续两次 `apply` 幂等 | 建议保留为运维习惯 |
| 6 | **无** Docker | OK |

远程验收命令（存档）：

```bash
ssh -i ~/infra-ops/ansible/keys/infra-ci-deploy deploy@172.21.127.123 <<'REMOTE'
set -e
id deploy
id jump_ops
timedatectl | grep 'Time zone'
ls -la /opt/mgmt /var/log/mgmt
test -d /opt/wireguard && echo "/opt/wireguard exists"
command -v docker && echo "WARN: docker 不应存在" || echo "OK: 无 Docker"
REMOTE
```

## 下一步

- WireGuard 密钥：`docs/wireguard/wg-keys.runbook.md`
- WG Server：`wireguard-hub.yml`（待实现）
- 控制台安全组 id 回填 `hub-01.yaml`（若尚未写入）

## 故障排查

| 现象 | 处理 |
|------|------|
| `--list-hosts` 无 hub-01 | 确认 `bootstrap.yml` 使用 `hosts: dev:mgmt` |
| preflight SSH 失败 | 查 Hub 安全组是否放行 `172.21.226.38/32`；确认 `~/.ssh/config` 对 Hub IP 指定 `IdentityFile` |
| `sudo: a password is required`（`delegate_to: localhost`） | 控制机 task 须 `become: false`；用 `deploy` 跑 Ansible 时**不要**在控制机 sudo。更新仓库后重新 `apply` |
| verify 要求 docker | 确认 `mgmt/bootstrap.yml` 中 `docker_install: false` |
| verify 报 RDS | 确认 `mgmt/bootstrap.yml` 中 `rds_verify: false` |
| steady 后 root 不可用 | 预期行为；使用 `deploy` + infra-ci-deploy 私钥 |
| `ls /opt/wireguard` Permission denied | 预期（目录 mode 0750 root）；用 `sudo ls` 或验收脚本 `test -d` |
