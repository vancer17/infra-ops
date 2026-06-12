#!/usr/bin/env bash
# =============================================================================
# scripts/ci/compile-requirements.sh — 用 uv 重新生成 requirements-dev.txt
# =============================================================================
#
# 【用途】
#   当你修改 requirements-dev.in（增删包、调整版本范围）后，运行本脚本
#   更新锁定文件 requirements-dev.txt，保证 CI 与本地使用相同精确版本。
#
# 【用法】
#   ./scripts/ci/compile-requirements.sh
#
# 【前置】
#   已安装 uv：https://docs.astral.sh/uv/
#
# 【输出】
#   覆盖写入 ${REPO_ROOT}/requirements-dev.txt（含顶部说明注释 + uv 锁定正文）
#   请与 requirements-dev.in 一并 git add / commit
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ci_require_cmd uv

PYTHON_VERSION="${CI_PYTHON_VERSION:-3.12}"
tmp_file="$(mktemp)"

cleanup() {
  rm -f "${tmp_file}"
}
trap cleanup EXIT

ci_log "Compiling ${CI_REQUIREMENTS_DEV_IN} → ${CI_REQUIREMENTS_DEV} (python ${PYTHON_VERSION})..."

uv pip compile "${CI_REQUIREMENTS_DEV_IN}" \
  -o "${tmp_file}" \
  --python-version "${PYTHON_VERSION}" \
  --annotation-style line

# 写入固定顶部注释块（人工维护的说明）+ uv 生成的锁定正文
cat > "${CI_REQUIREMENTS_DEV}" <<'HEADER'
# =============================================================================
# requirements-dev.txt — 本地 / CI 静态检查 Python 依赖（uv 锁定输出）
# =============================================================================
#
# 【这个文件是什么】
#   由 uv 根据 requirements-dev.in 解析得到的「精确版本锁定」清单。
#   包含直接依赖（yamllint、ansible、ansible-lint）及其全部传递依赖。
#
# 【能否直接编辑】
#   不要手改包版本行。需要升级或增删包时：
#     1. 改 requirements-dev.in
#     2. 执行：./scripts/ci/compile-requirements.sh
#     3. 将 .in 与本文件一并提交
#
# 【重新生成锁定文件】
#   ./scripts/ci/compile-requirements.sh
#   或：uv pip compile requirements-dev.in -o requirements-dev.txt \
#         --python-version 3.12 --annotation-style line
#
#   --python-version 3.12 必须与 .github/workflows/ci.yml 中 PYTHON_VERSION 一致。
#
# 【各检查脚本用到的「顶层」包】
#   yamllint.sh       → yamllint
#   ansible-syntax.sh → ansible
#   ansible-lint.sh   → ansible-lint
#
# 【不在本文件中的依赖】
#   Ansible Galaxy collections → ansible/requirements.yml
#   gitleaks                   → install-deps.sh profile gitleaks
#
# =============================================================================

HEADER

cat "${tmp_file}" >> "${CI_REQUIREMENTS_DEV}"

ci_log "Lock file updated: ${CI_REQUIREMENTS_DEV}"
ci_log "Review diff and commit requirements-dev.in + requirements-dev.txt"
