# 运维笔记本 WireGuard Client（运维简版）

> **同事接入**：请阅读并分发 **[办公笔记本 WG Client 接入指南](./办公笔记本-WG-Client-接入指南.md)**（面向开发/运维同事的完整步骤、验收与安全说明）。
>
> 本文档供 infra 维护 inventory、脚本与 Hub Peer 时快速查阅。

## 状态

Hub 已登记 `developer-laptop` 等 Peer（`10.200.10.x/32`）。Hub Server 与 ci-01 Client 已 **operational**（2026-06-14）。

## 参数（与 inventory 一致）

| 项 | 值 |
|----|-----|
| 本机 WG 地址 | `10.200.10.1/32`（示例；多人接入时每人独立 `10.200.10.x`） |
| Hub Endpoint | `121.43.49.58:51820` |
| Hub 公钥 | `MNczHi1IQ4l8zkEPIQL1sPxSEPputkPdo2neaZWkFj8=` |
| AllowedIPs | `10.200.0.0/24`, `10.200.1.0/24`（不含 Prod `10.200.3.0/24`） |
| PersistentKeepalive | `25` |

## 运维：新 Peer 快速命令

```bash
cd ~/infra-ops
./scripts/wireguard/wg-keys.sh generate-peer <peer-name>
./scripts/wireguard/wg-keys.sh sync-inventory
export ANSIBLE_VAULT_PASSWORD_FILE=~/infra-ops/.vault_pass
ansible-playbook ansible/playbooks/wireguard-hub.yml \
  -i ansible/inventories/mgmt/ --limit hub-01 \
  --vault-password-file .vault_pass
```

配置模板：`ansible/keys/wireguard/developer-laptop.conf.example`

## 安全说明

- 不要将 `*.private` 提交 Git
- 笔记本丢失：Hub 移除 Peer 公钥并 `wireguard-hub.yml` 再 apply
- 家庭动态 IP：Hub UDP 51820 可对 `0.0.0.0/0`（仅 Dev Hub；见接入指南 FAQ）

## 相关文档

- [办公笔记本-WG-Client-接入指南.md](./办公笔记本-WG-Client-接入指南.md) — **分发给同事**
- [stage-f-console-checklist.md](./stage-f-console-checklist.md) — Hub 安全组核对
