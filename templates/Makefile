# Thin shim: every target calls helpoupou (https://github.com/elopin42/helpoupou).
# Project behaviour lives in helpoupou.conf and .helpoupou/hooks/, not here.

.DEFAULT_GOAL := menu
.PHONY: menu dev prod up down restart ps logs shell doctor help

menu: ## Open the helpoupou menu
	@helpoupou

dev: ## Start the stack in dev mode
	@helpoupou --mode dev up

prod: ## Deploy / redeploy in production mode
	@helpoupou --mode prod up

up: ## Start in this machine's mode
	@helpoupou up

down: ## Stop the stack (volumes are kept)
	@helpoupou down

restart: ## Restart the services
	@helpoupou restart

ps: ## Show the services
	@helpoupou ps

logs: ## Follow the logs (SERVICE=name to pick one)
	@helpoupou logs $(SERVICE)

shell: ## Open a shell (SERVICE=name to pick one)
	@helpoupou shell $(SERVICE)

doctor: ## Health report
	@helpoupou doctor

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
