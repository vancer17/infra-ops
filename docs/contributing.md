# 贡献指南

本文说明如何向 `infra-ops` 提交变更：本地静态检查、与 GitHub CI 对齐、以及何时进行实机 Bootstrap/Deploy。

## 1. 贡献流程（推荐）

```
首次 clone
    │
    ▼
make setup                    # 安装 Python/Galaxy/gitleaks
    │
    ▼
（可选）sudo apt install shellcheck
    │
    ▼
修改 Ansible / inventory / scripts / workflows
    │
    ├─ 只改 inventories/dev/     → make inventory
    ├─ 只改 inventories/mgmt/    → make inventory-mgmt
    ├─ 只改 roles/playbooks 规范 → make lint
    └─ 准备 push / 开 PR          → make ci
    │
    ▼
git push → 开 PR → 等待 GitHub CI Gate 绿 → 合并
    │
    ▼
（若涉及实机）scripts/dev/bootstrap.sh 或 deploy.yml
```

**约定**：本地 `make ci` 通过后再 push，减少 CI 失败往返。  
**强制**：Branch Protection 要求远程 **CI Gate** 通过才能合并；本地 Make **无法**阻止 push，也不替代远程门禁。

## 2. 三层检查模型

| 层级 | 工具 | 连 SSH | 改 ECS | 作用 |
|------|------|--------|--------|------|
| L1 本地静态 | `make ci` / `make lint` … | 否 | 否 | 开发反馈循环 |
| L2 远程静态 | GitHub Actions `ci.yml` → **CI Gate** | 否 | 否 | 合并门禁 |
| L3 实机运行时 | `bootstrap.sh`、`deploy.yml` | 是 | 是 | Bootstrap / 部署验收 |

### 2.1 L1：`make ci` 包含什么

与 `.github/workflows/ci.yml` 中 `ci-gate` 之前的 job 一致，底层脚本为单一事实来源：

| 检查 | Make target | 脚本 | CI job |
|------|-------------|------|--------|
| YAML 格式 | `make yamllint` | `scripts/ci/yamllint.sh` | yaml-lint |
| Shell 脚本 | `make shellcheck` | `scripts/ci/shellcheck.sh` | shellcheck |
| Ansible 规范 | `make ansible-lint` | `scripts/ci/ansible-lint.sh` | ansible-lint |
| Playbook 语法 | `make ansible-syntax` | `scripts/ci/ansible-syntax.sh` | ansible-syntax |
| Compose 校验 | `make docker-validate` | `scripts/ci/docker-validate.sh` | docker-validate |
| 敏感信息 | `make secret-scan` | `scripts/ci/secret-scan.sh` | secret-scan |
| **全量** | **`make ci`** | **`scripts/ci/run-all.sh`** | **ci-gate 前置** |

### 2.2 本地专用（未纳入 CI job）

| 检查 | Make target | 脚本 | 何时跑 |
|------|-------------|------|--------|
| Inventory 深度校验（dev） | `make inventory` | `scripts/ci/inventory-check.sh` | 修改 `inventories/dev/` 后 |
| Inventory 深度校验（mgmt） | `make inventory-mgmt` | `scripts/ci/inventory-check-mgmt.sh` | 修改 `inventories/mgmt/`、Hub 台账后 |

原因：`ansible-syntax.sh` 已含轻量 inventory 抽查；跨 VPC `ansible_host` 校验留本地，避免 CI 与 Jinja 渲染差异导致误报。改 inventory 后务必 `make inventory`。

### 2.3 L3：实机操作（不在 `make ci` 内）

| 场景 | 入口 |
|------|------|
| Dev ECS Bootstrap（1.2） | `./scripts/dev/bootstrap.sh all dev-01`（在 yax 控制机上，**deploy 用户**，无需控制机 sudo） |
| Hub Bootstrap（1.2） | `ANSIBLE_INVENTORY=ansible/inventories/mgmt/ ./scripts/dev/bootstrap.sh all hub-01` |
| SSH 密钥（1.3） | `./scripts/dev/ssh-keys.sh all dev-01`（mgmt 同理换 inventory） |
| 远程部署 | GitHub `deploy.yml`（Self-hosted Runner，CI 替代机 `121.41.58.20`） |

