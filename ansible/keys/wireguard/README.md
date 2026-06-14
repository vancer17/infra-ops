# WireGuard 密钥目录

Hub 与 Peer 的 WireGuard 密钥对存放位置。保管策略与 SSH 密钥（`../README.md`）对称。

## 文件约定

| 文件 | 提交 Git | 说明 |
|------|----------|------|
| `hub.private` | **否** | Hub 私钥；`wg-keys.sh generate-hub` 生成 |
| `hub.pub` | **是** | Hub 公钥；Peer 客户端配置需要 |
| `<peer>.private` | **否** | Peer 私钥（如 `ci-01.private`） |
| `<peer>.pub` | **是** | Peer 公钥；Hub `wg0.conf` 的 `[Peer]` 需要 |
| `*.example` | 是 | 格式示例 |

## 生成命令（在 CI 机或运维笔记本执行）

```bash
# 安装依赖
sudo apt install -y wireguard-tools
make setup    # 提供 ansible-vault、PyYAML

chmod +x scripts/wireguard/wg-keys.sh

# Hub 密钥（本期）
./scripts/wireguard/wg-keys.sh check-deps
./scripts/wireguard/wg-keys.sh all-hub
openssl rand -base64 32 > .vault_pass && chmod 600 .vault_pass
./scripts/wireguard/wg-keys.sh vault-encrypt-hub

# vault 文件存在后，Ansible 需要密码（见 runbook §五）
export ANSIBLE_VAULT_PASSWORD_FILE="${PWD}/.vault_pass"
make inventory-mgmt

# Peer 密钥（实施各 Peer 时）
./scripts/wireguard/wg-keys.sh generate-peer ci-01
./scripts/wireguard/wg-keys.sh sync-inventory
```

## 保管层次

```
Hub 私钥
├── hub.private          本地备份（gitignore）
├── group_vars/all/wireguard_vault.yml  ansible-vault 加密（提交 Git）
└── Hub:/etc/wireguard/  playbook 部署后（实施 WG Server 时）

Hub 公钥
├── hub.pub              Git
└── wireguard.yml        wireguard.hub_public_key

Peer 私钥
└── 仅保留在 Peer 本机 /etc/wireguard/（或 gitignore 的 *.private）

Peer 公钥
├── <name>.pub           Git
└── wireguard.yml        wireguard_peers_planned[].public_key
```

## GitHub Secrets

| Secret | 内容 |
|--------|------|
| `ANSIBLE_VAULT_PASSWORD` | 与仓库根目录 `.vault_pass` 相同；解密 `wireguard_vault.yml` |

## Vault 与 Ansible

`vault-encrypt-hub` 后，`group_vars/all/wireguard_vault.yml` 会被 Ansible 自动加载。未提供密码时：

```text
ERROR! Attempting to decrypt but no vault secrets found
```

处理：设置 `ANSIBLE_VAULT_PASSWORD_FILE` 或 `--vault-password-file .vault_pass`。详见 [wg-keys.runbook.md §五](../../../docs/wireguard/wg-keys.runbook.md#五vault-与-ansible--inventory-检查)。

## 相关文档

- [docs/wireguard/wg-keys.runbook.md](../../../docs/wireguard/wg-keys.runbook.md)
- [inventories/mgmt/group_vars/all/wireguard_keys.yml](../../inventories/mgmt/group_vars/all/wireguard_keys.yml)
