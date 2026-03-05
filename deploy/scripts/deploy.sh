#!/usr/bin/env bash
# Deploy script — runs ON the Hetzner server.
# Called by GitHub Actions or manually via SSH.
#
# Usage: ssh deploy@your-server 'bash /srv/recipes/deploy/scripts/deploy.sh'

set -euo pipefail

APP_DIR="/srv/recipes"
COMPOSE_FILE="deploy/docker-compose.prod.yml"

cd "$APP_DIR"

echo "=== Deploying Recipe Platform ==="

# Pull latest code
echo "[1/4] Pulling latest code..."
git pull origin main

# Pull pre-built image from GHCR and restart
echo "[2/4] Pulling container images..."
docker compose -f "$COMPOSE_FILE" --env-file .env pull app

echo "[3/4] Starting containers..."
docker compose -f "$COMPOSE_FILE" --env-file .env up -d

echo "      Restarting Caddy to reload config..."
docker compose -f "$COMPOSE_FILE" --env-file .env restart caddy

# Run migrations inside the app container
echo "[4/4] Running migrations..."
docker compose -f "$COMPOSE_FILE" --env-file .env exec -T app sh -c '
    for f in /app/db/migrations/*_*.up.sql; do
        echo "  Applying $f..."
        PGPASSWORD="${POSTGRES_PASSWORD:-recipe}" psql -h postgres -U "${POSTGRES_USER:-recipe}" -d "${POSTGRES_DB:-recipe_platform}" -f "$f" 2>&1 || true
    done
'

echo ""
echo "=== Deployment complete ==="
echo "Checking health..."
sleep 3
docker compose -f "$COMPOSE_FILE" --env-file .env exec -T app wget -qO- http://localhost:8080/health || echo "Warning: health check failed"
