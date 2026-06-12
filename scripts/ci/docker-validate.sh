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

ci_require_cmd docker

# 待校验的 compose 路径（相对描述名 → 用于日志）
declare -A COMPOSE_TARGETS=(
  ["jumpserver/docker-compose.yml"]="${CI_REPO_ROOT}/jumpserver/docker-compose.yml"
  ["monitoring/docker-compose.yml"]="${CI_REPO_ROOT}/monitoring/docker-compose.yml"
)

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

if [[ "${validated}" -eq 0 ]]; then
  ci_skip "no compose files to validate (all optional paths missing)"
else
  ci_log "docker-validate OK (${validated} file(s))"
fi
