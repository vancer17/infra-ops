#!/usr/bin/env bash
# =============================================================================
# scripts/ci/lib/common.sh — CI 脚本共享库
# =============================================================================
#
# 【用途】
#   被 scripts/ci/*.sh  source 引用，提供：
#     - 仓库根目录定位（无论从哪一级目录调用）
#     - 统一日志输出
#     - Ansible inventory / 配置文件路径常量
#
# 【用法】
#   在其它 CI 脚本顶部写：
#     # shellcheck source=scripts/ci/lib/common.sh
#     source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#   或（若脚本与 lib 同级）：
#     source "${CI_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib}/common.sh"
#
# 【设计原则】
#   - 本文件只做「路径与输出」，不安装依赖（安装见 install-deps.sh）
#   - 与 .github/workflows/ci.yml 使用相同路径常量，避免 CI 与本地漂移
#
# =============================================================================

# 若已被 source 过则跳过（防止重复定义）
if [[ -n "${CI_COMMON_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
CI_COMMON_LOADED=1

# 严格模式：未定义变量报错、管道失败传播、 errexit
set -euo pipefail

# -----------------------------------------------------------------------------
# 仓库根目录：scripts/ci/lib/common.sh → 上三级 = infra-ops/
# -----------------------------------------------------------------------------
CI_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# -----------------------------------------------------------------------------
# 与 ci.yml / ansible.cfg 对齐的路径常量
# -----------------------------------------------------------------------------
# Dev inventory 目录（syntax-check、inventory 解析共用）
CI_ANSIBLE_INVENTORY="${CI_ANSIBLE_INVENTORY:-${CI_REPO_ROOT}/ansible/inventories/dev/}"

# 配置文件（相对 repo root）
CI_YAMLLINT_CONFIG="${CI_YAMLLINT_CONFIG:-${CI_REPO_ROOT}/.yamllint.yml}"
CI_ANSIBLE_LINT_CONFIG="${CI_ANSIBLE_LINT_CONFIG:-${CI_REPO_ROOT}/.ansible-lint}"
CI_ANSIBLE_REQUIREMENTS="${CI_ANSIBLE_REQUIREMENTS:-${CI_REPO_ROOT}/ansible/requirements.yml}"

# Python 静态检查锁定依赖（uv pip compile 输出；源约束见 requirements-dev.in）
CI_REQUIREMENTS_DEV="${CI_REQUIREMENTS_DEV:-${CI_REPO_ROOT}/requirements-dev.txt}"
CI_REQUIREMENTS_DEV_IN="${CI_REQUIREMENTS_DEV_IN:-${CI_REPO_ROOT}/requirements-dev.in}"

# 本地 uv/pip 默认虚拟环境目录（PEP 668 下 install-deps 自动创建）
CI_VENV_DIR="${CI_VENV_DIR:-${CI_REPO_ROOT}/.venv}"

# ShellCheck 扫描目录
CI_SHELLCHECK_DIR="${CI_SHELLCHECK_DIR:-${CI_REPO_ROOT}/scripts}"

# Docker Compose 待校验文件（不存在则 skip）
CI_COMPOSE_FILES=(
  "${CI_REPO_ROOT}/jumpserver/docker-compose.yml"
  "${CI_REPO_ROOT}/jumpserver/docker-compose.yaml"
  "${CI_REPO_ROOT}/monitoring/docker-compose.yml"
  "${CI_REPO_ROOT}/monitoring/docker-compose.yaml"
)

# -----------------------------------------------------------------------------
# ci_cd — 进入仓库根目录后执行命令
# -----------------------------------------------------------------------------
# 参数：在 REPO_ROOT 下要执行的命令（字符串，由 caller eval 或 "$@"）
ci_cd() {
  (cd "${CI_REPO_ROOT}" && "$@")
}

# -----------------------------------------------------------------------------
# ci_log / ci_skip / ci_die — 统一控制台输出
# -----------------------------------------------------------------------------
ci_log() {
  printf '[ci] %s\n' "$*"
}

ci_skip() {
  printf '[ci] SKIP: %s\n' "$*" >&2
}

ci_die() {
  printf '[ci] ERROR: %s\n' "$*" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# ci_require_cmd — 检查外部命令是否存在
# -----------------------------------------------------------------------------
ci_require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || ci_die "required command not found: ${cmd} (run scripts/ci/install-deps.sh first?)"
}

# -----------------------------------------------------------------------------
# ci_glob_exists — 判断 glob 是否匹配至少一个文件
# -----------------------------------------------------------------------------
ci_glob_exists() {
  local pattern="$1"
  # shellcheck disable=SC2086
  compgen -G "$pattern" >/dev/null 2>&1
}
