#!/usr/bin/env bash
# =============================================================================
# 远程验收 — Hub JumpServer + Nginx jms.internal
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MGMT_INVENTORY="${ROOT}/ansible/inventories/mgmt/"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"
LIMIT="${ANSIBLE_LIMIT:-hub-01}"

export ANSIBLE_INVENTORY="${MGMT_INVENTORY}"
export ANSIBLE_LIMIT="${LIMIT}"
export ANSIBLE_PRIVATE_KEY_FILE="${PRIVATE_KEY}"

# shellcheck source=scripts/dev/lib/inventory-resolve.sh
source "${ROOT}/scripts/dev/lib/inventory-resolve.sh"

HUB_HOST="$(resolve_ansible_host)"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)

echo "[verify-hub-jumpserver] SSH deploy@${HUB_HOST} (limit=${LIMIT})"

remote() {
  ssh "${SSH_OPTS[@]}" -i "${PRIVATE_KEY}" "deploy@${HUB_HOST}" "$@"
}

echo "=== docker compose ps ==="
remote 'cd /opt/mgmt/jumpserver && docker compose ps'

echo "=== loopback HTTP 8080 ==="
remote 'curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/'

echo "=== nginx jms.local HTTPS (Host: jms.internal) ==="
remote 'curl -k -s -o /dev/null -w "%{http_code}\n" -H "Host: jms.internal" https://127.0.0.1/'

echo "=== /jms/status JSON ==="
STATUS_JSON="$(remote 'curl -k -s -H "Host: jms.internal" https://127.0.0.1/jms/status')"
printf '%s\n' "${STATUS_JSON}" | head -c 400
echo ""

echo "=== assert deploy_status=ready ==="
DEPLOY_STATUS="$(printf '%s' "${STATUS_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('deploy_status',''))")"
if [[ "${DEPLOY_STATUS}" != "ready" ]]; then
  echo "ERROR: /jms/status deploy_status=${DEPLOY_STATUS:-<unset>}, expected ready" >&2
  exit 1
fi
echo "OK: deploy_status=ready"

echo "verify-hub-jumpserver-remote OK"
echo "[verify-hub-jumpserver] From ci-01 also run:"
echo "  curl -k -s https://jms.internal/jms/status | python3 -m json.tool"
echo "  curl -k -o /dev/null -w '%{http_code}\n' https://jms.internal/"
