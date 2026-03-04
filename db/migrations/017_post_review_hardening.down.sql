-- Down Migration 017: close post-review integrity/performance gaps

-- ============================================================
-- 3) Remove queued async closure rebuild and restore sync rebuild triggers
-- ============================================================
DROP FUNCTION IF EXISTS process_recipe_closure_rebuild_queue();

DROP TRIGGER IF EXISTS trg_enqueue_recipe_closure_rebuild_on_recipe_delete ON recipes;
DROP TRIGGER IF EXISTS trg_enqueue_recipe_closure_rebuild_on_recipe_insert ON recipes;
DROP TRIGGER IF EXISTS trg_enqueue_recipe_closure_rebuild_on_step_delete ON recipe_steps;
DROP TRIGGER IF EXISTS trg_enqueue_recipe_closure_rebuild_on_step_update ON recipe_steps;
DROP TRIGGER IF EXISTS trg_enqueue_recipe_closure_rebuild_on_component_delete ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_enqueue_recipe_closure_rebuild_on_component_update ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_enqueue_recipe_closure_rebuild_on_component_insert ON recipe_step_components;

DROP FUNCTION IF EXISTS enqueue_recipe_closure_rebuild();
DROP TABLE IF EXISTS recipe_closure_rebuild_queue;

CREATE OR REPLACE FUNCTION refresh_recipe_closure_after_graph_mutation() RETURNS TRIGGER AS $$
BEGIN
    PERFORM rebuild_recipe_closure_all();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_refresh_recipe_closure_on_component_insert
    AFTER INSERT ON recipe_step_components
    FOR EACH STATEMENT
    EXECUTE FUNCTION refresh_recipe_closure_after_graph_mutation();

CREATE TRIGGER trg_refresh_recipe_closure_on_component_update
    AFTER UPDATE ON recipe_step_components
    FOR EACH STATEMENT
    EXECUTE FUNCTION refresh_recipe_closure_after_graph_mutation();

CREATE TRIGGER trg_refresh_recipe_closure_on_component_delete
    AFTER DELETE ON recipe_step_components
    FOR EACH STATEMENT
    EXECUTE FUNCTION refresh_recipe_closure_after_graph_mutation();

CREATE TRIGGER trg_refresh_recipe_closure_on_step_update
    AFTER UPDATE OF recipe_id ON recipe_steps
    FOR EACH STATEMENT
    EXECUTE FUNCTION refresh_recipe_closure_after_graph_mutation();

CREATE TRIGGER trg_refresh_recipe_closure_on_step_delete
    AFTER DELETE ON recipe_steps
    FOR EACH STATEMENT
    EXECUTE FUNCTION refresh_recipe_closure_after_graph_mutation();

CREATE TRIGGER trg_refresh_recipe_closure_on_recipe_insert
    AFTER INSERT ON recipes
    FOR EACH STATEMENT
    EXECUTE FUNCTION refresh_recipe_closure_after_graph_mutation();

CREATE TRIGGER trg_refresh_recipe_closure_on_recipe_delete
    AFTER DELETE ON recipes
    FOR EACH STATEMENT
    EXECUTE FUNCTION refresh_recipe_closure_after_graph_mutation();

-- ============================================================
-- 2) Remove polymorphic owner/principal hardening additions
-- ============================================================
DROP TRIGGER IF EXISTS trg_cleanup_org_polymorphic_refs ON organizations;
DROP TRIGGER IF EXISTS trg_cleanup_user_polymorphic_refs ON app_users;

DROP FUNCTION IF EXISTS cleanup_org_polymorphic_references();
DROP FUNCTION IF EXISTS cleanup_user_polymorphic_references();

DROP TRIGGER IF EXISTS trg_validate_ingredient_library_owner_reference ON ingredient_libraries;
DROP FUNCTION IF EXISTS validate_ingredient_library_owner_reference();

-- ============================================================
-- 1) Remove unit conversion stale invalidation trigger
-- ============================================================
DROP TRIGGER IF EXISTS trg_stale_on_unit_conversion_change ON units;
