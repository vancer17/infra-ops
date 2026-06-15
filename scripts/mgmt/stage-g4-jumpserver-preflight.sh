#!/usr/bin/env bash
# =============================================================================
# 阶段 G4 启动前预检 — Hub JumpServer Compose（hub-g4-jumpserver.yml）
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MGMT_INVENTORY="${ROOT}/ansible/inventories/mgmt/"
VAULT_FILE="${ROOT}/ansible/inventories/mgmt/group_vars/all/jumpserver_vault.yml"
LIMIT="${ANSIBLE_LIMIT:-hub-01}"

export ANSIBLE_VAULT_PASSWORD_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-${ROOT}/.vault_pass}"
export ANSIBLE_PRIVATE_KEY_FILE="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"
export ANSIBLE_INVENTORY="${MGMT_INVENTORY}"
export ANSIBLE_LIMIT="${LIMIT}"

echo "[stage-g4-jumpserver-preflight] repo: ${ROOT}"

echo ""
echo "=== 1/5 make inventory-mgmt ==="
make -C "${ROOT}" inventory-mgmt

echo ""
echo "=== 2/5 jumpserver vault ==="
if [[ ! -f "${VAULT_FILE}" ]]; then
  echo "ERROR: missing ${VAULT_FILE}"
  echo "Run: ./scripts/mgmt/jumpserver-vault-init.sh"
  exit 1
fi
if ! ansible-vault view "${VAULT_FILE}" --vault-password-file "${ANSIBLE_VAULT_PASSWORD_FILE}" >/dev/null 2>&1; then
  echo "ERROR: cannot decrypt jumpserver_vault.yml (check .vault_pass)"
  exit 1
fi
echo "OK: jumpserver_vault.yml decrypts"

echo ""
echo "=== 3/5 wg-keys verify-hub ==="
"${ROOT}/scripts/wireguard/wg-keys.sh" verify-hub

echo ""
echo "=== 4/5 Hub Docker remote verify ==="
"${ROOT}/scripts/mgmt/verify-hub-docker-remote.sh"

echo ""
echo "=== 5/5 manual reminders ==="
cat <<EOF

Before hub-g4-jumpserver.yml apply:
  [ ] Hub has RAM/disk headroom (jms_all ~1GB image + DB volume)
  [ ] jumpserver.image_tag matches desired JumpServer version
  [ ] First start may take 3–6 minutes (DB init)

Apply:
  ansible-playbook ansible/playbooks/hub-g4-jumpserver.yml \\
    -i ansible/inventories/mgmt/ --limit hub-01 \\
    --vault-password-file .vault_pass

After apply:
  [ ] ./scripts/mgmt/verify-hub-jumpserver-remote.sh
  [ ] Update jumpserver.status=operational, nginx.jumpserver.deploy_status=ready
  [ ] Change default admin password (ChangeMe)

EOF

echo "[stage-g4-jumpserver-preflight] OK"
