#!/usr/bin/env bash
# =============================================================================
# scripts/ci/ansible-lint.sh — Ansible 规范检查（对应 ci.yml job: ansible-lint）
# =============================================================================
#
# 【检查内容】
#   运行 ansible-lint，规则与扫描范围见 .ansible-lint：
#     - playbooks、roles、inventory group_vars/host_vars
#     - profile: production
#
# 【前置依赖】
#   ansible-lint、ansible、Galaxy collections
#   → ./scripts/ci/install-deps.sh ansible-lint
#
# 【用法】
#   ./scripts/ci/ansible-lint.sh
#
# 【说明】
#   ansible-lint 会读取 ansible.cfg（roles_path、inventory 等），
#   在仓库根目录执行以保证路径解析一致。
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ci_require_cmd ansible-lint

ci_log "Running ansible-lint (config: ${CI_ANSIBLE_LINT_CONFIG})..."
ci_cd ansible-lint -c "${CI_ANSIBLE_LINT_CONFIG}"

ci_log "ansible-lint OK"
