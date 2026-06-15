#!/usr/bin/env bash
# =============================================================================
# 阶段 F2-5 后续步骤 — WG 收口 + Ansible 经隧道 +（可选）Runner 注册
# =============================================================================
#
# 【用途】
#   在 F2 握手验收（console-acceptance.log）且 F2-4 台账/inventory 已更新为
#   wireguard.status: operational 后，在 ci-01 上执行：
#     1. 复核 WG 隧道仍正常
#     2. 确认 inventory 已切 access_mode / network_phase → wireguard
#     3. make inventory-mgmt + make inventory
#     4. Ansible ping hub-01（ansible_host 应为 10.200.0.1）
#     5. （可选）注册 GitHub Self-hosted Runner
#
# 【前提】
#   - git pull 含 F2-5 inventory 变更（access_mode: wireguard）
#   - wg-quick@wg0 已 enable
#   - .vault_pass、infra-ci-deploy 私钥可用
#
# 【用法】
#   ./scripts/mgmt/stage-f2-5-followup.sh
#   ./scripts/mgmt/stage-f2-5-followup.sh --register-runner
#   ./scripts/mgmt/stage-f2-5-followup.sh --skip-runner
#
# 【勿与 F2-5 混淆】
#   关公网 SSH、JumpServer、Hub 独立安全组 — 属 network_phase: steady，本期不做。
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MGMT_INV="${ROOT}/ansible/inventories/mgmt/"
DEV_INV="${ROOT}/ansible/inventories/dev/"
PRIVATE_KEY="${ROOT}/ansible/keys/infra-ci-deploy"
REGISTER_RUNNER=false
SKIP_RUNNER=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --register-runner   预检通过后调用 register-github-runner.sh
  --skip-runner       跳过 Runner 提示（默认仅打印下一步说明）
  -h, --help          显示帮助

Docs:
  docs/wireguard/stage-f2-5-runbook.md
  docs/wireguard/developer-laptop-client.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --register-runner) REGISTER_RUNNER=true; shift ;;
    --skip-runner) SKIP_RUNNER=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

export ANSIBLE_VAULT_PASSWORD_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-${ROOT}/.vault_pass}"
export ANSIBLE_PRIVATE_KEY_FILE="${ANSIBLE_PRIVATE_KEY_FILE:-${PRIVATE_KEY}}"

echo "[stage-f2-5] repo: ${ROOT}"

# -----------------------------------------------------------------------------
# 1/5 — WireGuard 隧道复核（与 console-acceptance.log 同标准）
# -----------------------------------------------------------------------------
echo ""
echo "=== 1/5 WireGuard tunnel health ==="

if ! sudo wg show wg0 >/dev/null 2>&1; then
  echo "ERROR: wg0 not up — run: sudo systemctl start wg-quick@wg0" >&2
  exit 1
fi

if ! sudo wg show wg0 | grep -q 'latest handshake'; then
  echo "ERROR: no latest handshake on wg0 — check Hub UDP 51820 / Endpoint" >&2
  exit 1
fi
echo "OK: wg0 handshake present"

if ! ping -c 2 -W 2 10.200.0.1 >/dev/null 2>&1; then
  echo "WARN: ping 10.200.0.1 failed (Hub may block ICMP); continuing with SSH check"
else
  echo "OK: ping 10.200.0.1"
fi

[[ -f "$PRIVATE_KEY" ]] || {
  echo "ERROR: missing ${PRIVATE_KEY}" >&2
  exit 1
}

ssh -o BatchMode=yes -o ConnectTimeout=10 \
  -i "$PRIVATE_KEY" deploy@10.200.0.1 'hostname' >/dev/null
echo "OK: ssh deploy@10.200.0.1"

# -----------------------------------------------------------------------------
# 2/5 — inventory 阶段变量（须已 git pull F2-5 变更）
# -----------------------------------------------------------------------------
echo ""
echo "=== 2/5 inventory access_mode / network_phase ==="

