#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# certbot-init — DNS-01 首次签发（一次性）
# 不触发 Nginx reload；Nginx 在 certbot-renew 健康后再启动
# ---------------------------------------------------------------------------

LETSENCRYPT_DIR="${LETSENCRYPT_DIR:-/etc/letsencrypt}"
CERTBOT_FORCE_ISSUE="${CERTBOT_FORCE_ISSUE:-0}"

# shellcheck source=/usr/local/lib/certbot-dns-lib.sh
source /usr/local/lib/certbot-dns-lib.sh

log() { printf '[certbot-init] %s\n' "$*"; }

main() {
  certbot_dns_require_env CERTBOT_EMAIL
  certbot_dns_require_env CERTBOT_DOMAINS

  local primary
  primary="$(certbot_dns_primary_domain)"
  log "主域名: ${primary}"
  log "全部域名: ${CERTBOT_DOMAINS}"
  log "挑战方式: DNS-01 (dns-aliyun)"

  certbot_dns_write_aliyun_credentials

  if [[ "${CERTBOT_FORCE_ISSUE}" != "1" ]] && certbot_dns_cert_exists_and_valid; then
    log "有效证书已存在: $(certbot_dns_cert_path) — 跳过签发"
    exit 0
  fi

  certbot_dns_issue_once
  log "DNS-01 签发完成: $(certbot_dns_cert_path)"
  log "init 任务结束 (exit 0)；等待 certbot-renew 标记就绪后启动 Nginx"
}

main "$@"
