#!/usr/bin/env bash
# =============================================================================
# 远程验收 — JumpServer 资产纳管 Ansible 准备（jump_ops / sshd）
# =============================================================================
#
# 在 ci-01 控制机执行。
#   - deploy@ 可读：getent、world-readable 的 sshd drop-in
#   - jump_ops home/.ssh、sudoers：0750/0700/0440，须 ansible -b（与 asset-prep verify 一致）
#
# JumpServer「测试连接」须在控制台账号推送后另行验收。
#
# Usage:
#   ./scripts/mgmt/verify-jumpserver-asset-remote.sh hub-01
#   ./scripts/mgmt/verify-jumpserver-asset-remote.sh dev-01
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIMIT="${1:-${ANSIBLE_LIMIT:-hub-01}}"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"
VAULT_PASS="${ANSIBLE_VAULT_PASSWORD_FILE:-${ROOT}/.vault_pass}"

resolve_inventory() {
  case "$1" in
    hub-01) echo "${ROOT}/ansible/inventories/mgmt/" ;;
    dev-01|dev-02) echo "${ROOT}/ansible/inventories/dev/" ;;
    *)
      echo "ERROR: unknown host ${1}; use hub-01, dev-01, or dev-02" >&2
      exit 1
      ;;
  esac
}

INVENTORY="$(resolve_inventory "$LIMIT")"
export ANSIBLE_INVENTORY="${INVENTORY}"
export ANSIBLE_LIMIT="${LIMIT}"
export ANSIBLE_PRIVATE_KEY_FILE="${PRIVATE_KEY}"
export ANSIBLE_VAULT_PASSWORD_FILE="${VAULT_PASS}"

# shellcheck source=scripts/dev/lib/inventory-resolve.sh
source "${ROOT}/scripts/dev/lib/inventory-resolve.sh"

command -v ansible >/dev/null || {
  echo "ERROR: ansible not found; run: make setup" >&2
  exit 1
}

TARGET_HOST="$(resolve_ansible_host)"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)

echo "[verify-jumpserver-asset] SSH deploy@${TARGET_HOST} (limit=${LIMIT})"

remote() {
  ssh "${SSH_OPTS[@]}" -i "${PRIVATE_KEY}" "deploy@${TARGET_HOST}" "$@"
}

ansible_become() {
  ansible "$LIMIT" -i "$INVENTORY" -b "$@"
}

echo "=== getent passwd jump_ops ==="
PASSWD_LINE="$(remote 'getent passwd jump_ops')"
printf '%s\n' "${PASSWD_LINE}"
if [[ "${PASSWD_LINE}" != *"/bin/bash" ]]; then
  echo "ERROR: jump_ops shell is not /bin/bash" >&2
  exit 1
fi

echo "=== .ssh directory (ansible -b; deploy 无权读 /home/jump_ops 0750) ==="
ansible_become -m ansible.builtin.shell -o \
  -a "mode=\$(stat -c '%a' /home/jump_ops/.ssh); stat -c '%a %U:%G %n' /home/jump_ops/.ssh; test \"\${mode}\" = 700"
echo "OK: .ssh mode 700"

echo "=== sshd AllowUsers (steady + jump_ops) ==="
remote "grep -E '^AllowUsers ' /etc/ssh/sshd_config.d/99-dev-bootstrap.conf"
remote "grep -E '^AllowUsers .*\bjump_ops\b' /etc/ssh/sshd_config.d/99-dev-bootstrap.conf"

echo "=== sudoers jump_ops (ansible -b; file mode 0440) ==="
ansible_become -m ansible.builtin.shell -o \
  -a 'test -f /etc/sudoers.d/jump_ops && head -n 5 /etc/sudoers.d/jump_ops || echo "(no sudoers file)"'

echo "verify-jumpserver-asset-remote OK"
echo "[verify-jumpserver-asset] Next: JumpServer UI → 资产 → 账号推送 → 测试连接"
