#!/usr/bin/env bash
# =============================================================================
# 阶段 E 前预检 — 修复交叉检查报告中的黄灯项
# =============================================================================
#
# 【用途】
#   在 ci-01（yax）上一次性执行：
#     1. 控制面 ~/.bashrc：ANSIBLE_PRIVATE_KEY_FILE → infra-ci-deploy（黄灯 1）
#     2. Ansible ping hub-01 / dev-01（验证 deploy 连通）
#     3. wireguard-tools 检查或安装（黄灯 2）
#     4. make inventory-mgmt（黄灯 3：steady → deploy 门禁）
#     5. Hub 远程验收（可选，需 SSH 可达）
#     6. wg-keys.sh check-deps
#
# 【执行位置】
#   仅 yax 上以 deploy 用户运行（hostname 含 rt2r 或手动确认）。
#
# 【用法】
#   ./scripts/mgmt/stage-e-preflight.sh
#   ./scripts/mgmt/stage-e-preflight.sh --install-wireguard
#   ./scripts/mgmt/stage-e-preflight.sh --skip-remote
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/dev/lib/bashrc-check.sh
source "${ROOT}/scripts/dev/lib/bashrc-check.sh"
INSTALL_WG=false
SKIP_REMOTE=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --install-wireguard   缺失时 sudo apt install wireguard-tools
  --skip-remote         跳过 Hub 远程 SSH 验收
  -h, --help            显示帮助

After success:
  source ~/.bashrc
  ./scripts/wireguard/wg-keys.sh all-hub
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-wireguard) INSTALL_WG=true; shift ;;
    --skip-remote) SKIP_REMOTE=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

echo "[stage-e-preflight] repo: ${ROOT}"

# --- 1. 控制面 bashrc + Ansible ping（黄灯 1）---
echo ""
echo "=== 1/5 control plane env (setup-control-plane-env.sh) ==="
bash "${ROOT}/scripts/dev/setup-control-plane-env.sh" all

# 当前 shell 使用正确密钥（无需用户已 source bashrc）
export ANSIBLE_PRIVATE_KEY_FILE="${ROOT}/ansible/keys/infra-ci-deploy"
export ANSIBLE_INVENTORY="${ROOT}/ansible/inventories/mgmt/"

if bashrc_has_stale_ansible_hub_root "${HOME}/.bashrc"; then
  echo "ERROR: ~/.bashrc 仍含指向 hub-root 的 ANSIBLE_PRIVATE_KEY_FILE 赋值（非注释行）" >&2
  echo "       请运行: ./scripts/dev/setup-control-plane-env.sh apply-bashrc" >&2
  exit 1
fi
echo "OK: ~/.bashrc 无 hub-root 密钥赋值（已忽略说明注释）"

# --- 2. inventory-mgmt（黄灯 3）---
echo ""
echo "=== 2/5 inventory-mgmt (steady → deploy gate) ==="
make -C "${ROOT}" inventory-mgmt

# --- 3. wireguard-tools（黄灯 2）---
echo ""
echo "=== 3/5 wireguard-tools ==="
if command -v wg >/dev/null 2>&1; then
  echo "OK: $(wg --version 2>/dev/null || true)"
elif [[ "${INSTALL_WG}" == "true" ]]; then
  echo "Installing wireguard-tools..."
  sudo apt update
  sudo apt install -y wireguard-tools
  wg --version
else
  echo "WARN: wg not found — rerun with --install-wireguard or: sudo apt install -y wireguard-tools" >&2
  exit 1
fi

# --- 4. wg-keys deps ---
echo ""
echo "=== 4/5 wg-keys check-deps ==="
bash "${ROOT}/scripts/wireguard/wg-keys.sh" check-deps

# --- 5. Hub 远程验收 ---
if [[ "${SKIP_REMOTE}" == "false" ]]; then
  echo ""
  echo "=== 5/5 Hub remote verify ==="
  bash "${ROOT}/scripts/mgmt/verify-hub-remote.sh" hub-01
else
  echo ""
  echo "=== 5/5 Hub remote verify (skipped) ==="
fi

echo ""
echo "=========================================="
echo "stage-e-preflight OK"
echo "=========================================="
echo "Run:  source ~/.bashrc"
echo "Next: ./scripts/wireguard/wg-keys.sh all-hub"
echo "      openssl rand -base64 32 > .vault_pass && chmod 600 .vault_pass"
echo "      ./scripts/wireguard/wg-keys.sh vault-encrypt-hub"
echo "      make inventory-mgmt   # 需 .vault_pass（见 docs/wireguard/wg-keys.runbook.md §五）"
