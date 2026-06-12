#!/usr/bin/env bash
# =============================================================================
# scripts/ci/yamllint.sh — YAML 格式检查（对应 ci.yml job: yaml-lint）
# =============================================================================
#
# 【检查内容】
#   对仓库内 YAML 文件运行 yamllint，规则见 .yamllint.yml
#   （行宽、truthy、注释缩进等；.github/ 与 venv 已在 ignore 中排除）
#
# 【前置依赖】
#   yamllint 命令（pip install yamllint 或 ./scripts/ci/install-deps.sh yamllint）
#
# 【用法】
#   ./scripts/ci/yamllint.sh
#
# 【退出码】
#   0 — 无违规
#   非 0 — yamllint 发现 error 或命令失败
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ci_require_cmd yamllint

ci_log "Running yamllint (config: ${CI_YAMLLINT_CONFIG})..."
ci_cd yamllint -c "${CI_YAMLLINT_CONFIG}" .

ci_log "yamllint OK"
