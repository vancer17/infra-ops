#!/usr/bin/env bash
# =============================================================================
# scripts/ci/secret-scan.sh — 敏感信息扫描（对应 ci.yml job: secret-scan）
# =============================================================================
#
# 【检查内容】
#   使用 gitleaks 扫描 Git 历史与工作区，检测误提交的密钥、Token、私钥等。
#   与 gitleaks/gitleaks-action@v2 目的一致；本脚本便于本地与 CI 共用。
#
# 【前置依赖】
#   gitleaks 在 PATH 中
#   → ./scripts/ci/install-deps.sh gitleaks
#   → 或将 ${REPO}/.ci-tools/bin 加入 PATH
#
# 【用法】
#   ./scripts/ci/secret-scan.sh
#
# 【环境变量】
#   GITLEAKS_EXTRA_ARGS  追加传给 gitleaks 的参数
#   CI_SKIP_SECRET_SCAN=1  本地临时跳过（CI 中勿设置）
#
# 【注意】
#   需要在 Git 仓库根目录执行（依赖 .git）；shallow clone 可能漏检旧提交。
#   CI job 应 checkout fetch-depth: 0 以扫描完整历史。
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

if [[ "${CI_SKIP_SECRET_SCAN:-}" == "1" ]]; then
  ci_skip "CI_SKIP_SECRET_SCAN=1"
  exit 0
fi

# 优先使用 install-deps 安装到 .ci-tools/bin 的 gitleaks
if [[ -x "${CI_REPO_ROOT}/.ci-tools/bin/gitleaks" ]]; then
  export PATH="${CI_REPO_ROOT}/.ci-tools/bin:${PATH}"
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  ci_die "gitleaks not found (run: ./scripts/ci/install-deps.sh gitleaks)"
fi

if [[ ! -d "${CI_REPO_ROOT}/.git" ]]; then
  ci_die "not a git repository: ${CI_REPO_ROOT}"
fi

ci_log "Running gitleaks detect (source: ${CI_REPO_ROOT})..."

# --verbose：输出详情；--redact：日志脱敏
# 无 .gitleaks.toml 时使用 gitleaks 默认规则
# shellcheck disable=SC2086
ci_cd gitleaks detect \
  --source . \
  --verbose \
  --redact \
  ${GITLEAKS_EXTRA_ARGS:-}

ci_log "secret-scan OK"
