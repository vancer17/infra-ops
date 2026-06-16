#!/usr/bin/env bash
# =============================================================================
# Dev 阶段 3 预检 — 业务 Nginx（nginx-dev.yml）
# =============================================================================
#
# 【用法】
#   ./scripts/dev/stage-dev-nginx-preflight.sh
#   make stage-dev-nginx-preflight
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

echo "[stage-dev-nginx-preflight] repo: ${ROOT}"

echo ""
echo "=== 1/5 make inventory ==="
make -C "${ROOT}" inventory

echo ""
echo "=== 2/5 inventory gates (nginx / app ports) ==="
python3 - <<'PY' "${ROOT}"
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
inv = root / "ansible/inventories/dev/group_vars/all"

def load(name: str) -> dict:
    with (inv / name).open(encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}

nginx = load("nginx.yml").get("nginx", {})
app = load("app.yml").get("app", {})

assert nginx.get("gateway_mode") == "app", nginx.get("gateway_mode")
assert nginx.get("upstream", {}).get("port") == app.get("listen", {}).get("port"), (
    nginx.get("upstream", {}).get("port"),
    app.get("listen", {}).get("port"),
)
print("OK: nginx.gateway_mode=app, upstream port matches app.listen.port")
PY

echo ""
echo "=== 3/5 ansible-playbook nginx-dev.yml --syntax-check ==="
ansible-playbook "${ROOT}/ansible/playbooks/nginx-dev.yml" \
  -i "${DEV_INVENTORY}" \
  --limit "${LIMIT}" \
  --syntax-check

echo ""
echo "=== 4/5 optional upstream probe on dev-01 ==="
if [[ -f "${PRIVATE_KEY}" ]]; then
  ansible "${LIMIT}" -i "${DEV_INVENTORY}" -m uri -a "url=http://127.0.0.1:8080/ return_content=no" || {
    echo "WARN: placeholder API not listening on 127.0.0.1:8080 — run dev-app.yml first for full proxy test"
  }
else
  echo "SKIP: private key not found at ${PRIVATE_KEY}"
fi

echo ""
echo "=== 5/5 deploy sudo probe ==="
if [[ -f "${PRIVATE_KEY}" ]]; then
  ansible "${LIMIT}" -i "${DEV_INVENTORY}" -m command -a "sudo -n true" -b || {
    echo "ERROR: deploy passwordless sudo required for nginx-dev.yml"
    exit 1
  }
  echo "OK: deploy passwordless sudo"
fi

echo ""
echo "[stage-dev-nginx-preflight] OK — next: ansible-playbook ansible/playbooks/nginx-dev.yml -i ansible/inventories/dev/ --limit ${LIMIT}"
