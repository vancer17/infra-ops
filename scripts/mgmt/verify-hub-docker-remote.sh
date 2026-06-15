#!/usr/bin/env bash
# =============================================================================
# Hub-01 阶段 G3 Docker 远程验收
# =============================================================================
#
# 【用途】
#   hub-g3-docker.yml apply 后，从 ci-01 SSH 到 Hub 验证 Docker 与目录。
#
# 【用法】
#   ./scripts/mgmt/verify-hub-docker-remote.sh
#   ./scripts/mgmt/verify-hub-docker-remote.sh hub-01
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/dev/lib/inventory-resolve.sh
source "${ROOT}/scripts/dev/lib/inventory-resolve.sh"

LIMIT="${1:-hub-01}"
MGMT_INVENTORY="${ROOT}/ansible/inventories/mgmt/"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"
SMOKE_IMAGE="${HUB_DOCKER_SMOKE_IMAGE:-5yrqsf19ms2mh4.xuanyuan.run/library/hello-world:latest}"

export ANSIBLE_INVENTORY="${MGMT_INVENTORY}"
export ANSIBLE_LIMIT="$LIMIT"

usage() {
  cat <<EOF
Usage: $(basename "$0") [hub-01]

Environment:
  HUB_DOCKER_SMOKE_IMAGE   smoke 镜像（默认国内镜像站 hello-world）
  ANSIBLE_PRIVATE_KEY_FILE 默认 ansible/keys/infra-ci-deploy
EOF
}

main() {
  [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage && exit 0

  [[ -f "$PRIVATE_KEY" ]] || {
    echo "ERROR: missing ${PRIVATE_KEY}" >&2
    exit 1
  }

  local host_ip smoke_image
  host_ip="$(resolve_ansible_host "${MGMT_INVENTORY}" "${LIMIT}")" || exit 1
  smoke_image="$SMOKE_IMAGE"
  echo "[verify-hub-docker] SSH deploy@${host_ip} (limit=${LIMIT})"

  ssh -i "$PRIVATE_KEY" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    "deploy@${host_ip}" bash -s "$smoke_image" <<'REMOTE'
set -euo pipefail
SMOKE_IMAGE="${1:?}"

echo "=== docker CLI ==="
command -v docker >/dev/null
docker --version
docker compose version

echo "=== deploy in docker group ==="
id deploy
id -nG deploy | grep -qw docker

echo "=== jumpserver directories ==="
ls -la /opt/mgmt/jumpserver
test -d /opt/mgmt/jumpserver/data
test -d /opt/mgmt/jumpserver/static

echo "=== docker smoke (as deploy) ==="
sudo -u deploy docker run --rm "$SMOKE_IMAGE" >/dev/null
echo "smoke OK"

echo "=== docker service ==="
systemctl is-active docker

echo "verify-hub-docker-remote OK"
REMOTE

  echo "[verify-hub-docker] remote checks passed"
}

main "$@"
