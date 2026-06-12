#!/usr/bin/env bash
# Dev ECS SSH 密钥体系（阶段 1.3）：generate → distribute → verify → known-hosts → steady
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INVENTORY="${ANSIBLE_INVENTORY:-${ROOT}/ansible/inventories/dev/}"
PLAYBOOK="${ROOT}/ansible/playbooks/ssh-keys.yml"
KEY_DIR="${ROOT}/ansible/keys"
PRIVATE_KEY="${KEY_DIR}/infra-ci-deploy"
PUBLIC_KEY="${KEY_DIR}/infra-ci-deploy.pub"
KEY_COMMENT="${SSH_CI_KEY_COMMENT:-infra-ci-deploy@47.98.161.33}"
LIMIT="${ANSIBLE_LIMIT:-dev-01}"

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
  mark-done     更新台账 bootstrap_status / ssh_keys_configured（可选）
  all           preflight → distribute → verify → known-hosts → github-hints

Environment:
  ANSIBLE_INVENTORY   默认 ansible/inventories/dev/
  ANSIBLE_LIMIT       默认 dev-01
  SSH_CI_KEY_COMMENT  公钥注释，默认 infra-ci-deploy@47.98.161.33

Examples:
  $(basename "$0") generate
  $(basename "$0") all dev-01
  $(basename "$0") steady dev-01
EOF
}

inventory_host_json() {
  ansible-inventory -i "$INVENTORY" --host "$LIMIT" 2>/dev/null
}

host_var() {
  local key="$1"
  inventory_host_json | python3 -c "
import json, sys
data = json.load(sys.stdin)
key = '''${key}'''
val = data
for part in key.split('.'):
    if isinstance(val, dict):
        val = val.get(part, '')
    else:
        val = ''
        break
if isinstance(val, bool):
    print(str(val).lower())
elif isinstance(val, (dict, list)):
    print(json.dumps(val))
elif val is None:
    print('')
else:
    print(val)
"
}

resolve_ansible_host() {
  local host
  host="$(host_var ansible_host)"
  [[ -n "$host" ]] || { echo "ERROR: cannot resolve ansible_host for ${LIMIT}"; exit 1; }
  echo "$host"
}

resolve_ansible_user() {
  local user
  user="$(host_var ansible_user)"
  echo "${user:-root}"
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
  if ! grep -qE 'bootstrap_status: "(bootstrap_done|sg_done)"' "$asset"; then
    echo "WARN: ${LIMIT} may not have completed 1.2 (bootstrap_status not bootstrap_done/sg_done)"
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
  command -v ansible-playbook >/dev/null || { echo "ERROR: ansible-playbook not found"; exit 1; }
  [[ -f "$PUBLIC_KEY" ]] || { echo "ERROR: missing ${PUBLIC_KEY}; run: $(basename "$0") generate"; exit 1; }

  echo "Root SSH probe: root@${host_ip} (limit=${LIMIT})"
  ssh "${SSH_OPTS[@]}" "root@${host_ip}" 'id deploy >/dev/null && echo deploy user OK'
  echo "preflight OK"
}

cmd_distribute() {
  ansible-galaxy collection install -r "${ROOT}/ansible/requirements.yml" --force-with-deps 2>/dev/null || true
  ansible-playbook "$PLAYBOOK" -i "$INVENTORY" --limit "$LIMIT" --tags distribute "$@"
  echo "distribute OK (limit=${LIMIT})"
}

cmd_verify() {
  [[ -f "$PRIVATE_KEY" ]] || { echo "ERROR: missing ${PRIVATE_KEY}"; exit 1; }
  local host_ip
  host_ip="$(resolve_ansible_host)"

  echo "Deploy SSH probe: deploy@${host_ip}"
  ssh "${SSH_OPTS[@]}" -i "$PRIVATE_KEY" "deploy@${host_ip}" 'whoami && id && test -d /opt/app/compose'
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
  local file="${ROOT}/ansible/inventories/dev/group_vars/all/ssh.yml"
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
  cmd_verify
  ansible-playbook "$PLAYBOOK" -i "$INVENTORY" --limit "$LIMIT" --tags steady -e ssh_phase=steady "$@"
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
