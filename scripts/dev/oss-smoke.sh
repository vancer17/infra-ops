#!/usr/bin/env bash
# =============================================================================
# OSS Dev 桶验收（阶段 H4）— 实例 RAM 绑定 + 读写 + 生产桶隔离
# =============================================================================
#
# 【这个脚本是什么】
#   封装「H4：ECS 绑定后的 OSS 验收」，与 ssh-keys.sh、wg-keys.sh 同级：
#     - 控制台绑定 RAM 角色（Dev-ECS-Role）仍须在阿里云完成，本脚本不代替绑定
#     - 在已绑定角色的 ECS 上验证：元数据 → Dev 桶 Put/Get → 生产桶访问被拒绝
#
# 【架构前提（2026-06 讨论）】
#   - Dev 专用桶：infra-dev-file-storage（资源组 InfraDevOss）
#   - 生产/历史桶：yzx-file-storage（另一资源组，Dev 角色应无权限）
#   - 访问走 VPC 内网 Endpoint，不经 WireGuard
#
# 【执行位置】
#   | 场景 | 命令 |
#   |------|------|
#   | 在 dev-01 / ci-01 同机上（yax） | ./scripts/dev/oss-smoke.sh all |
#   | 在控制机远程验收 | ./scripts/dev/oss-smoke.sh all dev-01 |
#   | Makefile | make oss-smoke OSS_SMOKE_LIMIT=dev-01 |
#
# 【子命令】
#   check-deps    检查 curl、python3、ossutil
#   check-meta    元数据 RAM 角色 + STS Code（不打印密钥）
#   write-config  生成 ~/.ossutilconfig（EcsRamRole）
#   put-get       Dev 桶上传 / 下载 / 列举 smoke 对象
#   deny-isolation  访问隔离桶（默认 yzx-file-storage）应失败
#   local all     必须在已绑 RAM 的 ECS 上执行的全量验收
#   all [host]    控制机入口：同机则 local all，否则 SSH 远程执行 local all
#   preflight     解析 inventory 变量 + SSH 可达性（远程时）
#
# 【环境变量】
#   OSS_DEV_BUCKET           Dev 桶名（默认 inventory oss.bucket 或 infra-dev-file-storage）
#   OSS_ISOLATION_BUCKET     隔离验收桶（默认 yzx-file-storage）
#   OSS_RAM_ROLE_NAME        RAM 角色名（默认 Dev-ECS-Role）
#   OSS_ENDPOINT             ossutil Endpoint（默认杭州内网）
#   OSS_SMOKE_KEY_PREFIX     对象键前缀（默认 smoke-test）
#   OSSUTIL_BIN / OSSUTIL_CONFIG
#   ANSIBLE_INVENTORY / ANSIBLE_LIMIT
#   ANSIBLE_PRIVATE_KEY_FILE  远程 SSH 私钥（默认 ansible/keys/infra-ci-deploy）
#   OSS_SMOKE_REMOTE_ROOT      远程 ECS 上本仓库路径（默认 ~/infra-ops）
#   INSTALL_OSSUTIL=1        check-deps 失败时打印安装提示
#
# 【注意】
#   - 勿将元数据返回的 STS JSON 写入日志文件或提交 Git
#   - 验收通过后请更新 docs/assets/dev-01.yaml → ram_role.attached: true
#
# 详见：docs/oss/20260616-OSS-实例现状与Dev规划.md §九、§十
#
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export OSS_SMOKE_REPO_ROOT="${ROOT}"

INVENTORY="${ANSIBLE_INVENTORY:-${ROOT}/ansible/inventories/dev/}"
export OSS_SMOKE_INVENTORY="${INVENTORY}"

LIMIT="${ANSIBLE_LIMIT:-dev-01}"
export OSS_SMOKE_LIMIT="${LIMIT}"

PRIVATE_KEY="${ANSIBLE_PRIVATE_KEY_FILE:-${ROOT}/ansible/keys/infra-ci-deploy}"

