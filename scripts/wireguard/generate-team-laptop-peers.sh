#!/usr/bin/env bash
# =============================================================================
# 为待接入开发人员批量生成 WireGuard Peer 密钥并同步 inventory
# =============================================================================
#
# 跳过已有公钥的 peer（如 laptop-zhengyaoyuan）。
# 执行后需 wireguard-hub.yml apply 使 Hub 登记新 Peer。
#
# Usage:
#   ./scripts/wireguard/generate-team-laptop-peers.sh
#   ./scripts/wireguard/generate-team-laptop-peers.sh --dry-run
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/wireguard/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
WG_KEYS="${SCRIPT_DIR}/wg-keys.sh"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

PEERS=(
  laptop-billmiao
  laptop-sammao
  laptop-zhu
  laptop-xinxin
)

for peer in "${PEERS[@]}"; do
  pub="${WG_KEYS_DIR}/${peer}.pub"
  if [[ -f "$pub" ]]; then
    echo "[skip] ${peer} — ${pub} exists"
    continue
  fi
  if $DRY_RUN; then
    echo "[dry-run] would generate-peer ${peer}"
  else
    "$WG_KEYS" generate-peer "$peer"
  fi
done

if ! $DRY_RUN; then
  "$WG_KEYS" sync-inventory
  cat <<'EOF'

Next:
  ansible-playbook ansible/playbooks/wireguard-hub.yml \
    -i ansible/inventories/mgmt/ --limit hub-01 \
    --vault-password-file .vault_pass

  Per member:
    ./scripts/wireguard/render-laptop-conf.sh <peer_name> /tmp/wg0.conf
    # deliver /tmp/wg0.conf via secure channel; delete after handoff

EOF
fi
