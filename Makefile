# =============================================================================
# infra-ops/Makefile — 本地静态质量检查入口
# =============================================================================
#
# 【用途】
#   为 push / 开 PR 前提供与 GitHub Actions ci.yml 对齐的标准命令，
#   避免开发者记住多条 shell 命令，并减少「本地绿、CI 红」的维护漂移。
#
# 【前提】
#   - 底层逻辑在 scripts/ci/*.sh（单一事实来源）；本文件只做 target 聚合
#   - Python / Ansible 工具版本由 requirements-dev.txt 锁定
#   - 首次使用请先：make setup
#
# 【常用流程】
#   make setup          # 一次性安装 Python 依赖、Galaxy collections、gitleaks
#   make ci             # push 前全量静态检查（等同 run-all.sh）
#   make lint           # 只改 YAML/Ansible 规范时
#   make inventory      # 只改 inventories/dev/ 时
#
# 【与实机 Bootstrap 的分工】
#   make ci / make lint / make syntax / make inventory → 只读静态，不 SSH
#   scripts/dev/bootstrap.sh                         → 实机 preflight/apply/verify
#
# 【PATH 说明】
#   各 recipe 自动把 .venv/bin 与 .ci-tools/bin 加入 PATH，
#   以便 make setup 后无需手动 source .venv/bin/activate
#
# =============================================================================

# 使用 bash 执行 recipe（部分脚本依赖 bash 特性）
SHELL := /bin/bash

# 仓库根目录（Makefile 所在目录）
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# CI 脚本目录（与 scripts/ci/lib/common.sh 中路径约定一致）
SCRIPTS_CI := $(REPO_ROOT)/scripts/ci
SCRIPTS_WG := $(REPO_ROOT)/scripts/wireguard
SCRIPTS_MGMT := $(REPO_ROOT)/scripts/mgmt

# 本地工具路径：install-deps.sh 创建的 venv 与 gitleaks 安装目录
VENV_BIN := $(REPO_ROOT)/.venv/bin
CI_TOOLS_BIN := $(REPO_ROOT)/.ci-tools/bin

# 将本地工具目录置于 PATH 最前，使 recipe 能找到 yamllint/ansible/gitleaks
export PATH := $(VENV_BIN):$(CI_TOOLS_BIN):$(PATH)

# .PHONY：声明这些 target 不对应同名文件，避免「文件已存在则跳过 recipe」
.PHONY: help setup lint syntax inventory inventory-mgmt ci \
        yamllint shellcheck ansible-lint ansible-syntax \
        docker-validate secret-scan \
        wg-keys-check wg-keys-list stage-e-preflight control-plane-setup

# -----------------------------------------------------------------------------
# help — 默认目标；make 无参数时显示可用命令
# -----------------------------------------------------------------------------
help:
	@echo "infra-ops — local static CI (mirror of .github/workflows/ci.yml)"
	@echo ""
	@echo "Setup:"
	@echo "  make setup          Install Python deps, Galaxy collections, gitleaks"
	@echo ""
	@echo "Aggregates (run before push / PR):"
	@echo "  make ci             All static checks (scripts/ci/run-all.sh)"
	@echo "  make lint           yamllint + shellcheck + ansible-lint"
	@echo "  make syntax         Ansible playbook --syntax-check + light inventory"
	@echo "  make inventory      Dev inventory parse + cross-VPC ansible_host check"
	@echo "  make inventory-mgmt Mgmt inventory parse (hub-01 ansible_host check)"
	@echo ""
	@echo "Control plane (ci-01, on yax as deploy):"
	@echo "  make control-plane-setup     Fix bashrc + ansible ping (黄灯 1)"
	@echo "  make stage-e-preflight       Full preflight before WireGuard keys"
	@echo ""
	@echo "WireGuard keys (on CI machine with wireguard-tools):"
	@echo "  make wg-keys-check   Check wg/ansible-vault deps"
	@echo "  make wg-keys-list    List hub/peer key files status"
	@echo "  See: docs/wireguard/wg-keys.runbook.md"
	@echo ""
	@echo "Individual checks (same as CI jobs):"
	@echo "  make yamllint       YAML format (.yamllint.yml)"
	@echo "  make shellcheck     Shell scripts under scripts/"
	@echo "  make ansible-lint   Ansible style (.ansible-lint)"
	@echo "  make ansible-syntax Playbook syntax-check"
	@echo "  make docker-validate docker compose config (skip if files missing)"
	@echo "  make secret-scan    gitleaks (requires make setup or system gitleaks)"
	@echo ""
	@echo "Notes:"
	@echo "  - First time: make setup"
	@echo "  - shellcheck: apt install shellcheck (not installed by setup)"
	@echo "  - Remote gate: GitHub CI Gate must still pass on PR"

