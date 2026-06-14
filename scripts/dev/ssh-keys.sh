#!/usr/bin/env bash
# =============================================================================
# ECS SSH 密钥体系（阶段 1.3）：generate → distribute → verify → steady
# =============================================================================
#
# 支持 dev 与 mgmt inventory（ANSIBLE_INVENTORY）。
# distribute/steady 在同机部署时自动追加 ansible_connection=local。
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INVENTORY="${ANSIBLE_INVENTORY:-${ROOT}/ansible/inventories/dev/}"
PLAYBOOK="${ROOT}/ansible/playbooks/ssh-keys.yml"
KEY_DIR="${ROOT}/ansible/keys"
PRIVATE_KEY="${KEY_DIR}/infra-ci-deploy"
PUBLIC_KEY="${KEY_DIR}/infra-ci-deploy.pub"
KEY_COMMENT="${SSH_CI_KEY_COMMENT:-infra-ci-deploy@121.41.58.20}"
LIMIT="${ANSIBLE_LIMIT:-dev-01}"

# shellcheck source=scripts/dev/lib/inventory-resolve.sh
source "${ROOT}/scripts/dev/lib/inventory-resolve.sh"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [host]

Commands:
  generate      在 CI 机生成 ED25519 密钥对（ansible/keys/infra-ci-deploy*）
  preflight     检查 1.2 完成、root SSH、公钥文件、deploy 用户
  distribute    Ansible 分发公钥到 deploy@authorized_keys
  verify        用私钥验证 deploy@ 登录
  known-hosts   输出 GitHub Secret ANSIBLE_SSH_KNOWN_HOSTS 内容
  github-hints  输出 GitHub Secrets 配置说明（私钥勿提交 Git）
  steady        收紧 SSH（禁止 root），并切换 inventory 为 deploy 用户
  mark-done     更新台账 bootstrap_status（可选）
  all           preflight → distribute → verify → known-hosts → github-hints

Environment:
  ANSIBLE_INVENTORY   默认 ansible/inventories/dev/
  ANSIBLE_LIMIT       默认 dev-01
  SSH_CI_KEY_COMMENT  公钥注释

Examples:
  $(basename "$0") generate
  $(basename "$0") all dev-01
  ANSIBLE_INVENTORY=ansible/inventories/mgmt/ $(basename "$0") all hub-01
EOF
}

host_var() {
  resolve_inventory_var "$INVENTORY" "$LIMIT" "$1"
}

resolve_ansible_host() {
  local host
  host="$(host_var ansible_host)"
  [[ -n "$host" ]] || { echo "ERROR: cannot resolve ansible_host for ${LIMIT}"; exit 1; }
  [[ "$host" != *"{{"* ]] || {
    echo "ERROR: ansible_host not rendered for ${LIMIT}" >&2
    exit 1
  }
  echo "$host"
}

resolve_ansible_user() {
  local user
  user="$(host_var ansible_user)"
  echo "${user:-root}"
}

ssh_yml_file() {
  echo "${INVENTORY%/}/group_vars/all/ssh.yml"
}

asset_file() {
  echo "${ROOT}/docs/assets/${LIMIT}.yaml"
}

check_bootstrap_done() {
  local asset
  asset="$(asset_file)"
  if [[ ! -f "$asset" ]]; then
    echo "WARN: missing ${asset}; ensure step 1.2 bootstrap completed"
    return 0
  fi
  if ! grep -qE 'bootstrap_status:\s*"? *(bootstrap_done|sg_done|ssh_done)"?' "$asset"; then
    echo "WARN: ${LIMIT} may not have completed 1.2 (bootstrap_status not bootstrap_done/sg_done/ssh_done)"
  fi
}

cmd_generate() {
  mkdir -p "$KEY_DIR"
  if [[ -f "$PRIVATE_KEY" ]]; then
    echo "ERROR: ${PRIVATE_KEY} already exists; remove manually to regenerate"
    exit 1
  fi
  ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -C "$KEY_COMMENT" -N ""
  chmod 600 "$PRIVATE_KEY"
  chmod 644 "$PUBLIC_KEY"
  echo "Generated:"
  echo "  private: ${PRIVATE_KEY}  (gitignored — copy to GitHub Secret ANSIBLE_SSH_PRIVATE_KEY)"
  echo "  public:  ${PUBLIC_KEY}   (commit to Git)"
  ssh-keygen -lf "$PUBLIC_KEY"
}

cmd_preflight() {
  check_bootstrap_done
  command -v ansible-playbook >/dev/null || { echo "ERROR: ansible-playbook not found" >&2; exit 1; }
  command -v ansible >/dev/null 2>&1 || { echo "ERROR: ansible not found; run: make setup" >&2; exit 1; }
  [[ -f "$PUBLIC_KEY" ]] || { echo "ERROR: missing ${PUBLIC_KEY}; run: $(basename "$0") generate"; exit 1; }

  local host_ip
  host_ip="$(resolve_ansible_host)"

  if is_colocated_target "$host_ip"; then
    echo "Colocated: checking deploy user locally (limit=${LIMIT})"
    id deploy >/dev/null && echo "deploy user OK"
  else
    echo "Root SSH probe: root@${host_ip} (limit=${LIMIT})"
    ssh "${SSH_OPTS[@]}" "root@${host_ip}" 'id deploy >/dev/null && echo deploy user OK'
  fi
  echo "preflight OK"
}

