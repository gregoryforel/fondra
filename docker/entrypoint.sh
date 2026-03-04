#!/bin/sh
set -e

echo "Running migrations..."
for f in /app/db/migrations/*_*.up.sql; do
    echo "  Applying $f..."
    psql "$DATABASE_URL" -f "$f" 2>&1 || true
done

echo "Running seeds..."
for f in /app/db/seed/*.sql; do
    echo "  Loading $f..."
    psql "$DATABASE_URL" -f "$f" 2>&1 || true
done

echo "Compiling recipes..."
/app/server compile-recipes

echo "Starting server..."
exec /app/server
