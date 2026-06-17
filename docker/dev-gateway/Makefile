#!/usr/bin/env bash
# =============================================================================
# Dev Gateway 本地运维快捷命令
# 在 docker/dev-gateway 目录下执行
#
# 镜像构建在仓库根：make build-gateway-images / scripts/docker/build-gateway-images.sh
# 目标机由 Ansible gateway-compose.yml pull + up（不在此 build）
# =============================================================================

COMPOSE := docker compose
ENV_FILE := .env

.PHONY: help pull up down ps logs logs-init logs-renew logs-nginx verify issue-staging config

help:
	@echo "Dev Gateway Compose targets:"
	@echo "  make pull           从 registry 拉取三件套镜像（需 .env 中 GATEWAY_IMAGE_*）"
	@echo "  make up             启动全栈（init → renew healthy → nginx），不 build"
	@echo "  make down           停止 nginx / renew（保留 letsencrypt 卷）"
	@echo "  make ps             查看服务状态"
	@echo "  make logs           跟踪 renew + nginx 日志"
	@echo "  make verify         运行验收脚本（需已配置 .env）"
	@echo "  make issue-staging  使用 LE Staging 重新跑 init（验证 DNS-01）"
	@echo "  make config         校验 compose 配置渲染结果"
	@echo ""
	@echo "构建/推送镜像（在仓库根目录）："
	@echo "  make build-gateway-images"
	@echo "  make push-gateway-images"

pull: $(ENV_FILE)
	$(COMPOSE) pull

up: $(ENV_FILE)
	$(COMPOSE) pull
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

ps:
	$(COMPOSE) ps -a

logs:
	$(COMPOSE) logs -f certbot-renew nginx

logs-init:
	$(COMPOSE) logs certbot-init

logs-renew:
	$(COMPOSE) logs -f certbot-renew

logs-nginx:
	$(COMPOSE) logs -f nginx

verify: $(ENV_FILE)
	@chmod +x scripts/verify-gateway.sh
	@./scripts/verify-gateway.sh

issue-staging: $(ENV_FILE)
	CERTBOT_STAGING=1 CERTBOT_FORCE_ISSUE=1 $(COMPOSE) run --rm certbot-init

config: $(ENV_FILE)
	$(COMPOSE) config

$(ENV_FILE):
	@echo "缺少 .env：请执行 cp .env.example .env 并填写凭据与 GATEWAY_IMAGE_*" >&2
	@exit 1
