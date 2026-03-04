.PHONY: up down migrate seed sqlc templ test compile-recipes dev build clean \
       deploy-build deploy-up deploy-down deploy-logs deploy-ps

DATABASE_URL ?= postgres://recipe:recipe@localhost:5433/recipe_platform?sslmode=disable

# Docker compose
up:
	docker compose up -d

down:
	docker compose down

# Run migrations in order
migrate:
	@echo "Running migrations..."
	@for f in db/migrations/*_*.up.sql; do \
		echo "  Applying $$f..."; \
		psql "$(DATABASE_URL)" -f "$$f"; \
	done
	@echo "Migrations complete."

# Run seed data
seed:
	@echo "Seeding data..."
	@for f in db/seed/*.sql; do \
		echo "  Loading $$f..."; \
		psql "$(DATABASE_URL)" -f "$$f"; \
	done
	@echo "Seed data loaded."

# Regenerate sqlc
sqlc:
	sqlc generate

# Regenerate templ
templ:
	templ generate

# Run tests
test:
	go test ./... -v -count=1

# Compile all recipes
compile-recipes:
	go run ./cmd/server compile-recipes

# Development with hot reload (requires air: go install github.com/air-verse/air@latest)
dev:
	air -c .air.toml 2>/dev/null || go run ./cmd/server

# Build binary
build: templ
	go build -o bin/server ./cmd/server

# Clean build artifacts
clean:
	rm -rf bin/ tmp/

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