实机 Dry Run（预览变更、需 SSH）：

```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventories/dev/ \
  --limit dev-01 \
  --check --diff
```

或通过 `deploy.yml` 设置 `dry_run: true`。

## 3. 首次环境准备

### 3.1 `make setup`

等价于 `scripts/ci/install-deps.sh all`：

- 创建/同步 `.venv`（`requirements-dev.txt`）
- `ansible-galaxy collection install -r ansible/requirements.yml`
- 下载 gitleaks 到 `.ci-tools/bin/`（若系统 PATH 无 gitleaks）

Makefile 已把 `.venv/bin` 与 `.ci-tools/bin` 加入 PATH，**无需**手动 `source .venv/bin/activate`。

在 **ECS 上跑 `bootstrap.sh` / `ssh-keys.sh`** 时 Makefile 的 PATH 不生效，须先：

```bash
make setup
source .venv/bin/activate   # 或 export PATH="$PWD/.venv/bin:$PATH"
```

否则 `preflight` 会报 `ansible-playbook not found`。

### 3.2 系统依赖（不随 setup 安装）

| 工具 | 用途 | 安装 |
|------|------|------|
| **shellcheck** | `make shellcheck` | `sudo apt install shellcheck` |
| **docker** | `make docker-validate` | 仅在有 compose 文件时需；CI 用 ubuntu-latest 预装 |
| **uv**（可选） | 更快 sync / 编译锁定文件 | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |

无 shellcheck 时 `make shellcheck` 会失败；CI 镜像已预装。

### 3.3 Python 版本

- CI：`.github/workflows/ci.yml` 中 `PYTHON_VERSION: "3.12"`
- 锁定：`requirements-dev.txt` 用 `--python-version 3.12` 编译
- 本地：3.12 最佳；3.11+ 通常可用

## 4. Python 依赖与版本锁定

| 文件 | 角色 |
|------|------|
| `requirements-dev.in` | 人工维护：包名 + 版本**范围** |
| `requirements-dev.txt` | `uv pip compile` 输出：精确版本，**提交 Git** |

### 4.1 更新依赖流程

1. 编辑 `requirements-dev.in`
2. 重新生成锁定文件：

   ```bash
   ./scripts/ci/compile-requirements.sh
   ```

3. `make setup && make ci`
4. 提交 `requirements-dev.in` 与 `requirements-dev.txt` 同一 PR

Galaxy collections 独立维护于 `ansible/requirements.yml`，由 `install-deps.sh` 安装。

## 5. 按变更类型选择命令

| 你改了什么 | 建议命令 |
|------------|----------|
| 任意 YAML / workflow / Ansible | `make ci`（push 前） |
| 仅 `inventories/dev/` | `make inventory` + `make ci` |
| 仅 role / playbook 逻辑 | `make lint` + `make syntax` |
| 仅 `scripts/*.sh` | `make shellcheck` + `make ci` |
| 准备 Bootstrap 实机 | 先 `make ci`，再 `bootstrap.sh preflight` |

## 6. GitHub Branch Protection

在 **Settings → Branches → Branch protection rules**（`main` / `develop`）：

| 项 | 建议 |
|----|------|
| Require pull request | 是 |
| Require status checks | 勾选 **CI Gate** |
| Require branches up to date | 可选 |

开发者本地 `make ci` 与远程 job 使用同一套 `scripts/ci/*.sh`；若本地绿、CI 红，优先检查 shellcheck/gitleaks 是否安装、Python 是否 3.12、是否忘记提交 `requirements-dev.txt`。

## 7. 密钥与敏感信息

