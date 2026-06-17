#!/bin/sh
set -eu

# 当设置 NGINX_INTERNAL_SERVER_NAMES 时，生成 WG 内网 HTTP vhost（不跳转 HTTPS）
if [ -z "${NGINX_INTERNAL_SERVER_NAMES:-}" ]; then
  exit 0
fi

template="/etc/nginx/templates/internal-http.conf.template"
output="/etc/nginx/conf.d/internal-http.conf"

if [ ! -f "${template}" ]; then
  echo "WARN: internal template missing: ${template}" >&2
  exit 0
fi

export NGINX_INTERNAL_SERVER_NAMES APP_UPSTREAM_HOST APP_UPSTREAM_PORT
envsubst '${NGINX_INTERNAL_SERVER_NAMES} ${APP_UPSTREAM_HOST} ${APP_UPSTREAM_PORT}' \
  < "${template}" > "${output}"

echo "Generated WG internal HTTP vhost: ${output} (server_name: ${NGINX_INTERNAL_SERVER_NAMES})"
