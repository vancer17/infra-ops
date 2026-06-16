# 人员笔记本 WireGuard Client（运维简版）

> **同事接入**：请阅读并分发 **[办公笔记本 WG Client 接入指南](./办公笔记本-WG-Client-接入指南.md)**。
>
> 本文档供 infra 维护 inventory、Hub Peer 与密钥时快速查阅。

## 团队台账（2026-06-17）

SSOT：`docs/assets/wireguard-clients.yaml`

| Peer | 人员 | WG 地址 | 角色 | Client AllowedIPs |
|------|------|---------|------|-------------------|
| `laptop-zhengyaoyuan` | zhengyaoyuan | `10.200.10.1` | 开发/运维 | `10.200.0.0/16` |
| `laptop-billmiao` | billmiao | `10.200.10.2` | 开发 | 管理 + Dev + Test |
| `laptop-sammao` | sammao | `10.200.10.3` | 开发 | 管理 + Dev + Test |
| `laptop-zhu` | zhu | `10.200.10.4` | 开发 | 管理 + Dev + Test |
| `laptop-xinxin` | xinxin | `10.200.10.5` | 开发 | 管理 + Dev + Test |

开发角色不含 Prod 网段 `10.200.3.0/24`（见台账 `allowed_ips_profiles.dev`）。

## 状态

- Hub Server 与 ci-01：**operational**（2026-06-14）
- `laptop-zhengyaoyuan`：公钥已登记（由原 `developer-laptop` 迁移）
- 其余四人：`pending_key` — 见下方批量命令

## 运维：新成员 / 批量接入

```bash
cd ~/infra-ops

# 为 billmiao / sammao / zhu / xinxin 生成密钥并同步 inventory
./scripts/wireguard/generate-team-laptop-peers.sh

export ANSIBLE_VAULT_PASSWORD_FILE=~/infra-ops/.vault_pass
ansible-playbook ansible/playbooks/wireguard-hub.yml \
  -i ansible/inventories/mgmt/ --limit hub-01 \
  --vault-password-file .vault_pass

# 为每位同学生成 wg0.conf（私钥勿提交 Git）
./scripts/wireguard/render-laptop-conf.sh laptop-billmiao /tmp/wg0-billmiao.conf
```

单人接入仍可用：

```bash
./scripts/wireguard/wg-keys.sh generate-peer laptop-<name>
./scripts/wireguard/wg-keys.sh sync-inventory
```

配置模板：

- 运维：`ansible/keys/wireguard/laptop-zhengyaoyuan.conf.example`
- 开发：`ansible/keys/wireguard/laptop-client-dev.conf.example`

## 安全说明

- 每人独立密钥，禁止共用 `developer-laptop` 旧名私钥
- 不要将 `*.private` 或含私钥的 `wg0.conf` 提交 Git
- 笔记本丢失：Hub 移除 Peer 公钥并 `wireguard-hub.yml` 再 apply

## 相关文档

- [办公笔记本-WG-Client-接入指南.md](./办公笔记本-WG-Client-接入指南.md)
- [wireguard-clients.yaml](../assets/wireguard-clients.yaml)
- [stage-f-console-checklist.md](./stage-f-console-checklist.md)
