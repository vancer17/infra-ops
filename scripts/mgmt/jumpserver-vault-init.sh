#!/usr/bin/env bash
# =============================================================================
# 生成 JumpServer Vault 密钥并加密 jumpserver_vault.yml
# =============================================================================
#
# 【用途】
#   为 jms_all 生成 SECRET_KEY / BOOTSTRAP_TOKEN，写入 ansible-vault 加密文件。
#
# 【用法】
#   ./scripts/mgmt/jumpserver-vault-init.sh
#   ./scripts/mgmt/jumpserver-vault-init.sh --force   # 覆盖已有 vault 文件
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VAULT_FILE="${ROOT}/ansible/inventories/mgmt/group_vars/all/jumpserver_vault.yml"
VAULT_PASS="${ROOT}/.vault_pass"
FORCE=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--force]

  --force   Overwrite existing jumpserver_vault.yml

Requires: openssl, python3, ansible-vault (make setup)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

command -v openssl >/dev/null || { echo "ERROR: openssl required"; exit 1; }
command -v ansible-vault >/dev/null || { echo "ERROR: ansible-vault required (make setup)"; exit 1; }

if [[ -f "${VAULT_FILE}" && "${FORCE}" != "true" ]]; then
  echo "ERROR: ${VAULT_FILE} exists; use --force to regenerate"
  exit 1
fi

if [[ ! -f "${VAULT_PASS}" ]]; then
  echo "ERROR: missing ${VAULT_PASS}; create vault password first (see wg-keys runbook)"
  exit 1
fi

SECRET_KEY="$(openssl rand -base64 48 | tr -d '/+=' | head -c 50)"
BOOTSTRAP_TOKEN="$(openssl rand -base64 32 | tr -d '/+=' | head -c 24)"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' RETURN

cat >"${tmp}" <<EOF
# Ansible Vault: JumpServer secrets (encrypted on write)
jumpserver_vault:
  secret_key: "${SECRET_KEY}"
  bootstrap_token: "${BOOTSTRAP_TOKEN}"
  key_version: 1
  generated_by: jumpserver-vault-init.sh
EOF

ansible-vault encrypt "${tmp}" --vault-password-file "${VAULT_PASS}" --output "${VAULT_FILE}"

echo "[jumpserver-vault-init] wrote encrypted ${VAULT_FILE}"
echo "[jumpserver-vault-init] view: ansible-vault view ${VAULT_FILE#${ROOT}/} --vault-password-file .vault_pass"
echo "[jumpserver-vault-init] NEVER commit .vault_pass or plaintext secrets"
