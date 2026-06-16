#!/usr/bin/env bash
# =============================================================================
# JumpServer 资产纳管 — Ansible 准备 jump_ops（系统用户侧）
# =============================================================================
#
# 封装 jumpserver-asset-prep.yml；在 ci-01 控制机执行。
#
# Usage:
#   ./scripts/mgmt/jumpserver-asset-prep.sh preflight [hub-01|dev-01|dev-02]
#   ./scripts/mgmt/jumpserver-asset-prep.sh apply [host]
#   ./scripts/mgmt/jumpserver-asset-prep.sh verify [host]
#   ./scripts/mgmt/jumpserver-asset-prep.sh all hub-01
#
# Environment:
#   ANSIBLE_INVENTORY  默认按 host 自动选择 mgmt 或 dev
#   ANSIBLE_LIMIT      同命令行 host 参数
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLAYBOOK="${ROOT}/ansible/playbooks/jumpserver-asset-prep.yml"
LIMIT="${ANSIBLE_LIMIT:-hub-01}"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"
VAULT_PASS="${ANSIBLE_VAULT_PASSWORD_FILE:-${ROOT}/.vault_pass}"

export ANSIBLE_PRIVATE_KEY_FILE="${PRIVATE_KEY}"
export ANSIBLE_VAULT_PASSWORD_FILE="${VAULT_PASS}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <preflight|apply|verify|all> [host]

  preflight  调用 stage-jumpserver-asset-preflight.sh（完整门禁）
  apply      执行 jumpserver-asset-prep.yml
  verify     apply 后远程验收 jump_ops / sshd
  all        preflight → apply → verify

Hosts:
  hub-01   → ansible/inventories/mgmt/
  dev-01, dev-02 → ansible/inventories/dev/

Examples:
  $(basename "$0") all hub-01
  $(basename "$0") apply dev-01
EOF
}

resolve_inventory() {
  local host="$1"
  case "$host" in
    hub-01) echo "${ROOT}/ansible/inventories/mgmt/" ;;
    dev-01|dev-02) echo "${ROOT}/ansible/inventories/dev/" ;;
    *)
      echo "ERROR: unknown host ${host}; use hub-01, dev-01, or dev-02" >&2
      exit 1
      ;;
  esac
}

cmd_preflight() {
  local host="$1"
  export ANSIBLE_LIMIT="$host"
  bash "${ROOT}/scripts/mgmt/stage-jumpserver-asset-preflight.sh"
}

cmd_apply() {
  local host="$1"
  shift
  local inv
  inv="$(resolve_inventory "$host")"
  export ANSIBLE_INVENTORY="$inv"

  ansible-galaxy collection install -r "${ROOT}/ansible/requirements.yml" --force-with-deps 2>/dev/null || true

  ansible-playbook "$PLAYBOOK" -i "$inv" --limit "$host" "$@"
  echo "apply OK (limit=${host})"
}

cmd_verify() {
  local host="$1"
  local inv
  inv="$(resolve_inventory "$host")"

  ansible "$host" -i "$inv" -m ansible.builtin.command -a "getent passwd jump_ops" -b
  ansible "$host" -i "$inv" -m ansible.builtin.shell \
    -a "grep -E '^AllowUsers .*\bjump_ops\b' /etc/ssh/sshd_config.d/99-dev-bootstrap.conf" -b
  ansible "$host" -i "$inv" -m ansible.builtin.stat -a "path=/home/jump_ops/.ssh" -b

  echo "verify OK (limit=${host})"
  echo "Next in JumpServer UI:"
  echo "  1. 创建节点 ${host%%-*}/..."
  echo "  2. 资产使用 host_vars jumpserver_asset_console 中的 address"
  echo "  3. 从模板添加账户 linux-jump-ops → 账号推送 → 测试连接"
}

cmd_all() {
  cmd_preflight "$1"
  cmd_apply "$1"
  cmd_verify "$1"
}

main() {
  local cmd="${1:-}"
  shift || true
  if [[ -n "${1:-}" ]]; then
    LIMIT="$1"
    shift
  fi

  case "$cmd" in
    preflight) cmd_preflight "$LIMIT" ;;
    apply) cmd_apply "$LIMIT" "$@" ;;
    verify) cmd_verify "$LIMIT" ;;
    all) cmd_all "$LIMIT" ;;
    -h|--help|help) usage ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
