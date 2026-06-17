# =============================================================================
# Dev 业务层 Nginx 容器
#
# 构建（在 docker/ 目录下）：
#   docker build -f nginx/Dockerfile -t infra-ops/dev-nginx:latest .
# =============================================================================

FROM nginx:1.26-alpine

RUN rm -f /etc/nginx/conf.d/default.conf

COPY templates/dev-app.conf.template /etc/nginx/templates/dev-app.conf.template
COPY templates/internal-http.conf.template /etc/nginx/templates/internal-http.conf.template
COPY docker-entrypoint.d/50-internal-http.sh /docker-entrypoint.d/50-internal-http.sh

RUN chmod +x /docker-entrypoint.d/50-internal-http.sh \
    && mkdir -p /var/log/nginx
