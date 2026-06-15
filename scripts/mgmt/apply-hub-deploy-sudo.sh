#!/usr/bin/env bash
# =============================================================================
# Hub deploy 免密 sudo 一次性修复 / 幂等同步（阶段 F 前置）
# =============================================================================
#
# 【背景】
#   wireguard-hub.yml 使用 become: true，要求 deploy@hub-01 能 sudo -n。
#   mgmt/bootstrap.yml 中 sudo_mgmt: true 由 common/users.yml 写入
#   /etc/sudoers.d/deploy；若 Hub 已在 steady 且无 sudo，Ansible 无法自举。
#
# 【注意】
#   本脚本始终使用 mgmt inventory，不继承 shell 中的 ANSIBLE_INVENTORY。
#
# 【用法】
#   ./scripts/mgmt/apply-hub-deploy-sudo.sh              # 检测 + 尝试 Ansible
#   ./scripts/mgmt/apply-hub-deploy-sudo.sh --console    # 仅打印阿里云工作台命令
#
# 【执行位置】
#   ci-01（yax）deploy 用户，仓库 ~/infra-ops
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MGMT_INVENTORY="${ROOT}/ansible/inventories/mgmt/"
LIMIT="${ANSIBLE_LIMIT:-hub-01}"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"
PLAYBOOK="${ROOT}/ansible/playbooks/bootstrap.yml"

CONSOLE_ONLY=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --console    仅输出阿里云 ECS 工作台（root）一次性命令，不跑 Ansible
  -h, --help   显示帮助

After deploy has NOPASSWD sudo:
  ansible-playbook ansible/playbooks/wireguard-hub.yml \\
    -i ansible/inventories/mgmt/ --limit hub-01 \\
    --vault-password-file .vault_pass --check --diff
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --console) CONSOLE_ONLY=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# shellcheck source=scripts/dev/lib/inventory-resolve.sh
source "${ROOT}/scripts/dev/lib/inventory-resolve.sh"

export ANSIBLE_INVENTORY="${MGMT_INVENTORY}"
export ANSIBLE_LIMIT="$LIMIT"
export ANSIBLE_PRIVATE_KEY_FILE="$PRIVATE_KEY"

# mgmt inventory 含 wireguard_vault.yml（ansible-vault 加密）；未设置则无法渲染 ansible_host
if [[ -z "${ANSIBLE_VAULT_PASSWORD_FILE:-}" && -f "${ROOT}/.vault_pass" ]]; then
  export ANSIBLE_VAULT_PASSWORD_FILE="${ROOT}/.vault_pass"
fi

# 控制台指引用；inventory 解析失败时回退 Hub 私网（与 network.yml 一致）
HUB_HOST_FALLBACK="172.21.127.123"

resolve_hub_host() {
  local host
  if host="$(resolve_ansible_host "${MGMT_INVENTORY}" "${LIMIT}" 2>/dev/null)" && [[ -n "$host" ]]; then
    printf '%s' "$host"
    return 0
  fi
  if [[ -n "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ]]; then
    echo "ERROR: cannot resolve ansible_host for ${LIMIT} (inventory: ${MGMT_INVENTORY})" >&2
    echo "       Run: ansible localhost -i ${MGMT_INVENTORY} -m debug -a \"var=hostvars['${LIMIT}'].ansible_host\" -e ansible_connection=local" >&2
    return 1
  fi
  echo "WARN: set ANSIBLE_VAULT_PASSWORD_FILE or ${ROOT}/.vault_pass for inventory resolve; using ${HUB_HOST_FALLBACK}" >&2
  printf '%s' "$HUB_HOST_FALLBACK"
}

print_console_instructions() {
  cat <<EOF

================================================================================
Hub deploy 尚无免密 sudo — 请用阿里云 ECS「远程连接 / 工作台」以 root 执行一次：
================================================================================

tee /etc/sudoers.d/deploy > /dev/null <<'SUDOERS_EOF'
# Managed by Ansible infra-ops — mgmt Hub deploy passwordless sudo
deploy ALL=(ALL) NOPASSWD: ALL
SUDOERS_EOF
chmod 440 /etc/sudoers.d/deploy
visudo -cf /etc/sudoers.d/deploy && echo "OK: deploy NOPASSWD sudo"

然后在 ci-01 验证：

  ssh -i ${PRIVATE_KEY} deploy@${hub_host} 'sudo -n id -u'

成功后重跑：

  ./scripts/mgmt/apply-hub-deploy-sudo.sh
  ansible-playbook ansible/playbooks/wireguard-hub.yml \\
    -i ansible/inventories/mgmt/ --limit hub-01 \\
    --vault-password-file .vault_pass --check --diff

================================================================================
EOF
}

if [[ "$CONSOLE_ONLY" == "true" ]]; then
  hub_host="$(resolve_hub_host)"
  print_console_instructions
  exit 0
fi

hub_host="$(resolve_hub_host)"

echo "[apply-hub-deploy-sudo] target: deploy@${hub_host} (limit=${LIMIT})"

if ssh -i "$PRIVATE_KEY" -o BatchMode=yes -o ConnectTimeout=10 \
  "deploy@${hub_host}" 'sudo -n true' 2>/dev/null; then
  echo "[apply-hub-deploy-sudo] deploy already has passwordless sudo"
else
  echo "[apply-hub-deploy-sudo] deploy cannot sudo -n (expected before fix)"
  print_console_instructions
  echo "[apply-hub-deploy-sudo] After console fix, re-run: $(basename "$0")"
  exit 1
fi

echo "[apply-hub-deploy-sudo] Applying sudo_mgmt via Ansible (idempotent)..."
ansible-playbook "$PLAYBOOK" \
  -i "${MGMT_INVENTORY}" \
  --limit "$LIMIT" \
  --tags sudo_mgmt \
  ${ANSIBLE_VAULT_PASSWORD_FILE:+--vault-password-file "$ANSIBLE_VAULT_PASSWORD_FILE"}

echo "[apply-hub-deploy-sudo] OK — you can run wireguard-hub.yml"
