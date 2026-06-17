# =============================================================================
# Container B — certbot-renew
# 证书就绪门控 + DNS-01 续期；续期成功后 reload Nginx
#
# 构建（在 docker/ 目录下）：
#   docker build -f certbot-renew/Dockerfile -t infra-ops/certbot-renew:latest .
# =============================================================================

FROM certbot/certbot:v2.11.0

USER root

RUN apk add --no-cache bash curl openssl \
    && pip install --no-cache-dir certbot-dns-aliyun \
    && mkdir -p /etc/letsencrypt /var/run/certbot-renew

COPY certbot-common/certbot-dns-lib.sh /usr/local/lib/certbot-dns-lib.sh
COPY certbot-renew/entrypoint.sh certbot-renew/reload-nginx.sh /usr/local/bin/
RUN chmod +x /usr/local/lib/certbot-dns-lib.sh /usr/local/bin/entrypoint.sh /usr/local/bin/reload-nginx.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
