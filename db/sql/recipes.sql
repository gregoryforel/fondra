-- name: GetRecipeByID :one
SELECT * FROM recipes WHERE id = $1;

-- name: GetRecipeBySlug :one
SELECT * FROM recipes WHERE slug = $1;

-- name: ListPublicRecipes :many
SELECT * FROM recipes
WHERE visibility = 'public'
ORDER BY created_at DESC
LIMIT $1 OFFSET $2;

-- name: SearchPublicRecipes :many
SELECT * FROM recipes
WHERE visibility = 'public'
  AND (title ILIKE '%' || $1 || '%' OR description ILIKE '%' || $1 || '%')
ORDER BY created_at DESC
LIMIT $2;

-- name: ListRecipeSteps :many
SELECT * FROM recipe_steps
WHERE recipe_id = $1
ORDER BY position;

-- name: ListStepComponents :many
SELECT
    rsc.*,
    i.name AS ingredient_name,
    i.name_slug AS ingredient_slug,
    u.name AS unit_name,
    u.name_plural AS unit_name_plural,
    sr.title AS sub_recipe_title,
    sr.slug AS sub_recipe_slug
FROM recipe_step_components rsc
JOIN units u ON u.id = rsc.unit_id
LEFT JOIN ingredients i ON i.id = rsc.ingredient_id
LEFT JOIN recipes sr ON sr.id = rsc.sub_recipe_id
WHERE rsc.step_id = $1
ORDER BY rsc.position;

-- name: GetCompiledRecipe :one
SELECT cr.*, r.title, r.slug, r.description, r.servings, r.yield_amount, r.yield_unit_id,
       r.source_locale, r.visibility,
       r.author_id, r.created_at AS recipe_created_at, r.updated_at AS recipe_updated_at
FROM compiled_recipes cr
JOIN recipes r ON r.id = cr.recipe_id
WHERE cr.recipe_id = $1;

-- name: GetCompiledRecipeBySlug :one
SELECT cr.*, r.title, r.slug, r.description, r.servings, r.yield_amount, r.yield_unit_id,
       r.source_locale, r.visibility,
       r.author_id, r.created_at AS recipe_created_at, r.updated_at AS recipe_updated_at
FROM compiled_recipes cr
JOIN recipes r ON r.id = cr.recipe_id
WHERE r.slug = $1;

-- name: ListCompiledRecipes :many
SELECT cr.*, r.title, r.slug, r.description, r.servings, r.yield_amount, r.yield_unit_id,
       r.source_locale, r.visibility,
       r.author_id, r.created_at AS recipe_created_at, r.updated_at AS recipe_updated_at
FROM compiled_recipes cr
JOIN recipes r ON r.id = cr.recipe_id
WHERE r.visibility = 'public'
ORDER BY r.created_at DESC
LIMIT $1 OFFSET $2;

-- name: SearchCompiledRecipes :many
SELECT cr.*, r.title, r.slug, r.description, r.servings, r.yield_amount, r.yield_unit_id,
       r.source_locale, r.visibility,
       r.author_id, r.created_at AS recipe_created_at, r.updated_at AS recipe_updated_at
FROM compiled_recipes cr
JOIN recipes r ON r.id = cr.recipe_id
WHERE r.visibility = 'public'
  AND (r.title ILIKE '%' || $1 || '%' OR r.description ILIKE '%' || $1 || '%')
ORDER BY r.created_at DESC
LIMIT $2;

