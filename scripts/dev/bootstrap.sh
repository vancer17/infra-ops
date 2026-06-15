#!/usr/bin/env bash
# =============================================================================
# Dev/Mgmt ECS Bootstrap 入口：preflight → apply → verify
# =============================================================================
#
# 支持 inventories/dev/ 与 inventories/mgmt/（通过 ANSIBLE_INVENTORY 切换）。
# 同机部署（如 ci-01 与 dev-01 同 ECS）时自动使用 ansible_connection=local。
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INVENTORY="${ANSIBLE_INVENTORY:-${ROOT}/ansible/inventories/dev/}"
PLAYBOOK="${ROOT}/ansible/playbooks/bootstrap.yml"
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
Usage: $(basename "$0") <preflight|apply|verify|all> [host]

  preflight  检查台账、Ansible 依赖、SSH/同机探测
  apply      执行 bootstrap.yml（同机时自动 -e ansible_connection=local）
  verify     运行主机验收检查
  all        preflight → apply → verify

Environment:
  ANSIBLE_INVENTORY  默认 ansible/inventories/dev/
  ANSIBLE_LIMIT      默认 dev-01（也可作为第二个参数传入）

Examples:
  $(basename "$0") apply dev-01
  ANSIBLE_INVENTORY=ansible/inventories/mgmt/ $(basename "$0") apply hub-01

Do NOT:
  $(basename "$0") apply -e ansible_connection=local
  (use plain "apply" on colocated hosts; script adds -e automatically)
EOF
}

asset_file() {
  echo "${ROOT}/docs/assets/${LIMIT}.yaml"
}

host_var() {
  resolve_inventory_var "$INVENTORY" "$LIMIT" "$1"
}

check_cross_vpc_host() {
  local host="$1"
  local same_vpc
  # dev inventory: same_vpc_as_dev；mgmt inventory: same_vpc_as_ci
  same_vpc="$(host_var ci_connectivity.same_vpc_as_dev 2>/dev/null || true)"
  if [[ -z "$same_vpc" ]]; then
    same_vpc="$(host_var ci_connectivity.same_vpc_as_ci 2>/dev/null || true)"
  fi
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

  if ! grep -Eq 'private_ip:\s*"?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$asset"; then
    echo "WARN: ${LIMIT} private_ip may be unset in ${asset}"
  fi
  if ! grep -qE 'bootstrap_status:\s*"? *(sg_done|bootstrap_done)"?' "$asset"; then
    echo "WARN: complete step 1.1 (sg_done) before bootstrap on ${LIMIT}"
  fi
}

# 读取 inventory 中 docker_install（Hub 为 false，Dev 为 true）
resolve_docker_install() {
  local v
  v="$(host_var docker_install 2>/dev/null || true)"
  if [[ -z "$v" ]]; then
    echo "true"
  else
    echo "$v"
  fi
}

# 是否执行 verify 阶段的 RDS 3306 探测（Hub：false；Dev：true，见 group_vars/bootstrap.yml）
resolve_rds_verify() {
  local v
  v="$(host_var rds_verify 2>/dev/null || true)"
  case "${v,,}" in
    true|yes|1) echo "true" ;;
    *) echo "false" ;;
  esac
}

# 仅在 rds_verify=true 且 rds.host 为合法 FQDN 时返回主机名，否则空
resolve_rds_host_for_verify() {
  local rds_host
  [[ "$(resolve_rds_verify)" == "true" ]] || return 0
  rds_host="$(host_var rds.host 2>/dev/null || true)"
  is_valid_inventory_value "$rds_host" || return 0
  echo "$rds_host"
}

# Bootstrap verify 使用的 Docker smoke 镜像（见 group_vars/bootstrap.yml）
resolve_docker_smoke_image() {
  local img
  img="$(host_var bootstrap_docker_smoke_image 2>/dev/null || true)"
  if is_valid_inventory_value "$img"; then
    echo "$img"
  else
    echo "hello-world"
  fi
}

run_verify_checks() {
  local rds_host="${1:-}"
  local docker_install="${2:-true}"
  local smoke_image="${3:-hello-world}"
  timedatectl | grep -q 'Time zone: Asia/Shanghai'
  id deploy >/dev/null
  id jump_ops >/dev/null
  if [[ "$docker_install" == "true" ]]; then
    if [[ -f /var/run/docker.sock ]] || command -v docker >/dev/null 2>&1; then
      docker run --rm "$smoke_image" >/dev/null
    fi
  fi
  test -d /opt/app/compose || test -d /opt/mgmt
  if command -v ufw >/dev/null 2>&1; then ufw status | grep -qi inactive; fi
  if [[ -n "$rds_host" ]]; then
    nc -z -w 5 "$rds_host" 3306
  fi
  echo "verify OK on $(hostname) (docker_install=${docker_install})"
}

