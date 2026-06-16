#!/usr/bin/env bash
# =============================================================================
# Dev 阶段 3 预检 — 占位 API（dev-app.yml）
# =============================================================================
#
# 【用法】
#   ./scripts/dev/stage-dev-app-preflight.sh
#   make stage-dev-app-preflight
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIMIT="${ANSIBLE_LIMIT:-dev-01}"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"
DEV_INVENTORY="${ROOT}/ansible/inventories/dev/"

export ANSIBLE_PRIVATE_KEY_FILE="${PRIVATE_KEY}"
export ANSIBLE_INVENTORY="${DEV_INVENTORY}"
export ANSIBLE_LIMIT="${LIMIT}"

echo "[stage-dev-app-preflight] repo: ${ROOT}"

echo ""
echo "=== 1/4 make inventory ==="
make -C "${ROOT}" inventory

echo ""
echo "=== 2/4 inventory gates (app / ssh / docker) ==="
python3 - <<'PY' "${ROOT}"
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
inv = root / "ansible/inventories/dev/group_vars/all"

def load(name: str) -> dict:
    with (inv / name).open(encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}

app = load("app.yml").get("app", {})
ssh = load("ssh.yml")
bootstrap = load("bootstrap.yml")

assert app.get("deploy_status") in {"placeholder", "operational"}, app.get("deploy_status")
assert ssh.get("ssh_phase") == "steady", ssh.get("ssh_phase")
assert bootstrap.get("docker_install") is True, bootstrap.get("docker_install")
print("OK: app.deploy_status, ssh_phase=steady, docker_install=true")
PY

echo ""
echo "=== 3/4 ansible-playbook dev-app.yml --syntax-check ==="
ansible-playbook "${ROOT}/ansible/playbooks/dev-app.yml" \
  -i "${DEV_INVENTORY}" \
  --limit "${LIMIT}" \
  --syntax-check

echo ""
echo "=== 4/4 deploy sudo probe (optional) ==="
if [[ -f "${PRIVATE_KEY}" ]]; then
  ansible "${LIMIT}" -i "${DEV_INVENTORY}" -m command -a "sudo -n true" -b || {
    echo "WARN: deploy passwordless sudo missing — re-run bootstrap users on dev-01:"
    echo "  ansible-playbook ansible/playbooks/bootstrap.yml -i ansible/inventories/dev/ --limit dev-01 --tags sudo"
    exit 1
  }
  echo "OK: deploy passwordless sudo"
else
  echo "SKIP: private key not found at ${PRIVATE_KEY}"
fi

echo ""
echo "[stage-dev-app-preflight] OK — next: ansible-playbook ansible/playbooks/dev-app.yml -i ansible/inventories/dev/ --limit ${LIMIT}"
