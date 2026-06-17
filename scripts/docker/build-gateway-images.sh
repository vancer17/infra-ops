#!/usr/bin/env bash
# =============================================================================
# 手工构建并推送 Dev Gateway 三件套镜像
#
# 在 infra-ops 仓库根目录执行：
#   ./scripts/docker/build-gateway-images.sh build
#   ./scripts/docker/build-gateway-images.sh push
#   GATEWAY_IMAGE_TAG=1.0.1 ./scripts/docker/build-gateway-images.sh build push
#
# 环境变量（与 gateway.yml images.* 对齐）：
#   GATEWAY_IMAGE_REGISTRY  默认 5yrqsf19ms2mh4.xuanyuan.run/infra-ops
#   GATEWAY_IMAGE_TAG       默认 1.0.0
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCKER_CTX="${ROOT}/docker"

REGISTRY="${GATEWAY_IMAGE_REGISTRY:-5yrqsf19ms2mh4.xuanyuan.run/infra-ops}"
TAG="${GATEWAY_IMAGE_TAG:-1.0.0}"

IMAGE_CERTBOT_INIT="${REGISTRY}/certbot-init:${TAG}"
IMAGE_CERTBOT_RENEW="${REGISTRY}/certbot-renew:${TAG}"
IMAGE_NGINX="${REGISTRY}/dev-nginx:${TAG}"

log() { printf '[build-gateway-images] %s\n' "$*"; }

usage() {
  cat <<EOF
用法: $(basename "$0") <build|push|build push|list>

  build   在本地 docker/ 上下文构建三张镜像
  push    推送至 GATEWAY_IMAGE_REGISTRY（需已 docker login）
  list    打印当前 tag 与完整镜像名

环境变量:
  GATEWAY_IMAGE_REGISTRY  (默认: ${REGISTRY})
  GATEWAY_IMAGE_TAG       (默认: ${TAG})
EOF
}

require_docker() {
  command -v docker >/dev/null 2>&1 || {
    log "ERROR: docker 未安装"
    exit 1
  }
}

do_build() {
  require_docker
  log "构建上下文: ${DOCKER_CTX}"
  log "tag: ${TAG}"

  docker build -f "${DOCKER_CTX}/certbot-init/Dockerfile" -t "${IMAGE_CERTBOT_INIT}" "${DOCKER_CTX}"
  docker build -f "${DOCKER_CTX}/certbot-renew/Dockerfile" -t "${IMAGE_CERTBOT_RENEW}" "${DOCKER_CTX}"
  docker build -f "${DOCKER_CTX}/nginx/Dockerfile" -t "${IMAGE_NGINX}" "${DOCKER_CTX}"

  log "构建完成:"
  log "  ${IMAGE_CERTBOT_INIT}"
  log "  ${IMAGE_CERTBOT_RENEW}"
  log "  ${IMAGE_NGINX}"
  log "更新 gateway.yml images.tag=${TAG} 后执行 gateway-compose.yml"
}

do_push() {
  require_docker
  for img in "${IMAGE_CERTBOT_INIT}" "${IMAGE_CERTBOT_RENEW}" "${IMAGE_NGINX}"; do
    log "push ${img}"
    docker push "${img}"
  done
  log "推送完成"
}

do_list() {
  printf 'GATEWAY_IMAGE_REGISTRY=%s\n' "${REGISTRY}"
  printf 'GATEWAY_IMAGE_TAG=%s\n' "${TAG}"
  printf 'GATEWAY_IMAGE_CERTBOT_INIT=%s\n' "${IMAGE_CERTBOT_INIT}"
  printf 'GATEWAY_IMAGE_CERTBOT_RENEW=%s\n' "${IMAGE_CERTBOT_RENEW}"
  printf 'GATEWAY_IMAGE_NGINX=%s\n' "${IMAGE_NGINX}"
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      build) do_build ;;
      push) do_push ;;
      list) do_list ;;
      -h|--help) usage; exit 0 ;;
      *)
        log "ERROR: 未知命令: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

main "$@"
