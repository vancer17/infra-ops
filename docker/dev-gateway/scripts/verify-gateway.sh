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

# Compose .env 由 docker compose 读取；本脚本仅需少量变量。
# 勿对含空格的整文件 source（NGINX_SERVER_NAMES 等会触发「command not found」）。
read_env() {
  local key="$1"
  grep -E "^${key}=" .env | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

PRIMARY="$(read_env CERTBOT_PRIMARY_DOMAIN)"
SERVER_NAMES="$(read_env NGINX_SERVER_NAMES)"
UPSTREAM_HOST="$(read_env APP_UPSTREAM_HOST)"
UPSTREAM_PORT="$(read_env APP_UPSTREAM_PORT)"
CERTBOT_STAGING="$(read_env CERTBOT_STAGING)"
UPSTREAM_HOST="${UPSTREAM_HOST:-127.0.0.1}"
UPSTREAM_PORT="${UPSTREAM_PORT:-8080}"
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

# --- Docker 网段：不得与 VPC RDS(172.20)/ECS(172.21) 重叠 ---
while IFS= read -r net_line; do
  [[ -z "${net_line}" ]] && continue
  n="${net_line%% *}"
  s="${net_line#* }"
  case "${s}" in
    172.20.*|172.21.*)
      fail "Docker 网络 ${n} 子网 ${s} 与 VPC 冲突，会导致 RDS 不可达"
      ;;
  esac
done < <(
  docker network ls --format '{{.Name}}' | while read -r n; do
    s="$(docker network inspect "$n" -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)"
    [[ -n "${s}" ]] && printf '%s %s\n' "$n" "$s"
  done
)

gw_net="dev-gateway-certbot-internal"
if docker network inspect "${gw_net}" >/dev/null 2>&1; then
  gw_subnet="$(docker network inspect "${gw_net}" -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}')"
  echo "certbot-internal 子网: ${gw_subnet}"
  case "${gw_subnet}" in
    172.20.*|172.21.*)
      fail "Docker 网络 ${gw_net} 子网 ${gw_subnet} 与 VPC 冲突，会导致 RDS 不可达"
      ;;
    172.30.0.0/24)
      ok "certbot-internal 子网为 ${gw_subnet}"
      ;;
    *)
      ok "certbot-internal 子网未占用 VPC 段（当前 ${gw_subnet}）"
      ;;
  esac
else
  echo "WARN: 未找到网络 ${gw_net}"
fi

# --- RDS 路由（若可解析内网域名）---
if command -v getent >/dev/null 2>&1; then
  rds_ip="$(getent hosts rm-bp1wjjf373l7t331v.mysql.rds.aliyuncs.com 2>/dev/null | awk '{print $1}' | head -1 || true)"
  if [[ -n "${rds_ip}" ]] && command -v ip >/dev/null 2>&1; then
    route_dev="$(ip route get "${rds_ip}" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)"
    if [[ "${route_dev}" == br-* ]]; then
      fail "RDS ${rds_ip} 路由走 Docker 网桥 ${route_dev}，连库将失败"
    elif [[ -n "${route_dev}" ]]; then
      ok "RDS ${rds_ip} 路由走 ${route_dev}（非 docker 网桥）"
    fi
  fi
fi

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
  if curl -sf --max-time 15 "http://${UPSTREAM}/readyz" >/dev/null 2>&1; then
    ok "上游 http://${UPSTREAM}/readyz 可达（RDS 就绪）"
  else
    echo "WARN: /readyz 不可达或超时（检查 RDS 路由与数据库）"
  fi
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
