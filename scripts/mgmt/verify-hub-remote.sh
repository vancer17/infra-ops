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
# 【注意】
#   本脚本始终使用 mgmt inventory，不继承 shell 中的 ANSIBLE_INVENTORY。
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
MGMT_INVENTORY="${ROOT}/ansible/inventories/mgmt/"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"

export ANSIBLE_INVENTORY="${MGMT_INVENTORY}"
export ANSIBLE_LIMIT="$LIMIT"

usage() {
  cat <<EOF
Usage: $(basename "$0") [hub-01]

Environment:
  ANSIBLE_PRIVATE_KEY_FILE   默认 ansible/keys/infra-ci-deploy
  ANSIBLE_VAULT_PASSWORD_FILE  解析 ansible_host 时需 .vault_pass

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
  host_ip="$(resolve_ansible_host "${MGMT_INVENTORY}" "${LIMIT}")" || exit 1
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
echo "=== docker ==="
if command -v docker >/dev/null 2>&1; then
  docker --version
  docker compose version 2>/dev/null || true
  id -nG deploy | grep -qw docker && echo "OK: deploy in docker group" || echo "WARN: deploy not in docker group"
else
  echo "OK: docker not installed (expected before stage G3; run hub-g3-docker.yml)"
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
