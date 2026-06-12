#!/usr/bin/env bash
# =============================================================================
# scripts/wireguard/lib/common.sh — WireGuard 密钥脚本共享库
# =============================================================================
#
# 【用途】
#   被 scripts/wireguard/wg-keys.sh source 引用，提供：
#     - 仓库根目录与密钥目录路径常量
#     - 与 ansible/inventories/mgmt/group_vars 对齐的文件路径
#     - 统一日志与前置检查（wg、python3 等）
#
# 【设计原则】
#   - 私钥路径常量集中在此，避免 wg-keys.sh 与文档多处硬编码
#   - 不执行密钥生成逻辑（生成见 wg-keys.sh）
#
# =============================================================================

# 防止重复 source
if [[ -n "${WG_COMMON_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
WG_COMMON_LOADED=1

set -euo pipefail

# -----------------------------------------------------------------------------
# 路径常量
# -----------------------------------------------------------------------------
# scripts/wireguard/lib/common.sh → 上三级 = infra-ops/
WG_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# 密钥存放目录（公钥可提交 Git；*.private 在 .gitignore）
WG_KEYS_DIR="${WG_KEYS_DIR:-${WG_REPO_ROOT}/ansible/keys/wireguard}"

# Hub 密钥文件名（与 ansible/keys/wireguard/README.md 一致）
WG_HUB_PRIVATE="${WG_HUB_PRIVATE:-${WG_KEYS_DIR}/hub.private}"
WG_HUB_PUBLIC="${WG_HUB_PUBLIC:-${WG_KEYS_DIR}/hub.pub}"

# Mgmt inventory 与 WG 变量文件
WG_INVENTORY_MGMT="${WG_INVENTORY_MGMT:-${WG_REPO_ROOT}/ansible/inventories/mgmt/}"
WG_VARS_WIREGUARD="${WG_VARS_WIREGUARD:-${WG_REPO_ROOT}/ansible/inventories/mgmt/group_vars/all/wireguard.yml}"
WG_VARS_KEYS="${WG_VARS_KEYS:-${WG_REPO_ROOT}/ansible/inventories/mgmt/group_vars/all/wireguard_keys.yml}"

# Ansible Vault：Hub 私钥加密文件（位于 group_vars/all/ 以便 inventory 自动加载）
WG_VAULT_FILE="${WG_VAULT_FILE:-${WG_REPO_ROOT}/ansible/inventories/mgmt/group_vars/all/wireguard_vault.yml}"
WG_VAULT_EXAMPLE="${WG_VAULT_EXAMPLE:-${WG_REPO_ROOT}/ansible/inventories/mgmt/group_vars/all/wireguard_vault.yml.example}"

# 本地 vault 密码文件（gitignore；与 deploy.yml 的 .vault_pass 一致）
WG_VAULT_PASS_FILE="${WG_VAULT_PASS_FILE:-${WG_REPO_ROOT}/.vault_pass}"

# 资产台账（同步公钥状态 / wireguard_status 时可选更新）
WG_ASSET_HUB="${WG_ASSET_HUB:-${WG_REPO_ROOT}/docs/assets/hub-01.yaml}"

# -----------------------------------------------------------------------------
# 日志
# -----------------------------------------------------------------------------
wg_log() {
  printf '[wg-keys] %s\n' "$*"
}

wg_warn() {
  printf '[wg-keys] WARN: %s\n' "$*" >&2
}

wg_die() {
  printf '[wg-keys] ERROR: %s\n' "$*" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# 依赖检查
# -----------------------------------------------------------------------------
wg_require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || wg_die "missing command: ${cmd}"
}

wg_check_deps() {
  wg_require_cmd wg
  wg_require_cmd python3
}

# -----------------------------------------------------------------------------
# 密钥文件工具
# -----------------------------------------------------------------------------
wg_ensure_keys_dir() {
  mkdir -p "$WG_KEYS_DIR"
  chmod 700 "$WG_KEYS_DIR"
}

wg_peer_private() {
  local name="$1"
  echo "${WG_KEYS_DIR}/${name}.private"
}

wg_peer_public() {
  local name="$1"
  echo "${WG_KEYS_DIR}/${name}.pub"
}

# 读取 WireGuard 密钥文件内容（去除首尾空白与换行）
wg_read_key_file() {
  local file="$1"
  [[ -f "$file" ]] || wg_die "key file not found: ${file}"
  tr -d ' \t\n\r' <"$file"
}

# 由私钥派生公钥并校验与已有 .pub 是否一致
wg_verify_keypair() {
  local private_file="$1"
  local public_file="$2"
  local derived actual

  derived="$(wg pubkey <"$private_file")"
  if [[ -f "$public_file" ]]; then
    actual="$(wg_read_key_file "$public_file")"
    [[ "$derived" == "$actual" ]] || wg_die "keypair mismatch: ${private_file} vs ${public_file}"
  fi
  wg_log "keypair OK: $(basename "$private_file")"
}