- **勿提交**：私钥、`.env`、vault 明文、`ansible/keys/infra-ci-deploy`
- **勿写入** `logs/` 或临时文件：SSH/WG 私钥（`logs/` 虽在 gitignore，仍可能被误复制）
- **可提交**：`.pub` 公钥、`*.example` 模板
- `make secret-scan` / CI `secret-scan` job 扫描 Git 历史（gitleaks）
- 数据库密码等放 GitHub Environment Secrets 或 ansible-vault
- 若私钥曾泄露：轮换密钥并更新 GitHub Secret `ANSIBLE_SSH_PRIVATE_KEY`

## 8. 实机 Bootstrap 与静态检查的关系

改 Ansible 后推荐顺序：

1. `make ci`（及改 inventory 时 `make inventory`）
2. `git push` → PR → CI Gate 绿 → 合并
3. `source .venv/bin/activate`（ECS 上必需）
4. `./scripts/dev/bootstrap.sh preflight dev-01`
5. `./scripts/dev/bootstrap.sh apply dev-01`（**勿**加 `-e ansible_connection=local`，同机时脚本自动处理）
6. `./scripts/dev/bootstrap.sh verify dev-01`
7. 第二次 `apply` 验证幂等；确认日志含 `Create jump_ops user`（`bootstrap.yml` 使用 `import_role` 分别导入 base/users）

详见 [dev-01-bootstrap.runbook.md](bootstrap/dev-01-bootstrap.runbook.md)、[hub-01-bootstrap.runbook.md](bootstrap/hub-01-bootstrap.runbook.md)。

## 9. 常见问题

### 本地绿、CI 红

- 是否安装 shellcheck？
- 是否运行 `make setup` 同步 `requirements-dev.txt`？
- gitleaks 是否可用（`make setup` 或系统 PATH）？
- 是否只改了 inventory 但未跑 `make inventory`（本地问题，CI 可能不覆盖）？

### `make ci` 能否代替 Bootstrap 验收？

不能。`make ci` 不 SSH、不跑 `docker hello-world`、不测 RDS/OSS。

### `ansible-playbook not found`（实机 Bootstrap）

在 ECS 上未 `make setup` 或未 `source .venv/bin/activate`。见 §3.1。

### `argument -l/--limit: expected one argument`

勿执行 `./scripts/dev/bootstrap.sh apply -e ansible_connection=local`。  
`-e` 会被误解析为主机名。同机部署用 `./scripts/dev/bootstrap.sh apply` 或 `apply dev-01` 即可。

### `apply OK` 但缺少 jump_ops、`/opt/app/compose`

`bootstrap.yml` 须用 `tasks` + `import_role` 分别导入 `common`（base/users），勿在 `roles:` 中重复同名 `common`（Ansible 2.16 可能两次都跑 base）。修复后重新 `apply`。

### `sudo: a password is required`（控制机 localhost task）

Bootstrap / ssh-keys 在控制机读 `ansible/keys/*.pub` 时使用 `delegate_to: localhost` + `become: false`。以 `deploy` 跑 Ansible 时控制机不应 sudo；远程 ECS task 仍正常 `become: true`。

### 能否用 pre-commit / pre-push hook？

可选。团队可配置 commit 前跑 `make lint`、push 前跑 `make ci`；hook 可被 `--no-verify` 跳过，**不能**替代 Branch Protection。

## 10. 相关文档

- [README.md](../README.md) — 仓库概览与快速开始
- [dev-01-bootstrap.runbook.md](bootstrap/dev-01-bootstrap.runbook.md)
- [hub-01-bootstrap.runbook.md](bootstrap/hub-01-bootstrap.runbook.md)
- [dev-ssh-keys.runbook.md](bootstrap/dev-ssh-keys.runbook.md)
- [20260608-ECS 企业开发环境（Dev）实施方案.md](20260608-ECS%20企业开发环境（Dev）实施方案.md)
