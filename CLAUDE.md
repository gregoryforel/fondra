# Recipe Platform — Claude Code Instructions

## Architecture

This is a **data-first, SQL-first** recipe platform. Core principles:

- **SQL is the source of truth.** Raw SQL lives in `/db/sql/`, sqlc generates Go types into `/internal/dbgen/`. Never edit generated code.
- **Compiled recipes pattern.** When a recipe is saved, a "compilation" pipeline resolves the sub-recipe DAG, aggregates nutrition, consolidates the grocery list, collects allergens, and writes the result to `compiled_recipes`. The website reads compiled data, never recomputes on the fly.
- **Metric storage, US display.** All quantities are stored in metric (grams, ml, °C). US units are computed at display time using per-ingredient density factors for volume↔weight conversions.
- **No ORM.** Direct SQL queries, sqlc code generation.

## Stack

- Go 1.22+ with net/http stdlib router (no frameworks)
- PostgreSQL 17
- sqlc for type-safe SQL
- templ for server-rendered HTML components
- htmx for dynamic HTML partials
- Alpine.js for client-side interactivity (unit toggle)
- pgx/v5 as the Postgres driver

## Project Structure

```
/cmd/server/          — Main entry point
/internal/handler/    — HTTP handlers (HTML + JSON)
/internal/middleware/  — Logging, recovery, auth stub, unit preference
/internal/dbgen/      — sqlc-generated code (DO NOT EDIT)
/internal/domain/     — Business logic (compile, grocery rollup)
/internal/convert/    — Unit conversion (metric ↔ US)
/db/migrations/       — Numbered SQL migrations
/db/sql/              — sqlc query files
/db/seed/             — Seed data SQL
/web/templates/       — templ component files
/web/static/          — CSS, static assets
/web/islands/         — Future Svelte islands (placeholder)
/mobile/              — Future Flutter app (placeholder)
/docs/                — Architecture and dev docs
```

## How to Run

```bash
# Start Postgres
make up

# Run migrations
make migrate

# Load seed data
make seed

# Compile all recipes (populates compiled_recipes table)
make compile-recipes

# Run the server
make dev
```

## Coding Conventions

1. **SQL first.** Write SQL in `/db/sql/`, run `make sqlc` to regenerate Go types.
2. **templ for HTML.** Write `.templ` files in `/web/templates/`, run `make templ` to generate Go files.
3. **htmx partials.** For dynamic updates, create a partial handler returning an HTML fragment and a full-page handler that wraps it in the layout.
4. **Unit system.** Everything stored metric. Use `/internal/convert/` for display conversions. Never store US units in the database.
5. **i18n ready.** Per-entity translation tables exist (`recipe_translations`, `ingredient_translations`, `step_translations`). Currently English only.
6. **Tags.** Recipes support tags via `tags` + `recipe_tags` tables. Categories: cuisine, meal_type, difficulty, course, technique, season. Compiled into `compiled_tags` text array.
7. **Stale cascade.** A database trigger (`mark_ancestors_stale`) automatically marks a recipe and all its DAG ancestors as stale when sub-recipe data changes. Use `CompileAllRecipes(ctx, pool, true)` to recompile only stale recipes.
8. **Explicit column lists.** Never use `SELECT cr.*` with positional scanning in handlers — always list columns explicitly to prevent breakage when columns are added.

## Schema Changes

1. Write a new migration SQL file in `/db/migrations/` (numbered: `009_*.up.sql`)
2. Run `make migrate`
3. Update sqlc queries in `/db/sql/` if needed
4. Run `make sqlc`
5. Update Go code to use new types

## Definition of Done

- [ ] Migration runs cleanly (`make migrate`)
- [ ] sqlc regenerates without errors (`make sqlc`)
- [ ] templ compiles (`make templ`)
- [ ] Tests pass (`make test`)
- [ ] Compilation pipeline handles new fields

## Safety Rules

- **Never commit secrets.** No `.env` files, no API keys, no passwords in code.
- **No auto-executing hooks.** `.claude/settings.json` has no hooks configured.
- **No real `.env` file in repo.** Only `.env.example` is committed.
- **No destructive migrations without review.** Always create `*.down.sql` files.
