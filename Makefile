.PHONY: up down start stop logs sqlc templ test \
       deploy-build deploy-up deploy-down deploy-logs deploy-ps

# Local dev — everything in Docker
start:
	docker compose up --build

stop:
	docker compose down

logs:
	docker compose logs -f

# Aliases
up: start
down: stop

# Code generation
sqlc:
	sqlc generate

templ:
	templ generate

# Tests
test:
	go test ./... -v -count=1

# ---- Production (deploy/docker-compose.prod.yml) ----
PROD_COMPOSE = docker compose -f deploy/docker-compose.prod.yml

deploy-build:
	$(PROD_COMPOSE) build

deploy-up:
	$(PROD_COMPOSE) up -d

deploy-down:
	$(PROD_COMPOSE) down

deploy-logs:
	$(PROD_COMPOSE) logs -f

deploy-ps:
	$(PROD_COMPOSE) ps
