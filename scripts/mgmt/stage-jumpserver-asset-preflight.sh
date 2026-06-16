#!/usr/bin/env bash
# =============================================================================
# JumpServer 资产纳管启动前预检 — jumpserver-asset-prep.yml
# =============================================================================
#
# 在 ci-01 上、执行 jumpserver-asset-prep 前运行：
#   - inventory 解析与门禁（steady / jumpserver operational / bootstrap）
#   - Hub：vault 可解密、WG 握手
#   - ansible ping、jump_ops 占位用户探测
#   - playbook --syntax-check
#
# Usage:
#   ./scripts/mgmt/stage-jumpserver-asset-preflight.sh
#   ANSIBLE_LIMIT=dev-01 ./scripts/mgmt/stage-jumpserver-asset-preflight.sh
#
# Runbook: docs/jumpserver/asset-prep.runbook.md
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
export ANSIBLE_LIMIT="${LIMIT}"

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

INVENTORY="$(resolve_inventory "${LIMIT}")"
export ANSIBLE_INVENTORY="${INVENTORY}"

# shellcheck source=scripts/dev/lib/inventory-resolve.sh
source "${ROOT}/scripts/dev/lib/inventory-resolve.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Environment:
  ANSIBLE_LIMIT   hub-01 (default) | dev-01 | dev-02

Runbook: docs/jumpserver/asset-prep.runbook.md
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

echo "[stage-jumpserver-asset-preflight] repo: ${ROOT} limit=${LIMIT}"

echo ""
echo "=== 1/7 inventory parse ==="
if [[ "${LIMIT}" == hub-01 ]]; then
  make -C "${ROOT}" inventory-mgmt
else
  make -C "${ROOT}" inventory
fi

echo ""
echo "=== 2/7 inventory gates (ssh steady / jumpserver_asset / bootstrap) ==="
python3 - <<'PY' "${ROOT}" "${LIMIT}" "${INVENTORY}"
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
limit = sys.argv[2]
inventory = Path(sys.argv[3])

def load_dir(inv_dir: Path) -> dict:
    merged: dict = {}
    for pattern in ("group_vars/all/*.yml", "group_vars/jumpserver_assets/*.yml"):
        for f in sorted(inv_dir.glob(pattern)):
            data = yaml.safe_load(f.read_text()) or {}
            if isinstance(data, dict):
                for k, v in data.items():
                    if isinstance(v, dict) and isinstance(merged.get(k), dict):
                        merged[k] = {**merged[k], **v}
                    else:
                        merged[k] = v
    host_vars = inv_dir / "host_vars" / f"{limit}.yml"
    if host_vars.is_file():
        data = yaml.safe_load(host_vars.read_text()) or {}
        if isinstance(data, dict):
            merged.update(data)
    return merged

vars_ = load_dir(inventory)
ssh = {k: vars_.get(k) for k in ("ssh_phase", "ssh_keys_configured", "ssh_inventory_user")}
ja = vars_.get("jumpserver_asset") or {}
jump_ops = ja.get("jump_ops") if isinstance(ja.get("jump_ops"), dict) else {}

checks: list[tuple[bool, str]] = [
    (ssh.get("ssh_phase") == "steady", "ssh_phase=steady"),
    (ssh.get("ssh_keys_configured") is True, "ssh_keys_configured=true"),
    (ssh.get("ssh_inventory_user") == "deploy", "ssh_inventory_user=deploy"),
    (ja.get("enabled") is True, "jumpserver_asset.enabled=true (host in jumpserver_assets)"),
    (jump_ops.get("enabled") is True, "jumpserver_asset.jump_ops.enabled=true"),
]

if limit == "hub-01":
    jms = vars_.get("jumpserver") or {}
    checks.extend([
        (vars_.get("jumpserver_gateway") is True, "jumpserver_gateway=true"),
        (jms.get("status") == "operational", "jumpserver.status=operational"),
    ])