preflight() {
  check_asset_ledger

  command -v ansible-playbook >/dev/null || { echo "ERROR: ansible-playbook not found; run: make setup" >&2; exit 1; }
  command -v ansible >/dev/null || { echo "ERROR: ansible not found; run: make setup" >&2; exit 1; }

  ansible-galaxy collection install -r "${ROOT}/ansible/requirements.yml" --force-with-deps 2>/dev/null || true

  local host_ip user
  host_ip="$(resolve_ansible_host "$INVENTORY" "$LIMIT")" || exit 1
  user="$(resolve_ansible_user "$INVENTORY" "$LIMIT")"
  check_cross_vpc_host "$host_ip"

  if is_colocated_target "$host_ip"; then
    echo "Colocated target: ${LIMIT}@${host_ip} — skip SSH probe (apply will use ansible_connection=local)"
    echo "preflight OK"
    return 0
  fi

  echo "SSH probe: ${user}@${host_ip} (limit=${LIMIT})"
  ssh "${SSH_OPTS[@]}" "${user}@${host_ip}" true \
    || { echo "ERROR: cannot SSH to ${LIMIT}"; exit 1; }
  echo "preflight OK"
}

apply() {
  local -a colocated_args=()
  mapfile -t colocated_args < <(ansible_colocated_extra_args "$INVENTORY" "$LIMIT" "$@")

  if [[ ${#colocated_args[@]} -gt 0 ]]; then
    echo "Colocated: applying with ${colocated_args[*]}"
  fi

  ansible-playbook "$PLAYBOOK" -i "$INVENTORY" --limit "$LIMIT" \
    "${colocated_args[@]}" "$@"
  echo "apply OK (limit=$LIMIT)"
}

verify() {
  local host_ip user rds_host docker_install rds_verify smoke_image
  host_ip="$(resolve_ansible_host "$INVENTORY" "$LIMIT")" || exit 1
  user="$(resolve_ansible_user "$INVENTORY" "$LIMIT")"
  rds_verify="$(resolve_rds_verify)"
  rds_host="$(resolve_rds_host_for_verify)"
  docker_install="$(resolve_docker_install)"
  smoke_image="$(resolve_docker_smoke_image)"

  if is_colocated_target "$host_ip"; then
    echo "Colocated verify on ${host_ip} (docker_install=${docker_install}, rds_verify=${rds_verify})"
    echo "Docker smoke image: ${smoke_image}"
    run_verify_checks "$rds_host" "$docker_install" "$smoke_image"
    return 0
  fi

  echo "Remote verify: ${user}@${host_ip} (docker_install=${docker_install}, rds_verify=${rds_verify})"
  if [[ -n "$rds_host" ]]; then
    echo "RDS check: ${rds_host}:3306"
  fi
  echo "Docker smoke image: ${smoke_image}"
  # docker_install 必须在前：SSH 会丢弃空 positional arg；若 rds_host 为空而 docker_install 在后，
  # 远程 bash 会把 "false"/"true" 当成 $1（rds_host），误触发 nc。
  ssh "${SSH_OPTS[@]}" "${user}@${host_ip}" bash -s "$docker_install" "$rds_host" "$smoke_image" <<'REMOTE'
set -euo pipefail
docker_install="${1:-true}"
rds_host="${2:-}"
smoke_image="${3:-hello-world}"
timedatectl | grep -q 'Time zone: Asia/Shanghai'
id deploy >/dev/null
id jump_ops >/dev/null
if [[ "$docker_install" == "true" ]]; then
  if command -v docker >/dev/null 2>&1; then
    docker run --rm "$smoke_image" >/dev/null
  fi
fi
test -d /opt/app/compose || test -d /opt/mgmt
if command -v ufw >/dev/null 2>&1; then ufw status | grep -qi inactive; fi
if [[ -n "$rds_host" ]]; then
  nc -z -w 5 "$rds_host" 3306
fi
echo "verify OK on $(hostname)"
REMOTE
}

main() {
  local cmd="${1:-}"
  shift || true

  # 仅将非选项参数视为主机名；勿把 -e/-i 等 ansible-playbook 标志误当作 LIMIT
  if [[ -n "${1:-}" && "$1" != --* && "$1" != -* ]]; then
    LIMIT="$1"
    shift
  fi
  export ANSIBLE_LIMIT="$LIMIT"

  case "$cmd" in
    preflight) preflight ;;
    apply) apply "$@" ;;
    verify) verify ;;
    all) preflight; apply "$@"; verify ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
