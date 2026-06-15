# WireGuard 密钥生成与保管 Runbook

建立 **Hub WireGuard Server** 所需的密钥体系。不包含 WG 隧道安装（见后续 `wireguard-hub.yml`）。

**前提**：Hub Ansible 纳管已完成（`inventories/mgmt/`）；资产台账与安全组已更新。

---

## 一、保管策略总览

| 材料 | 存放 | 提交 Git |
|------|------|----------|
| Hub 公钥 | `ansible/keys/wireguard/hub.pub` | 是 |
| Hub 私钥（明文） | `ansible/keys/wireguard/hub.private` | **否** |
| Hub 私钥（密文） | `ansible/inventories/mgmt/group_vars/all/wireguard_vault.yml` | 是（vault 加密） |
| Peer 公钥 | `ansible/keys/wireguard/<name>.pub` | 是 |
| Peer 私钥 | Peer 本机或 `*.private`（gitignore） | **否** |
| Vault 密码 | `.vault_pass`、GitHub `ANSIBLE_VAULT_PASSWORD` | **否** |

---

## 二、环境准备

在 **CI 替代机**（`121.41.58.20`，与 Hub 同 VPC）执行：

```bash
cd ~/infra-ops
git pull

# 修复交叉检查黄灯项（bashrc、inventory、wireguard-tools、Hub 远程验收）
make stage-e-preflight INSTALL_WG=1
source ~/.bashrc

# 仓库：Ansible、PyYAML、ansible-vault（若尚未 setup）
make setup
```

---

## 三、Hub 密钥 — 完整命令序列

### 3.1 检查依赖

```bash
chmod +x scripts/wireguard/wg-keys.sh
./scripts/wireguard/wg-keys.sh check-deps
```

### 3.2 生成 Hub 密钥对

```bash
./scripts/wireguard/wg-keys.sh generate-hub
```

产出：

- `ansible/keys/wireguard/hub.private`（权限 600，**勿提交**）
- `ansible/keys/wireguard/hub.pub`（待 `git add`）

### 3.3 校验密钥对

```bash
./scripts/wireguard/wg-keys.sh verify-hub
```

### 3.4 同步公钥到 Inventory

```bash
./scripts/wireguard/wg-keys.sh sync-inventory
```

将 `hub.pub` 写入 `wireguard.yml` 的 `wireguard.hub_public_key`。

### 3.5 创建 Vault 密码文件

```bash
# 生成随机密码（仅示例；可自行设定强密码）
openssl rand -base64 32 > .vault_pass
chmod 600 .vault_pass
```

将**相同内容**填入 GitHub Environment → Secret `ANSIBLE_VAULT_PASSWORD`。

### 3.6 加密 Hub 私钥到 Ansible Vault

```bash
./scripts/wireguard/wg-keys.sh vault-encrypt-hub
```

产出：`ansible/inventories/mgmt/group_vars/all/wireguard_vault.yml`（密文，可提交）。

验证解密：

```bash
./scripts/wireguard/wg-keys.sh vault-view
```

### 3.7 一键流程（等价于 3.2～3.4 + 提示）

```bash
./scripts/wireguard/wg-keys.sh all-hub
./scripts/wireguard/wg-keys.sh vault-encrypt-hub
```

### 3.8 查看 Hub 公钥（配置 Peer 时用）

```bash
./scripts/wireguard/wg-keys.sh show-hub-pub
```

---

## 四、Peer 密钥（实施各 Peer 时）

Peer 名称须与 `wireguard.yml` 中 `wireguard_peers_planned[].name` 一致（如 `ci-01`）。

```bash
# 在 CI 机生成 ci-01 密钥对
./scripts/wireguard/wg-keys.sh generate-peer ci-01
./scripts/wireguard/wg-keys.sh verify-peer ci-01
./scripts/wireguard/wg-keys.sh sync-inventory

# 列出所有规划 Peer 的密钥状态
./scripts/wireguard/wg-keys.sh list
```

**ci-01 与 dev-01 同机时**：可只生成 `ci-01` 一个 Peer，Dev 应用走本机回环或单一 WG 地址 `10.200.0.2`。

Peer 私钥分发到目标机属于 **wireguard-peer playbook** 范围，不在本 Runbook。

---

## 五、提交 Git 前检查

```bash
# 静态门禁
make inventory-mgmt
make ci

# 确认私钥未被跟踪
git status
# 不应出现 hub.private、*.private、.vault_pass

# 应提交的文件示例
git add ansible/keys/wireguard/hub.pub
git add ansible/inventories/mgmt/group_vars/all/wireguard.yml
git add ansible/inventories/mgmt/group_vars/all/wireguard_keys.yml
git add ansible/inventories/mgmt/group_vars/all/wireguard_vault.yml
git add scripts/wireguard/
git add docs/wireguard/wg-keys.runbook.md
```

---

## 六、GitHub Secrets 清单

| Secret | 何时需要 |
|--------|----------|
| `ANSIBLE_VAULT_PASSWORD` | `deploy.yml` 解密 `vault/wireguard.yml` 部署 WG Server 时 |
| `ANSIBLE_SSH_PRIVATE_KEY` | 已有（SSH Bootstrap）；与 WG 密钥无关 |

```bash
./scripts/wireguard/wg-keys.sh github-hints
```

---

## 七、验收标准（密钥阶段）

| # | 项 | 通过标准 |
|---|-----|----------|
| 1 | Hub 密钥对 | `verify-hub` 成功 |
| 2 | 公钥入 inventory | `wireguard.hub_public_key` 非 null |
| 3 | Vault | `vault-view` 可见 `wireguard_vault.hub_private_key` |
| 4 | Git 卫生 | `make secret-scan` 通过；无私钥明文提交 |
| 5 | 台账 | `hub-01.yaml` / `wireguard.status` 为 `keys_ready`（F1 后 `server_up`） |

---

## 八、下一步（非本 Runbook）

- 阶段 F 前：`make stage-f-preflight`；控制台核对 [stage-f-console-checklist.md](stage-f-console-checklist.md)
- `wireguard` role + `wireguard-hub.yml`：在 Hub 安装 WG Server
- `wireguard-peer.yml`：ci-01 Client（方案 A：同机不单独 dev-01 Peer）
- **握手成功后**再切换 `ci_connectivity.access_mode: wireguard`
- 安全组 Hub 迁移 `sg-hub-wg`、关 Bootstrap 公网 SSH

---

## 九、故障排查

| 现象 | 处理 |
|------|------|
| `wg: command not found` | `sudo apt install wireguard-tools` |
| `PyYAML required` | 已改为 ruamel；`make setup` |
| `Hub private key already exists` | 勿重复 generate；备份后手动删除再生成 |
| `ansible-vault not found` | `make setup` |
| vault 解密失败 | 检查 `.vault_pass` 与 GitHub Secret 是否一致 |
