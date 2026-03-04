# Architecture

## System Design

```
         Cloudflare CDN (later)
              |
         Go backend (stdlib + sqlc + templ)
              |
          PostgreSQL 17
              |
    +---------+---------+
    |                   |
  Web                 Mobile
  (htmx + templ +     (Flutter, later)
   Alpine.js)
```

## Data Model

### Recipe DAG

Recipes can reference sub-recipes through `recipe_step_components`. Each step component is either a direct ingredient or a reference to another recipe. This forms a directed acyclic graph (DAG).

Example: Beef Wellington references Puff Pastry as a sub-recipe. The Puff Pastry recipe's ingredients (flour, butter, water, salt) roll up into the Beef Wellington's consolidated grocery list.

Cycle prevention is enforced at the database level via a trigger (`check_recipe_cycle`) that walks the DAG before allowing inserts.

### Compilation Pipeline

When a recipe is saved/published, it is "compiled":

1. **DAG resolution:** A recursive CTE walks the sub-recipe tree, resolving all leaf ingredients. The yield multiplier uses `COALESCE(yield_amount, servings)` to support recipes with explicit yield semantics (e.g., "makes 1kg" vs "serves 4").
2. **Grocery list consolidation:** Quantities are normalized to each ingredient's `default_unit_id` using `units.to_base_factor` for same-dimension conversion and `ingredient_densities.density_g_per_ml` for cross-dimension (volume↔mass). Then aggregated per `(ingredient_id, unit_id)`.
3. **Allergen collection:** Union of all allergens (severity = 'contains') from all ingredients in the DAG.
4. **Diet compatibility:** A recipe is compatible with a diet only if ALL ingredients explicitly have `compatible = true` for that flag. Missing data (no row in `ingredient_diet_flags`) means NOT compatible.
5. **Tag collection:** Tags from `recipe_tags JOIN tags` are compiled into a `TEXT[]` column with a GIN index for fast filtering.
6. **Timing aggregation:** Sum of active_seconds and passive_seconds across all steps.
7. **Nutrition rollup:** Ingredient quantities are converted to grams (using unit dimension and density for volume→mass), then per-100g nutrient data is scaled and summed.

The compiled result is stored in `compiled_recipes` as structured JSONB plus extracted columns for indexing.

### Stale Cascade

A database trigger (`mark_ancestors_stale`) fires on changes to `recipe_step_components`, `recipe_steps`, and `recipes(servings, yield_amount)`. It walks the DAG upward and sets `is_stale = true` on the changed recipe and all its ancestors in `compiled_recipes`. Use `CompileAllRecipes(ctx, pool, true)` to recompile only stale recipes.

### Unit System

- All quantities stored in metric base units (g, ml, °C)
- US conversion uses `units.to_base_factor` and `units.to_base_offset`
- Volume↔mass conversion uses per-ingredient `ingredient_densities.density_g_per_ml`
- Temperature: °C to °F = (°C × 1.8) + 32

### Tags

Recipes support categorized tags via `tags` + `recipe_tags` tables. Tag categories: `cuisine`, `meal_type`, `difficulty`, `course`, `technique`, `season`. Tags are compiled into `compiled_recipes.compiled_tags` (TEXT[] with GIN index) for fast filtering.

### i18n

Per-entity translation tables exist:
- `recipe_translations` (recipe_id, locale, title, description)
- `ingredient_translations` (ingredient_id, locale, name)
- `step_translations` (step_id, locale, instruction)

Currently English only. The old EAV `translations` table was replaced in migration 008.

## Data Sources

Nutrient data comes from USDA FoodData Central (SR Legacy and Foundation Foods databases). Each ingredient tracks its `fdc_id` for provenance. See `docs/DATA_SOURCES.md` for details.
