#!/usr/bin/env bash
# =============================================================================
# WireGuard 密钥生成与保管（Hub + Peer）
# =============================================================================
#
# 【这个脚本是什么】
#   建立企业方案中的 WireGuard 密钥体系，与 SSH 密钥脚本（scripts/dev/ssh-keys.sh）
#   对称设计：
#     - 本地生成密钥对（wg genkey / wg pubkey）
#     - 公钥提交 Git，私钥 gitignore
#     - Hub 私钥额外写入 ansible-vault 供后续 wireguard role 使用
#     - 公钥同步到 inventories/mgmt/group_vars/all/wireguard.yml
#
# 【执行位置】
#   在 CI 替代机（ci-01，121.41.58.20）或运维笔记本上执行。
#   需要安装：wireguard-tools（apt install wireguard）、python3、ansible（vault 子命令）
#
# 【保管策略摘要】
#   | 材料              | 存放位置                          | 提交 Git |
#   |-------------------|-----------------------------------|----------|
#   | Hub 公钥          | ansible/keys/wireguard/hub.pub    | 是       |
#   | Hub 私钥（明文）  | ansible/keys/wireguard/hub.private| 否       |
#   | Hub 私钥（密文）  | group_vars/all/wireguard_vault.yml | 是(vault)|
#   | Peer 公钥         | ansible/keys/wireguard/<name>.pub | 是       |
#   | Peer 私钥         | 各 Peer 机器 / keys/*.private     | 否       |
#   | Vault 密码        | .vault_pass / GitHub Secret       | 否       |
#
# 【典型流程 — 仅 Hub 密钥（本期范围）】
#   chmod +x scripts/wireguard/wg-keys.sh
#   ./scripts/wireguard/wg-keys.sh check-deps
#   ./scripts/wireguard/wg-keys.sh generate-hub
#   ./scripts/wireguard/wg-keys.sh verify-hub
#   ./scripts/wireguard/wg-keys.sh sync-inventory
#   ./scripts/wireguard/wg-keys.sh vault-encrypt-hub    # 需先 ansible-vault create 或设置 .vault_pass
#   git add ansible/keys/wireguard/hub.pub \
#           ansible/inventories/mgmt/group_vars/all/wireguard.yml \
#           ansible/inventories/mgmt/group_vars/all/wireguard_vault.yml
#   make ci && make inventory-mgmt
#
# 详见：docs/wireguard/wg-keys.runbook.md
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/wireguard/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Hub 密钥（本期重点）:
  check-deps          检查 wg、python3、可选 ansible-vault
  generate-hub        生成 Hub 密钥对 hub.private / hub.pub
  verify-hub          校验 Hub 私钥与 hub.pub 匹配
  show-hub-pub        打印 Hub 公钥（配置 Peer 时填入 Hub 的 [Peer]）

Peer 密钥（实施各 Peer 客户端时使用）:
  generate-peer NAME  生成 Peer 密钥对（如 ci-01、developer-laptop）
  verify-peer NAME    校验指定 Peer 密钥对

Inventory / Vault:
  sync-inventory      将已生成的 .pub 同步到 wireguard.yml 的 public_key 字段
  vault-encrypt-hub   用 ansible-vault 加密 Hub 私钥到 vault/wireguard.yml
  vault-view          查看已加密的 vault/wireguard.yml（需 .vault_pass）
  list                列出 keys/ 目录下各密钥存在状态

辅助:
  github-hints        输出 GitHub Secret ANSIBLE_VAULT_PASSWORD 等说明
  all-hub             generate-hub → verify-hub → sync-inventory → 后续提示

Environment:
  WG_KEYS_DIR         默认 ansible/keys/wireguard
  WG_VAULT_PASS_FILE  默认仓库根目录 .vault_pass

Examples:
  $(basename "$0") generate-hub
  $(basename "$0") generate-peer ci-01
  $(basename "$0") sync-inventory
  $(basename "$0") vault-encrypt-hub
EOF
}

# -----------------------------------------------------------------------------
# Python：从 wireguard.yml 读取 wireguard_peers_planned 中的 name 列表
# -----------------------------------------------------------------------------
read_planned_peer_names() {
  python3 - "$WG_VARS_WIREGUARD" <<'PY'
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

path = Path(sys.argv[1])
text = path.read_text()

if yaml is not None:
    data = yaml.safe_load(text) or {}
    peers = data.get("wireguard_peers_planned") or []
    for p in peers:
        name = p.get("name")
        if name:
            print(name)
else:
    # 无 PyYAML 时的简易解析（仅匹配 "  - name: xxx"）
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("- name:"):
            print(line.split(":", 1)[1].strip())
PY
}

