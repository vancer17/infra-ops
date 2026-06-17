#!/usr/bin/env bash
# =============================================================================
# 手工构建 Dev Gateway 三件套镜像（本地 tag，不向轩辕镜像加速站 push）
#
# 轩辕（5yrqsf19ms2mh4.xuanyuan.run）仅用于 docker build 时拉取公网基础镜像
# （certbot/certbot、nginx 等），不能作为 infra-ops 自建镜像的私有仓库。
#
# 在 infra-ops 仓库根目录执行：
#   ./scripts/docker/build-gateway-images.sh build
#   ./scripts/docker/build-gateway-images.sh save
#   GATEWAY_IMAGE_TAG=1.0.1 ./scripts/docker/build-gateway-images.sh build save
#
# 环境变量（与 gateway.yml images.* 对齐）：
#   GATEWAY_IMAGE_NAMESPACE  默认 infra-ops
#   GATEWAY_IMAGE_TAG          默认 1.0.0
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCKER_CTX="${ROOT}/docker"
BUNDLE_DIR="${ROOT}/docker/dev-gateway/bundles"

NAMESPACE="${GATEWAY_IMAGE_NAMESPACE:-infra-ops}"
TAG="${GATEWAY_IMAGE_TAG:-1.0.0}"

IMAGE_CERTBOT_INIT="${NAMESPACE}/certbot-init:${TAG}"
IMAGE_CERTBOT_RENEW="${NAMESPACE}/certbot-renew:${TAG}"
IMAGE_NGINX="${NAMESPACE}/dev-nginx:${TAG}"
BUNDLE_FILE="${BUNDLE_DIR}/${NAMESPACE}-gateway-${TAG}.tar"

log() { printf '[build-gateway-images] %s\n' "$*"; }

usage() {
  cat <<EOF
用法: $(basename "$0") <build|save|list>

  build   在本地 docker/ 上下文构建三张镜像（tag: ${NAMESPACE}/*:${TAG}）
  save    docker save 为 tar（供 gateway.images.delivery=bundle Ansible load）
  list    打印镜像名与 bundle 路径

环境变量:
  GATEWAY_IMAGE_NAMESPACE  (默认: ${NAMESPACE})
  GATEWAY_IMAGE_TAG        (默认: ${TAG})

分发方式（gateway.yml images.delivery）:
  local    在目标机 build 后直接 compose up
  bundle   控制机 build+save，Ansible 同步 tar 并 docker load
  registry  推送到真实私有仓库（阿里云 ACR）；本脚本不 push 到轩辕加速站
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
  log "本地 tag: ${NAMESPACE}/*:${TAG}"

  docker build -f "${DOCKER_CTX}/certbot-init/Dockerfile" -t "${IMAGE_CERTBOT_INIT}" "${DOCKER_CTX}"
  docker build -f "${DOCKER_CTX}/certbot-renew/Dockerfile" -t "${IMAGE_CERTBOT_RENEW}" "${DOCKER_CTX}"
  docker build -f "${DOCKER_CTX}/nginx/Dockerfile" -t "${IMAGE_NGINX}" "${DOCKER_CTX}"

  log "构建完成:"
  log "  ${IMAGE_CERTBOT_INIT}"
  log "  ${IMAGE_CERTBOT_RENEW}"
  log "  ${IMAGE_NGINX}"
  log "更新 gateway.yml images.tag=${TAG}；目标机 delivery=local 可直接 compose up"
}

do_save() {
  require_docker
  for img in "${IMAGE_CERTBOT_INIT}" "${IMAGE_CERTBOT_RENEW}" "${IMAGE_NGINX}"; do
    docker image inspect "${img}" >/dev/null 2>&1 || {
      log "ERROR: 镜像不存在: ${img} — 先执行 build"
      exit 1
    }
  done
  mkdir -p "${BUNDLE_DIR}"
  log "保存 bundle: ${BUNDLE_FILE}"
  docker save -o "${BUNDLE_FILE}" \
    "${IMAGE_CERTBOT_INIT}" \
    "${IMAGE_CERTBOT_RENEW}" \
    "${IMAGE_NGINX}"
  log "bundle 已写入；设置 gateway.images.delivery=bundle"
  log "  bundle_filename: $(basename "${BUNDLE_FILE}")"
}

do_list() {
  printf 'GATEWAY_IMAGE_NAMESPACE=%s\n' "${NAMESPACE}"
  printf 'GATEWAY_IMAGE_TAG=%s\n' "${TAG}"
  printf 'GATEWAY_IMAGE_CERTBOT_INIT=%s\n' "${IMAGE_CERTBOT_INIT}"
  printf 'GATEWAY_IMAGE_CERTBOT_RENEW=%s\n' "${IMAGE_CERTBOT_RENEW}"
  printf 'GATEWAY_IMAGE_NGINX=%s\n' "${IMAGE_NGINX}"
  printf 'GATEWAY_BUNDLE_FILE=%s\n' "${BUNDLE_FILE}"
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      build) do_build ;;
      save) do_save ;;
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
