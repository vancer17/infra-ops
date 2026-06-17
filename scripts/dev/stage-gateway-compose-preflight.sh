#!/usr/bin/env bash
# =============================================================================
# Dev 网关 Compose 预检 — gateway-compose.yml
# =============================================================================
#
# 【用法】
#   ./scripts/dev/stage-gateway-compose-preflight.sh
#   make stage-gateway-compose-preflight
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIMIT="${ANSIBLE_LIMIT:-dev-01}"
PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"
DEV_INVENTORY="${ROOT}/ansible/inventories/dev/"
VAULT_PASS="${ANSIBLE_VAULT_PASSWORD_FILE:-${ROOT}/.vault_pass}"

export ANSIBLE_PRIVATE_KEY_FILE="${PRIVATE_KEY}"
export ANSIBLE_INVENTORY="${DEV_INVENTORY}"
export ANSIBLE_LIMIT="${LIMIT}"

echo "[stage-gateway-compose-preflight] repo: ${ROOT}"

echo ""
echo "=== 1/7 make inventory ==="
make -C "${ROOT}" inventory

echo ""
echo "=== 2/7 inventory gates (gateway / app / docker / images) ==="
python3 - <<'PY' "${ROOT}"
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
inv = root / "ansible/inventories/dev/group_vars/all"

def load(name: str) -> dict:
    with (inv / name).open(encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}

gateway = load("gateway.yml").get("gateway", {})
app = load("app.yml").get("app", {})
bootstrap = load("bootstrap.yml")

assert gateway.get("enabled") is True, "gateway.enabled"
assert gateway.get("certbot", {}).get("primary_domain"), "gateway.certbot.primary_domain"
assert gateway.get("upstream", {}).get("port") == app.get("listen", {}).get("port"), (
    gateway.get("upstream", {}).get("port"),
    app.get("listen", {}).get("port"),
)
assert bootstrap.get("docker_install") is True, "docker_install must be true on dev-01"

compose = gateway.get("compose", {})
assert compose.get("build") == "never", "gateway.compose.build must be never (pre-built images)"
images = gateway.get("images", {})
assert images.get("tag"), "gateway.images.tag"
for key in ("certbot_init", "certbot_renew", "nginx"):
    assert images.get(key), f"gateway.images.{key}"
print("OK: gateway.enabled, certbot domain, upstream port, docker_install, images.*, compose.build=never")
PY

echo ""
echo "=== 3/7 compose project + Dockerfiles present on controller ==="
test -d "${ROOT}/docker/dev-gateway"
test -f "${ROOT}/docker/dev-gateway/docker-compose.yml"
test -f "${ROOT}/docker/certbot-init/Dockerfile"
test -f "${ROOT}/docker/certbot-renew/Dockerfile"
test -f "${ROOT}/docker/nginx/Dockerfile"
echo "OK: dev-gateway compose + image build sources"

echo ""
echo "=== 4/7 build-gateway-images.sh list ==="
"${ROOT}/scripts/docker/build-gateway-images.sh" list

echo ""
echo "=== 5/7 ansible-playbook gateway-compose.yml --syntax-check ==="
SYNTAX_ARGS=(-i "${DEV_INVENTORY}" --limit "${LIMIT}" --syntax-check)
if [[ -f "${VAULT_PASS}" ]]; then
  SYNTAX_ARGS+=(--vault-password-file "${VAULT_PASS}")
else
  echo "WARN: ${VAULT_PASS} missing — syntax-check may fail if secrets.yml is encrypted"
fi
ansible-playbook "${ROOT}/ansible/playbooks/gateway-compose.yml" "${SYNTAX_ARGS[@]}"

echo ""
echo "=== 6/7 optional upstream probe on dev-01 ==="
if [[ -f "${PRIVATE_KEY}" ]]; then
  UP_PROBE=fail
  if ansible "${LIMIT}" -i "${DEV_INVENTORY}" -m uri \
    -a "url=http://127.0.0.1:8080/healthz return_content=no"; then
    UP_PROBE=healthz
  elif ansible "${LIMIT}" -i "${DEV_INVENTORY}" -m uri \
    -a "url=http://127.0.0.1:8080/ return_content=no"; then
    UP_PROBE=root
  fi
  case "${UP_PROBE}" in
    healthz) echo "OK: upstream /healthz（operational 应用）" ;;
    root) echo "OK: upstream /（placeholder 应用）" ;;
    *) echo "WARN: 127.0.0.1:8080 不可达 — 先 run dev-app.yml" ;;
  esac
else
  echo "SKIP: private key not found at ${PRIVATE_KEY}"
fi

echo ""
echo "=== 7/7 deploy sudo probe ==="
if [[ -f "${PRIVATE_KEY}" ]]; then
  ansible "${LIMIT}" -i "${DEV_INVENTORY}" -m command -a "sudo -n true" -b || {
    echo "ERROR: deploy passwordless sudo required for gateway-compose.yml"
    exit 1
  }
  echo "OK: deploy passwordless sudo"
fi

echo ""
echo "[stage-gateway-compose-preflight] OK — next:"
echo "  1) make build-gateway-images && make push-gateway-images"
echo "  2) ansible-playbook ansible/playbooks/gateway-compose.yml -i ansible/inventories/dev/ --limit ${LIMIT} --vault-password-file .vault_pass"
