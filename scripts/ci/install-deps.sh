#!/usr/bin/env bash
# =============================================================================
# scripts/ci/install-deps.sh — CI / 本地静态检查依赖安装
# =============================================================================
#
# 【用途】
#   按「检查类型 profile」安装 Python 包、Ansible Galaxy collections、
#   或 gitleaks 二进制。GitHub Actions 各 job 在跑检查脚本前先调用本脚本，
#   本地开发者也可在首次 clone 后执行一次。
#
# 【用法】
#   ./scripts/ci/install-deps.sh <profile>
#
#   profile 可选值：
#     yamllint       → sync requirements-dev.txt（含 yamllint 及锁定传递依赖）
#     ansible-lint   → sync requirements-dev.txt + galaxy collections
#     ansible        → sync requirements-dev.txt + galaxy（syntax-check 用）
#     gitleaks       → 下载 gitleaks 到 .ci-tools/bin/（若系统未安装）
#     all            → 上述全部（本地 run-all.sh --install 前置步骤）
#
# 【Python 依赖与版本锁定】
#   源约束：requirements-dev.in（人工维护版本范围）
#   锁定输出：requirements-dev.txt（uv pip compile 生成，提交到 Git）
#   本脚本通过 uv pip sync 或 pip install -r 安装锁定版本，避免 CI 与本地漂移。
#
# 【环境变量】
#   CI_REQUIREMENTS_DEV    默认 ${REPO_ROOT}/requirements-dev.txt
#   CI_GITLEAKS_VERSION    默认 v8.24.2
#   UV_SYSTEM_PYTHON=1     在 CI 无 venv 时让 uv 写入 setup-python 提供的解释器
#
# 【注意】
#   - 若需隔离环境，先 python -m venv .venv && source .venv/bin/activate 再执行
#   - galaxy install 幂等，重复执行安全
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PROFILE="${1:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <profile>

Profiles:
  yamllint      Sync Python deps from requirements-dev.txt
  ansible-lint  Sync Python deps + Ansible Galaxy collections
  ansible       Sync Python deps + Galaxy collections (syntax-check)
  gitleaks      Install gitleaks CLI to .ci-tools/bin
  all           Python deps + Galaxy + gitleaks

Python packages are pinned in:
  ${CI_REQUIREMENTS_DEV}
Regenerate lock file:
  uv pip compile requirements-dev.in -o requirements-dev.txt --python-version 3.12 --annotation-style line

Example:
  ./scripts/ci/install-deps.sh ansible-lint
EOF
}

# -----------------------------------------------------------------------------
# install_python_deps — 从 requirements-dev.txt 安装锁定版本
# -----------------------------------------------------------------------------
# 优先 uv pip sync；无 uv 时回退 pip install -r
# 本地 Debian（PEP 668）：无激活 venv 时自动创建 .venv 并 sync 进去
# GitHub Actions：setup-python 环境使用 --system
install_python_deps() {
  [[ -f "${CI_REQUIREMENTS_DEV}" ]] || ci_die "missing ${CI_REQUIREMENTS_DEV} (run uv pip compile from requirements-dev.in)"

  local venv_dir="${CI_VENV_DIR:-${CI_REPO_ROOT}/.venv}"

  if command -v uv >/dev/null 2>&1; then
    ci_log "Syncing Python deps with uv from ${CI_REQUIREMENTS_DEV}..."

    local python_bin=""
    if [[ -n "${VIRTUAL_ENV:-}" && -x "${VIRTUAL_ENV}/bin/python" ]]; then
      python_bin="${VIRTUAL_ENV}/bin/python"
    elif [[ -x "${venv_dir}/bin/python" ]]; then
      python_bin="${venv_dir}/bin/python"
    fi

    if [[ -n "${python_bin}" ]]; then
      uv pip sync "${CI_REQUIREMENTS_DEV}" --python "${python_bin}"
    elif [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${UV_SYSTEM_PYTHON:-}" ]]; then
      uv pip sync "${CI_REQUIREMENTS_DEV}" --system
    else
      ci_log "Creating ${venv_dir} (PEP 668: avoid system-wide pip on Debian)..."
      uv venv "${venv_dir}"
      uv pip sync "${CI_REQUIREMENTS_DEV}" --python "${venv_dir}/bin/python"
      ci_log "Hint: source ${venv_dir}/bin/activate before running checks"
    fi
  else
    ci_log "uv not found; falling back to pip install -r ${CI_REQUIREMENTS_DEV}..."
    if [[ -n "${VIRTUAL_ENV:-}" ]] || [[ -d "${venv_dir}" ]]; then
      local py="${VIRTUAL_ENV:+"${VIRTUAL_ENV}/bin/python"}"
      py="${py:-${venv_dir}/bin/python}"
      "${py}" -m pip install --quiet -r "${CI_REQUIREMENTS_DEV}"
    elif [[ -n "${GITHUB_ACTIONS:-}" ]]; then
      python3 -m pip install --quiet -r "${CI_REQUIREMENTS_DEV}"
    else
      ci_log "Creating ${venv_dir} for pip fallback..."
      python3 -m venv "${venv_dir}"
      "${venv_dir}/bin/python" -m pip install --quiet -r "${CI_REQUIREMENTS_DEV}"
      ci_log "Hint: source ${venv_dir}/bin/activate before running checks"
    fi
  fi
}

install_ansible_galaxy() {
  ci_log "Installing Ansible Galaxy collections from ${CI_ANSIBLE_REQUIREMENTS}..."
  ansible-galaxy collection install -r "${CI_ANSIBLE_REQUIREMENTS}" --force-with-deps
}

install_gitleaks() {
  if command -v gitleaks >/dev/null 2>&1; then
    ci_log "gitleaks already in PATH: $(command -v gitleaks)"
    return 0
  fi

  local version="${CI_GITLEAKS_VERSION:-v8.24.2}"
  local ver_no_v="${version#v}"
  local tools_dir="${CI_REPO_ROOT}/.ci-tools/bin"
  local archive="gitleaks_${ver_no_v}_linux_x64.tar.gz"
  local url="https://github.com/gitleaks/gitleaks/releases/download/${version}/${archive}"

  ci_log "Downloading gitleaks ${version} to ${tools_dir}..."
  mkdir -p "${tools_dir}"
  curl -fsSL "${url}" | tar -xz -C "${tools_dir}" gitleaks
  chmod +x "${tools_dir}/gitleaks"

  ci_log "gitleaks installed at ${tools_dir}/gitleaks"
  ci_log "Add to PATH: export PATH=\"${tools_dir}:\$PATH\""
}

case "${PROFILE}" in
  yamllint)
    install_python_deps
    ;;
  ansible-lint)
    install_python_deps
    install_ansible_galaxy
    ;;
  ansible)
    install_python_deps
    install_ansible_galaxy
    ;;
  gitleaks)
    install_gitleaks
    ;;
  all)
    install_python_deps
    install_ansible_galaxy
    install_gitleaks
    ;;
  ""|-h|--help|help)
    usage
    exit 0
    ;;
  *)
    ci_die "unknown profile: ${PROFILE} (run with --help)"
    ;;
esac

ci_log "install-deps (${PROFILE}) OK"
