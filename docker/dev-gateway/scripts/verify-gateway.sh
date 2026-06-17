#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Dev Gateway 验收脚本（在 dev-01 或已部署主机上、dev-gateway 目录内执行）
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${COMPOSE_DIR}"

if [[ ! -f .env ]]; then
  echo "ERROR: 缺少 ${COMPOSE_DIR}/.env" >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a
source .env
set +a

PRIMARY="${CERTBOT_PRIMARY_DOMAIN:-}"
SERVER_NAMES="${NGINX_SERVER_NAMES:-}"
UPSTREAM_HOST="${APP_UPSTREAM_HOST:-127.0.0.1}"
UPSTREAM_PORT="${APP_UPSTREAM_PORT:-8080}"
UPSTREAM="${UPSTREAM_HOST}:${UPSTREAM_PORT}"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

echo "=== Dev Gateway 验收 ==="
echo "主域名: ${PRIMARY}"
echo "Nginx server_name: ${SERVER_NAMES}"
echo "上游: ${UPSTREAM}"
echo

# --- Compose 服务状态 ---
docker compose ps -a || fail "docker compose ps 失败"

if ! docker compose ps --status running | grep -q dev-gateway-certbot-renew; then
  fail "certbot-renew 未运行"
fi
ok "certbot-renew 运行中"

if ! docker compose ps --status running | grep -q dev-gateway-nginx; then
  fail "nginx 未运行"
fi
ok "nginx 运行中"

# --- 证书卷 ---
cert_path="/etc/letsencrypt/live/${PRIMARY}/fullchain.pem"
if ! docker compose exec -T certbot-renew test -f "${cert_path}"; then
  fail "证书不存在: ${cert_path}"
fi
ok "LE 证书文件存在"

if ! docker compose exec -T certbot-renew openssl x509 -checkend 86400 -noout -in "${cert_path}"; then
  fail "证书 24 小时内过期或无效"
fi
ok "证书有效期 > 24h"

issuer="$(docker compose exec -T certbot-renew openssl x509 -noout -issuer -in "${cert_path}" | sed 's/issuer=//')"
echo "证书颁发者: ${issuer}"

if [[ "${CERTBOT_STAGING:-0}" != "1" ]] && [[ "${issuer}" != *"Let's Encrypt"* ]]; then
  echo "WARN: 非 Let's Encrypt 颁发者（若为 Staging 可忽略）"
fi

# --- ready 门控 ---
if ! docker compose exec -T certbot-renew test -f /var/run/certbot-renew/ready; then
  fail "certbot-renew ready 文件不存在"
fi
ok "证书就绪门控已标记"

# --- Nginx 配置 ---
docker compose exec -T nginx nginx -t || fail "nginx -t 失败"
ok "nginx -t 通过"

# --- HTTP 探测 ---
if ! command -v curl >/dev/null 2>&1; then
  echo "SKIP: 未安装 curl，跳过 HTTP 探测"
  echo
  echo "=== 验收完成 ==="
  exit 0
fi

# 上游：优先 /healthz（PetIntelli），否则 /（占位 API）
if curl -sf --max-time 5 "http://${UPSTREAM}/healthz" >/dev/null 2>&1; then
  ok "上游 http://${UPSTREAM}/healthz 可达（operational 应用）"
elif curl -sf --max-time 5 "http://${UPSTREAM}/" >/dev/null 2>&1; then
  ok "上游 http://${UPSTREAM}/ 可达（placeholder 应用）"
else
  echo "WARN: 上游不可达（应用未启动？）"
fi

if [[ -n "${PRIMARY}" ]]; then
  # 公网 HTTPS：优先 /healthz，否则 Nginx 静态 /health
  if curl -sf --max-time 10 "https://${PRIMARY}/healthz" >/dev/null 2>&1; then
    ok "HTTPS https://${PRIMARY}/healthz 可达（未跳过证书校验）"
  elif curl -sf --max-time 10 "https://${PRIMARY}/health" >/dev/null 2>&1; then
    ok "HTTPS https://${PRIMARY}/health 可达（Nginx 静态探针）"
  else
    echo "WARN: https://${PRIMARY}/healthz 与 /health 均失败（DNS/安全组/证书？）"
  fi
fi

echo
echo "=== 验收完成 ==="