access_mode="$(ansible hub-01 -i "$MGMT_INV" -m debug -a var=ci_connectivity.access_mode -c local 2>/dev/null \
  | python3 -c "import json,re,sys; t=sys.stdin.read(); m=re.search(r'=>\s*(\{.*\})',t,re.S); print(json.loads(m.group(1)).get('ci_connectivity.access_mode','') if m else '')" 2>/dev/null || true)"
network_phase="$(ansible hub-01 -i "$MGMT_INV" -m debug -a var=network_phase -c local 2>/dev/null \
  | python3 -c "import json,re,sys; t=sys.stdin.read(); m=re.search(r'=>\s*(\{.*\})',t,re.S); print(json.loads(m.group(1)).get('network_phase','') if m else '')" 2>/dev/null || true)"
hub_host="$(ansible hub-01 -i "$MGMT_INV" -m debug -a var=ansible_host -c local 2>/dev/null \
  | python3 -c "import json,re,sys; t=sys.stdin.read(); m=re.search(r'=>\s*(\{.*\})',t,re.S); print(json.loads(m.group(1)).get('ansible_host','') if m else '')" 2>/dev/null || true)"

if [[ "$access_mode" != "wireguard" ]]; then
  echo "ERROR: ci_connectivity.access_mode=${access_mode:-<unset>} — expected wireguard" >&2
  echo "       git pull 最新 infra-ops（F2-5 inventory 变更）后重试" >&2
  exit 1
fi
echo "OK: ci_connectivity.access_mode=wireguard"

if [[ "$network_phase" != "wireguard" ]]; then
  echo "ERROR: network_phase=${network_phase:-<unset>} — expected wireguard" >&2
  exit 1
fi
echo "OK: network_phase=wireguard"

if [[ "$hub_host" != "10.200.0.1" ]]; then
  echo "ERROR: hub-01 ansible_host=${hub_host:-<unset>} — expected 10.200.0.1" >&2
  exit 1
fi
echo "OK: hub-01 ansible_host=10.200.0.1"

# -----------------------------------------------------------------------------
# 3/5 — 静态 inventory 门禁
# -----------------------------------------------------------------------------
echo ""
echo "=== 3/5 make inventory-mgmt + inventory ==="
make -C "$ROOT" inventory-mgmt
make -C "$ROOT" inventory

# -----------------------------------------------------------------------------
# 4/5 — Ansible 经 WG 连通 Hub / 本机 Dev
# -----------------------------------------------------------------------------
echo ""
echo "=== 4/5 Ansible ping (via inventory ansible_host) ==="

ANSIBLE_INVENTORY="$MGMT_INV" ansible hub-01 -i "$MGMT_INV" -m ping -u deploy
echo "OK: ansible ping hub-01"

ANSIBLE_INVENTORY="$DEV_INV" ansible dev-01 -i "$DEV_INV" -m ping -u deploy \
  -e ansible_connection=local
echo "OK: ansible ping dev-01 (local)"

# -----------------------------------------------------------------------------
# 5/5 — Runner / 笔记本 Peer 指引
# -----------------------------------------------------------------------------
echo ""
echo "=== 5/5 optional follow-ups ==="

if [[ "$REGISTER_RUNNER" == "true" ]]; then
  bash "${ROOT}/scripts/mgmt/register-github-runner.sh"
elif [[ "$SKIP_RUNNER" != "true" ]]; then
  cat <<EOF

GitHub Self-hosted Runner（可选，deploy.yml 需要）:
  export RUNNER_REGISTRATION_TOKEN="<from GitHub Settings → Actions → Runners>"
  ./scripts/mgmt/register-github-runner.sh

运维笔记本 WireGuard Client（可选）:
  见 docs/wireguard/developer-laptop-client.md
  模板: ansible/keys/wireguard/developer-laptop.conf.example

本期不做（steady 阶段）:
  - 关闭 Bootstrap 公网 SSH
  - Hub 迁移独立安全组 sg-hub-wg
  - JumpServer

EOF
fi

echo ""
echo "=========================================="
echo "stage-f2-5-followup OK"
echo "=========================================="
