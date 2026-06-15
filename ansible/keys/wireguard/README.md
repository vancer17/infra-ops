# WireGuard 密钥目录

Hub 与 Peer 的 WireGuard 密钥对存放位置。保管策略与 SSH 密钥（`../README.md`）对称。

## 文件约定

| 文件 | 提交 Git | 说明 |
|------|----------|------|
| `hub.private` | **否** | Hub 私钥；`wg-keys.sh generate-hub` 生成 |
| `hub.pub` | **是** | Hub 公钥；Peer 客户端配置需要 |
| `<peer>.private` | **否** | Peer 私钥（如 `ci-01.private`） |
| `ci-01.pub` / `developer-laptop.pub` | **是** | Peer 公钥；Hub `[Peer]` 需要 |
| `*.example` | 是 | 格式示例 |

`sync-inventory` 使用 **ruamel.yaml** 更新公钥字段，**保留本文件顶部注释**。

## 生成命令（在 CI 机或运维笔记本执行）

```bash
# 安装依赖
sudo apt install -y wireguard-tools
make setup    # 提供 ansible-vault、PyYAML

chmod +x scripts/wireguard/wg-keys.sh

# Hub 密钥（本期）
./scripts/wireguard/wg-keys.sh check-deps
./scripts/wireguard/wg-keys.sh all-hub
./scripts/wireguard/wg-keys.sh vault-encrypt-hub

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
| `ANSIBLE_VAULT_PASSWORD` | 与仓库根目录 `.vault_pass` 相同，供 `deploy.yml` 解密 vault（**已配置**，2026-06-14） |

## 相关文档

- [办公笔记本 WG Client 接入指南（分发给同事）](../../../docs/wireguard/办公笔记本-WG-Client-接入指南.md)
- [docs/wireguard/wg-keys.runbook.md](../../../docs/wireguard/wg-keys.runbook.md)
- [inventories/mgmt/group_vars/all/wireguard_keys.yml](../../inventories/mgmt/group_vars/all/wireguard_keys.yml)
