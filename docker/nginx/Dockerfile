# =============================================================================
# Dev 业务层 Nginx 容器
#
# 构建（在 docker/ 目录下）：
#   docker build -f nginx/Dockerfile -t infra-ops/dev-nginx:latest .
#
# 基础信息：
#   - 镜像内置公网 HTTPS、WG 内网 HTTP 与 MQTT stream 模板。
#   - device-management-system 通过 /device-management 路径隔离，API 反代到
#     宿主机 127.0.0.1:18080，前端静态目录由 Compose 只读挂载。
# =============================================================================

FROM nginx:1.26-alpine

RUN rm -f /etc/nginx/conf.d/default.conf

# build context 为 docker/（与 dev-gateway compose context: .. 一致），路径须带 nginx/ 前缀
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/templates/dev-app.conf.template /etc/nginx/templates/dev-app.conf.template
COPY nginx/templates/internal-http.conf.template /etc/nginx/internal-templates/internal-http.conf.template
COPY nginx/stream-templates/mqtt-stream.conf.template /etc/nginx/stream-templates/mqtt-stream.conf.template
COPY nginx/docker-entrypoint.d/04-device-management.envsh /docker-entrypoint.d/04-device-management.envsh
COPY nginx/docker-entrypoint.d/50-internal-http.sh /docker-entrypoint.d/50-internal-http.sh
COPY nginx/docker-entrypoint.d/60-mqtt-stream.sh /docker-entrypoint.d/60-mqtt-stream.sh

RUN chmod +x /docker-entrypoint.d/04-device-management.envsh \
    && chmod +x /docker-entrypoint.d/50-internal-http.sh \
    && chmod +x /docker-entrypoint.d/60-mqtt-stream.sh \
    && mkdir -p /var/log/nginx /etc/nginx/stream.d /etc/nginx/stream-templates /etc/nginx/internal-templates
