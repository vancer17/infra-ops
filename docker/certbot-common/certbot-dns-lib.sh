#!/usr/bin/env bash
# 供 certbot-init / certbot-renew 共用的 DNS-01 辅助函数

certbot_dns_log() { printf '[certbot-dns] %s\n' "$*"; }
certbot_dns_die() { certbot_dns_log "ERROR: $*"; exit 1; }

certbot_dns_require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || certbot_dns_die "环境变量 ${name} 未设置"
}

certbot_dns_primary_domain() {
  read -r -a _domains <<< "${CERTBOT_DOMAINS}"
  printf '%s' "${_domains[0]}"
}

certbot_dns_write_aliyun_credentials() {
  certbot_dns_require_env ALIYUN_DNS_ACCESS_KEY
  certbot_dns_require_env ALIYUN_DNS_ACCESS_KEY_SECRET

  local cred_file="${CERTBOT_DNS_CREDENTIALS:-/etc/letsencrypt/aliyun-dns.ini}"
  install -d -m 0700 "$(dirname "${cred_file}")"
  cat > "${cred_file}" <<EOF
dns_aliyun_access_key = ${ALIYUN_DNS_ACCESS_KEY}
dns_aliyun_access_key_secret = ${ALIYUN_DNS_ACCESS_KEY_SECRET}
EOF
  chmod 600 "${cred_file}"
  certbot_dns_log "已写入 DNS 凭据: ${cred_file}"
}

certbot_dns_build_domain_args() {
  local d
  read -r -a domains <<< "${CERTBOT_DOMAINS}"
  for d in "${domains[@]}"; do
    printf '%s\n' "-d" "${d}"
  done
}

certbot_dns_cert_path() {
  local primary
  primary="$(certbot_dns_primary_domain)"
  printf '%s/live/%s/fullchain.pem' "${LETSENCRYPT_DIR:-/etc/letsencrypt}" "${primary}"
}

certbot_dns_cert_exists_and_valid() {
  local cert min_days="${1:-30}"
  cert="$(certbot_dns_cert_path)"
  [[ -f "${cert}" ]] || return 1
  openssl x509 -checkend $((min_days * 86400)) -noout -in "${cert}" 2>/dev/null
}

certbot_dns_staging_args() {
  if [[ "${CERTBOT_STAGING:-0}" == "1" ]]; then
    certbot_dns_log "使用 Let's Encrypt STAGING（证书不受微信信任）"
    printf '%s\n' --staging
  fi
}

certbot_dns_issue_once() {
  local cred_file="${CERTBOT_DNS_CREDENTIALS:-/etc/letsencrypt/aliyun-dns.ini}"
  local propagation="${CERTBOT_DNS_PROPAGATION_SECONDS:-90}"
  local primary rsa_key_size="${CERTBOT_RSA_KEY_SIZE:-4096}"
  local -a domain_args staging_args cmd

  mapfile -t domain_args < <(certbot_dns_build_domain_args)
  mapfile -t staging_args < <(certbot_dns_staging_args)
  primary="$(certbot_dns_primary_domain)"

  cmd=(
    certbot certonly
    --non-interactive
    --agree-tos
    --email "${CERTBOT_EMAIL}"
    --preferred-challenges dns-01
    --authenticator dns-aliyun
    --dns-aliyun-credentials "${cred_file}"
    --dns-aliyun-propagation-seconds "${propagation}"
    --rsa-key-size "${rsa_key_size}"
    --cert-name "${primary}"
    --keep-until-expiring
  )

  if ((${#staging_args[@]})); then
    cmd+=("${staging_args[@]}")
  fi
  cmd+=("${domain_args[@]}")

  certbot_dns_log "执行 DNS-01 签发: ${cmd[*]}"
  "${cmd[@]}"
}

certbot_dns_renew_once() {
  local -a cmd staging_args
  mapfile -t staging_args < <(certbot_dns_staging_args)

  cmd=(
    certbot renew
    --no-random-sleep-on-renew
  )
  if ((${#staging_args[@]})); then
    cmd+=("${staging_args[@]}")
  fi
  if [[ "${CERTBOT_QUIET:-1}" == "1" ]]; then
    cmd+=(--quiet)
  fi
  if [[ -n "${CERTBOT_DEPLOY_HOOK:-}" ]]; then
    cmd+=(--deploy-hook "${CERTBOT_DEPLOY_HOOK}")
  fi

  certbot_dns_log "执行 DNS-01 renew 检查..."
  "${cmd[@]}"
}
