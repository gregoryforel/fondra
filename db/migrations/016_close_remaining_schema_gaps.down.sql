-- Down Migration 016: close remaining data-model correctness gaps

-- ============================================================
-- 5) Stop maintaining recipe_closure from DAG mutations
-- ============================================================
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_recipe_delete ON recipes;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_recipe_insert ON recipes;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_step_delete ON recipe_steps;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_step_update ON recipe_steps;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_component_delete ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_component_update ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_component_insert ON recipe_step_components;

DROP FUNCTION IF EXISTS refresh_recipe_closure_after_graph_mutation();
DROP FUNCTION IF EXISTS rebuild_recipe_closure_all();

-- ============================================================
-- 4) Remove ingredient library owner invariant check
-- ============================================================
ALTER TABLE ingredient_libraries
    DROP CONSTRAINT IF EXISTS chk_ingredient_libraries_owner_shape;

-- ============================================================
-- 3) Remove principal validation trigger
-- ============================================================
DROP TRIGGER IF EXISTS trg_validate_recipe_permission_principal ON recipe_permissions;
DROP FUNCTION IF EXISTS validate_recipe_permission_principal();

-- ============================================================
-- 2) Remove taxonomy/unit rename stale invalidation
-- ============================================================
DROP TRIGGER IF EXISTS trg_stale_on_unit_rename ON units;
DROP TRIGGER IF EXISTS trg_stale_on_diet_flag_rename ON diet_flags;
DROP TRIGGER IF EXISTS trg_stale_on_allergen_rename ON allergens;

DROP FUNCTION IF EXISTS mark_all_compiled_recipes_stale();

-- ============================================================
-- 1) Remove sub-recipe yield unit compatibility enforcement
-- ============================================================
DROP TRIGGER IF EXISTS trg_enforce_subrecipe_unit_matches_yield ON recipe_step_components;
DROP FUNCTION IF EXISTS enforce_subrecipe_unit_matches_yield();
