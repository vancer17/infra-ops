#!/usr/bin/env bash
# Dev ECS Bootstrap 入口：preflight → apply → verify
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INVENTORY="${ANSIBLE_INVENTORY:-${ROOT}/ansible/inventories/dev/}"
PLAYBOOK="${ROOT}/ansible/playbooks/bootstrap.yml"
LIMIT="${ANSIBLE_LIMIT:-dev-01}"

# 与 ansible.cfg host_key_checking=False 对齐；BatchMode 避免 CI 无人值守挂起
SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)

usage() {
  cat <<EOF
Usage: $(basename "$0") <preflight|apply|verify|all> [host]

  preflight  检查台账、SSH、Ansible 依赖、跨 VPC 连通地址
  apply      执行 bootstrap.yml
  verify     运行主机验收检查
  all        preflight → apply → verify

Environment:
  ANSIBLE_INVENTORY  默认 ansible/inventories/dev/
  ANSIBLE_LIMIT      默认 dev-01
EOF
}

asset_file() {
  echo "${ROOT}/docs/assets/${LIMIT}.yaml"
}

inventory_host_json() {
  ansible-inventory -i "$INVENTORY" --host "$LIMIT" 2>/dev/null
}

# 读取 inventory 合并变量；支持点号路径，如 ci_connectivity.same_vpc_as_dev
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

check_cross_vpc_host() {
  local host="$1"
  local same_vpc
  same_vpc="$(host_var ci_connectivity.same_vpc_as_dev)"
  same_vpc="${same_vpc:-false}"

  if [[ "$same_vpc" == "false" && "$host" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
    echo "ERROR: CI 与 Dev 跨 VPC，ansible_host 不能使用私网地址: ${host}"
    echo "       请检查 host_vars/${LIMIT}.yml 与 group_vars/all/network.yml"
    exit 1
  fi

  if [[ "$same_vpc" == "true" && "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && ! "$host" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
    echo "WARN: same_vpc_as_dev=true 但 ansible_host 为公网 ${host}，请确认是否应使用内网地址"
  fi
}

check_asset_ledger() {
  local asset
  asset="$(asset_file)"
  if [[ ! -f "$asset" ]]; then
    echo "WARN: missing asset ledger ${asset} (optional for ${LIMIT})"
    return 0
  fi

  if ! grep -Eq 'private_ip: "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' "$asset"; then
    echo "WARN: ${LIMIT} private_ip may be unset in ${asset}"
  fi
  if ! grep -qE 'bootstrap_status: "(sg_done|bootstrap_done)"' "$asset"; then
    echo "WARN: complete step 1.1 (sg_done) before bootstrap on ${LIMIT}"
  fi
}

preflight() {
  check_asset_ledger

  command -v ansible-playbook >/dev/null || { echo "ERROR: ansible-playbook not found"; exit 1; }
  command -v ansible-inventory >/dev/null || { echo "ERROR: ansible-inventory not found"; exit 1; }

  ansible-galaxy collection install -r "${ROOT}/ansible/requirements.yml" --force-with-deps 2>/dev/null || true

  local host_ip user
  host_ip="$(resolve_ansible_host)"
  user="$(resolve_ansible_user)"
  check_cross_vpc_host "$host_ip"

  echo "SSH probe: ${user}@${host_ip} (limit=${LIMIT})"
  ssh "${SSH_OPTS[@]}" "${user}@${host_ip}" true \
    || { echo "ERROR: cannot SSH to ${LIMIT}"; exit 1; }
  echo "preflight OK"
}

apply() {
  ansible-playbook "$PLAYBOOK" -i "$INVENTORY" --limit "$LIMIT" "$@"
  echo "apply OK (limit=$LIMIT)"
}

verify() {
  local host_ip user rds_host
  host_ip="$(resolve_ansible_host)"
  user="$(resolve_ansible_user)"
  rds_host="$(host_var rds.host)"

  ssh "${SSH_OPTS[@]}" "${user}@${host_ip}" bash -s "$rds_host" <<'REMOTE'
set -euo pipefail
rds_host="${1:-}"
timedatectl | grep -q 'Time zone: Asia/Shanghai'
id deploy >/dev/null
id jump_ops >/dev/null
docker run --rm hello-world >/dev/null
test -d /opt/app/compose
if command -v ufw >/dev/null 2>&1; then ufw status | grep -qi inactive; fi
if [[ -n "$rds_host" ]]; then
  nc -z -w 5 "$rds_host" 3306
fi
echo "verify OK on $(hostname)"
REMOTE
}

cmd="${1:-}"
shift || true
case "$cmd" in
  preflight) preflight ;;
  apply) apply "$@" ;;
  verify) verify ;;
  all) preflight; apply "$@"; verify ;;
  *) usage; exit 1 ;;
esac
