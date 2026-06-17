#!/usr/bin/env bash
set -euo pipefail

NGINX_CONTAINER_NAME="${NGINX_CONTAINER_NAME:-dev-gateway-nginx}"
NGINX_RELOAD_SIGNAL="${NGINX_RELOAD_SIGNAL:-HUP}"
DOCKER_API_VERSION="${DOCKER_API_VERSION:-v1.43}"

log() { printf '[certbot-renew:reload] %s\n' "$*"; }

reload_via_docker_api() {
  curl -fsS --unix-socket /var/run/docker.sock \
    -X POST \
    "http://localhost/${DOCKER_API_VERSION}/containers/${NGINX_CONTAINER_NAME}/kill?signal=${NGINX_RELOAD_SIGNAL}" \
    >/dev/null
}

if [[ -S /var/run/docker.sock ]]; then
  if reload_via_docker_api; then
    log "已向容器 ${NGINX_CONTAINER_NAME} 发送 SIG${NGINX_RELOAD_SIGNAL} (nginx reload)"
    exit 0
  fi
  log "Docker API reload 失败，请检查 NGINX_CONTAINER_NAME=${NGINX_CONTAINER_NAME}"
  exit 1
fi

RELOAD_SENTINEL="${RELOAD_SENTINEL:-/etc/letsencrypt/.nginx-reload-requested}"
date -Iseconds > "${RELOAD_SENTINEL}"
log "未挂载 docker.sock，已写入 reload 哨兵: ${RELOAD_SENTINEL}"
