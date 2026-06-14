#!/usr/bin/env bash
# =============================================================================
# ci-01 控制面环境配置（阶段 C 完成后 → 阶段 E 前）
# =============================================================================
#
# 【用途】
#   在 yax（ci-01 / dev-01 同机）上修正交叉检查报告中的黄灯项：
#     1. ANSIBLE_PRIVATE_KEY_FILE 从 hub-root 改为 infra-ci-deploy
#     2. 验证 Ansible 以 deploy 用户连通 hub-01 / 本机
#     3. 检查或安装 wireguard-tools（阶段 E 依赖）
#
# 【执行位置】
#   仅在本机 ci-01 上以 deploy 用户运行（勿在笔记本跑 apply-bashrc）。
#
# 【用法】
#   chmod +x scripts/dev/setup-control-plane-env.sh
#   ./scripts/dev/setup-control-plane-env.sh all
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRIVATE_KEY="${ROOT}/ansible/keys/infra-ci-deploy"
MGMT_INV="${ROOT}/ansible/inventories/mgmt/"
DEV_INV="${ROOT}/ansible/inventories/dev/"
BASHRC="${HOME}/.bashrc"
MARKER_BEGIN="# >>> infra-ops control-plane >>>"
MARKER_END="# <<< infra-ops control-plane <<<"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  apply-bashrc       写入/更新 ~/.bashrc 中 infra-ops 控制面块（deploy 密钥）
  verify-ansible     ansible ping hub-01（mgmt）与本机 dev-01（dev inventory）
  check-wireguard    检查 wg 命令；缺失时提示 apt install
  install-wireguard  sudo apt install wireguard-tools（需交互确认）
  all                apply-bashrc → verify-ansible → check-wireguard

After all:
  source ~/.bashrc
  make -C ${ROOT} inventory-mgmt
EOF
}

write_bashrc_block() {
  local block
  block=$(cat <<'EOF'
# >>> infra-ops control-plane >>>
# 由 scripts/dev/setup-control-plane-env.sh 维护；勿手工改 ANSIBLE_PRIVATE_KEY_FILE 为 hub-root
INFRA_OPS_ROOT="${HOME}/infra-ops"

if [ -d "${INFRA_OPS_ROOT}/.venv/bin" ]; then
  export PATH="${INFRA_OPS_ROOT}/.venv/bin:${PATH}"
fi

export ANSIBLE_INVENTORY="${INFRA_OPS_ROOT}/ansible/inventories/mgmt/"
export ANSIBLE_PRIVATE_KEY_FILE="${INFRA_OPS_ROOT}/ansible/keys/infra-ci-deploy"

_infra_ops_auto_venv() {
  if [ -d "${INFRA_OPS_ROOT}/.venv" ]; then
    case "${PWD}/" in
      "${INFRA_OPS_ROOT}"/*)
        if [ -z "${VIRTUAL_ENV:-}" ]; then
          # shellcheck source=/dev/null
          source "${INFRA_OPS_ROOT}/.venv/bin/activate"
        fi
        ;;
      *)
        if [ -n "${VIRTUAL_ENV:-}" ] && [ "${VIRTUAL_ENV}" = "${INFRA_OPS_ROOT}/.venv" ]; then
          deactivate 2>/dev/null || true
        fi
        ;;
    esac
  fi
}

if [ -n "${PROMPT_COMMAND:-}" ]; then
  case "${PROMPT_COMMAND}" in
    *_infra_ops_auto_venv*) ;;
    *) PROMPT_COMMAND="_infra_ops_auto_venv; ${PROMPT_COMMAND}" ;;
  esac
else
  PROMPT_COMMAND="_infra_ops_auto_venv"
fi

if [[ "${PWD}" == "${INFRA_OPS_ROOT}"* ]]; then
  _infra_ops_auto_venv
fi

alias infra='cd "${INFRA_OPS_ROOT}"'
alias inv-mgmt='make -C "${INFRA_OPS_ROOT}" inventory-mgmt'
alias inv-dev='make -C "${INFRA_OPS_ROOT}" inventory'
# <<< infra-ops control-plane <<<
EOF
)

  if [[ ! -f "$BASHRC" ]]; then
    touch "$BASHRC"
  fi

  if grep -qF "$MARKER_BEGIN" "$BASHRC" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
      index($0, begin) { skip = 1; next }
      index($0, end) { skip = 0; next }
      skip == 0 { print }
    ' "$BASHRC" >"$tmp"
    mv "$tmp" "$BASHRC"
  fi

  # 删除可能残留的旧版独立块（2026-06-14 手动追加、含 hub-root 的行）
  if grep -q 'ANSIBLE_PRIVATE_KEY_FILE.*hub-root' "$BASHRC" 2>/dev/null; then
    sed -i '/ANSIBLE_PRIVATE_KEY_FILE.*hub-root/d' "$BASHRC"
    sed -i '/# Hub Bootstrap：Ansible 连 Hub 的 root 密钥/d' "$BASHRC"
    sed -i '/# infra-ops 控制面（yax \/ ci-01）/d' "$BASHRC"
  fi

  printf '\n%s\n' "$block" >>"$BASHRC"
  echo "Updated ${BASHRC} (${MARKER_BEGIN} block)"
  echo "Run: source ~/.bashrc"
}

cmd_apply_bashrc() {
  write_bashrc_block
}

cmd_verify_ansible() {
  [[ -f "$PRIVATE_KEY" ]] || {
    echo "ERROR: missing ${PRIVATE_KEY}; run: scripts/dev/ssh-keys.sh generate" >&2
    exit 1
  }
  export ANSIBLE_PRIVATE_KEY_FILE="$PRIVATE_KEY"
  command -v ansible >/dev/null || {
    echo "ERROR: ansible not found; run: make setup" >&2
    exit 1
  }

  echo "=== hub-01 (mgmt, deploy) ==="
  ANSIBLE_INVENTORY="$MGMT_INV" ansible hub-01 -i "$MGMT_INV" -m ping -u deploy

  echo "=== dev-01 (dev, deploy, colocated → local) ==="
  ANSIBLE_INVENTORY="$DEV_INV" ansible dev-01 -i "$DEV_INV" -m ping -u deploy \
    -e ansible_connection=local

  echo "verify-ansible OK"
}

cmd_check_wireguard() {
  if command -v wg >/dev/null 2>&1; then
    echo "wireguard-tools: OK ($(wg --version 2>/dev/null || wg -v))"
    return 0
  fi
  echo "WARN: wg not found — stage E requires: sudo apt install -y wireguard-tools"
  return 1
}

cmd_install_wireguard() {
  if command -v wg >/dev/null 2>&1; then
    echo "wireguard-tools already installed"
    return 0
  fi
  echo "Installing wireguard-tools (requires sudo)..."
  sudo apt update
  sudo apt install -y wireguard-tools
  wg --version
}

cmd_all() {
  cmd_apply_bashrc
  echo ""
  export ANSIBLE_PRIVATE_KEY_FILE="$PRIVATE_KEY"
  cmd_verify_ansible
  echo ""
  cmd_check_wireguard || true
  echo ""
  echo "Next:"
  echo "  source ~/.bashrc"
  echo "  make -C ${ROOT} inventory-mgmt"
  echo "  ./scripts/wireguard/wg-keys.sh check-deps"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    apply-bashrc) cmd_apply_bashrc ;;
    verify-ansible) cmd_verify_ansible ;;
    check-wireguard) cmd_check_wireguard ;;
    install-wireguard) cmd_install_wireguard ;;
    all) cmd_all ;;
    -h | --help | help) usage ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
