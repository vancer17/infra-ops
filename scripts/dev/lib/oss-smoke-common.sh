#!/usr/bin/env bash
# =============================================================================
# scripts/dev/lib/oss-smoke-common.sh — OSS smoke 脚本共享库
# =============================================================================
#
# 【用途】
#   被 scripts/dev/oss-smoke.sh source，提供：
#     - 路径常量、日志函数
#     - 从 Ansible inventory 读取 oss.* / ram_role_name
#     - ECS 实例元数据（RAM 角色）探测（不打印 STS 密钥）
#     - ossutil 配置（EcsRamRole 模式）
#
# 【设计原则】
#   - 不在日志中输出 AccessKeySecret / SecurityToken
#   - Dev 桶名优先读 inventory，可用环境变量覆盖（便于独立桶 infra-dev-file-storage）
#   - 生产隔离桶默认 yzx-file-storage（资源组隔离验收用）
#
# =============================================================================

if [[ -n "${OSS_SMOKE_COMMON_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
OSS_SMOKE_COMMON_LOADED=1

set -euo pipefail

# -----------------------------------------------------------------------------
# 路径与默认值（可由 oss-smoke.sh 在 source 前预设 REPO_ROOT）
# -----------------------------------------------------------------------------
OSS_SMOKE_REPO_ROOT="${OSS_SMOKE_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OSS_SMOKE_INVENTORY="${OSS_SMOKE_INVENTORY:-${OSS_SMOKE_REPO_ROOT}/ansible/inventories/dev/}"
OSS_SMOKE_LIMIT="${OSS_SMOKE_LIMIT:-dev-01}"

# 阿里云 ECS 实例元数据（仅 VPC 内可访问）
OSS_META_BASE="${OSS_META_BASE:-http://100.100.100.200/latest/meta-data/ram/security-credentials}"

# ossutil 与配置文件
OSSUTIL_BIN="${OSSUTIL_BIN:-ossutil}"
OSSUTIL_CONFIG="${OSSUTIL_CONFIG:-${HOME}/.ossutilconfig}"

# 内网 Endpoint（杭州，与 Dev ECS / Bucket 同区）
OSS_ENDPOINT_DEFAULT="${OSS_ENDPOINT_DEFAULT:-oss-cn-hangzhou-internal.aliyuncs.com}"

# 隔离验收：Dev 角色不应能访问的生产/历史 Bucket（资源组隔离）
OSS_ISOLATION_BUCKET_DEFAULT="${OSS_ISOLATION_BUCKET_DEFAULT:-yzx-file-storage}"

# smoke 对象键前缀（Bucket 已代表 Dev 环境时，不必再用 dev/ 前缀）
OSS_SMOKE_KEY_PREFIX="${OSS_SMOKE_KEY_PREFIX:-smoke-test}"

# -----------------------------------------------------------------------------
# 日志
# -----------------------------------------------------------------------------
oss_smoke_log() {
  printf '[oss-smoke] %s\n' "$*"
}

oss_smoke_warn() {
  printf '[oss-smoke] WARN: %s\n' "$*" >&2
}

oss_smoke_die() {
  printf '[oss-smoke] ERROR: %s\n' "$*" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# 依赖 inventory-resolve（读取已渲染的 group_vars / host_vars）
# -----------------------------------------------------------------------------
_oss_smoke_load_inventory_resolver() {
  # shellcheck source=scripts/dev/lib/inventory-resolve.sh
  source "${OSS_SMOKE_REPO_ROOT}/scripts/dev/lib/inventory-resolve.sh"
}

# 从 inventory 加载变量；环境变量可覆盖（OSS_DEV_BUCKET 等）
oss_smoke_load_config() {
  _oss_smoke_load_inventory_resolver

  local inv_bucket inv_role inv_prefix

  inv_bucket="$(resolve_inventory_var "$OSS_SMOKE_INVENTORY" "$OSS_SMOKE_LIMIT" oss.bucket 2>/dev/null || true)"
  inv_role="$(resolve_inventory_var "$OSS_SMOKE_INVENTORY" "$OSS_SMOKE_LIMIT" ram_role_name 2>/dev/null || true)"
  inv_prefix="$(resolve_inventory_var "$OSS_SMOKE_INVENTORY" "$OSS_SMOKE_LIMIT" oss.prefix 2>/dev/null || true)"

  # Dev 目标桶：环境变量 > inventory（若为历史 yzx 桶则改用独立 Dev 桶）> 兜底
  if [[ -n "${OSS_DEV_BUCKET:-}" ]]; then
    :
  elif [[ -n "${inv_bucket}" && "${inv_bucket}" != "yzx-file-storage" ]]; then
    OSS_DEV_BUCKET="${inv_bucket}"
  else
    OSS_DEV_BUCKET="infra-dev-file-storage"
    if [[ "${inv_bucket}" == "yzx-file-storage" ]]; then
      oss_smoke_warn "inventory oss.bucket 仍为 yzx-file-storage；smoke 默认使用独立 Dev 桶: ${OSS_DEV_BUCKET}"
      oss_smoke_warn "  验收通过后请更新 ansible/inventories/dev/group_vars/all/main.yml"
    fi
  fi

  OSS_RAM_ROLE_NAME="${OSS_RAM_ROLE_NAME:-${inv_role:-Dev-ECS-Role}}"
  OSS_INVENTORY_PREFIX="${OSS_INVENTORY_PREFIX:-${inv_prefix:-}}"

  OSS_ISOLATION_BUCKET="${OSS_ISOLATION_BUCKET:-${OSS_ISOLATION_BUCKET_DEFAULT}}"
  OSS_ENDPOINT="${OSS_ENDPOINT:-${OSS_ENDPOINT_DEFAULT}}"
}

# -----------------------------------------------------------------------------
# 依赖检查
# -----------------------------------------------------------------------------
oss_smoke_require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || oss_smoke_die "missing command: ${cmd}"
}

oss_smoke_check_deps() {
  oss_smoke_require_cmd curl
  oss_smoke_require_cmd python3
  if command -v "${OSSUTIL_BIN}" >/dev/null 2>&1; then
    oss_smoke_log "ossutil: OK ($(${OSSUTIL_BIN} --version 2>&1 | head -1))"
  else
    oss_smoke_die "ossutil not found; install or set INSTALL_OSSUTIL=1 for hint"
  fi
}

# 可选：打印 ossutil 安装提示（不自动安装，避免生产机意外改 PATH）
oss_smoke_install_hint() {
  cat <<EOF
Install ossutil (on Debian ECS), for example:
  cd /tmp
  curl -sO https://gosspublic.alicdn.com/ossutil/1.7.19/linux-amd64/ossutil
  chmod +x ossutil
  sudo mv ossutil /usr/local/bin/ossutil
EOF
}

# -----------------------------------------------------------------------------
# RAM 元数据（不泄露 STS 密钥）
# -----------------------------------------------------------------------------
oss_smoke_meta_role_name() {
  curl -sf --connect-timeout 3 "${OSS_META_BASE}/" 2>/dev/null || echo ""
}

oss_smoke_meta_sts_summary() {
  local role="$1"
  curl -sf --connect-timeout 3 "${OSS_META_BASE}/${role}" 2>/dev/null \
    | python3 -c "
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(1)
d = json.loads(raw)
print('Code:', d.get('Code', ''))
print('Expiration:', d.get('Expiration', ''))
" 2>/dev/null || return 1
}

# 当前 shell 是否运行在已绑定 RAM 的 ECS 上（元数据可读到角色名）
oss_smoke_running_on_ecs_with_ram() {
  local role expected
  expected="${OSS_RAM_ROLE_NAME:-Dev-ECS-Role}"
  role="$(oss_smoke_meta_role_name)"
  [[ -n "$role" ]] && [[ "$role" == *"${expected}"* ]]
}

# -----------------------------------------------------------------------------
# ossutil 配置（EcsRamRole — 使用实例绑定的 RAM 角色，无需 AK/SK）
# -----------------------------------------------------------------------------
oss_smoke_write_ossutil_config() {
  local cfg_dir
  cfg_dir="$(dirname "${OSSUTIL_CONFIG}")"
  mkdir -p "${cfg_dir}"
  cat >"${OSSUTIL_CONFIG}" <<EOF
[Credentials]
language = CH
endpoint = ${OSS_ENDPOINT}
mode = EcsRamRole
ecsRoleName = ${OSS_RAM_ROLE_NAME}
EOF
  chmod 600 "${OSSUTIL_CONFIG}"
  oss_smoke_log "wrote ossutil config: ${OSSUTIL_CONFIG} (EcsRamRole=${OSS_RAM_ROLE_NAME})"
}

# 所有 ossutil 调用统一加 -c 配置文件；-e 显式传入 endpoint 防止配置节误读
oss_smoke_ossutil() {
  "${OSSUTIL_BIN}" -c "${OSSUTIL_CONFIG}" -e "${OSS_ENDPOINT}" "$@"
}

# -----------------------------------------------------------------------------
# 同机判断（CI 与 dev-01 同 ECS 时无需 SSH）
# -----------------------------------------------------------------------------
oss_smoke_is_colocated_target() {
  _oss_smoke_load_inventory_resolver
  local host_ip
  host_ip="$(resolve_inventory_var "$OSS_SMOKE_INVENTORY" "$OSS_SMOKE_LIMIT" ansible_host 2>/dev/null || true)"
  is_colocated_target "$host_ip"
}
