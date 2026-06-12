#!/usr/bin/env bash
# =============================================================================
# scripts/ci/shellcheck.sh — Shell 脚本静态分析（对应 ci.yml job: shellcheck）
# =============================================================================
#
# 【检查内容】
#   对 scripts/ 目录下所有 *.sh 运行 ShellCheck（severity >= warning）
#   与 GitHub Action ludeeus/action-shellcheck@2.0.0 行为对齐：
#     - scandir: scripts
#     - severity: warning
#
# 【前置依赖】
#   ShellCheck 可执行文件（Debian/Ubuntu: apt install shellcheck；GitHub ubuntu-latest 已预装）
#
# 【用法】
#   ./scripts/ci/shellcheck.sh
#
# 【说明】
#   使用 find + shellcheck 而非 action，便于本地与 CI 共用同一脚本。
#   排除 scripts/ci/lib 下被 source 的文件时仍扫描（lib 也是 shell）。
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ci_require_cmd shellcheck

# 最低告警级别：warning（与 action-shellcheck severity 一致）
SHELLCHECK_SEVERITY="${SHELLCHECK_SEVERITY:-warning}"

ci_log "Running shellcheck on ${CI_SHELLCHECK_DIR} (severity >= ${SHELLCHECK_SEVERITY})..."

# 排除 lib/*.sh：仅供 source，不应作为独立脚本执行
mapfile -t shell_scripts < <(
  find "${CI_SHELLCHECK_DIR}" -type f -name '*.sh' ! -path '*/lib/*' | sort
)

if [[ ${#shell_scripts[@]} -eq 0 ]]; then
  ci_skip "no *.sh files under ${CI_SHELLCHECK_DIR}"
  exit 0
fi

# -x：跟随 source；--severity：过滤级别
shellcheck --severity="${SHELLCHECK_SEVERITY}" -x "${shell_scripts[@]}"

ci_log "shellcheck OK (${#shell_scripts[@]} files)"
