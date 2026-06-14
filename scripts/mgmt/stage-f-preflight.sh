#!/usr/bin/env bash
# =============================================================================
# 阶段 F 启动前预检 — 修复交叉检查黄灯项中的可自动化部分
# =============================================================================
#
# 【用途】
#   在 ci-01 上、阶段 F（wireguard-hub playbook）开发/执行前运行：
#     - make ci / inventory-mgmt
#     - wg-keys verify + vault-view
#     - Hub UDP 51820 探测（可选）
#     - 打印 GitHub Secrets / Runner 待办
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
echo "=== 1/5 make inventory-mgmt ==="
make -C "${ROOT}" inventory-mgmt

echo ""
echo "=== 2/5 wg-keys verify-hub / verify-peer ci-01 ==="
bash "${ROOT}/scripts/wireguard/wg-keys.sh" verify-hub
bash "${ROOT}/scripts/wireguard/wg-keys.sh" verify-peer ci-01

echo ""
echo "=== 3/5 vault-view (requires .vault_pass) ==="
if [[ -f "${ROOT}/.vault_pass" ]]; then
  bash "${ROOT}/scripts/wireguard/wg-keys.sh" vault-view | head -20
  echo "... (truncated)"
else
  echo "WARN: missing ${ROOT}/.vault_pass — skip vault-view" >&2
fi

echo ""
echo "=== 4/5 UDP 51820 probe ==="
if [[ "${PROBE_UDP}" == "true" ]]; then
  if command -v nc >/dev/null 2>&1; then
    nc -zvu -w 3 121.43.49.58 51820 || echo "WARN: UDP probe failed (Hub may not listen yet — OK before stage F apply)"
  else
    echo "WARN: nc not found" >&2
  fi
else
  echo "SKIP (use --probe-udp); see docs/wireguard/stage-f-console-checklist.md"
fi

echo ""
echo "=== 5/5 manual reminders ==="
cat <<EOF

Before wireguard-hub.yml apply, confirm:
  [ ] GitHub Environment Secret ANSIBLE_VAULT_PASSWORD = ci-01 .vault_pass
  [ ] Aliyun SG sg-bp122tjy3h95um8kv4f9 has IN-WG-UDP-* (see stage-f-console-checklist.md)
  [ ] Peer model: Hub active peers = ci-01 + developer-laptop (not dev-01)
  [ ] Self-hosted Runner: register after WG handshake (ci-01.yaml runner_status)

Git commit on ci-01 (deploy user):
  git config user.email "you@example.com"
  git config user.name "Your Name"

Next: implement ansible/roles/wireguard + playbooks/wireguard-hub.yml

EOF

echo "[stage-f-preflight] OK"
