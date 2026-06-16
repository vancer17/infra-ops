# JumpServer 资产纳管 — Linux 系统用户准备（Ansible）

在 JumpServer 控制台「账号推送」之前，用 Ansible 将 `jump_ops` 从 Bootstrap 占位升级为可登录账号。

## 分工

| 层 | 工具 | 职责 |
|----|------|------|
| OS 用户骨架 | `bootstrap.yml` | 创建 `jump_ops`（nologin 占位）、`deploy` |
| 堡垒机可用账号 | `jumpserver-asset-prep.yml` | shell、home、.ssh、sudo、AllowUsers |
| SSH 公钥 | JumpServer 账号推送 | **不由 Ansible 写入** |
| CI 部署 | `deploy` + `infra-ci-deploy` | **不录入 JumpServer** |

## 执行（ci-01）

```bash
chmod +x scripts/mgmt/jumpserver-asset-prep.sh scripts/mgmt/stage-jumpserver-asset-preflight.sh

# 预检 + apply + verify（推荐先单独 preflight）
make stage-jumpserver-asset-preflight LIMIT=hub-01
make jumpserver-asset-prep LIMIT=hub-01

# Dev（须已 bootstrap + steady）
make stage-jumpserver-asset-preflight LIMIT=dev-01
make jumpserver-asset-prep LIMIT=dev-01
```

**Dev-01 与 ci-01 同机**：JumpServer 只录入 Dev-01，勿再建 ci-01 重复资产。

## JumpServer 控制台（Ansible 之后）

1. 创建节点：`Mgmt/Hub`、`Dev/ECS`
2. 新建资产：名称与 `host_vars` 中 `jumpserver_asset_console` 一致
3. IP：Hub 建议 `10.200.0.1`（或容器不可达时 `172.21.127.123`）
4. 账户：**从模板添加** `linux-jump-ops`（用户 `jump_ops`）→ **账号推送** → 测试连接

## 相关文件

| 路径 | 说明 |
|------|------|
| `ansible/playbooks/jumpserver-asset-prep.yml` | Playbook |
| `scripts/mgmt/stage-jumpserver-asset-preflight.sh` | 执行前预检（WG / steady / ping） |
| `ansible/roles/jump_ops/` | Role |
| `ansible/inventories/*/group_vars/all/jumpserver_asset.yml` | 变量 SSOT |
| `ansible/inventories/*/hosts.yml` → `jumpserver_assets` | 目标主机组 |

## 验收

- `getent passwd jump_ops` → `/bin/bash`
- `sshd` AllowUsers 含 `jump_ops` 与 `deploy`
- JumpServer 测试连接成功（推送后）

详见 [asset-prep.runbook.md](asset-prep.runbook.md)。
