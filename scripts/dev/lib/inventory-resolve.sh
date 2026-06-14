#!/usr/bin/env bash
# =============================================================================
# scripts/dev/lib/inventory-resolve.sh — 解析已渲染的 Ansible inventory 变量
# =============================================================================
#
# 【问题背景】
#   ansible-inventory --host 对 host_vars 中的 Jinja2 表达式（如 ansible_host）
#   常返回未渲染的模板字符串，导致 bootstrap.sh / ssh-keys.sh 的 SSH 探测失败。
#
# 【做法】
#   在控制机上以 ansible_connection=local 对 localhost 执行 debug，
#   读取 hostvars['<host>'].<key>，由 Ansible 在 play 上下文中完成模板渲染。
#
# 【用法】
#   source scripts/dev/lib/inventory-resolve.sh
#   resolve_inventory_var "$INVENTORY" "$LIMIT" ansible_host
#
# =============================================================================

if [[ -n "${INVENTORY_RESOLVE_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
INVENTORY_RESOLVE_LOADED=1

# 从 ansible debug 输出解析变量值
# shellcheck disable=SC2034  # 供 source 方使用
_resolve_debug_var() {
  local inventory="$1"
  local limit="$2"
  local var_expr="$3"

  command -v ansible >/dev/null 2>&1 || {
    echo "ERROR: ansible not found; run: make setup" >&2
    return 1
  }

  ansible localhost -i "$inventory" -m ansible.builtin.debug \
    -a "var=${var_expr}" \
    -e ansible_connection=local \
    -o 2>/dev/null | python3 -c "
import json, sys

limit = '''${limit}'''
for line in sys.stdin:
    if 'SUCCESS' not in line or '=>' not in line:
        continue
    payload = line.split('=>', 1)[1].strip()
    try:
        data = json.loads(payload)
    except json.JSONDecodeError:
        continue
    for key, val in data.items():
        if key in ('changed', 'failed', 'skipped', 'msg', 'ansible_facts'):
            continue
        if val is None:
            print('')
            sys.exit(0)
        if isinstance(val, bool):
            print(str(val).lower())
            sys.exit(0)
        if isinstance(val, (dict, list)):
            print(json.dumps(val))
            sys.exit(0)
        print(val)
        sys.exit(0)
sys.exit(1)
"
}

# 判断 Ansible debug 返回值是否为「有效变量」（非未定义/未渲染模板）
# shellcheck disable=SC2034  # 供 bootstrap.sh 等 source 方使用
is_valid_inventory_value() {
  local val="${1:-}"
  [[ -n "$val" ]] || return 1
  [[ "$val" == *"{{"* ]] && return 1
  [[ "$val" == *"VARIABLE IS NOT DEFINED!"* ]] && return 1
  [[ "$val" == *"<< error"* ]] && return 1
  return 0
}

# 读取 hostvars 中的键；支持点号路径，如 rds.host、ci_connectivity.same_vpc_as_dev
# 未定义或 Jinja 未渲染时返回空（stdout 无输出），避免脚本把 Ansible 占位符当实值使用
resolve_inventory_var() {
  local inventory="$1"
  local limit="$2"
  local key="$3"
  local var_expr="hostvars['${limit}']"
  local raw

  local part
  IFS='.' read -ra parts <<<"$key"
  for part in "${parts[@]}"; do
    var_expr="${var_expr}['${part}']"
  done

  raw="$(_resolve_debug_var "$inventory" "$limit" "$var_expr" 2>/dev/null || true)"
  if is_valid_inventory_value "$raw"; then
    printf '%s' "$raw"
  fi
  return 0
}

# 控制机 IP 列表是否包含目标 ansible_host（CI 与 dev-01 同机时为 true）
is_colocated_target() {
  local host_ip="$1"
  local ip
  [[ -n "$host_ip" ]] || return 1
  [[ "$host_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  for ip in $(hostname -I 2>/dev/null); do
    [[ "$ip" == "$host_ip" ]] && return 0
  done
  return 1
}

# 用户未显式指定 ansible_connection 且同机部署时，自动追加 -e ansible_connection=local
ansible_colocated_extra_args() {
  local inventory="$1"
  local limit="$2"
  shift 2
  local -a user_args=("$@")

  local arg
  for arg in "${user_args[@]}"; do
    if [[ "$arg" == *ansible_connection* ]]; then
      return 0
    fi
  done

  local host_ip
  host_ip="$(resolve_inventory_var "$inventory" "$limit" ansible_host)" || return 0
  if is_colocated_target "$host_ip"; then
    printf '%s\n' "-e" "ansible_connection=local"
  fi
}