-- name: UpsertCompiledRecipe :exec
INSERT INTO compiled_recipes (
    recipe_id, compiled_at, is_stale,
    compiled_steps, compiled_grocery_list,
    compiled_nutrition_per_serving, compiled_nutrition_total,
    compiled_allergens, compiled_diet_flags,
    total_active_seconds, total_passive_seconds, total_calories_per_serving,
    compiled_tags
) VALUES ($1, now(), false, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
ON CONFLICT (recipe_id) DO UPDATE SET
    compiled_at = now(),
    is_stale = false,
    compiled_steps = EXCLUDED.compiled_steps,
    compiled_grocery_list = EXCLUDED.compiled_grocery_list,
    compiled_nutrition_per_serving = EXCLUDED.compiled_nutrition_per_serving,
    compiled_nutrition_total = EXCLUDED.compiled_nutrition_total,
    compiled_allergens = EXCLUDED.compiled_allergens,
    compiled_diet_flags = EXCLUDED.compiled_diet_flags,
    total_active_seconds = EXCLUDED.total_active_seconds,
    total_passive_seconds = EXCLUDED.total_passive_seconds,
    total_calories_per_serving = EXCLUDED.total_calories_per_serving,
    compiled_tags = EXCLUDED.compiled_tags;

-- name: ResolveRecipeTree :many
-- Resolves all leaf ingredients from a recipe's full sub-recipe tree
-- and aggregates total quantities per ingredient, normalizing to default unit.
WITH RECURSIVE recipe_tree AS (
    SELECT
        rsc.ingredient_id,
        rsc.sub_recipe_id,
        rsc.quantity,
        rsc.unit_id,
        1.0::numeric AS multiplier
    FROM recipe_steps rs
    JOIN recipe_step_components rsc ON rsc.step_id = rs.id
    WHERE rs.recipe_id = $1

    UNION ALL

    SELECT
        rsc.ingredient_id,
        rsc.sub_recipe_id,
        rsc.quantity,
        rsc.unit_id,
        rt.multiplier * (rt.quantity / NULLIF(COALESCE(r.yield_amount, r.servings::numeric), 0))
    FROM recipe_tree rt
    JOIN recipes r ON r.id = rt.sub_recipe_id
    JOIN recipe_steps rs ON rs.recipe_id = r.id
    JOIN recipe_step_components rsc ON rsc.step_id = rs.id
    WHERE rt.sub_recipe_id IS NOT NULL
),
-- Normalize quantities to each ingredient's default unit
normalized AS (
    SELECT
        rt.ingredient_id,
        COALESCE(i.default_unit_id, rt.unit_id) AS unit_id,
        CASE
            -- Same unit: no conversion needed
            WHEN rt.unit_id = COALESCE(i.default_unit_id, rt.unit_id) THEN
                rt.quantity * rt.multiplier
            -- Same dimension: convert via base factor ratio
            WHEN su.dimension = du.dimension THEN
                rt.quantity * rt.multiplier * su.to_base_factor / NULLIF(du.to_base_factor, 0)
            -- Cross-dimension (volume<->mass): use density
            WHEN su.dimension = 'volume' AND du.dimension = 'mass' AND id_dens.density_g_per_ml IS NOT NULL THEN
                rt.quantity * rt.multiplier * su.to_base_factor * id_dens.density_g_per_ml / NULLIF(du.to_base_factor, 0)
            WHEN su.dimension = 'mass' AND du.dimension = 'volume' AND id_dens.density_g_per_ml IS NOT NULL THEN
                rt.quantity * rt.multiplier * su.to_base_factor / id_dens.density_g_per_ml / NULLIF(du.to_base_factor, 0)
            -- Fallback: keep raw quantity (no conversion possible)
            ELSE
                rt.quantity * rt.multiplier
        END AS converted_quantity
    FROM recipe_tree rt
    JOIN ingredients i ON i.id = rt.ingredient_id
    JOIN units su ON su.id = rt.unit_id
    LEFT JOIN units du ON du.id = i.default_unit_id
    LEFT JOIN ingredient_densities id_dens ON id_dens.ingredient_id = rt.ingredient_id AND id_dens.notes IS NULL
    WHERE rt.ingredient_id IS NOT NULL
)
SELECT
    ingredient_id,
    unit_id,
    SUM(converted_quantity) AS total_quantity
FROM normalized
GROUP BY ingredient_id, unit_id;

-- name: ListAllRecipeIDs :many
SELECT id FROM recipes ORDER BY created_at;

-- name: ListStaleRecipeIDs :many
SELECT cr.recipe_id AS id FROM compiled_recipes cr
WHERE cr.is_stale = true
ORDER BY cr.compiled_at;

-- name: CollectRecipeAllergens :many
-- Collects all allergens for a recipe by traversing sub-recipes.
WITH RECURSIVE recipe_tree AS (
    SELECT rsc.ingredient_id, rsc.sub_recipe_id, 1.0::numeric AS multiplier, rsc.quantity
    FROM recipe_steps rs
    JOIN recipe_step_components rsc ON rsc.step_id = rs.id
    WHERE rs.recipe_id = $1
    UNION ALL
    SELECT rsc.ingredient_id, rsc.sub_recipe_id,
           rt.multiplier * (rt.quantity / NULLIF(COALESCE(r.yield_amount, r.servings::numeric), 0)),
           rsc.quantity
    FROM recipe_tree rt
    JOIN recipes r ON r.id = rt.sub_recipe_id
    JOIN recipe_steps rs ON rs.recipe_id = r.id
    JOIN recipe_step_components rsc ON rsc.step_id = rs.id
    WHERE rt.sub_recipe_id IS NOT NULL
)
SELECT DISTINCT a.name
FROM recipe_tree rt
JOIN ingredient_allergens ia ON ia.ingredient_id = rt.ingredient_id
JOIN allergens a ON a.id = ia.allergen_id
WHERE rt.ingredient_id IS NOT NULL AND ia.severity = 'contains';

-- name: CollectRecipeDietFlags :many
-- Determines diet compatibility: a recipe is compatible with a diet
-- only if ALL its ingredients explicitly have compatible=true for that flag.
-- Missing data (no row in ingredient_diet_flags) means NOT compatible.
WITH RECURSIVE recipe_tree AS (
    SELECT rsc.ingredient_id, rsc.sub_recipe_id, 1.0::numeric AS multiplier, rsc.quantity
    FROM recipe_steps rs
    JOIN recipe_step_components rsc ON rsc.step_id = rs.id
    WHERE rs.recipe_id = $1
    UNION ALL
    SELECT rsc.ingredient_id, rsc.sub_recipe_id,
           rt.multiplier * (rt.quantity / NULLIF(COALESCE(r.yield_amount, r.servings::numeric), 0)),
           rsc.quantity
    FROM recipe_tree rt
    JOIN recipes r ON r.id = rt.sub_recipe_id
    JOIN recipe_steps rs ON rs.recipe_id = r.id
    JOIN recipe_step_components rsc ON rsc.step_id = rs.id
    WHERE rt.sub_recipe_id IS NOT NULL
)
SELECT df.name
FROM diet_flags df
WHERE NOT EXISTS (
    -- No ingredient that lacks a compatible=true row for this flag
    SELECT 1
    FROM recipe_tree rt
    WHERE rt.ingredient_id IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM ingredient_diet_flags idf
        WHERE idf.ingredient_id = rt.ingredient_id
        AND idf.diet_flag_id = df.id
        AND idf.compatible = true
    )
)
AND EXISTS (
    SELECT 1
    FROM recipe_tree rt
    WHERE rt.ingredient_id IS NOT NULL
);

-- name: ListRecipeTags :many
SELECT t.name, t.category
FROM recipe_tags rtag
JOIN tags t ON t.id = rtag.tag_id
WHERE rtag.recipe_id = $1
ORDER BY t.category, t.name;

-- name: UpsertTag :one
INSERT INTO tags (name, category)
VALUES ($1, $2)
ON CONFLICT (name, category) DO UPDATE SET updated_at = now()
RETURNING id;

-- name: AddRecipeTag :exec
INSERT INTO recipe_tags (recipe_id, tag_id)
VALUES ($1, $2)
ON CONFLICT DO NOTHING;

-- name: RemoveRecipeTag :exec
DELETE FROM recipe_tags WHERE recipe_id = $1 AND tag_id = $2;
