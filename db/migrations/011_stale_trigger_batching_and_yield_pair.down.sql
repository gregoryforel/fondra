-- Migration 011 down: revert stale batching and yield consistency

-- Drop statement-level stale triggers and helper functions
DROP TRIGGER IF EXISTS trg_stale_on_component_delete_stmt ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_stale_on_component_update_stmt ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_stale_on_component_insert_stmt ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_stale_on_step_delete_stmt ON recipe_steps;
DROP TRIGGER IF EXISTS trg_stale_on_step_update_stmt ON recipe_steps;
DROP TRIGGER IF EXISTS trg_stale_on_step_insert_stmt ON recipe_steps;
DROP TRIGGER IF EXISTS trg_stale_on_recipe_change_stmt ON recipes;

DROP FUNCTION IF EXISTS mark_ancestors_stale_from_component_rows_both();
DROP FUNCTION IF EXISTS mark_ancestors_stale_from_component_rows_old();
DROP FUNCTION IF EXISTS mark_ancestors_stale_from_component_rows_new();
DROP FUNCTION IF EXISTS mark_ancestors_stale_from_step_rows_both();
DROP FUNCTION IF EXISTS mark_ancestors_stale_from_step_rows_old();
DROP FUNCTION IF EXISTS mark_ancestors_stale_from_step_rows_new();
DROP FUNCTION IF EXISTS mark_ancestors_stale_from_recipe_rows_new();

-- Restore row-level stale triggers from migration 008.
CREATE TRIGGER trg_stale_on_component_change
    AFTER INSERT OR UPDATE OR DELETE ON recipe_step_components
    FOR EACH ROW EXECUTE FUNCTION mark_ancestors_stale();

CREATE TRIGGER trg_stale_on_step_change
    AFTER INSERT OR UPDATE OR DELETE ON recipe_steps
    FOR EACH ROW EXECUTE FUNCTION mark_ancestors_stale();

CREATE TRIGGER trg_stale_on_recipe_change
    AFTER UPDATE OF servings, yield_amount ON recipes
    FOR EACH ROW EXECUTE FUNCTION mark_ancestors_stale();

-- Drop yield consistency constraint
ALTER TABLE recipes
    DROP CONSTRAINT IF EXISTS chk_recipes_yield_pair;
