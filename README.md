# infra-ops

企业 Dev/Test/Prod 基础设施与运维仓库：Ansible 主机基线、Inventory、GitHub Actions CI/CD。

## 仓库职责

| 内容 | 说明 |
|------|------|
| Ansible | Bootstrap、SSH 密钥、后续应用部署 Playbook |
| Inventory | `ansible/inventories/dev/`（Test/Prod 后续扩展） |
| CI | 静态质量门禁（与本地 `make ci` 同源） |
| Deploy | `deploy.yml`（Self-hosted Runner，实机部署） |

业务应用代码在独立 **app-repo**；本仓库只管机器、配置与部署编排。

## 快速开始（贡献者）

```bash
git clone <repo-url> && cd infra-ops

# 一次性：Python 依赖、Galaxy collections、gitleaks
make setup

# 可选：系统安装 shellcheck（Debian）
sudo apt install -y shellcheck

# push / 开 PR 前：全量静态检查
make ci
```

**流程约定**：本地 `make ci` 通过后再 `git push`、开 PR；合并仍以 GitHub **CI Gate** 为准。详见 [贡献指南](docs/contributing.md)。

## 常用 Make 命令

| 命令 | 说明 |
|------|------|
| `make help` | 列出所有 target |
| `make setup` | 安装静态检查依赖（`.venv`、Galaxy、gitleaks） |
| `make ci` | 全量静态检查（等同 `scripts/ci/run-all.sh`） |
| `make lint` | yamllint + shellcheck + ansible-lint |
| `make syntax` | Playbook `--syntax-check` |
| `make inventory` | Dev inventory 解析 + 跨 VPC `ansible_host` 校验 |

实机 Bootstrap（SSH、改 ECS）**不在** `make ci` 内，见 [Bootstrap Runbook](docs/bootstrap/dev-01-bootstrap.runbook.md)。

## 目录结构

```
infra-ops/
├── Makefile                    # 本地静态检查入口
├── requirements-dev.in         # Python 工具版本约束（人工维护）
├── requirements-dev.txt        # uv 锁定输出（与 CI 对齐）
├── ansible/
│   ├── inventories/dev/        # Dev 主机与 group_vars
│   ├── playbooks/              # bootstrap.yml、ssh-keys.yml …
│   └── roles/                  # common、docker …
├── scripts/
│   ├── ci/                     # 静态检查脚本（CI 与 make 共用）
│   └── dev/                    # bootstrap.sh、ssh-keys.sh（实机）
├── .github/workflows/
│   ├── ci.yml                  # PR 静态门禁
│   └── deploy.yml              # 实机部署（Self-hosted）
└── docs/                       # 方案、Runbook、资产台账
```

## 文档索引

| 文档 | 说明 |
|------|------|
| [docs/contributing.md](docs/contributing.md) | 贡献流程、静态 vs 实机检查、依赖与 Branch Protection |
| [docs/20260608-ECS 企业开发环境（Dev）实施方案.md](docs/20260608-ECS%20企业开发环境（Dev）实施方案.md) | Dev 环境总体方案 |
| [docs/bootstrap/dev-01-bootstrap.runbook.md](docs/bootstrap/dev-01-bootstrap.runbook.md) | Dev-01 Bootstrap（1.2） |
| [docs/bootstrap/dev-ssh-keys.runbook.md](docs/bootstrap/dev-ssh-keys.runbook.md) | SSH 密钥体系（1.3） |
| [docs/plan/20260608-开发环境（Dev）部署计划.md](docs/plan/20260608-开发环境（Dev）部署计划.md) | 分阶段部署计划 |

## 三层检查（勿混淆）

| 层级 | 入口 | 何时用 |
|------|------|--------|
| **静态（本地）** | `make ci` | 改 YAML/Ansible/脚本后，push 前 |
| **静态（远程）** | GitHub `CI Gate` | PR 合并门禁 |
| **实机（运行时）** | `scripts/dev/bootstrap.sh`、`deploy.yml` | 真正改 Dev ECS 时 |

本地静态检查**不能**替代实机 Bootstrap 验收；实机操作也**不能**跳过静态门禁。

## 许可证

见 [LICENSE](LICENSE)。