validate_peer_name() {
  local name="$1"
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || wg_die "invalid peer name: ${name} (use lowercase, digits, hyphen)"
  if [[ "$name" == "hub" ]]; then
    wg_die "use generate-hub for Hub keys, not generate-peer hub"
  fi
}

# -----------------------------------------------------------------------------
# sync-inventory：把 .pub 公钥写回 wireguard.yml
# -----------------------------------------------------------------------------
cmd_sync_inventory() {
  wg_check_deps
  python3 - "$WG_VARS_WIREGUARD" "$WG_KEYS_DIR" "$WG_HUB_PUBLIC" <<'PY'
import sys
from pathlib import Path

try:
    import yaml
except ImportError as e:
    raise SystemExit("PyYAML required: pip install pyyaml or use .venv from make setup") from e

wg_file, keys_dir, hub_pub = sys.argv[1:4]
path = Path(wg_file)
data = yaml.safe_load(path.read_text()) or {}

def read_pub(p: Path) -> str | None:
    if not p.is_file():
        return None
    return p.read_text().strip()

hub_key = read_pub(Path(hub_pub))
if hub_key:
    data.setdefault("wireguard", {})["hub_public_key"] = hub_key

peers = data.get("wireguard_peers_planned") or []
for peer in peers:
    name = peer.get("name")
    if not name:
        continue
    pub = read_pub(Path(keys_dir) / f"{name}.pub")
    if pub:
        peer["public_key"] = pub
    elif peer.get("public_key") is None:
        pass  # 保持 null

path.write_text(yaml.dump(data, allow_unicode=True, default_flow_style=False, sort_keys=False))
print(f"Updated {path}")
if hub_key:
    print(f"  wireguard.hub_public_key = {hub_key[:16]}...")
for peer in peers:
    pk = peer.get("public_key")
    if pk:
        print(f"  peer {peer.get('name')}: public_key set")
PY
  wg_log "sync-inventory OK — review ${WG_VARS_WIREGUARD} then: make inventory-mgmt"
}

# -----------------------------------------------------------------------------
# Hub 密钥生成
# -----------------------------------------------------------------------------
cmd_generate_hub() {
  wg_check_deps
  wg_ensure_keys_dir

  if [[ -f "$WG_HUB_PRIVATE" ]]; then
    wg_die "Hub private key already exists: ${WG_HUB_PRIVATE} (remove manually to regenerate)"
  fi

  umask 077
  wg genkey | tee "$WG_HUB_PRIVATE" | wg pubkey >"$WG_HUB_PUBLIC"
  chmod 600 "$WG_HUB_PRIVATE"
  chmod 644 "$WG_HUB_PUBLIC"

  wg_log "Generated Hub keypair:"
  wg_log "  private: ${WG_HUB_PRIVATE}  (gitignored — also encrypt with vault-encrypt-hub)"
  wg_log "  public:  ${WG_HUB_PUBLIC}   (commit to Git after sync-inventory)"
  wg_log "Hub public key:"
  cat "$WG_HUB_PUBLIC"
}

cmd_verify_hub() {
  wg_check_deps
  [[ -f "$WG_HUB_PRIVATE" ]] || wg_die "missing ${WG_HUB_PRIVATE}; run: generate-hub"
  [[ -f "$WG_HUB_PUBLIC" ]] || wg_die "missing ${WG_HUB_PUBLIC}; run: generate-hub"
  wg_verify_keypair "$WG_HUB_PRIVATE" "$WG_HUB_PUBLIC"
}

cmd_show_hub_pub() {
  [[ -f "$WG_HUB_PUBLIC" ]] || wg_die "missing ${WG_HUB_PUBLIC}; run: generate-hub"
  wg_read_key_file "$WG_HUB_PUBLIC"
}

