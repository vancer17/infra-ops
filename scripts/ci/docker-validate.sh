#!/usr/bin/env bash
# =============================================================================
# scripts/ci/docker-validate.sh — Docker Compose 配置校验
#                                              （对应 ci.yml job: docker-validate）
# =============================================================================
#
# 【检查内容】
#   对以下 compose 文件（若存在）运行 `docker compose config`：
#     - jumpserver/docker-compose.yml
#     - monitoring/docker-compose.yml
#
#   `docker compose config` 仅解析/合并 YAML，不启动容器。
#   文件不存在时 skip（与原先 ci.yml 行为一致）。
#
# 【前置依赖】
#   docker 与 compose 插件（GitHub ubuntu-latest 已预装）
#
# 【用法】
#   ./scripts/ci/docker-validate.sh
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# 待校验的 compose 路径（相对描述名 → 用于日志）
declare -A COMPOSE_TARGETS=(
  ["jumpserver/docker-compose.yml"]="${CI_REPO_ROOT}/jumpserver/docker-compose.yml"
  ["monitoring/docker-compose.yml"]="${CI_REPO_ROOT}/monitoring/docker-compose.yml"
)

# 先统计是否存在待校验文件；全无则跳过，不要求本机安装 docker
# （Bootstrap 前 ECS 上常无 docker CLI，且仓库可能尚未添加 compose 文件）
pending=0
for label in jumpserver/docker-compose.yml monitoring/docker-compose.yml; do
  if [[ -f "${COMPOSE_TARGETS[$label]}" ]]; then
    pending=$((pending + 1))
  fi
done

if [[ "${pending}" -eq 0 ]]; then
  ci_skip "no compose files to validate (all optional paths missing)"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  ci_die "docker not found but ${pending} compose file(s) exist; install Docker CE or docker.io + compose plugin"
fi

validated=0

for label in jumpserver/docker-compose.yml monitoring/docker-compose.yml; do
  compose_file="${COMPOSE_TARGETS[$label]}"

  if [[ ! -f "${compose_file}" ]]; then
    ci_skip "${label} not found"
    continue
  fi

  ci_log "Validating compose: ${label}"
  docker compose -f "${compose_file}" config >/dev/null
  validated=$((validated + 1))
done

ci_log "docker-validate OK (${validated} file(s))"
