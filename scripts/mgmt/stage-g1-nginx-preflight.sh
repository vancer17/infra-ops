#!/usr/bin/env bash
# =============================================================================
# 阶段 G1 启动前预检 — Hub 宿主机 Nginx（nginx-hub.yml）
# =============================================================================
#
# 【用途】
#   在 ci-01 上、执行 nginx-hub.yml 前运行：
#     - make inventory-mgmt
#     - wireguard / ssh / nginx_gateway 门禁（inventory）
#     - deploy@hub-01 免密 sudo 探测
#     - 可选：从 WG 探测 Hub 443（部署前应为 refused）
#
# 【注意】
#   本脚本始终使用 mgmt inventory，不继承 shell 中的 ANSIBLE_INVENTORY（ci-01 上常为 dev/）。
#
# 【用法】
#   ./scripts/mgmt/stage-g1-nginx-preflight.sh
#   ./scripts/mgmt/stage-g1-nginx-preflight.sh --probe-443
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_443=false
HUB_WG="${HUB_WG:-10.200.0.1}"
# Hub 操作固定 mgmt inventory；勿用 ${ANSIBLE_INVENTORY:-...}（ci-01 上常为 dev/）
MGMT_INVENTORY="${ROOT}/ansible/inventories/mgmt/"
LIMIT="${ANSIBLE_LIMIT:-hub-01}"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --probe-443   从本机 nc 探测 Hub \${HUB_WG} TCP 443（部署前通常为 refused）
  -h, --help    显示帮助

Runbook: docs/nginx/hub-nginx.runbook.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe-443) PROBE_443=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

export ANSIBLE_VAULT_PASSWORD_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-${ROOT}/.vault_pass}"
export ANSIBLE_PRIVATE_KEY_FILE="${PRIVATE_KEY}"
export ANSIBLE_INVENTORY="${MGMT_INVENTORY}"
export ANSIBLE_LIMIT="${LIMIT}"

# shellcheck source=scripts/dev/lib/inventory-resolve.sh
source "${ROOT}/scripts/dev/lib/inventory-resolve.sh"

echo "[stage-g1-nginx-preflight] repo: ${ROOT}"

echo ""
echo "=== 1/6 make inventory-mgmt ==="
make -C "${ROOT}" inventory-mgmt

echo ""
echo "=== 2/6 inventory gates (wireguard / ssh / nginx_gateway) ==="
python3 - <<'PY' "${ROOT}"
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
mgmt = root / "ansible/inventories/mgmt"

wg = yaml.safe_load((mgmt / "group_vars/all/wireguard.yml").read_text()) or {}
wg_cfg = wg.get("wireguard", {})
wg_status = wg_cfg.get("status")
wg_enabled = wg_cfg.get("enabled")
print(f"wireguard.enabled={wg_enabled} status={wg_status}")
if wg_status != "operational" or not wg_enabled:
    raise SystemExit("ERROR: wireguard must be enabled=true and status=operational before nginx-hub")

ssh = yaml.safe_load((mgmt / "group_vars/all/ssh.yml").read_text()) or {}
ssh_phase = ssh.get("ssh_phase")
ssh_user = ssh.get("ssh_inventory_user")
print(f"ssh_phase={ssh_phase} ssh_inventory_user={ssh_user}")
if ssh_phase != "steady" or ssh_user != "deploy":
    raise SystemExit("ERROR: ssh_phase must be steady and ssh_inventory_user=deploy before nginx-hub")

hub = yaml.safe_load((mgmt / "host_vars/hub-01.yml").read_text()) or {}
nginx_gateway = hub.get("nginx_gateway")
print(f"nginx_gateway={nginx_gateway}")
if not nginx_gateway:
    raise SystemExit("ERROR: host_vars/hub-01.yml must set nginx_gateway: true")

print("inventory gates OK")
PY

echo ""
echo "=== 3/6 deploy@hub-01 passwordless sudo ==="
hub_host="$(resolve_ansible_host "${MGMT_INVENTORY}" "${LIMIT}")"
echo "target: deploy@${hub_host} (inventory: ${MGMT_INVENTORY})"
if ssh -i "${PRIVATE_KEY}" -o BatchMode=yes -o ConnectTimeout=10 \
  "deploy@${hub_host}" 'sudo -n true' 2>/dev/null; then
  echo "deploy@${hub_host} sudo -n OK"
else
  echo "ERROR: deploy@${hub_host} cannot sudo -n" >&2
  echo "       Run: ./scripts/mgmt/apply-hub-deploy-sudo.sh" >&2
  echo "       Or:  ./scripts/mgmt/apply-hub-deploy-sudo.sh --console" >&2
  exit 1
fi

echo ""
echo "=== 4/6 nginx-hub.yml --list-hosts ==="
ansible-playbook "${ROOT}/ansible/playbooks/nginx-hub.yml" \
  -i "${MGMT_INVENTORY}" \
  --limit hub-01 \
  --list-hosts >/dev/null
echo "nginx-hub.yml targets hub-01 OK"

echo ""
echo "=== 5/6 optional probes ==="
if [[ "${PROBE_443}" == "true" ]]; then
  if nc -zv -w 3 "${HUB_WG}" 443 2>&1; then
    echo "NOTE: 443 already open — Nginx may already be running or another service listens"
  else
    echo "443 not listening on ${HUB_WG} (expected before first nginx-hub apply)"
  fi
else
  echo "SKIP (use --probe-443)"
fi

echo ""
echo "=== 6/6 manual reminders ==="
cat <<EOF
  [ ] Aliyun SG: IN-HTTPS-WG 443 from 10.200.0.0/16 (G0 已验收)
  [ ] Recommended: add IN-HTTP-WG TCP 80 from 10.200.0.0/16

Next:
  ansible-playbook ansible/playbooks/nginx-hub.yml \\
    -i ansible/inventories/mgmt/ --limit hub-01

After success, update nginx.yml:
  nginx.enabled: true
  nginx.status: operational

EOF

echo "[stage-g1-nginx-preflight] OK"
