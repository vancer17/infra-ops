#!/usr/bin/env bash
# =============================================================================
# Hub-01 远程 Bootstrap 验收（阶段 C / 阶段 E 前）
# =============================================================================
#
# 【用途】
#   从 ci-01 控制机 SSH 到 Hub，验证 Bootstrap 结果。
#   修复 console-install.log 中 set -e + ls /opt/wireguard 导致脚本提前退出的问题。
#
# 【执行位置】
#   仅 yax（ci-01）上以 deploy 用户运行；需 infra-ci-deploy 私钥。
#
# 【用法】
#   ./scripts/mgmt/verify-hub-remote.sh
#   ./scripts/mgmt/verify-hub-remote.sh hub-01
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/dev/lib/inventory-resolve.sh
source "${ROOT}/scripts/dev/lib/inventory-resolve.sh"

LIMIT="${1:-hub-01}"
INVENTORY="${ANSIBLE_INVENTORY:-${ROOT}/ansible/inventories/mgmt/}"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"

export ANSIBLE_INVENTORY="$INVENTORY"
export ANSIBLE_LIMIT="$LIMIT"

usage() {
  cat <<EOF
Usage: $(basename "$0") [hub-01]

Environment:
  ANSIBLE_INVENTORY          默认 ansible/inventories/mgmt/
  ANSIBLE_PRIVATE_KEY_FILE   默认 ansible/keys/infra-ci-deploy

Prerequisite:
  ./scripts/dev/setup-control-plane-env.sh all
EOF
}

main() {
  [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage && exit 0

  [[ -f "$PRIVATE_KEY" ]] || {
    echo "ERROR: missing ${PRIVATE_KEY}; run: scripts/dev/setup-control-plane-env.sh all" >&2
    exit 1
  }

  local host_ip
  host_ip="$(resolve_ansible_host)"
  echo "[verify-hub] SSH deploy@${host_ip} (limit=${LIMIT})"

  ssh -i "$PRIVATE_KEY" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    "deploy@${host_ip}" bash -s <<'REMOTE'
set -euo pipefail
echo "=== users ==="
id deploy
id jump_ops
echo "=== timezone ==="
timedatectl | grep 'Time zone'
echo "=== directories ==="
ls -la /opt/mgmt /var/log/mgmt
if test -d /opt/wireguard; then
  echo "OK: /opt/wireguard exists (deploy 无 list 权限为预期)"
else
  echo "ERROR: /opt/wireguard missing" >&2
  exit 1
fi
echo "=== docker (Hub 不应安装) ==="
if command -v docker >/dev/null 2>&1; then
  echo "WARN: docker 不应存在于 Hub" >&2
  exit 1
else
  echo "OK: 无 Docker"
fi
echo "=== ufw ==="
if command -v ufw >/dev/null 2>&1; then
  ufw status || true
else
  echo "OK: ufw 未安装（云安全组为主）"
fi
echo "verify-hub-remote OK"
REMOTE

  echo "[verify-hub] remote checks passed"
}

main "$@"
