#!/usr/bin/env bash
# =============================================================================
# 阶段 G3 启动前预检 — Hub 启用 Docker（hub-g3-docker.yml）
# =============================================================================
#
# 【用途】
#   在 ci-01 上、执行 hub-g3-docker.yml 前运行：
#     - make inventory-mgmt
#     - G1/G2/F 门禁（wireguard / nginx / internal_dns operational）
#     - deploy@hub-01 免密 sudo
#     - 可选：探测 Hub 上是否已有 docker
#
# 【用法】
#   ./scripts/mgmt/stage-g3-docker-preflight.sh
#   ./scripts/mgmt/stage-g3-docker-preflight.sh --probe-docker
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_DOCKER=false
MGMT_INVENTORY="${ROOT}/ansible/inventories/mgmt/"
LIMIT="${ANSIBLE_LIMIT:-hub-01}"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --probe-docker   SSH 到 Hub 检查是否已安装 docker（已安装则提示幂等 apply）
  -h, --help       显示帮助

Runbook: docs/docker/hub-docker.runbook.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe-docker) PROBE_DOCKER=true; shift ;;
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

echo "[stage-g3-docker-preflight] repo: ${ROOT}"

echo ""
echo "=== 1/5 make inventory-mgmt ==="
make -C "${ROOT}" inventory-mgmt

echo ""
echo "=== 2/5 inventory gates (wireguard / nginx / internal_dns / hub_docker) ==="
python3 - <<'PY' "${ROOT}"
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
mgmt = root / "ansible/inventories/mgmt/group_vars/all"

def load(name):
    p = mgmt / name
    return yaml.safe_load(p.read_text()) if p.is_file() else {}

merged = {}
for f in sorted(mgmt.glob("*.yml")):
    data = yaml.safe_load(f.read_text()) or {}
    if isinstance(data, dict):
        merged.update(data)

wg = merged.get("wireguard", {})
ngx = merged.get("nginx", {})
dns = merged.get("internal_dns", {})
hd = merged.get("hub_docker", {})

checks = [
    (wg.get("status") == "operational", "wireguard.status=operational"),
    (wg.get("enabled") is True, "wireguard.enabled=true"),
    (ngx.get("status") == "operational", "nginx.status=operational"),
    (dns.get("status") == "operational", "internal_dns.status=operational"),
    (hd.get("enabled") is True, "hub_docker.enabled=true"),
    (merged.get("docker_install") is True, "docker_install=true"),
]
failed = [msg for ok, msg in checks if not ok]
if failed:
    print("FAIL inventory gates:", ", ".join(failed), file=sys.stderr)
    sys.exit(1)
print("OK: wireguard + nginx + internal_dns + hub_docker gates")
PY

echo ""
echo "=== 3/5 deploy@hub-01 limited sudo probe ==="
HUB_IP="$(resolve_ansible_host "${MGMT_INVENTORY}" "${LIMIT}")"
ssh -i "${PRIVATE_KEY}" \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=accept-new \
  "deploy@${HUB_IP}" 'sudo -n true && echo OK: deploy passwordless sudo'

echo ""
echo "=== 4/5 hub-g3-docker.yml --list-hosts ==="
ansible-playbook "${ROOT}/ansible/playbooks/hub-g3-docker.yml" \
  -i "${MGMT_INVENTORY}" \
  --limit "${LIMIT}" \
  --list-hosts

if [[ "${PROBE_DOCKER}" == "true" ]]; then
  echo ""
  echo "=== 5/5 remote docker probe ==="
  ssh -i "${PRIVATE_KEY}" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    "deploy@${HUB_IP}" bash -s <<'REMOTE' || true
if command -v docker >/dev/null 2>&1; then
  echo "NOTE: docker already installed — hub-g3-docker.yml should be idempotent"
  docker --version
  docker compose version 2>/dev/null || true
else
  echo "OK: docker not installed yet (expected before G3 apply)"
fi
REMOTE
else
  echo ""
  echo "=== 5/5 docker probe skipped (use --probe-docker) ==="
fi

cat <<EOF

Next (dry-run):
  ansible-playbook ansible/playbooks/hub-g3-docker.yml \\
    -i ansible/inventories/mgmt/ --limit hub-01 \\
    --vault-password-file .vault_pass --check --diff

Next (apply):
  ansible-playbook ansible/playbooks/hub-g3-docker.yml \\
    -i ansible/inventories/mgmt/ --limit hub-01 \\
    --vault-password-file .vault_pass

Then:
  ./scripts/mgmt/verify-hub-docker-remote.sh
  # 更新 group_vars/all/docker.yml → hub_docker.status: operational

EOF

echo "[stage-g3-docker-preflight] OK"
