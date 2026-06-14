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

**说明**：若末尾曾出现 `tmp: unbound variable`，多为旧版脚本的 cleanup bug；加密本身通常已成功（见 `Encryption successful`）。用 `vault-view` 确认即可，无需重复 encrypt。

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

## 五、Vault 与 Ansible / inventory 检查

阶段 E 生成 `group_vars/all/wireguard_vault.yml` 后，Ansible 加载 **mgmt inventory** 时会**自动**尝试解密该文件。

### 5.1 现象

未提供 vault 密码时，任意需要合并 group_vars 的命令会失败，例如：

```bash
ansible hub-01 -i ansible/inventories/mgmt/ -m debug -a "var=ansible_host" -c local
# ERROR! Attempting to decrypt but no vault secrets found
```

带密码则正常：

```bash
ansible hub-01 -i ansible/inventories/mgmt/ \
  -m debug -a "var=ansible_host" -c local \
  --vault-password-file .vault_pass
```

`ansible-inventory --graph` 可能仍成功（不展开 vault 变量），但 `make inventory-mgmt` 会调用 `ansible -m debug`，**必须有 vault 密码**。

### 5.2 推荐做法（ci-01 控制面）

**创建 `.vault_pass` 之后**，任选一种：

```bash
# 方式 A：环境变量（setup-control-plane-env.sh 写入 ~/.bashrc）
export ANSIBLE_VAULT_PASSWORD_FILE="${HOME}/infra-ops/.vault_pass"
source ~/.bashrc   # 若已运行 setup-control-plane-env.sh apply-bashrc

# 方式 B：每条命令显式指定
ansible ... --vault-password-file .vault_pass
ansible-playbook ... --vault-password-file .vault_pass
```

`make inventory-mgmt` 在存在 `.vault_pass` 且存在 `wireguard_vault.yml` 时会**自动**附加 `--vault-password-file`（见 `scripts/ci/inventory-check-mgmt.sh`）。

若仅有加密 vault 文件、尚无 `.vault_pass`，脚本会给出明确错误提示。

### 5.3 GitHub Actions

`deploy.yml` 从 Secret `ANSIBLE_VAULT_PASSWORD` 写入 `.vault_pass`，逻辑与本地一致。

---

## 六、提交 Git 前检查

```bash
# 确保 .vault_pass 存在（inventory-mgmt 在 vault 文件存在时需要）
test -f .vault_pass && chmod 600 .vault_pass

# 静态门禁
make inventory-mgmt
make secret-scan
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

## 七、GitHub Secrets 清单

| Secret | 何时需要 |
|--------|----------|
| `ANSIBLE_VAULT_PASSWORD` | 与本地 `.vault_pass` 相同；`deploy.yml` 与 `make inventory-mgmt`（经脚本）解密 `wireguard_vault.yml` |
| `ANSIBLE_SSH_PRIVATE_KEY` | 已有（SSH Bootstrap）；与 WG 密钥无关 |

```bash
./scripts/wireguard/wg-keys.sh github-hints
```

---

## 八、验收标准（密钥阶段）

| # | 项 | 通过标准 |
|---|-----|----------|
| 1 | Hub 密钥对 | `verify-hub` 成功 |
| 2 | 公钥入 inventory | `wireguard.hub_public_key` 非 null |
| 3 | Vault | `vault-view` 可见 `wireguard_vault.hub_private_key` |
| 4 | Git 卫生 | `make secret-scan` 通过；无私钥明文提交 |
| 5 | inventory | `make inventory-mgmt` 通过（需 `.vault_pass` 若已有 `wireguard_vault.yml`） |
| 6 | 台账 | 可选：更新 `hub-01.yaml` 中 `wireguard_status: keys_ready` |

---

## 九、下一步（非本 Runbook）

- `wireguard` role + `wireguard-hub.yml`：在 Hub 安装 WG Server
- `wireguard-peer.yml`：各 ECS 配置客户端
- 切换 `ci_connectivity.access_mode: wireguard`
- 安全组从 bootstrap 切到 wireguard 阶段

---

## 十、故障排查

| 现象 | 处理 |
|------|------|
| `wg: command not found` | `sudo apt install wireguard-tools` |
| `PyYAML required` | `make setup` 或 `pip install pyyaml` |
| `Hub private key already exists` | 勿重复 generate；备份后手动删除再生成 |
| `ansible-vault not found` | `make setup` |
| vault 解密失败 | 检查 `.vault_pass` 与 GitHub Secret 是否一致 |
| `Attempting to decrypt but no vault secrets found` | 创建 `.vault_pass` 或 `export ANSIBLE_VAULT_PASSWORD_FILE=.../infra-ops/.vault_pass`；见 **§五** |
| `make inventory-mgmt` 静默 Error 1 | 同上；或查看更新后的脚本 stderr 提示 |
| `vault-encrypt-hub` 末尾 `tmp: unbound variable` | 旧版脚本 bug；若已有 `Encryption successful` 且 `vault-view` 正常则无需重跑；升级仓库后重跑无副作用 |
