# =============================================================================
# Container A — certbot-init
# 首次 DNS-01 向 Let's Encrypt 申请证书（一次性任务）
#
# 构建（在 docker/ 目录下；基础镜像 certbot/certbot 可走 Docker 镜像加速，与自建 tag 无关）：
#   docker build -f certbot-init/Dockerfile -t infra-ops/certbot-init:1.0.0 .
# =============================================================================

FROM certbot/certbot:v2.11.0

USER root

RUN apk add --no-cache bash curl openssl \
    && pip install --no-cache-dir certbot-dns-aliyun \
    && mkdir -p /etc/letsencrypt /var/run/certbot-renew

COPY certbot-common/certbot-dns-lib.sh /usr/local/lib/certbot-dns-lib.sh
COPY certbot-init/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/lib/certbot-dns-lib.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
