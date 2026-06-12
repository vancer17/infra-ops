#!/usr/bin/env bash
# =============================================================================
# scripts/ci/inventory-check-mgmt.sh — Mgmt Inventory 解析与连通性地址校验
# =============================================================================
#
# 【用途】
#   在修改 inventories/mgmt/ 后验证：
#     1. mgmt inventory 可被 ansible-inventory 正确解析
#     2. hub-01 的 ansible_host / ansible_user 经 Jinja2 展开后为预期值
#     3. CI 与 Hub 同 VPC 时 ansible_host 优先私网；跨 VPC 时禁止误用私网
#
# 【与 inventory-check.sh 的分工】
#   inventory-check.sh      → inventories/dev/
#   inventory-check-mgmt.sh → inventories/mgmt/（本脚本）
#
# 【用法】
#   ./scripts/ci/inventory-check-mgmt.sh
#   make inventory-mgmt
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ci_require_cmd ansible-inventory
ci_require_cmd ansible

MGMT_INVENTORY="${CI_ANSIBLE_INVENTORY_MGMT}"

# -----------------------------------------------------------------------------
# resolved_host_var — 获取已渲染的 inventory 变量（与 dev 版脚本同源逻辑）
# -----------------------------------------------------------------------------
resolved_host_var() {
  local host_name="$1"
  local var_name="$2"

  ci_cd ansible "${host_name}" \
    -i "${MGMT_INVENTORY}" \
    -m ansible.builtin.debug \
    -a "var=${var_name}" \
    -c local \
    2>/dev/null | python3 -c "
import json, re, sys

host = '''${host_name}'''
var_name = '''${var_name}'''
text = sys.stdin.read()
match = re.search(r'=>\s*(\{.*\})\s*$', text, re.DOTALL)
if not match:
    sys.exit(1)
payload = json.loads(match.group(1))
val = payload.get(var_name, '')
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

is_private_ip() {
  local ip="$1"
  [[ "$ip" =~ ^10\. ]] && return 0
  [[ "$ip" =~ ^192\.168\. ]] && return 0
  [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && return 0
  return 1
}

# -----------------------------------------------------------------------------
# check_ci_hub_connectivity — CI 到 Hub 的 ansible_host 策略门禁
# -----------------------------------------------------------------------------
check_ci_hub_connectivity() {
  local host_name="$1"
  local ansible_host="$2"
  local same_vpc
  local access_mode

  same_vpc="$(resolved_host_var "${host_name}" "ci_connectivity.same_vpc_as_ci")"
  same_vpc="${same_vpc:-false}"
  access_mode="$(resolved_host_var "${host_name}" "ci_connectivity.access_mode")"
  access_mode="${access_mode:-public}"

  if [[ "${access_mode}" == "wireguard" ]]; then
    if [[ ! "${ansible_host}" =~ ^10\.200\. ]]; then
      ci_log "WARN: host ${host_name}: access_mode=wireguard 但 ansible_host=${ansible_host} 非 10.200.x.x（请确认隧道已上线）"
    fi
    return 0
  fi

  if [[ "${same_vpc}" == "false" ]] && is_private_ip "${ansible_host}"; then
    ci_die "host ${host_name}: CI 与 Hub 跨 VPC，ansible_host 不能使用私网: ${ansible_host}"
  fi

  if [[ "${same_vpc}" == "true" ]] && [[ "${ansible_host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && ! is_private_ip "${ansible_host}"; then
    ci_log "WARN: host ${host_name}: same_vpc_as_ci=true 但 ansible_host 为公网 ${ansible_host}，请确认是否应使用 Hub 私网"
  fi
}

ci_log "Mgmt inventory graph: ${MGMT_INVENTORY}"
ci_cd ansible-inventory -i "${MGMT_INVENTORY}" --graph

mapfile -t mgmt_hosts < <(
  ci_cd ansible mgmt -i "${MGMT_INVENTORY}" --list-hosts 2>/dev/null \
    | awk '/^[[:space:]]+hub-/ { print $1 }' \
    | sort -u
)

if [[ ${#mgmt_hosts[@]} -eq 0 ]]; then
  ci_die "no hosts found in mgmt group (check ansible/inventories/mgmt/hosts.yml)"
fi

ci_log "Checking ${#mgmt_hosts[@]} host(s) in mgmt group..."

for host_name in "${mgmt_hosts[@]}"; do
  ansible_host="$(resolved_host_var "${host_name}" "ansible_host")"
  ansible_user="$(resolved_host_var "${host_name}" "ansible_user")"
  planned_wg="$(resolved_host_var "${host_name}" "wireguard.hub_address")"

  [[ -n "${ansible_host}" ]] || ci_die "host ${host_name}: ansible_host is empty"
  [[ "${ansible_host}" != *"{{"* ]] || ci_die "host ${host_name}: ansible_host has unresolved Jinja2"

  ci_log "  ${host_name}: ansible_user=${ansible_user:-<unset>} ansible_host=${ansible_host} planned_wg=${planned_wg:-<unset>}"
  check_ci_hub_connectivity "${host_name}" "${ansible_host}"

  wireguard_enabled="$(resolved_host_var "${host_name}" "wireguard.enabled")"
  ci_log "  ${host_name}: wireguard.enabled=${wireguard_enabled:-<unset>}"
done

ci_log "inventory-check-mgmt OK"
