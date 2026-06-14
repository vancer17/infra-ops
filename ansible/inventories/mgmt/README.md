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

## 常用命令

```bash
# 查看分组树
ansible-inventory -i ansible/inventories/mgmt/ --graph

# 静态校验（本地）
make inventory-mgmt

# WireGuard 密钥（Hub 私钥勿提交 Git）
./scripts/wireguard/wg-keys.sh all-hub
./scripts/wireguard/wg-keys.sh vault-encrypt-hub

# Bootstrap Hub（已完成 2026-06-14；日常用 deploy 密钥）
export ANSIBLE_INVENTORY=ansible/inventories/mgmt/
ansible hub-01 -m ping -u deploy --private-key=ansible/keys/infra-ci-deploy
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
