#!/bin/sh
set -eu

# 公网 MQTTS（stream 8883）→ 127.0.0.1:1883；NGINX_MQTT_TLS_ENABLED=0 时不生成配置
stream_dir="/etc/nginx/stream.d"
template="/etc/nginx/templates/mqtt-stream.conf.template"
output="${stream_dir}/mqtt-stream.conf"
placeholder="${stream_dir}/00-disabled.conf"

mkdir -p "${stream_dir}"

if [ "${NGINX_MQTT_TLS_ENABLED:-0}" != "1" ]; then
  rm -f "${output}"
  printf '# MQTT stream disabled (NGINX_MQTT_TLS_ENABLED != 1)\n' > "${placeholder}"
  echo "MQTT stream: disabled"
  exit 0
fi

rm -f "${placeholder}"

if [ -z "${MQTT_TLS_DOMAIN:-}" ]; then
  echo "ERROR: NGINX_MQTT_TLS_ENABLED=1 但 MQTT_TLS_DOMAIN 未设置" >&2
  exit 1
fi

export MQTT_TLS_PORT="${MQTT_TLS_PORT:-8883}"
export MQTT_UPSTREAM_HOST="${MQTT_UPSTREAM_HOST:-127.0.0.1}"
export MQTT_UPSTREAM_PORT="${MQTT_UPSTREAM_PORT:-1883}"
export MQTT_TLS_CERT_DOMAIN="${MQTT_TLS_CERT_DOMAIN:-${CERTBOT_PRIMARY_DOMAIN:-}}"

if [ -z "${MQTT_TLS_CERT_DOMAIN}" ]; then
  echo "ERROR: MQTT_TLS_CERT_DOMAIN 或 CERTBOT_PRIMARY_DOMAIN 未设置" >&2
  exit 1
fi

if [ ! -f "${template}" ]; then
  echo "ERROR: missing template ${template}" >&2
  exit 1
fi

envsubst '${MQTT_TLS_PORT} ${MQTT_UPSTREAM_HOST} ${MQTT_UPSTREAM_PORT} ${MQTT_TLS_CERT_DOMAIN}' \
  < "${template}" > "${output}"

echo "Generated MQTT stream: ${output} (tls :${MQTT_TLS_PORT} -> ${MQTT_UPSTREAM_HOST}:${MQTT_UPSTREAM_PORT}, cert live/${MQTT_TLS_CERT_DOMAIN})"