cmd_distribute() {
  local -a colocated_args=()
  mapfile -t colocated_args < <(ansible_colocated_extra_args "$INVENTORY" "$LIMIT" "$@")

  ansible-galaxy collection install -r "${ROOT}/ansible/requirements.yml" --force-with-deps 2>/dev/null || true
  ansible-playbook "$PLAYBOOK" -i "$INVENTORY" --limit "$LIMIT" --tags distribute \
    "${colocated_args[@]}" "$@"
  echo "distribute OK (limit=${LIMIT})"
}

cmd_verify() {
  [[ -f "$PRIVATE_KEY" ]] || { echo "ERROR: missing ${PRIVATE_KEY}"; exit 1; }
  local host_ip
  host_ip="$(resolve_ansible_host)"

  echo "Deploy SSH probe: deploy@${host_ip}"
  ssh "${SSH_OPTS[@]}" -i "$PRIVATE_KEY" "deploy@${host_ip}" \
    'whoami && id && (test -d /opt/app/compose || test -d /opt/mgmt)'
  echo "verify OK"
}

cmd_known_hosts() {
  local host_ip
  host_ip="$(resolve_ansible_host)"
  echo "# Paste into GitHub Environment dev → Secret ANSIBLE_SSH_KNOWN_HOSTS"
  echo "# Host: ${LIMIT} (${host_ip})"
  ssh-keyscan -H "$host_ip" 2>/dev/null
}

cmd_github_hints() {
  [[ -f "$PRIVATE_KEY" ]] || { echo "ERROR: missing ${PRIVATE_KEY}; run generate first"; exit 1; }
  cat <<EOF

GitHub Environment: dev → Secrets
---------------------------------
ANSIBLE_SSH_PRIVATE_KEY
  $(basename "$PRIVATE_KEY") full content (including BEGIN/END lines):

$(cat "$PRIVATE_KEY")

ANSIBLE_SSH_KNOWN_HOSTS
  Run: $(basename "$0") known-hosts ${LIMIT}

Security:
  - Never commit ${PRIVATE_KEY}
  - Public key ${PUBLIC_KEY} may be committed
  - Rotate keys if private key was exposed

EOF
}

update_ssh_yml() {
  local key="$1"
  local value="$2"
  local file
  file="$(ssh_yml_file)"
  python3 - "$file" "$key" "$value" <<'PY'
import pathlib, re, sys
path, key, value = sys.argv[1:4]
text = pathlib.Path(path).read_text()
pattern = rf"^({re.escape(key)}:\s*).*$"
replacement = rf"\g<1>{value}"
new_text, n = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
if n == 0:
    raise SystemExit(f"key not found in {path}: {key}")
pathlib.Path(path).write_text(new_text)
print(f"Updated {key}={value} in {path}")
PY
}

cmd_steady() {
  local -a colocated_args=()
  mapfile -t colocated_args < <(ansible_colocated_extra_args "$INVENTORY" "$LIMIT" "$@")

  cmd_verify
  ansible-playbook "$PLAYBOOK" -i "$INVENTORY" --limit "$LIMIT" --tags steady \
    -e ssh_phase=steady "${colocated_args[@]}" "$@"
  update_ssh_yml "ssh_phase" "steady"
  update_ssh_yml "ssh_inventory_user" "deploy"
  update_ssh_yml "ssh_keys_configured" "true"
  echo "steady OK — future Ansible/CI should use deploy@${LIMIT}"
  echo "NOTE: root SSH is now disabled; keep ${PRIVATE_KEY} safe"
}

cmd_mark_done() {
  local asset
  asset="$(asset_file)"
  [[ -f "$asset" ]] || { echo "WARN: no asset file ${asset}"; return 0; }
  if grep -q 'bootstrap_status:' "$asset"; then
    sed -i 's/bootstrap_status: .*/bootstrap_status: "ssh_done"/' "$asset"
    echo "Updated ${asset} bootstrap_status=ssh_done"
  fi
}

cmd_all() {
  cmd_preflight
  cmd_distribute "$@"
  cmd_verify
  cmd_known_hosts
  echo ""
  cmd_github_hints
  echo ""
  echo "Next: review output above, set GitHub Secrets, then run:"
  echo "  $(basename "$0") steady ${LIMIT}"
}

main() {
  local cmd="${1:-}"
  shift || true

  if [[ -n "${1:-}" && "$1" != --* ]]; then
    LIMIT="$1"
    shift
  fi
  export ANSIBLE_LIMIT="$LIMIT"

  case "$cmd" in
    generate) cmd_generate ;;
    preflight) cmd_preflight ;;
    distribute) cmd_distribute "$@" ;;
    verify) cmd_verify ;;
    known-hosts) cmd_known_hosts ;;
    github-hints) cmd_github_hints ;;
    steady) cmd_steady "$@" ;;
    mark-done) cmd_mark_done ;;
    all) cmd_all "$@" ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