if limit == "dev-02":
    bs = vars_.get("bootstrap_status", "")
    checks.append((bs not in ("pending", "", None), f"bootstrap_status not pending (got {bs!r})"))

failed = [msg for ok, msg in checks if not ok]
if failed:
    print("FAIL:", ", ".join(failed), file=sys.stderr)
    sys.exit(1)
print("OK:", ", ".join(msg for _, msg in checks))
PY

if [[ "${LIMIT}" == hub-01 ]]; then
  echo ""
  echo "=== 3/7 jumpserver vault (mgmt) ==="
  VAULT_FILE="${ROOT}/ansible/inventories/mgmt/group_vars/all/jumpserver_vault.yml"
  if [[ ! -f "${VAULT_FILE}" ]]; then
    echo "ERROR: missing ${VAULT_FILE}" >&2
    exit 1
  fi
  if ! ansible-vault view "${VAULT_FILE}" --vault-password-file "${VAULT_PASS}" >/dev/null 2>&1; then
    echo "ERROR: cannot decrypt jumpserver_vault.yml (check .vault_pass)" >&2
    exit 1
  fi
  echo "OK: jumpserver_vault.yml decrypts"

  echo ""
  echo "=== 4/7 wg-keys verify-hub ==="
  "${ROOT}/scripts/wireguard/wg-keys.sh" verify-hub
else
  echo ""
  echo "=== 3/7 vault / wg skipped (${LIMIT} is dev inventory) ==="
  echo "=== 4/7 wg skipped ==="
fi

if [[ "${LIMIT}" == dev-01 ]]; then
  echo ""
  echo "=== dev-01 / ci-01 提醒 ==="
  cat <<'EOF'
NOTE: dev-01 与 ci-01 为同一台 ECS。
  - JumpServer 只录入 **Dev-01** 一个资产（WG: 10.200.0.2）
  - **不要**再建名为 ci-01 的重复资产
  - CI/Ansible 使用 deploy，永不纳入 JumpServer
EOF
fi

echo ""
echo "=== 5/7 ansible ping ==="
ansible "${LIMIT}" -i "${INVENTORY}" -m ping -o

echo ""
echo "=== 6/7 remote jump_ops placeholder probe ==="
TARGET_IP="$(resolve_ansible_host "${INVENTORY}" "${LIMIT}")"
ssh -i "${PRIVATE_KEY}" \
  -o BatchMode=yes \
  -o ConnectTimeout=15 \
  -o StrictHostKeyChecking=accept-new \
  "deploy@${TARGET_IP}" bash -s <<'REMOTE'
set -euo pipefail
if ! getent passwd jump_ops >/dev/null; then
  echo "ERROR: jump_ops user missing — run bootstrap.yml first" >&2
  exit 1
fi
line="$(getent passwd jump_ops)"
echo "OK: ${line}"
if echo "${line}" | grep -q '/usr/sbin/nologin'; then
  echo "OK: jump_ops still bootstrap placeholder (expected before asset-prep apply)"
elif echo "${line}" | grep -q '/bin/bash'; then
  echo "NOTE: jump_ops already has /bin/bash — asset-prep apply should be idempotent"
else
  echo "WARN: unexpected jump_ops shell"
fi
REMOTE

echo ""
echo "=== 7/7 jumpserver-asset-prep.yml --syntax-check ==="
ansible-playbook "${PLAYBOOK}" -i "${INVENTORY}" --limit "${LIMIT}" --syntax-check

cat <<EOF

Next:
  make jumpserver-asset-prep LIMIT=${LIMIT}
  # 或
  ./scripts/mgmt/jumpserver-asset-prep.sh apply ${LIMIT}
  ./scripts/mgmt/verify-jumpserver-asset-remote.sh ${LIMIT}

Then JumpServer UI: 资产 → linux-jump-ops 模板 → 账号推送 → 测试连接

EOF

echo "[stage-jumpserver-asset-preflight] OK"
