# Dev SSH 密钥体系 Runbook（阶段 1.3）

> 前置：1.1 安全组完成、1.2 Bootstrap 完成（`deploy` 用户、Docker、目录已就绪）

## 静态检查（改 Playbook 后）

修改 `ansible/playbooks/ssh-keys.yml` 或 `group_vars/all/ssh.yml` 后，实机执行前：

```bash
make ci          # 或至少 make lint && make syntax
make inventory   # 若同时改了 inventories/dev/
```

详见 [贡献指南](../contributing.md)。

## 目标

| 项 | 说明 |
|----|------|
| CI 私钥 | CI 机 / GitHub Secret `ANSIBLE_SSH_PRIVATE_KEY` |
| Dev 公钥 | `deploy@` 的 `authorized_keys` |
| known_hosts | GitHub Secret `ANSIBLE_SSH_KNOWN_HOSTS` |
| 稳态 | 禁止 root SSH，Ansible 改用 `deploy@` |

## 步骤

### 1. 在 CI 机生成密钥对

```bash
./scripts/dev/ssh-keys.sh generate
```

产出：

- `ansible/keys/infra-ci-deploy` — 私钥，**勿提交 Git**
- `ansible/keys/infra-ci-deploy.pub` — 公钥，**提交 Git**

### 2. 分发公钥到 Dev-01

```bash
./scripts/dev/ssh-keys.sh all dev-01
```

等价于：`preflight` → `distribute`（Ansible `ssh-keys.yml`）→ `verify` → 输出 `known-hosts` 与 GitHub 提示。

### 3. 配置 GitHub Secrets

在仓库 **Settings → Environments → dev**：

| Secret | 内容 |
|--------|------|
| `ANSIBLE_SSH_PRIVATE_KEY` | `ansible/keys/infra-ci-deploy` 全文 |
| `ANSIBLE_SSH_KNOWN_HOSTS` | `./scripts/dev/ssh-keys.sh known-hosts dev-01` 输出 |

### 4. 收紧 SSH（禁止 root）

确认 `deploy@` 登录正常后：

```bash
./scripts/dev/ssh-keys.sh steady dev-01
./scripts/dev/ssh-keys.sh mark-done dev-01
```

脚本会：

- 执行 `ssh-keys.yml --tags steady`，`PermitRootLogin no`
- 更新 `group_vars/all/ssh.yml`：`ssh_inventory_user: deploy`、`ssh_phase: steady`

### 5. Dev-02

Dev-02 完成 1.2 后重复：

```bash
./scripts/dev/ssh-keys.sh all dev-02
./scripts/dev/ssh-keys.sh steady dev-02
```

同一 CI 密钥对可授权多台 Dev（公钥相同）。

## 验收

| # | 检查 | 命令 |
|---|------|------|
| 1 | deploy 登录 | `ssh -i ansible/keys/infra-ci-deploy deploy@121.41.58.20` |
| 2 | root 拒绝 | `ssh root@121.41.58.20` 应失败 |
| 3 | Ansible deploy | `ansible dev-01 -i ansible/inventories/dev/ -m ping` |
| 4 | 幂等 | `./scripts/dev/ssh-keys.sh distribute dev-01` 第二次无变更 |

## 相关文件

- `ansible/playbooks/ssh-keys.yml`
- `ansible/inventories/dev/group_vars/all/ssh.yml`
- `ansible/roles/common/tasks/users.yml`
- `.github/workflows/deploy.yml`
