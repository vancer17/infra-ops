# Hub-01 Bootstrap Runbook（阶段 C）

> 主机：hub-01 | 公网 121.43.49.58 | 私网 172.21.127.123  
> 控制机：ci-01（develop / yax，121.41.58.20）  
> Inventory：`ansible/inventories/mgmt/`

## 前置条件

- [ ] 阶段 A：能以 **root + 实例密钥** SSH 登录 Hub（公网或私网）
- [ ] 阶段 B：ci-01（dev-01 同机）已完成 Bootstrap（`bootstrap_status: bootstrap_done`）
- [ ] Hub 安全组已按 [hub-bootstrap.rules.yaml](../security-groups/hub-bootstrap.rules.yaml) 配置并绑定实例
- [ ] 从控制机验证：`ssh root@172.21.127.123`（优先私网）

## 执行用户（控制机）

在 **yax** 上以 **`deploy` 用户**跑 Ansible（无需控制机 sudo）：

```bash
cd ~/infra-ops
make setup
source .venv/bin/activate

export ANSIBLE_INVENTORY=ansible/inventories/mgmt/
export ANSIBLE_PRIVATE_KEY_FILE=~/.ssh/hub-root   # 连接 Hub 的 root 密钥
```

Playbook 对 **远程 Hub** 仍使用 `become: true`（装包、建用户等需 root）；仅在控制机读仓库公钥的 task 显式 `become: false`，避免 `sudo: a password is required`。

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

## Step 3 — 回填台账

- [ ] `docs/assets/hub-01.yaml` → `bootstrap_status: bootstrap_done`
- [ ] `hub-01.yaml` → 安全组 `id`（控制台创建后填入）
- [ ] `ansible/inventories/mgmt/group_vars/all/network.yml` → `mgmt_hosts.hub-01.bootstrap_status`

## 验收

| # | 项 |
|---|-----|
| 1 | `id deploy`、`id jump_ops` 存在 |
| 2 | `/opt/mgmt`、`/opt/wireguard` 存在 |
| 3 | `timedatectl` → Asia/Shanghai |
| 4 | `deploy@172.21.127.123` SSH 成功 |
| 5 | 连续两次 `apply` 幂等（changed 极少） |
| 6 | **无** Docker（Hub 预期） |

## 下一步

- WireGuard 密钥：`docs/wireguard/wg-keys.runbook.md`
- WG Server：`wireguard-hub.yml`（待实现）

## 故障排查

| 现象 | 处理 |
|------|------|
| `--list-hosts` 无 hub-01 | 确认 `bootstrap.yml` 使用 `hosts: dev:mgmt` |
| preflight SSH 失败 | 查 Hub 安全组是否放行 `172.21.226.38/32`；确认 `~/.ssh/config` 对 Hub IP 指定 `IdentityFile` |
| `sudo: a password is required`（`delegate_to: localhost`） | 控制机 task 须 `become: false`；用 `deploy` 跑 Ansible 时**不要**在控制机 sudo。更新仓库后重新 `apply` |
| verify 要求 docker | 确认 `mgmt/bootstrap.yml` 中 `docker_install: false` |
| verify 报 `nc ... VARIABLE` / RDS | 确认 `mgmt/bootstrap.yml` 中 `rds_verify: false`；更新仓库后重跑 verify |
| verify 报 `nc ... "false"` | 旧版 remote verify 在 `rds_host` 为空时 SSH 丢弃空参数，误把 `docker_install=false` 当 RDS 主机；拉取含参数顺序修复的版本 |
| steady 后 root 不可用 | 预期行为；使用 `deploy` + infra-ci-deploy 私钥 |
