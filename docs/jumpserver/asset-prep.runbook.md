# JumpServer 资产纳管 Runbook（Ansible + 控制台）

> **前置**：G4 JumpServer operational；目标主机 `bootstrap` + `ssh-keys steady` 已完成。

## 一、流程总览

```text
Ansible jumpserver-asset-prep.yml
    → jump_ops 可登录 + AllowUsers
JumpServer 控制台
    → 资产 + 账户模板 + 账号推送
人工验证
    → 网页终端 / SSH 经堡垒机登录
```

## 二、Ansible 步骤

### 2.1 Hub-01

```bash
cd ~/infra-ops
make stage-jumpserver-asset-preflight LIMIT=hub-01
make jumpserver-asset-prep LIMIT=hub-01
```

或：

```bash
./scripts/mgmt/jumpserver-asset-prep.sh all hub-01
```

### 2.2 Dev-01（与 ci-01 同机）

```bash
make stage-jumpserver-asset-preflight LIMIT=dev-01
make jumpserver-asset-prep LIMIT=dev-01
```

> **勿重复纳管**：dev-01 与 ci-01 为**同一台 ECS**。JumpServer 只录入 **Dev-01** 一个资产（建议 WG IP `10.200.0.2`），**不要**再建名为 ci-01 的重复资产。CI/Ansible 走 `deploy`，永不录入堡垒机。

### 2.3 Dev-02

须先完成 dev-02 Bootstrap，再：

```bash
./scripts/mgmt/jumpserver-asset-prep.sh all dev-02
```

## 三、JumpServer 控制台配置

### 3.1 节点

| 节点路径 | 资产 | 说明 |
|----------|------|------|
| `Mgmt/Hub` | Hub-01 | |
| `Dev/ECS` | Dev-01、Dev-02 | **Dev-01 与 ci-01 同机，只录 Dev-01，勿重复建 ci-01 资产** |

### 3.2 账户模板（建议先建一次，后续批量复用）

| 模板名 | 用户名 | 说明 |
|--------|--------|------|
| `linux-jump-ops` | `jump_ops` | 日常运维；Ansible 已准备 home/sudo |
| `linux-jump-readonly` | `jump_readonly` | Prod 预留（inventory 默认未启用） |

模板中认证方式：**SSH 密钥**（由 JumpServer 生成并推送）。

### 3.3 资产 Hub-01 示例

| 字段 | 值 |
|------|-----|
| 名称 | Hub-01 |
| IP | `10.200.0.1`（不通则试 `172.21.127.123`） |
| 平台 | Linux |
| 节点 | Mgmt/Hub |
| 协议 | SSH 22、SFTP 22 |
| 账户 | 从模板添加 `linux-jump-ops` |

**不要**添加 `deploy` 账户。

### 3.4 账号推送与测试

1. 资产 → 账户 → 推送  
2. 测试连接 → 应成功  
3. 授权：将资产/节点授权给运维用户组（平台用户一人一号 + MFA）

## 四、验收标准

| # | 项 | 标准 |
|---|-----|------|
| 1 | Ansible | `jumpserver-asset-prep.sh verify` 通过 |
| 2 | jump_ops | `getent passwd jump_ops` 为 bash |
| 3 | sshd | AllowUsers 含 `deploy jump_ops` |
| 4 | JMS | 测试连接成功 |
| 5 | 隔离 | `deploy` 未出现在 JumpServer 资产账户中 |
| 6 | 去重 | Dev 环境无 ci-01 重复资产（dev-01 与 ci-01 同机） |

## 五、故障排查

| 现象 | 处理 |
|------|------|
| 测试连接 Permission denied | 是否已账号推送；AllowUsers 是否含 jump_ops |
| `verify-jumpserver-asset-remote` 对 `.ssh` Permission denied | 旧版脚本用 deploy 直读私有目录会误报；已改为 `ansible -b`；`deploy` 无权读 `0750` home 属正常 |
| Hub 资产连不上 | 换 `172.21.127.123`；确认 JumpServer 容器能访问宿主机 22 |
| Ansible 报 steady 未完成 | 先 `ssh-keys.sh steady` |
| dev-02 失败 | 先 bootstrap dev-02 |
| JMS 上 ci-01 与 Dev-01 重复 | 删除 ci-01 资产，仅保留 Dev-01（同 ECS） |

## 六、相关文档

- [asset-prep.md](asset-prep.md)
- [hub-jumpserver.runbook.md](hub-jumpserver.runbook.md)
- 企业方案 §8.3–8.4 资产分组与系统用户