# 远程 ECS 上仓库路径（SSH 执行 local all 时使用；同机则用本机 ROOT）
REMOTE_ROOT="${OSS_SMOKE_REMOTE_ROOT:-~/infra-ops}"

# shellcheck source=scripts/dev/lib/oss-smoke-common.sh
source "${ROOT}/scripts/dev/lib/oss-smoke-common.sh"

# shellcheck source=scripts/dev/lib/inventory-resolve.sh
source "${ROOT}/scripts/dev/lib/inventory-resolve.sh"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=15
  -o StrictHostKeyChecking=accept-new
)

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [host]

Commands:
  check-deps       检查 curl、python3、ossutil
  check-meta       ECS 元数据：RAM 角色名 + STS Code（不输出密钥）
  write-config     写入 ~/.ossutilconfig（EcsRamRole）
  put-get          Dev 桶 Put/Get/List smoke 对象
  deny-isolation   隔离桶访问应失败（默认 ${OSS_ISOLATION_BUCKET_DEFAULT}）
  local all        在已绑 RAM 的 ECS 上跑全量验收
  all [host]       控制机：同机 local all，否则 SSH 到目标执行 local all
  preflight        加载 inventory 配置并检查 SSH（远程时）

Environment:
  OSS_DEV_BUCKET=${OSS_DEV_BUCKET:-<from inventory>}
  OSS_ISOLATION_BUCKET=${OSS_ISOLATION_BUCKET_DEFAULT}
  OSS_RAM_ROLE_NAME=Dev-ECS-Role
  ANSIBLE_INVENTORY  default: ansible/inventories/dev/
  ANSIBLE_LIMIT      default: dev-01

Examples:
  $(basename "$0") preflight
  $(basename "$0") all
  $(basename "$0") all dev-01
  OSS_DEV_BUCKET=infra-dev-file-storage $(basename "$0") local all
EOF
}

# -----------------------------------------------------------------------------
# preflight — 加载配置；远程目标时检查 SSH
# -----------------------------------------------------------------------------
cmd_preflight() {
  oss_smoke_load_config
  oss_smoke_log "target host: ${LIMIT}"
  oss_smoke_log "dev bucket: ${OSS_DEV_BUCKET}"
  oss_smoke_log "isolation bucket: ${OSS_ISOLATION_BUCKET}"
  oss_smoke_log "ram role: ${OSS_RAM_ROLE_NAME}"
  oss_smoke_log "endpoint: ${OSS_ENDPOINT}"

  if oss_smoke_running_on_ecs_with_ram; then
    oss_smoke_log "execution context: local ECS (RAM metadata OK)"
    return 0
  fi

  if oss_smoke_is_colocated_target; then
    oss_smoke_log "execution context: colocated with ${LIMIT} (will use local all)"
    return 0
  fi

  local host user
  host="$(resolve_ansible_host "$INVENTORY" "$LIMIT")"
  user="$(resolve_ansible_user "$INVENTORY" "$LIMIT")"
  [[ -f "${PRIVATE_KEY}" ]] || oss_smoke_die "missing SSH key: ${PRIVATE_KEY}"

  oss_smoke_log "execution context: remote via SSH ${user}@${host}"
  ssh "${SSH_OPTS[@]}" -i "${PRIVATE_KEY}" "${user}@${host}" 'hostname && whoami'
  oss_smoke_log "preflight OK (SSH reachable)"
}

# -----------------------------------------------------------------------------
# check-deps / check-meta / write-config
# -----------------------------------------------------------------------------
cmd_check_deps() {
  oss_smoke_load_config
  if ! command -v "${OSSUTIL_BIN}" >/dev/null 2>&1; then
    if [[ "${INSTALL_OSSUTIL:-}" == "1" ]]; then
      oss_smoke_install_hint
    fi
    oss_smoke_die "ossutil not found; install ossutil or set INSTALL_OSSUTIL=1 for hint"
  fi
  oss_smoke_check_deps
  oss_smoke_log "check-deps OK"
}