# -----------------------------------------------------------------------------
# setup — 安装本地静态检查所需的全部依赖
# -----------------------------------------------------------------------------
# 调用 install-deps.sh all：
#   - uv/pip sync requirements-dev.txt
#   - ansible-galaxy collection install
#   - 下载 gitleaks 到 .ci-tools/bin（若系统 PATH 无 gitleaks）
setup:
	@echo "[make] Running scripts/ci/install-deps.sh all ..."
	bash "$(SCRIPTS_CI)/install-deps.sh" all
	@echo "[make] setup OK — you can run: make ci"

# -----------------------------------------------------------------------------
# lint — 代码风格与规范（不含 playbook syntax / inventory 深度校验）
# -----------------------------------------------------------------------------
# 对应 ci.yml jobs: yaml-lint, shellcheck, ansible-lint
# 适用：修改 roles、group_vars、playbooks 结构后快速反馈
lint: yamllint shellcheck ansible-lint
	@echo "[make] lint OK"

yamllint:
	bash "$(SCRIPTS_CI)/yamllint.sh"

shellcheck:
	bash "$(SCRIPTS_CI)/shellcheck.sh"

ansible-lint:
	bash "$(SCRIPTS_CI)/ansible-lint.sh"

# -----------------------------------------------------------------------------
# syntax — Ansible Playbook 语法检查
# -----------------------------------------------------------------------------
# 对应 ci.yml job: ansible-syntax
# 内含轻量 inventory graph 抽查；深度 inventory 校验见 make inventory
syntax: ansible-syntax
	@echo "[make] syntax OK"

ansible-syntax:
	bash "$(SCRIPTS_CI)/ansible-syntax.sh"

# -----------------------------------------------------------------------------
# inventory — Dev inventory 解析与 ansible_host 策略校验
# -----------------------------------------------------------------------------
# 对应开发计划中的「ansible-inventory 解析 + 跨 VPC 地址检查」
# 修改 inventories/dev/、host_vars、network.yml 后建议单独运行
inventory:
	bash "$(SCRIPTS_CI)/inventory-check.sh"
	@echo "[make] inventory OK"

# -----------------------------------------------------------------------------
# inventory-mgmt — Mgmt inventory 解析与 Hub ansible_host 策略校验
# -----------------------------------------------------------------------------
# 修改 inventories/mgmt/ 后运行；对应 scripts/ci/inventory-check-mgmt.sh
inventory-mgmt:
	bash "$(SCRIPTS_CI)/inventory-check-mgmt.sh"
	@echo "[make] inventory-mgmt OK"

# -----------------------------------------------------------------------------
# ci — 全量静态门禁（push / PR 前推荐）
# -----------------------------------------------------------------------------
# 对应 ci.yml 在 ci-gate 之前的全部 job，顺序见 scripts/ci/run-all.sh
# 不包含 bootstrap.sh 等实机 SSH 操作
ci:
	bash "$(SCRIPTS_CI)/run-all.sh"
	@echo "[make] ci OK — safe to push (GitHub CI Gate still required on PR)"

# -----------------------------------------------------------------------------
# 以下为 ci 全量子步骤；可单独调用，也可被 lint / syntax 间接使用
# -----------------------------------------------------------------------------
docker-validate:
	bash "$(SCRIPTS_CI)/docker-validate.sh"

secret-scan:
	bash "$(SCRIPTS_CI)/secret-scan.sh"

# -----------------------------------------------------------------------------
# wg-keys — WireGuard 密钥脚本快捷入口（实机操作，非 make ci 一部分）
# -----------------------------------------------------------------------------
wg-keys-check:
	bash "$(SCRIPTS_WG)/wg-keys.sh" check-deps

wg-keys-list:
	bash "$(SCRIPTS_WG)/wg-keys.sh" list

# -----------------------------------------------------------------------------
# control-plane-setup — 修正 ci-01 控制面 bashrc（黄灯 1）
# -----------------------------------------------------------------------------
control-plane-setup:
	bash "$(REPO_ROOT)/scripts/dev/setup-control-plane-env.sh" all
	@echo "[make] control-plane-setup OK — run: source ~/.bashrc"

# -----------------------------------------------------------------------------
# stage-e-preflight — 阶段 E 前全量预检（黄灯 1–3 + Hub 远程验收）
# -----------------------------------------------------------------------------
# 在 yax 上：make stage-e-preflight
# 自动安装 wireguard-tools：make stage-e-preflight INSTALL_WG=1
stage-e-preflight:
	bash "$(SCRIPTS_MGMT)/stage-e-preflight.sh" \
		$(if $(INSTALL_WG),--install-wireguard,) \
		$(if $(SKIP_REMOTE),--skip-remote,)
	@echo "[make] stage-e-preflight OK"
