# 管理面 Inventory（`inventories/mgmt/`）

Ansible 对 **Hub / 管理面** 的主机清单，与 `inventories/dev/` 分离。

**hub-01 状态（2026-06-14）**：阶段 C Bootstrap + SSH 1.3 完成（`bootstrap_status: ssh_done`）；Ansible 连接用户 `deploy`；GitHub Secrets `ANSIBLE_SSH_PRIVATE_KEY` / `ANSIBLE_SSH_KNOWN_HOSTS` 已配置。

## 用途

| 目录/文件 | 说明 |
|-----------|------|
| `hosts.yml` | 分组：`mgmt` → `mgmt_hub` → `hub-01` |
| `host_vars/hub-01.yml` | 主机级 `ansible_host`（私网 / 公网 / WG 切换逻辑） |
| `group_vars/all/main.yml` | 环境标识、时区、`network_phase` |
| `group_vars/all/network.yml` | IP 台账、`ci_connectivity`、`mgmt_hosts` |
| `group_vars/all/ssh.yml` | SSH 用户与 CI 密钥路径 |
| `group_vars/all/bootstrap.yml` | Hub Bootstrap 参数（默认不装 Docker） |
| `group_vars/all/wireguard.yml` | WG 规划、`hub_public_key`、Peer 公钥 |
| `group_vars/all/wireguard_keys.yml` | 密钥路径与保管策略（无私钥） |
| `group_vars/all/wireguard_vault.yml` | Hub 私钥（ansible-vault 加密后提交） |

## Ansible Vault（阶段 E 后必读）

存在 `wireguard_vault.yml` 时，加载 mgmt inventory 的 Ansible 命令需要 vault 密码：

```bash
# 推荐：控制面 ~/.bashrc（setup-control-plane-env.sh 在 .vault_pass 存在时自动设置）
export ANSIBLE_VAULT_PASSWORD_FILE="${HOME}/infra-ops/.vault_pass"

# 或单次命令
ansible hub-01 -i ansible/inventories/mgmt/ -m ping -u deploy \
  --vault-password-file .vault_pass \
  --private-key=ansible/keys/infra-ci-deploy
```

未带密码时的典型错误：`Attempting to decrypt but no vault secrets found`。

`make inventory-mgmt` 在仓库根存在 `.vault_pass` 时会自动附加 vault 参数。

## 常用命令

```bash
# 查看分组树（通常无需 vault）
ansible-inventory -i ansible/inventories/mgmt/ --graph

# 静态校验（vault 文件存在时需要 .vault_pass）
make inventory-mgmt

# WireGuard 密钥（Hub 私钥勿提交 Git）
./scripts/wireguard/wg-keys.sh all-hub
openssl rand -base64 32 > .vault_pass && chmod 600 .vault_pass
./scripts/wireguard/wg-keys.sh vault-encrypt-hub

# 日常连通（deploy + vault）
ansible hub-01 -m ping -u deploy \
  --private-key=ansible/keys/infra-ci-deploy \
  --vault-password-file .vault_pass
```

Runbook：`docs/bootstrap/hub-01-bootstrap.runbook.md`  
WireGuard 密钥：`docs/wireguard/wg-keys.runbook.md`

## 资产同步

修改 IP/角色后，须同步：

1. `docs/assets/hub-01.yaml`
2. `docs/assets/registry.yaml`
3. 本目录 `group_vars` / `host_vars`
4. `make inventory-mgmt`

## 与 dev inventory 的关系

- **dev**：`dev-01`、`dev-02` — 应用环境
- **mgmt**：`hub-01` — WireGuard Server、未来 JumpServer
- **ci-01**：不纳入 mgmt hosts，仅在 `network.yml` 的 `control_plane_hosts` 中文档化
