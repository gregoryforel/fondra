# Data Model Review Prompt for Fondra

Paste the following into GPT (or any LLM) for a thorough schema review.

---

## System prompt

You are a senior database architect specializing in PostgreSQL, food-tech platforms, and recipe management systems. You have deep expertise in nutritional data modeling (USDA FoodData Central), i18n patterns, graph-structured data (DAGs), and unit conversion systems. Be critical, specific, and actionable. Don't praise what works — focus on what's wrong, missing, or will break at scale.

## Context

**Fondra** is a data-first recipe platform. Core design principles:

- **SQL is the source of truth.** No ORM. Raw SQL queries, sqlc for Go type generation.
- **Compiled recipes pattern.** When a recipe is saved, a compilation pipeline resolves the full sub-recipe DAG, aggregates nutrition, consolidates the grocery list, collects allergens/diet flags/tags, and writes a denormalized result to `compiled_recipes`. The website reads compiled data only — never recomputes on the fly.
- **Metric storage, US display.** All quantities stored in metric (grams, ml, °C). US units computed at display time using per-ingredient density factors for volume↔weight conversion.
- **Sub-recipe DAG.** Recipes can reference other recipes as components (e.g., Beef Wellington → Puff Pastry). A trigger prevents cycles. A stale cascade trigger marks ancestors as stale when any sub-recipe changes.

**Stack:** Go 1.22+, PostgreSQL 17, pgx/v5, sqlc, templ (server-rendered HTML), htmx, Alpine.js.

**Current scale:** 3 demo recipes, 20 ingredients, 30 nutrients. Target: thousands of recipes, hundreds of ingredients, community contributions, mobile app (Flutter), multi-language support.

**Data sources:** USDA FoodData Central (SR Legacy + Foundation Foods) for nutrition. Open Food Facts for branded/packaged foods. EU14 + FALCPA for allergens. Densities from USDA Handbook 456 and King Arthur.

---

## Schema Source

Use the canonical schema from `db/migrations` (currently `001` through `018`).
Do not review the old inline SQL snapshot; it was removed to avoid drift.

When reviewing, derive the effective schema by applying migrations in order and include recent additions such as:
- statement-level stale triggers and ingredient/tag invalidation
- count-unit nutrition via `ingredient_portions`
- i18n translation expansion
- `compile_schema_version` and compile hash metadata
- `recipe_closure` plus queued rebuild via `recipe_closure_rebuild_queue`
- FK-backed auth tables: `recipe_user_permissions`, `recipe_org_permissions`
- FK-backed library ownership columns: `scope`, `user_id`, `organization_id`

---

## Compilation Pipeline (Go code behavior)

The compilation pipeline runs per recipe and does:

1. **Resolve grocery list** — Recursive CTE walks the sub-recipe DAG. Yield multiplier: `quantity / NULLIF(COALESCE(yield_amount, servings::numeric), 0)`. Quantities are normalized to each ingredient's `default_unit_id` using `units.to_base_factor` for same-dimension and `ingredient_densities.density_g_per_ml` for cross-dimension (volume↔mass). Grouped by `(ingredient_id, unit_id)`.

2. **Collect allergens** — Same recursive CTE, DISTINCT allergen names where `severity = 'contains'`.

3. **Collect diet flags** — Double NOT EXISTS: a flag is compatible only if ALL leaf ingredients explicitly have `compatible = true`. Missing rows = NOT compatible.

4. **Collect tags** — Simple join on `recipe_tags` → `tags`.

5. **Compute nutrition** — Grocery list quantities are converted to grams (mass units via `to_base_factor`, volume units via `to_base_factor * density`). Then `amount_per_100g * (grams / 100)` for each nutrient. Count/other dimension units are skipped.

6. **Upsert compiled_recipes** — All results written as JSONB + extracted columns. `is_stale = false`, `compiled_at = now()`.

---

## What I want you to review

Analyze this schema critically across the following dimensions. For each issue, state the severity (critical / important / minor / nitpick), explain why it matters, and propose a specific fix with SQL.

### 1. Correctness & Data Integrity
- Are there missing constraints, CHECK constraints, or foreign keys?
- Can invalid data sneak in? (nulls where there shouldn't be, orphaned rows, etc.)
- Are the trigger functions correct? Any edge cases they miss?
- Is the cycle prevention trigger complete?
- Does the stale cascade cover all mutation paths?

### 2. Nutrition & Unit Conversion
- Is `amount_per_100g` sufficient, or do some nutrients need different reference units?
- Does the density-based volume→mass conversion handle all real-world cases?
- What happens with "count" units (e.g., 2 eggs) for nutrition? Currently skipped — is that acceptable?
- Are there edge cases in the yield multiplier logic?

### 3. Scalability & Performance
- Which queries will be slow at 10K+ recipes, 1K+ ingredients?
- Are there missing indexes?
- Is the recursive CTE approach for DAG resolution viable at scale, or should we materialize the tree?
- Are there concerns with the per-row trigger approach for stale marking?
- JSONB vs. normalized tables for compiled data — right tradeoff?

### 4. Missing Features (for the target use case)
- Recipe versioning / edit history
- User-generated content (ratings, reviews, recipe forks)
- Meal planning / weekly plans
- Shopping list aggregation across multiple recipes
- Recipe scaling (adjusting servings dynamically)
- Prep-ahead / make-ahead annotations on steps
- Equipment/tool tracking per step
- Photo/media attachments
- Cost estimation per recipe

For each missing feature: is the current schema compatible (easy to extend), or does it need structural changes? Don't design the full feature — just flag what would need to change and whether it's additive or breaking.

### 5. i18n
- Are the per-entity translation tables complete? What entities are missing translations?
- How should the compilation pipeline handle multi-locale compiled data?
- Is `source_locale` on recipes sufficient for knowing which language the base content is in?

### 6. Multi-tenancy & Authorization
- Currently there's a single `author_id` on recipes. What's needed for:
  - Recipe sharing / collaboration?
  - Organization/team accounts?
  - Private ingredient libraries per user/org?
- Is the `visibility` enum sufficient?

### 7. Naming & Conventions
- Any inconsistencies in naming (singular vs plural, snake_case, column naming)?
- Are `TEXT CHECK` columns better as enums or reference tables?
- UUID vs serial for primary keys — any concerns?

### 8. Anything Else
- What would you change if you were building this from scratch?
- What's the single most impactful improvement you'd make right now?
- Are there PostgreSQL-specific features we should leverage (e.g., GENERATED columns, row-level security, pg_trgm for search)?

---

## Format

Return your review as a prioritized list. Group by severity. For each item:

```
### [Severity] Short title

**Table(s):** affected tables
**Issue:** What's wrong
**Impact:** What breaks or degrades
**Fix:**
\```sql
-- proposed DDL or query change
\```
```


