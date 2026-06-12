#!/usr/bin/env bash
# =============================================================================
# scripts/ci/run-all.sh — 本地静态 CI 全量门禁（对应 ci.yml job: ci-gate 之前所有检查）
# =============================================================================
#
# 【用途】
#   在 push / 开 PR 前于本地依次执行与 GitHub Actions ci.yml 相同的静态检查，
#   缩短「推上去才发现 CI 红」的反馈循环。
#
# 【用法】
#   ./scripts/ci/run-all.sh              # 假设依赖已安装
#   ./scripts/ci/run-all.sh --install    # 先 install-deps all 再跑检查
#
# 【执行顺序】
#   1. yamllint.sh
#   2. shellcheck.sh
#   3. ansible-lint.sh
#   4. ansible-syntax.sh
#   5. docker-validate.sh
#   6. secret-scan.sh
#
# 【与 ci.yml 的关系】
#   各步骤脚本为单一事实来源；ci.yml 各 job 分别调用同名脚本。
#   本脚本仅做串行聚合，不含 ci-gate 的 echo 步骤。
#
# 【注意】
#   - 不包含 bootstrap.sh 等实机 SSH 操作
#   - secret-scan 需要 gitleaks；--install 会尝试安装
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DO_INSTALL=false
if [[ "${1:-}" == "--install" ]]; then
  DO_INSTALL=true
fi

run_step() {
  local name="$1"
  local script="$2"
  ci_log "========== ${name} =========="
  bash "${SCRIPT_DIR}/${script}"
}

if [[ "${DO_INSTALL}" == true ]]; then
  ci_log "Installing dependencies (profile: all)..."
  bash "${SCRIPT_DIR}/install-deps.sh" all
  export PATH="${CI_REPO_ROOT}/.ci-tools/bin:${PATH}"
  # install-deps 可能在 .venv 安装 Python 包；自动加入 PATH
  if [[ -d "${CI_VENV_DIR}/bin" ]]; then
    export PATH="${CI_VENV_DIR}/bin:${PATH}"
  fi
fi

run_step "yaml-lint" "yamllint.sh"
run_step "shellcheck" "shellcheck.sh"
run_step "ansible-lint" "ansible-lint.sh"
run_step "ansible-syntax" "ansible-syntax.sh"
run_step "docker-validate" "docker-validate.sh"
run_step "secret-scan" "secret-scan.sh"

ci_log "========== All static CI checks passed =========="
