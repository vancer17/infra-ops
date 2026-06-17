#!/usr/bin/env bash
# =============================================================================
# Dev Gateway 本地运维快捷命令
# 在 docker/dev-gateway 目录下执行
# =============================================================================

COMPOSE := docker compose
ENV_FILE := .env

.PHONY: help build up down ps logs logs-init logs-renew logs-nginx verify issue-staging config

help:
	@echo "Dev Gateway Compose targets:"
	@echo "  make build          构建 certbot-init / certbot-renew / nginx 镜像"
	@echo "  make up             启动全栈（init → renew healthy → nginx）"
	@echo "  make down           停止 nginx / renew（保留 letsencrypt 卷）"
	@echo "  make ps             查看服务状态"
	@echo "  make logs           跟踪 renew + nginx 日志"
	@echo "  make verify         运行验收脚本（需已配置 .env）"
	@echo "  make issue-staging  使用 LE Staging 重新跑 init（验证 DNS-01）"
	@echo "  make config         校验 compose 配置渲染结果"

build:
	$(COMPOSE) build

up: $(ENV_FILE)
	$(COMPOSE) up -d --build

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
	@echo "缺少 .env：请执行 cp .env.example .env 并填写凭据" >&2
	@exit 1
