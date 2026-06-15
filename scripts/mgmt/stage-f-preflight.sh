#!/usr/bin/env bash
# =============================================================================
# 阶段 F 启动前预检 — Hub Server（F1）与 ci-01 Peer Client（F2）可自动化项
# =============================================================================
#
# 【用途】
#   在 ci-01 上、阶段 F playbook 执行前运行：
#     - make inventory-mgmt
#     - wg-keys verify-hub / verify-peer ci-01
#     - ci-01.private 存在性
#     - deploy-wireguard 受限 sudo（apply-ci-wireguard-sudo.sh）
#     - Hub UDP 51820 探测（可选）
#
# 【用法】
#   ./scripts/mgmt/stage-f-preflight.sh
#   ./scripts/mgmt/stage-f-preflight.sh --probe-udp
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_UDP=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --probe-udp   从本机 nc 探测 Hub 121.43.49.58 UDP 51820（需安全组已放行）
  -h, --help    显示帮助

Manual checklist: docs/wireguard/stage-f-console-checklist.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe-udp) PROBE_UDP=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

export ANSIBLE_VAULT_PASSWORD_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-${ROOT}/.vault_pass}"
export ANSIBLE_PRIVATE_KEY_FILE="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"

echo "[stage-f-preflight] repo: ${ROOT}"

echo ""
echo "=== 1/7 make inventory-mgmt ==="
make -C "${ROOT}" inventory-mgmt

echo ""
echo "=== 2/7 wg-keys verify-hub / verify-peer ci-01 ==="
bash "${ROOT}/scripts/wireguard/wg-keys.sh" verify-hub
bash "${ROOT}/scripts/wireguard/wg-keys.sh" verify-peer ci-01

echo ""
echo "=== 3/7 ci-01 peer private key on controller ==="
peer_key="${ROOT}/ansible/keys/wireguard/ci-01.private"
if [[ -f "${peer_key}" ]]; then
  echo "OK: ${peer_key} present"
else
  echo "ERROR: missing ${peer_key} — run: ./scripts/wireguard/wg-keys.sh generate-peer ci-01" >&2
  exit 1
fi

echo ""
echo "=== 4/7 deploy-wireguard limited sudo (F2) ==="
bash "${ROOT}/scripts/mgmt/apply-ci-wireguard-sudo.sh"

echo ""
echo "=== 5/7 vault-view (requires .vault_pass) ==="
if [[ -f "${ROOT}/.vault_pass" ]]; then
  bash "${ROOT}/scripts/wireguard/wg-keys.sh" vault-view | head -20
  echo "... (truncated)"
else
  echo "WARN: missing ${ROOT}/.vault_pass — skip vault-view" >&2
fi

echo ""
echo "=== 6/7 UDP 51820 probe ==="
if [[ "${PROBE_UDP}" == "true" ]]; then
  if command -v nc >/dev/null 2>&1; then
    nc -zvu -w 3 121.43.49.58 51820 || echo "WARN: UDP probe failed (Hub may not listen yet — OK before F1 apply)"
  else
    echo "WARN: nc not found" >&2
  fi
else
  echo "SKIP (use --probe-udp); see docs/wireguard/stage-f-console-checklist.md"
fi

echo ""
echo "=== 7/7 manual reminders ==="
cat <<EOF

Before wireguard-hub.yml (F1), confirm:
  [ ] deploy@hub-01 can: sudo -n true  (if not: ./scripts/mgmt/apply-hub-deploy-sudo.sh)
  [ ] Aliyun SG sg-bp122tjy3h95um8kv4f9 has IN-WG-UDP-* (see stage-f-console-checklist.md)
  [ ] Peer model: Hub active peers = ci-01 + developer-laptop (not dev-01)

Before wireguard-peer.yml (F2), confirm:
  [ ] deploy-wireguard sudoers OK (step 4 above)
  [ ] wireguard.status is server_up (F1 applied)
  [ ] Do NOT set ci_connectivity.access_mode: wireguard until handshake stable
  [ ] GitHub Environment Secret ANSIBLE_VAULT_PASSWORD = ci-01 .vault_pass
  [ ] Self-hosted Runner: register after WG handshake (ci-01.yaml runner_status)

Git commit on ci-01 (deploy user):
  git config user.email "you@example.com"
  git config user.name "Your Name"

Next (F1): ansible-playbook ansible/playbooks/wireguard-hub.yml \\
  -i ansible/inventories/mgmt/ --limit hub-01 --vault-password-file .vault_pass

Next (F2): ansible-playbook ansible/playbooks/wireguard-peer.yml \\
  -i ansible/inventories/mgmt/ --limit ci-01 --vault-password-file .vault_pass

EOF

echo "[stage-f-preflight] OK"
