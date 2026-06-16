#!/usr/bin/env bash
# =============================================================================
# scripts/ci/inventory-check.sh — Dev Inventory 解析与连通性地址校验
# =============================================================================
#
# 【用途】
#   在修改 inventories/dev/ 后快速验证：
#     1. inventory 目录可被 ansible-inventory 正确解析（分组结构）
#     2. 各主机 ansible_host / ansible_user 经 Jinja2 展开后为预期值
#     3. CI 跨 VPC 场景下 ansible_host 未误用私网地址（与 bootstrap.sh preflight 对齐）
#
# 【为何不用 ansible-inventory --host】
#   host_vars 中含 Jinja2 模板时，--host 输出的是未渲染字符串；
#   本脚本用 `ansible <host> -m debug -c local` 获取 Playbook 运行时同源的最终变量。
#
# 【与 ansible-syntax.sh 的分工】
#   ansible-syntax.sh Step 3 做轻量 graph + host 存在性抽查；
#   本脚本做「可读输出 + 跨 VPC 门禁」，供 make inventory 单独调用。
#
# 【前置依赖】
#   ansible、Galaxy collections
#   → ./scripts/ci/install-deps.sh ansible  或  make setup
#
# 【用法】
#   ./scripts/ci/inventory-check.sh
#   make inventory
#
# 【注意】
#   纯静态检查，不发起 SSH；实机连通性见 scripts/dev/bootstrap.sh preflight
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ci_require_cmd ansible-inventory
ci_require_cmd ansible