cmd_check_meta() {
  oss_smoke_load_config

  local role
  role="$(oss_smoke_meta_role_name)"
  [[ -n "$role" ]] || oss_smoke_die "ECS metadata has no RAM role; bind Dev-ECS-Role in console first"

  oss_smoke_log "metadata role: ${role}"
  [[ "$role" == *"${OSS_RAM_ROLE_NAME}"* ]] \
    || oss_smoke_die "expected role ${OSS_RAM_ROLE_NAME}, got: ${role}"

  oss_smoke_meta_sts_summary "${OSS_RAM_ROLE_NAME}" || oss_smoke_die "STS metadata request failed"
  oss_smoke_log "check-meta OK"
}

cmd_write_config() {
  oss_smoke_load_config
  oss_smoke_write_ossutil_config
  oss_smoke_log "write-config OK"
}

# -----------------------------------------------------------------------------
# put-get — Dev 桶 smoke
# -----------------------------------------------------------------------------
cmd_put_get() {
  oss_smoke_load_config
  oss_smoke_check_deps
  oss_smoke_write_ossutil_config

  local date smoke_key smoke_local remote_uri
  date="$(date +%Y%m%d)"
  smoke_key="${OSS_SMOKE_KEY_PREFIX}/${date}-ecs-bind.txt"
  smoke_local="$(mktemp)"
  remote_uri="oss://${OSS_DEV_BUCKET}/${smoke_key}"

  echo "oss smoke ${date} from $(hostname) at $(date -Is)" >"${smoke_local}"

  oss_smoke_log "upload: ${remote_uri}"
  oss_smoke_ossutil cp "${smoke_local}" "${remote_uri}" -f

  # 不用 ossutil cat：v1.7 会在文件内容后追加 "0.xxx(s) elapsed"，导致字符串比对失败
  local smoke_downloaded
  smoke_downloaded="$(mktemp)"

  oss_smoke_log "download: ${remote_uri}"
  oss_smoke_ossutil cp "${remote_uri}" "${smoke_downloaded}" -f

  if ! cmp -s "${smoke_local}" "${smoke_downloaded}"; then
    rm -f "${smoke_local}" "${smoke_downloaded}"
    oss_smoke_die "content mismatch after get (local vs downloaded)"
  fi

  rm -f "${smoke_local}" "${smoke_downloaded}"

  oss_smoke_log "list prefix: oss://${OSS_DEV_BUCKET}/${OSS_SMOKE_KEY_PREFIX}/"
  oss_smoke_ossutil ls "oss://${OSS_DEV_BUCKET}/${OSS_SMOKE_KEY_PREFIX}/" --limited-num 5

  oss_smoke_log "put-get OK"
}

# -----------------------------------------------------------------------------
# deny-isolation — 生产/隔离桶应拒绝访问
# -----------------------------------------------------------------------------
cmd_deny_isolation() {
  oss_smoke_load_config
  oss_smoke_check_deps
  oss_smoke_write_ossutil_config

  local iso_bucket="${OSS_ISOLATION_BUCKET}"
  local probe_local probe_uri

  oss_smoke_log "isolation test: ${iso_bucket} (expect AccessDenied / failure)"

  if oss_smoke_ossutil ls "oss://${iso_bucket}/" --limited-num 1 >/dev/null 2>&1; then
    oss_smoke_die "isolation FAILED: can list ${iso_bucket} — check resource group / RAM policy"
  fi
  oss_smoke_log "list ${iso_bucket}: denied (OK)"

  probe_local="$(mktemp)"
  probe_uri="oss://${iso_bucket}/smoke-test-must-fail.txt"
  echo "must not upload" >"${probe_local}"

  if oss_smoke_ossutil cp "${probe_local}" "${probe_uri}" -f >/dev/null 2>&1; then
    rm -f "${probe_local}"
    oss_smoke_die "isolation FAILED: can put to ${iso_bucket}"
  fi
  rm -f "${probe_local}"
  oss_smoke_log "put ${iso_bucket}: denied (OK)"

  oss_smoke_log "deny-isolation OK"
}

