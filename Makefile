# —— Inspired by ——————————————————————————————————————————————————————————————
# https://speakerdeck.com/mykiwi/outils-pour-ameliorer-la-vie-des-developpeurs-CONSOLE?slide=47
# https://blog.theodo.fr/2018/05/why-you-need-a-makefile-on-your-project/

ENV_FILE = .env

-include $(ENV_FILE)
-include .env.local
-include api/.env
-include api/.env.local

PROJECT        = organizaer
DOCKER_COMPOSE = docker compose

# Docker containers
PHP_CONT = $(DOCKER_COMPOSE) exec php
NODE = $(DOCKER_COMPOSE) exec pwa
# Executables
PHP      = $(PHP_CONT) php -d memory_limit=-1
COMPOSER = $(PHP_CONT) composer
PHP_NO_TTY = $(DOCKER_COMPOSE) exec -T php php

GIT      = git
CONSOLE  = $(PHP) bin/console -e $(APP_ENV)

CONSOLE_TEST = $(PHP) bin/console -e test

CURRENT_BRANCH := $(shell git name-rev --name-only HEAD)

# Misc
.DEFAULT_GOAL = help
.PHONY        : help docker-build docker-up docker-start docker-down docker-logs sh composer vendor sf cc start stop restart create-env-file

all: help

init: create-env-file docker-init install generate-certificate fixtures-dev test ## Initialize the project
start: docker-up ## Start the project
stop: docker-down ## Stop the project
restart: docker-restart ## Restart the project

help: ## Outputs this help screen
	@grep -E '(^[a-zA-Z0-9\./_-]+:.*?##.*$$)|(^##)' Makefile | awk 'BEGIN {FS = ":.*?## "}{printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

create-env-file:
	if [ ! -f $(ENV_FILE) ]; then cp $(ENV_FILE).dist $(ENV_FILE); fi

## —— Docker 🐳 ————————————————————————————————————————————————————————————————
docker-build-no-cache: ## Builds the Docker images
	@$(DOCKER_COMPOSE) build --pull --no-cache

docker-build: ## Builds the Docker images
	@$(DOCKER_COMPOSE) build --pull

docker-up: ## Start the docker hub in detached mode (no logs)
	@$(DOCKER_COMPOSE) up --detach

docker-init: docker-build-no-cache docker-up docker-cert-gateway ## Build and start the containers

docker-down: ## Stop the docker hub
	@$(DOCKER_COMPOSE) down --remove-orphans

docker-restart: docker-down docker-up  ## STOP AND RESTART

docker-logs: ## Show live logs
	@$(DOCKER_COMPOSE) logs --tail=0 --follow

docker-cert-gateway: ## Generate certificate for gateway
	mkcert -cert-file docker/todo-app-cert.pem -key-file docker/todo-app-key.pem "todo-app.com.localhost" "*.todo-app.com.localhost"
	docker cp docker/todo-app-key.pem traefik-reverse-proxy:/etc/traefik/ssl/todo-app-key.pem
	docker cp docker/todo-app-cert.pem traefik-reverse-proxy:/etc/traefik/ssl/todo-app-cert.pem
	docker cp docker/traefik-config.yaml traefik-reverse-proxy:/etc/traefik/config/todo-app.yaml

## —— Composer 🧙 ——————————————————————————————————————————————————————————————
composer: ## Run composer, pass the parameter "c=" to run a given command, example: make composer c='req symfony/orm-pack'
	@$(eval c ?=)
	@$(COMPOSER) $(c)

vendor: ## Install vendors according to the current composer.lock file
vendor: c=install --prefer-dist --no-dev --no-progress --no-scripts --no-interaction
vendor: composer

install: ## Install vendors according to the current composer.lock file
	$(COMPOSER) -n install --prefer-dist

install-no-script:
	$(COMPOSER) -n install --prefer-dist --no-scripts

## —— CONSOLE —————————————————————————————————————————————————————————————————
sh: ## Connect to the PHP FPM container
	@$(PHP_CONT) sh

sf: ## List CONSOLE commands
	$(CONSOLE)

cc: ## Clear cache
	$(CONSOLE) cache:clear

warmup: ## Warm up the cache
	$(CONSOLE) cache:warmup

## —— PWA ————————————————————————————————————————————————————————————————————
pwa-install: ## Install PWA dependencies
	$(NODE) yarn install
eslint: ## Launch ESLINT
	$(NODE) yarn lint

## —— Test ————————————————————————————————————————————————————————————————————
test: ## Launch all tests
	$(CONSOLE_TEST) cache:warmup
	$(PHP) bin/phpunit --no-coverage

test-unit: ## Launch unit tests
	$(PHP) bin/phpunit --no-coverage --testsuite UnitTest

coverage: fixtures-test ## Launch all tests with coverage
	$(PHP) -dpcov.enabled=1 bin/phpunit --coverage-html .build/coverage --coverage-clover .build/clover.xml

## —— FIXTURE ———————————————————————————————————————————————————————————————
fixtures-dev: ## Load fixtures for dev
	$(CONSOLE) doctrine:fixtures:load -n

fixtures-test: ## Load fixtures for test
	$(CONSOLE_TEST) doctrine:fixtures:load -n

## —— Code Style ——————————————————————————————————————————————————————————————
cs: php-cs-fixer phpcbf eslint ## Launch all linters

php-cs-fixer: ## Launch PHPCSFIXER
	$(PHP) vendor/bin/php-cs-fixer fix -v

phpcbf: ## Launch PHPCBF
	$(PHP) vendor/bin/phpcbf -p --standard=phpcs.xml.dist

phpcs: ## Launch PHPCS
	$(PHP) vendor/bin/phpcs -p --standard=phpcs.xml.dist

## —— Static analysis —————————————————————————————————————————————————————————
sa: phpstan psalm ## Launch all quality tools

warmup-dev: ## Ensure the dev cache is build for static analysis
	[[ ! -f api/var/cache/dev/App_KernelDevDebugContainer.php ]] && $(CONSOLE) cache:warmup || true

phpstan: warmup-dev ## Launch PHPSTAN
	$(PHP) vendor/bin/phpstan analyse -c phpstan.neon

psalm: warmup-dev ## Launch PSALM
	$(PHP) vendor/bin/psalm -c psalm.xml

rector: ## Launch RECTOR
	$(PHP) vendor/bin/rector

git-update: ## Update Git only and refresh cache (sf+pagespeed)
	git fetch
	git pull

## —— ASYNC ———————————————————————————————————————————————————————————————————
consume-stop: ## Stop all consumers
	$(CONSOLE) messenger:stop-workers

## —— UTIL ——————————————————————————————————————————————————————————————
check: php-cs-fixer phpcs phpstan eslint test ## Launch all linters and static analysis tools

generate-certificate: ## Generate certificate for JWT
	$(CONSOLE) lexik:jwt:generate-keypair --overwrite --no-interaction