# -----------------------------------------------------------------------------
# resolved_host_var — 通过 ansible debug + local 连接获取已渲染的 inventory 变量
# -----------------------------------------------------------------------------
# 参数：$1=主机名  $2=变量名（支持点号路径，如 ci_connectivity.same_vpc_as_dev）
resolved_host_var() {
  local host_name="$1"
  local var_name="$2"

  ci_cd ansible "${host_name}" \
    -i "${CI_ANSIBLE_INVENTORY}" \
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

# -----------------------------------------------------------------------------
# is_private_ip — 判断 IPv4 是否为 RFC1918 私网段
# -----------------------------------------------------------------------------
is_private_ip() {
  local ip="$1"
  [[ "$ip" =~ ^10\. ]] && return 0
  [[ "$ip" =~ ^192\.168\. ]] && return 0
  [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && return 0
  return 1
}

# -----------------------------------------------------------------------------
# check_cross_vpc_host — CI 与 Dev 跨 VPC 时 ansible_host 必须为公网可达地址
# -----------------------------------------------------------------------------
check_cross_vpc_host() {
  local host_name="$1"
  local ansible_host="$2"
  local same_vpc

  same_vpc="$(resolved_host_var "${host_name}" "ci_connectivity.same_vpc_as_dev")"
  same_vpc="${same_vpc:-false}"

  if [[ "${same_vpc}" == "false" ]] && is_private_ip "${ansible_host}"; then
    ci_die "host ${host_name}: CI 与 Dev 跨 VPC，ansible_host 不能使用私网地址: ${ansible_host}（见 group_vars/all/network.yml）"
  fi

  if [[ "${same_vpc}" == "true" ]] && [[ "${ansible_host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && ! is_private_ip "${ansible_host}"; then
    ci_log "WARN: host ${host_name}: same_vpc_as_dev=true 但 ansible_host 为公网 ${ansible_host}，请确认是否应使用内网地址"
  fi
}

# -----------------------------------------------------------------------------
# Step 1 — 打印 inventory 分组树
# -----------------------------------------------------------------------------
ci_log "Inventory graph: ${CI_ANSIBLE_INVENTORY}"
ci_cd ansible-inventory -i "${CI_ANSIBLE_INVENTORY}" --graph

# -----------------------------------------------------------------------------
# Step 2 — 枚举 dev 组主机（ansible dev --list-hosts）
# -----------------------------------------------------------------------------
mapfile -t dev_hosts < <(
  ci_cd ansible dev -i "${CI_ANSIBLE_INVENTORY}" --list-hosts 2>/dev/null \
    | awk '/^[[:space:]]+dev-/ { print $1 }' \
    | sort -u
)

if [[ ${#dev_hosts[@]} -eq 0 ]]; then
  ci_die "no hosts found in dev group (check ansible/inventories/dev/hosts.yml)"
fi

# -----------------------------------------------------------------------------
# Step 3 — 逐主机校验 ansible_host / ansible_user 与跨 VPC 规则
# -----------------------------------------------------------------------------
ci_log "Checking ${#dev_hosts[@]} host(s) in dev group..."

for host_name in "${dev_hosts[@]}"; do
  ansible_host="$(resolved_host_var "${host_name}" "ansible_host")"
  ansible_user="$(resolved_host_var "${host_name}" "ansible_user")"

  [[ -n "${ansible_host}" ]] || ci_die "host ${host_name}: ansible_host is empty after Jinja2 merge"
  [[ "${ansible_host}" != *"{{"* ]] || ci_die "host ${host_name}: ansible_host still contains unresolved Jinja2 template"

  ci_log "  ${host_name}: ansible_user=${ansible_user:-<unset>} ansible_host=${ansible_host}"
  check_cross_vpc_host "${host_name}" "${ansible_host}"

  rds_host="$(resolved_host_var "${host_name}" "rds.host")"
  if [[ -n "${rds_host}" ]]; then
    ci_log "  ${host_name}: rds.host=${rds_host}"
  else
    ci_log "WARN: host ${host_name}: rds.host not set in merged vars"
  fi

  # ---------------------------------------------------------------------------
  # 业务 Nginx / 应用变量（阶段 2 inventory；dev-01 为网关主机）
  # ---------------------------------------------------------------------------
  nginx_app_gw="$(resolved_host_var "${host_name}" "nginx_app_gateway")"
  nginx_app_gw="${nginx_app_gw:-false}"

  if [[ "${nginx_app_gw}" == "true" ]]; then
    gw_mode="$(resolved_host_var "${host_name}" "nginx.gateway_mode")"
    nginx_upstream_port="$(resolved_host_var "${host_name}" "nginx.upstream.port")"
    app_port="$(resolved_host_var "${host_name}" "app_ports.app")"
    app_listen_port="$(resolved_host_var "${host_name}" "app.listen.port")"
    nginx_status="$(resolved_host_var "${host_name}" "nginx.status")"
    app_deploy="$(resolved_host_var "${host_name}" "app.deploy_status")"
    internal_domain="$(resolved_host_var "${host_name}" "app.domains.internal")"

    [[ "${gw_mode}" == "app" ]] || ci_die "host ${host_name}: nginx.gateway_mode must be 'app' (got ${gw_mode})"
    [[ -n "${nginx_upstream_port}" ]] || ci_die "host ${host_name}: nginx.upstream.port is empty"
    [[ -n "${app_port}" ]] || ci_die "host ${host_name}: app_ports.app is empty"
    [[ "${nginx_upstream_port}" == "${app_port}" ]] \
      || ci_die "host ${host_name}: nginx.upstream.port (${nginx_upstream_port}) != app_ports.app (${app_port})"
    [[ "${app_listen_port}" == "${app_port}" ]] \
      || ci_die "host ${host_name}: app.listen.port (${app_listen_port}) != app_ports.app (${app_port})"
    [[ "${internal_domain}" == "dev-app.internal" ]] \
      || ci_log "WARN: host ${host_name}: app.domains.internal=${internal_domain} (expected dev-app.internal)"

    ci_log "  ${host_name}: nginx.gateway_mode=${gw_mode} nginx.status=${nginx_status:-<unset>} app.deploy_status=${app_deploy:-<unset>}"
    ci_log "  ${host_name}: nginx upstream 127.0.0.1:${nginx_upstream_port} internal=${internal_domain} OK"
  fi
done

ci_log "inventory-check OK"
