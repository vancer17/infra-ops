# 本地与 CI 静态检查

本目录说明 `infra-ops` 静态质量门禁的设计；**操作步骤见 [贡献指南](../contributing.md)**。

## 设计原则

**单一事实来源**：检查逻辑在 `scripts/ci/*.sh`，GitHub Actions（`.github/workflows/ci.yml`）与本地 Make（`Makefile`）调用同一脚本，避免双份维护。

```
开发者                    GitHub Actions
   │                            │
   ├─ make ci ────────────────┼─ ci.yml jobs
   │     └─ run-all.sh         │     └─ 各 *.sh
   │                            │
   └─ scripts/ci/*.sh ◄────────┘
```

## 脚本索引

| 脚本 | 用途 |
|------|------|
| `install-deps.sh` | 按 profile 安装 Python/Galaxy/gitleaks |
| `compile-requirements.sh` | 从 `requirements-dev.in` 生成 `requirements-dev.txt` |
| `run-all.sh` | 串行执行全部静态检查（`make ci`） |
| `yamllint.sh` | YAML 格式 |
| `shellcheck.sh` | Shell 脚本 |
| `ansible-lint.sh` | Ansible 规范 |
| `ansible-syntax.sh` | Playbook syntax-check + 轻量 inventory |
| `inventory-check.sh` | Dev inventory 深度校验（**仅本地** `make inventory`） |
| `inventory-check-mgmt.sh` | Mgmt inventory 深度校验（**仅本地** `make inventory-mgmt`） |
| `docker-validate.sh` | docker compose config |
| `secret-scan.sh` | gitleaks |
| `lib/common.sh` | 路径常量、日志、die |

## Make 与 CI 对照

| 本地 | 远程 CI |
|------|---------|
| `make setup` | 各 job 内 `install-deps.sh <profile>` |
| `make ci` | jobs 1–6 并行 + **CI Gate** |
| `make inventory` | 未纳入 CI（见 contributing.md） |
| `make inventory-mgmt` | 未纳入 CI（改 inventories/mgmt/ 后本地运行） |

## 依赖文件

| 文件 | 说明 |
|------|------|
| `requirements-dev.in` | Python 包版本范围（人工编辑） |
| `requirements-dev.txt` | uv 锁定（提交 Git，CI/本地 sync） |
| `ansible/requirements.yml` | Galaxy collections |

更新 Python 依赖：`./scripts/ci/compile-requirements.sh`

## 不在此体系内

- `scripts/dev/bootstrap.sh` — 实机 Bootstrap（SSH）
- `.github/workflows/deploy.yml` — Self-hosted 实机部署

详见 [贡献指南 § 三层检查模型](../contributing.md#2-三层检查模型)。
