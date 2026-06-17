#!/usr/bin/env bash
# =============================================================================
# Dev Gateway 本地运维快捷命令
# 镜像：本地 tag infra-ops/*（make -C ~/infra-ops build-gateway-images）
# =============================================================================

COMPOSE := docker compose
ENV_FILE := .env

.PHONY: help pull up down ps logs logs-init logs-renew logs-nginx verify issue-staging config

help:
	@echo "Dev Gateway Compose targets:"
	@echo "  make up             启动全栈（需本机已 build infra-ops/* 镜像）"
	@echo "  make down           停止服务（保留 letsencrypt 卷）"
	@echo "  make ps / make logs / make verify"
	@echo ""
	@echo "构建镜像（仓库根）：make build-gateway-images"
	@echo "导出 tar（跨机）：  make save-gateway-images"

up: $(ENV_FILE)
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
	@echo "缺少 .env：cp .env.example .env（GATEWAY_IMAGE_* 使用 infra-ops/*:tag）" >&2
	@exit 1
