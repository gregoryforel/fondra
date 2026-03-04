#!/bin/sh
set -eu

psql_cmd() {
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 "$@"
}

echo "Ensuring migration metadata tables..."
psql_cmd <<'SQL'
CREATE TABLE IF NOT EXISTS codex_migrations (
    name TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS codex_seeds (
    name TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

# Legacy bootstrap compatibility:
# If this DB already has schema objects but no migration metadata,
# record current files as applied so we do not replay everything.
schema_exists="$(psql "$DATABASE_URL" -tA -c "SELECT to_regclass('public.app_users') IS NOT NULL;")"
migration_count="$(psql "$DATABASE_URL" -tA -c "SELECT count(*) FROM codex_migrations;")"
seed_count="$(psql "$DATABASE_URL" -tA -c "SELECT count(*) FROM codex_seeds;")"

if [ "$schema_exists" = "t" ] && [ "$migration_count" = "0" ]; then
    echo "Detected existing schema with no migration metadata. Baselining migrations..."
    for f in /app/db/migrations/*_*.up.sql; do
        name="$(basename "$f")"
        psql_cmd -c "INSERT INTO codex_migrations(name) VALUES ('$name') ON CONFLICT DO NOTHING;"
    done
fi

if [ "$schema_exists" = "t" ] && [ "$seed_count" = "0" ]; then
    echo "Detected existing schema with no seed metadata. Baselining seeds..."
    for f in /app/db/seed/*.sql; do
        name="$(basename "$f")"
        psql_cmd -c "INSERT INTO codex_seeds(name) VALUES ('$name') ON CONFLICT DO NOTHING;"
    done
fi

echo "Running pending migrations..."
for f in /app/db/migrations/*_*.up.sql; do
    name="$(basename "$f")"
    applied="$(psql "$DATABASE_URL" -tA -c "SELECT EXISTS (SELECT 1 FROM codex_migrations WHERE name = '$name');")"
    if [ "$applied" = "t" ]; then
        continue
    fi

    echo "  Applying $name..."
    psql_cmd -f "$f"
    psql_cmd -c "INSERT INTO codex_migrations(name) VALUES ('$name');"
done

echo "Running pending seeds..."
for f in /app/db/seed/*.sql; do
    name="$(basename "$f")"
    applied="$(psql "$DATABASE_URL" -tA -c "SELECT EXISTS (SELECT 1 FROM codex_seeds WHERE name = '$name');")"
    if [ "$applied" = "t" ]; then
        continue
    fi

    echo "  Loading $name..."
    psql_cmd -f "$f"
    psql_cmd -c "INSERT INTO codex_seeds(name) VALUES ('$name');"
done

echo "Compiling recipes..."
/app/server compile-recipes

echo "Starting server..."
exec /app/server
