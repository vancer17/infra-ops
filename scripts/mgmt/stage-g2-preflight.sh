#!/usr/bin/env bash
# =============================================================================
# 阶段 G2 启动前预检 — Hub 内网 DNS + JumpServer upstream 细化（hub-g2.yml）
# =============================================================================
#
# 【用途】
#   在 ci-01 上、执行 hub-g2.yml 前运行：
#     - make inventory-mgmt
#     - G1 nginx operational / F wireguard operational 门禁
#     - deploy@hub-01 免密 sudo
#     - 提醒 Hub SG IN-DNS-WG UDP 53
#
# 【用法】
#   ./scripts/mgmt/stage-g2-preflight.sh
#   ./scripts/mgmt/stage-g2-preflight.sh --probe-dns
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_DNS=false
HUB_WG="${HUB_WG:-10.200.0.1}"
MGMT_INVENTORY="${ROOT}/ansible/inventories/mgmt/"
LIMIT="${ANSIBLE_LIMIT:-hub-01}"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --probe-dns   从本机 nc 探测 Hub \${HUB_WG} UDP/TCP 53（部署前通常为 refused）
  -h, --help    显示帮助

Runbook: docs/dns/hub-internal-dns.runbook.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe-dns) PROBE_DNS=true; shift ;;
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

echo "[stage-g2-preflight] repo: ${ROOT}"

echo ""
echo "=== 1/7 make inventory-mgmt ==="
make -C "${ROOT}" inventory-mgmt

echo ""
echo "=== 2/7 inventory gates (wireguard / nginx / internal_dns) ==="
python3 - <<'PY' "${ROOT}"
import sys
from pathlib import Path
import yaml

root = Path(sys.argv[1])
mgmt = root / "ansible/inventories/mgmt"

wg = yaml.safe_load((mgmt / "group_vars/all/wireguard.yml").read_text()) or {}
wg_cfg = wg.get("wireguard", {})
if wg_cfg.get("status") != "operational" or not wg_cfg.get("enabled"):
    raise SystemExit("ERROR: wireguard must be operational before hub-g2")

ngx = yaml.safe_load((mgmt / "group_vars/all/nginx.yml").read_text()) or {}
ngx_cfg = ngx.get("nginx", {})
if ngx_cfg.get("status") != "operational" or not ngx_cfg.get("enabled"):
    raise SystemExit("ERROR: nginx must be operational (G1) before hub-g2")

dns = yaml.safe_load((mgmt / "group_vars/all/internal_dns.yml").read_text()) or {}
dns_cfg = dns.get("internal_dns", {})
if not dns_cfg.get("enabled"):
    raise SystemExit("ERROR: internal_dns.enabled must be true")

hub = yaml.safe_load((mgmt / "host_vars/hub-01.yml").read_text()) or {}
if not hub.get("dns_gateway"):
    raise SystemExit("ERROR: host_vars/hub-01.yml must set dns_gateway: true")

print("inventory gates OK")
PY

echo ""
echo "=== 3/7 deploy@hub-01 passwordless sudo ==="
hub_host="$(resolve_ansible_host "${MGMT_INVENTORY}" "${LIMIT}")"
if ssh -i "${PRIVATE_KEY}" -o BatchMode=yes -o ConnectTimeout=10 \
  "deploy@${hub_host}" 'sudo -n true' 2>/dev/null; then
  echo "deploy@${hub_host} sudo -n OK"
else
  echo "ERROR: deploy@${hub_host} cannot sudo -n" >&2
  exit 1
fi

echo ""
echo "=== 4/7 hub-g2.yml --list-hosts ==="
ansible-playbook "${ROOT}/ansible/playbooks/hub-g2.yml" \
  -i "${MGMT_INVENTORY}" \
  --limit hub-01 \
  --list-hosts >/dev/null
echo "hub-g2.yml targets hub-01 OK"

echo ""
echo "=== 5/7 wireguard-peer.yml --list-hosts (post G2) ==="
ansible-playbook "${ROOT}/ansible/playbooks/wireguard-peer.yml" \
  -i "${MGMT_INVENTORY}" \
  --limit ci-01 \
  --list-hosts >/dev/null
echo "wireguard-peer.yml targets ci-01 OK"

echo ""
echo "=== 6/7 optional DNS probe ==="
if [[ "${PROBE_DNS}" == "true" ]]; then
  if nc -zvu -w 2 "${HUB_WG}" 53 2>&1; then
    echo "NOTE: UDP 53 already open on ${HUB_WG}"
  else
    echo "UDP 53 not listening on ${HUB_WG} (expected before first hub-g2 apply)"
  fi
else
  echo "SKIP (use --probe-dns)"
fi

echo ""
echo "=== 7/7 manual reminders ==="
cat <<EOF
  [ ] Aliyun SG Hub: IN-DNS-WG UDP 53 from 10.200.0.0/16 (see hub-wg.rules.yaml pending_inbound)

Next:
  ansible-playbook ansible/playbooks/hub-g2.yml \\
    -i ansible/inventories/mgmt/ --limit hub-01 --vault-password-file .vault_pass

  ansible-playbook ansible/playbooks/wireguard-peer.yml \\
    -i ansible/inventories/mgmt/ --limit ci-01 --vault-password-file .vault_pass

  Update inventory: internal_dns.status: operational

  Laptop: add to WG [Interface]: DNS = 10.200.0.1 ; wg-quick down/up wg0

Acceptance:
  dig @10.200.0.1 jms.internal
  curl -k https://jms.internal/jms/status
  curl -k https://jms.internal/  → 503 (until JumpServer)

EOF

echo "[stage-g2-preflight] OK"
