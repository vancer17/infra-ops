#!/bin/sh
set -eu

# =============================================================================
# Dev Gateway Nginx entrypoint — WG 内网 HTTP vhost 生成
# =============================================================================
#
# 基础信息：
#   - 仅当 NGINX_INTERNAL_SERVER_NAMES 非空时生成 /etc/nginx/conf.d/internal-http.conf。
#   - 同步渲染 device-management-system 路径隔离变量，确保 WG 内网也支持
#     /device-management/ 与 /device-management/api/*。
# =============================================================================

# 当设置 NGINX_INTERNAL_SERVER_NAMES 时，生成 WG 内网 HTTP vhost（不跳转 HTTPS）
if [ -z "${NGINX_INTERNAL_SERVER_NAMES:-}" ]; then
  exit 0
fi

template="/etc/nginx/internal-templates/internal-http.conf.template"
output="/etc/nginx/conf.d/internal-http.conf"

if [ ! -f "${template}" ]; then
  echo "WARN: internal template missing: ${template}" >&2
  exit 0
fi

export DMS_SERVICE_PREFIX="${DMS_SERVICE_PREFIX:-/device-management}"
export DMS_UPSTREAM_HOST="${DMS_UPSTREAM_HOST:-127.0.0.1}"
export DMS_UPSTREAM_PORT="${DMS_UPSTREAM_PORT:-18080}"
export DMS_FRONTEND_WEB_ROOT="${DMS_FRONTEND_WEB_ROOT:-/srv/www}"
export NGINX_INTERNAL_SERVER_NAMES APP_UPSTREAM_HOST APP_UPSTREAM_PORT
envsubst '${NGINX_INTERNAL_SERVER_NAMES} ${APP_UPSTREAM_HOST} ${APP_UPSTREAM_PORT} ${DMS_SERVICE_PREFIX} ${DMS_UPSTREAM_HOST} ${DMS_UPSTREAM_PORT} ${DMS_FRONTEND_WEB_ROOT}' \
  < "${template}" > "${output}"

echo "Generated WG internal HTTP vhost: ${output} (server_name: ${NGINX_INTERNAL_SERVER_NAMES})"