# -----------------------------------------------------------------------------
# local all — 在 ECS 上顺序执行（元数据 → 读写 → 隔离）
# -----------------------------------------------------------------------------
cmd_local_all() {
  oss_smoke_load_config

  if ! oss_smoke_running_on_ecs_with_ram; then
    oss_smoke_die "local all must run on ECS with RAM role bound (metadata unavailable here)"
  fi

  cmd_check_deps
  cmd_check_meta
  cmd_put_get
  cmd_deny_isolation

  oss_smoke_log "=============================================="
  oss_smoke_log "local all OK — stage H4 OSS acceptance passed"
  oss_smoke_log "  dev bucket:    ${OSS_DEV_BUCKET}"
  oss_smoke_log "  isolated from: ${OSS_ISOLATION_BUCKET}"
  oss_smoke_log "  next: update dev-01.yaml ram_role.attached, write acceptance doc"
  oss_smoke_log "=============================================="
}

# -----------------------------------------------------------------------------
# all — 控制机入口：同机 local，否则 SSH 远程 local all
# -----------------------------------------------------------------------------
cmd_all() {
  cmd_preflight

  if oss_smoke_running_on_ecs_with_ram || oss_smoke_is_colocated_target; then
    oss_smoke_log "running local all on this host ..."
    cmd_local_all
    return 0
  fi

  local host user remote_cmd
  host="$(resolve_ansible_host "$INVENTORY" "$LIMIT")"
  user="$(resolve_ansible_user "$INVENTORY" "$LIMIT")"
  [[ -f "${PRIVATE_KEY}" ]] || oss_smoke_die "missing SSH key: ${PRIVATE_KEY}"

  # 远程执行：在目标 ECS 的仓库副本上跑 local all（路径默认 ~/infra-ops）
  remote_cmd="cd ${REMOTE_ROOT} && \
OSS_DEV_BUCKET='${OSS_DEV_BUCKET}' \
OSS_ISOLATION_BUCKET='${OSS_ISOLATION_BUCKET}' \
OSS_RAM_ROLE_NAME='${OSS_RAM_ROLE_NAME}' \
OSS_ENDPOINT='${OSS_ENDPOINT}' \
OSS_SMOKE_KEY_PREFIX='${OSS_SMOKE_KEY_PREFIX}' \
ANSIBLE_INVENTORY='ansible/inventories/dev/' \
ANSIBLE_LIMIT='${LIMIT}' \
bash scripts/dev/oss-smoke.sh local all"

  oss_smoke_log "SSH ${user}@${host} → local all (repo: ${REMOTE_ROOT})"
  ssh "${SSH_OPTS[@]}" -i "${PRIVATE_KEY}" "${user}@${host}" "bash -lc $(printf '%q' "${remote_cmd}")"
  oss_smoke_log "all OK (remote on ${LIMIT})"
}

# -----------------------------------------------------------------------------
# main
# -----------------------------------------------------------------------------
main() {
  local cmd="${1:-}"
  shift || true

  if [[ -n "${1:-}" && "$1" != --* ]]; then
    LIMIT="$1"
    export OSS_SMOKE_LIMIT="${LIMIT}"
    export ANSIBLE_LIMIT="${LIMIT}"
    shift
  fi

  case "$cmd" in
    check-deps) cmd_check_deps ;;
    check-meta) cmd_check_meta ;;
    write-config) cmd_write_config ;;
    put-get) cmd_put_get ;;
    deny-isolation) cmd_deny_isolation ;;
    local)
      case "${1:-}" in
        all) cmd_local_all ;;
        *)
          oss_smoke_die "usage: $(basename "$0") local all"
          ;;
      esac
      ;;
    all) cmd_all ;;
    preflight) cmd_preflight ;;
    -h | --help | help) usage ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
