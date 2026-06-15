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

在 **yax** 上以 **`deploy` 用户**跑 Ansible（无需控制机 sudo）。

**steady 之后（当前）**：Ansible / CI 使用 `deploy` + `ansible/keys/infra-ci-deploy`：

```bash
cd ~/infra-ops
make setup
source .venv/bin/activate

# 一次性：修正 ~/.bashrc（替换 hub-root 默认密钥）
./scripts/dev/setup-control-plane-env.sh all
source ~/.bashrc

export ANSIBLE_INVENTORY=ansible/inventories/mgmt/
# ANSIBLE_PRIVATE_KEY_FILE 由 bashrc 指向 infra-ci-deploy
ansible hub-01 -i ansible/inventories/mgmt/ -m ping -u deploy
```

GitHub Secret：`ANSIBLE_SSH_PRIVATE_KEY` = `infra-ci-deploy` 私钥内容。

**Bootstrap 历史**：初次 apply 曾用 `~/.ssh/hub-root` 连 root；steady 后勿再作为默认密钥。

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
- [x] 安全组 id `sg-bp122tjy3h95um8kv4f9`（与 Dev 共用；UDP 见 dev-ecs-bootstrap IN-WG-*）
- [x] `ansible/inventories/mgmt/group_vars/all/network.yml` → `mgmt_hosts.hub-01.bootstrap_status`
- [x] `ansible/inventories/mgmt/group_vars/all/ssh.yml` → `deploy` / `steady` / `ssh_keys_configured: true`
- [x] 控制面：`scripts/dev/setup-control-plane-env.sh all`（阶段 E 前）

## 阶段 E 前检查（交叉检查修复项）

在 **yax（ci-01）** 上执行一条命令即可修复黄灯 1–3 并验收 Hub：

```bash
cd ~/infra-ops
git pull
make stage-e-preflight INSTALL_WG=1
source ~/.bashrc
```

或分步：

```bash
make control-plane-setup    # 黄灯 1：bashrc → infra-ci-deploy
make inventory-mgmt         # 黄灯 3：steady → deploy 门禁
sudo apt install -y wireguard-tools   # 黄灯 2
./scripts/mgmt/verify-hub-remote.sh   # 远程验收（修复 set -e 问题）
./scripts/wireguard/wg-keys.sh check-deps
```

Dev inventory 应与 Hub 一致（`deploy` / `steady`）：

```bash
grep -E 'ssh_inventory_user|ssh_phase' ansible/inventories/dev/group_vars/all/ssh.yml
```

## 验收（2026-06-14 已通过）

| # | 项 | 结果 |
|---|-----|------|
| 1 | `id deploy`、`id jump_ops` 存在 | OK |
| 2 | `/opt/mgmt`、`/opt/wireguard` 存在 | OK（`/opt/wireguard` 为 root 0750，deploy 无 list 权限为预期） |
| 3 | `timedatectl` → Asia/Shanghai | OK |
| 4 | `deploy@172.21.127.123` SSH 成功 | OK（`infra-ci-deploy`） |
| 5 | 连续两次 `apply` 幂等 | 建议保留为运维习惯 |
| 6 | **无** Docker | OK |

远程验收（推荐脚本，避免 `ls /opt/wireguard` 权限导致 set -e 退出）：

```bash
./scripts/mgmt/verify-hub-remote.sh hub-01
```

或手动：

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

- 控制面环境：`./scripts/dev/setup-control-plane-env.sh all`
- **deploy sudo（阶段 F 前置）**：`./scripts/mgmt/apply-hub-deploy-sudo.sh`
- WireGuard 密钥：`docs/wireguard/wg-keys.runbook.md`
- WG Server：`ansible/playbooks/wireguard-hub.yml`（阶段 F；需 `--vault-password-file .vault_pass`）
- 控制台确认 UDP 51820 已按 `dev-ecs-bootstrap.rules.yaml` IN-WG-* 添加

## 阶段 F 前置：deploy 免密 sudo

`wireguard-hub.yml` 使用 `become: true`。Hub 上 `deploy` 须能 `sudo -n`（`mgmt/bootstrap.yml` → `sudo_mgmt: true`）。

**新 Hub**：在 `ssh-keys steady` **之前** 的 bootstrap 中会自动写入。

**已 steady 且无 sudo 的 Hub**（会报 `Missing sudo password`）：

```bash
# ci-01 上
./scripts/mgmt/apply-hub-deploy-sudo.sh          # 检测；失败则打印工作台命令
./scripts/mgmt/apply-hub-deploy-sudo.sh --console # 仅打印 root 一次性命令

# 控制台修复后再次执行（Ansible 幂等同步）：
./scripts/mgmt/apply-hub-deploy-sudo.sh
```

## 故障排查

| 现象 | 处理 |
|------|------|
| `--list-hosts` 无 hub-01 | 确认 `bootstrap.yml` 使用 `hosts: dev:mgmt` |
| preflight SSH 失败 | 查 Hub 安全组是否放行 `172.21.226.38/32`；确认 `~/.ssh/config` 对 Hub IP 指定 `IdentityFile` |
| `sudo: a password is required`（wireguard-hub / gather_facts） | Hub deploy 无免密 sudo；运行 `./scripts/mgmt/apply-hub-deploy-sudo.sh` |
| `sudo: a password is required`（`delegate_to: localhost`） | 控制机 task 须 `become: false`；用 `deploy` 跑 Ansible 时**不要**在控制机 sudo。更新仓库后重新 `apply` |
| verify 要求 docker | 确认 `mgmt/bootstrap.yml` 中 `docker_install: false` |
| verify 报 RDS | 确认 `mgmt/bootstrap.yml` 中 `rds_verify: false` |
| steady 后 root 不可用 | 预期行为；使用 `deploy` + infra-ci-deploy 私钥 |
| `ls /opt/wireguard` Permission denied | 预期（目录 mode 0750 root）；用 `sudo ls` 或验收脚本 `test -d` |