# -----------------------------------------------------------------------------
# Peer 密钥生成
# -----------------------------------------------------------------------------
cmd_generate_peer() {
  local name="${1:-}"
  [[ -n "$name" ]] || wg_die "usage: generate-peer <name> (e.g. ci-01)"
  validate_peer_name "$name"
  wg_check_deps
  wg_ensure_keys_dir

  local priv pub
  priv="$(wg_peer_private "$name")"
  pub="$(wg_peer_public "$name")"

  if [[ -f "$priv" ]]; then
    wg_die "Peer private key already exists: ${priv}"
  fi

  umask 077
  wg genkey | tee "$priv" | wg pubkey >"$pub"
  chmod 600 "$priv"
  chmod 644 "$pub"

  wg_log "Generated Peer keypair for ${name}:"
  wg_log "  private: ${priv}  (gitignored — deploy to Peer machine only)"
  wg_log "  public:  ${pub}   (commit + run sync-inventory)"
  wg_log "Peer public key:"
  cat "$pub"
  wg_log "Next: ./scripts/wireguard/wg-keys.sh sync-inventory"
}

cmd_verify_peer() {
  local name="${1:-}"
  [[ -n "$name" ]] || wg_die "usage: verify-peer <name>"
  wg_check_deps
  local priv pub
  priv="$(wg_peer_private "$name")"
  pub="$(wg_peer_public "$name")"
  [[ -f "$priv" ]] || wg_die "missing ${priv}"
  [[ -f "$pub" ]] || wg_die "missing ${pub}"
  wg_verify_keypair "$priv" "$pub"
}

# -----------------------------------------------------------------------------
# Ansible Vault：Hub 私钥加密保管
# -----------------------------------------------------------------------------
vault_password_args() {
  if [[ -f "$WG_VAULT_PASS_FILE" ]]; then
    echo "--vault-password-file" "$WG_VAULT_PASS_FILE"
  else
    wg_warn "no ${WG_VAULT_PASS_FILE}; ansible-vault will prompt interactively"
    echo ""
  fi
}

cmd_vault_encrypt_hub() {
  wg_check_deps
  command -v ansible-vault >/dev/null 2>&1 || wg_die "ansible-vault not found; run: make setup"
  [[ -f "$WG_HUB_PRIVATE" ]] || wg_die "missing Hub private key; run: generate-hub"

  local hub_priv hub_pub tmp
  hub_priv="$(wg_read_key_file "$WG_HUB_PRIVATE")"
  hub_pub="$(wg_read_key_file "$WG_HUB_PUBLIC")"

  mkdir -p "$(dirname "$WG_VAULT_FILE")"
  tmp="$(mktemp)"
  # 勿用 trap RETURN + local tmp（函数 return 时 local 已销毁，set -u 报 tmp unbound）

  # 明文结构仅存在于临时文件，随即被 ansible-vault 加密
  cat >"$tmp" <<EOF
# =============================================================================
# Ansible Vault：WireGuard Hub 私钥（加密文件 — 提交 Git 的是密文）
# =============================================================================
# 解密：ansible-vault view ${WG_VAULT_FILE#${WG_REPO_ROOT}/} --vault-password-file .vault_pass
# 消费者：未来 wireguard role（server 模式）读取 wireguard_vault.hub_private_key
# =============================================================================

wireguard_vault:
  hub_private_key: "${hub_priv}"
  hub_public_key: "${hub_pub}"
  key_version: 1
  generated_by: wg-keys.sh
EOF

  wg_log "Writing encrypted vault: ${WG_VAULT_FILE}"
  # 从临时明文加密输出到 vault 文件（覆盖旧密文）
  # shellcheck disable=SC2046
  ansible-vault encrypt $(vault_password_args) "$tmp" --output "$WG_VAULT_FILE"
  rm -f "$tmp"

  wg_log "vault-encrypt-hub OK"
  wg_log "  Commit: ansible/inventories/mgmt/group_vars/all/wireguard_vault.yml"
  wg_log "  Never commit: ${WG_HUB_PRIVATE} or .vault_pass"
  wg_log "  GitHub Secret: ANSIBLE_VAULT_PASSWORD = contents of .vault_pass"
}

cmd_vault_view() {
  command -v ansible-vault >/dev/null 2>&1 || wg_die "ansible-vault not found"
  [[ -f "$WG_VAULT_FILE" ]] || wg_die "missing ${WG_VAULT_FILE}; run: vault-encrypt-hub"
  # shellcheck disable=SC2046
  ansible-vault view $(vault_password_args) "$WG_VAULT_FILE"
}

