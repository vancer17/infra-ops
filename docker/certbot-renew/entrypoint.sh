#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# certbot-renew
#   1) 等待 certbot-init 写入的有效 LE 证书
#   2) 写入 /var/run/certbot-renew/ready → Compose healthcheck 放行 Nginx
#   3) 前台循环 DNS-01 renew；续期成功后 reload Nginx
# ---------------------------------------------------------------------------

LETSENCRYPT_DIR="${LETSENCRYPT_DIR:-/etc/letsencrypt}"
RENEW_INTERVAL_SECONDS="${RENEW_INTERVAL_SECONDS:-43200}"
READY_FILE="${CERTBOT_READY_FILE:-/var/run/certbot-renew/ready}"
WAIT_FOR_CERT_SEC="${WAIT_FOR_CERT_SEC:-900}"
CERTBOT_DEPLOY_HOOK="${CERTBOT_DEPLOY_HOOK:-/usr/local/bin/reload-nginx.sh}"

# shellcheck source=/usr/local/lib/certbot-dns-lib.sh
source /usr/local/lib/certbot-dns-lib.sh

log() { printf '[certbot-renew] %s\n' "$*"; }

wait_for_valid_cert() {
  local elapsed=0 cert
  cert="$(certbot_dns_cert_path)"

  log "等待有效 LE 证书: ${cert} (最长 ${WAIT_FOR_CERT_SEC}s)"
  while (( elapsed < WAIT_FOR_CERT_SEC )); do
    if certbot_dns_cert_exists_and_valid 1; then
      log "检测到有效证书"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  certbot_dns_die "在 ${WAIT_FOR_CERT_SEC}s 内未等到有效证书，请检查 certbot-init 日志与阿里云 DNS API 凭据"
}

mark_ready() {
  install -d -m 0755 "$(dirname "${READY_FILE}")"
  date -Iseconds > "${READY_FILE}"
  log "已标记证书就绪: ${READY_FILE}（Nginx 可启动）"
}

print_cert_expiry() {
  local cert
  cert="$(certbot_dns_cert_path)"
  [[ -f "${cert}" ]] || return 0
  log "证书到期: $(openssl x509 -enddate -noout -in "${cert}" | cut -d= -f2-)"
}

renew_loop() {
  while true; do
    certbot_dns_write_aliyun_credentials
    certbot_dns_renew_once || log "WARN: renew 检查未成功，将在下一周期重试"
    print_cert_expiry
    log "休眠 ${RENEW_INTERVAL_SECONDS}s ..."
    sleep "${RENEW_INTERVAL_SECONDS}"
  done
}

main() {
  certbot_dns_require_env CERTBOT_DOMAINS

  log "续期服务启动；挑战方式 DNS-01；轮询间隔 ${RENEW_INTERVAL_SECONDS}s"

  wait_for_valid_cert
  mark_ready
  print_cert_expiry

  renew_loop
}

main "$@"