# -----------------------------------------------------------------------------
# list / check-deps / hints / all-hub
# -----------------------------------------------------------------------------
cmd_list() {
  wg_ensure_keys_dir
  wg_log "WireGuard keys directory: ${WG_KEYS_DIR}"
  printf '  %-20s %-8s %-8s\n' "NAME" "PRIVATE" "PUBLIC"
  if [[ -f "$WG_HUB_PRIVATE" || -f "$WG_HUB_PUBLIC" ]]; then
    printf '  %-20s %-8s %-8s\n' "hub" \
      "$([[ -f "$WG_HUB_PRIVATE" ]] && echo yes || echo no)" \
      "$([[ -f "$WG_HUB_PUBLIC" ]] && echo yes || echo no)"
  fi
  while IFS= read -r name; do
    [[ "$name" == "hub" ]] && continue
    local priv pub
    priv="$(wg_peer_private "$name")"
    pub="$(wg_peer_public "$name")"
    printf '  %-20s %-8s %-8s\n' "$name" \
      "$([[ -f "$priv" ]] && echo yes || echo no)" \
      "$([[ -f "$pub" ]] && echo yes || echo no)"
  done < <(read_planned_peer_names 2>/dev/null || true)

  if [[ -f "$WG_VAULT_FILE" ]]; then
    wg_log "Vault file: ${WG_VAULT_FILE} (encrypted)"
  else
    wg_warn "Vault file not created yet; run: vault-encrypt-hub"
  fi
}

cmd_check_deps() {
  wg_check_deps
  if command -v ansible-vault >/dev/null 2>&1; then
    wg_log "ansible-vault: OK"
  else
    wg_warn "ansible-vault not found (optional until vault-encrypt-hub); run: make setup"
  fi
  if python3 -c "import yaml" 2>/dev/null; then
    wg_log "python3 PyYAML: OK"
  else
    wg_warn "python3 PyYAML not found (required for sync-inventory)"
  fi
  wg_log "check-deps OK"
}

cmd_github_hints() {
  cat <<EOF

WireGuard 密钥 — GitHub / 本地保管清单
======================================

Git 可提交:
  - ansible/keys/wireguard/hub.pub
  - ansible/keys/wireguard/<peer>.pub
  - ansible/inventories/mgmt/group_vars/all/wireguard.yml  (含 hub_public_key / peer public_key)
  - ansible/inventories/mgmt/group_vars/all/wireguard_vault.yml (ansible-vault 加密后)

切勿提交:
  - ansible/keys/wireguard/*.private
  - .vault_pass
  - 明文 Hub 私钥

GitHub Environment (dev / mgmt) → Secrets:
  ANSIBLE_VAULT_PASSWORD
    与本地 .vault_pass 内容相同，供 deploy.yml 解密 vault/wireguard.yml

Hub 私钥两份保管（冗余）:
  1. 本地 gitignored: ${WG_HUB_PRIVATE}
  2. Vault 加密:      ${WG_VAULT_FILE#${WG_REPO_ROOT}/}

Peer 私钥:
  - 生成后复制到对应 ECS 的 /etc/wireguard/（实施 wireguard-peer playbook 时）
  - 笔记本 Peer 私钥仅保留在运维笔记本

下一步（实施 WG Server 时，非本期密钥脚本范围）:
  - wireguard role + wireguard-hub.yml
  - 各 Peer 运行 wireguard-peer.yml

EOF
}

cmd_all_hub() {
  cmd_check_deps
  cmd_generate_hub
  cmd_verify_hub
  cmd_sync_inventory
  echo ""
  cmd_github_hints
  echo ""
  wg_log "Recommended next: ./scripts/wireguard/wg-keys.sh vault-encrypt-hub"
  wg_log "Then: git add hub.pub wireguard.yml vault/wireguard.yml && make ci"
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    check-deps) cmd_check_deps ;;
    generate-hub) cmd_generate_hub ;;
    verify-hub) cmd_verify_hub ;;
    show-hub-pub) cmd_show_hub_pub ;;
    generate-peer) cmd_generate_peer "${1:-}" ;;
    verify-peer) cmd_verify_peer "${1:-}" ;;
    sync-inventory) cmd_sync_inventory ;;
    vault-encrypt-hub) cmd_vault_encrypt_hub ;;
    vault-view) cmd_vault_view ;;
    list) cmd_list ;;
    github-hints) cmd_github_hints ;;
    all-hub) cmd_all_hub ;;
  -h | --help | help) usage ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
