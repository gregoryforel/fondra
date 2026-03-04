-- Migration 017: close post-review integrity/performance gaps

-- ============================================================
-- 1) Invalidate compiled cache when unit conversion metadata changes
-- ============================================================
DROP TRIGGER IF EXISTS trg_stale_on_unit_conversion_change ON units;

CREATE TRIGGER trg_stale_on_unit_conversion_change
    AFTER UPDATE OF to_base_factor, to_base_offset, dimension ON units
    FOR EACH ROW
    EXECUTE FUNCTION mark_all_compiled_recipes_stale();

-- ============================================================
-- 2) Prevent dangling polymorphic owners/principals
-- ============================================================
CREATE OR REPLACE FUNCTION validate_ingredient_library_owner_reference() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.owner_type = 'global' THEN
        RETURN NEW;
    END IF;

    IF NEW.owner_type = 'user' THEN
        IF NOT EXISTS (SELECT 1 FROM app_users u WHERE u.id = NEW.owner_id) THEN
            RAISE EXCEPTION 'Invalid user owner_id % in ingredient_libraries', NEW.owner_id;
        END IF;
    ELSIF NEW.owner_type = 'org' THEN
        IF NOT EXISTS (SELECT 1 FROM organizations o WHERE o.id = NEW.owner_id) THEN
            RAISE EXCEPTION 'Invalid org owner_id % in ingredient_libraries', NEW.owner_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'Unknown owner_type % in ingredient_libraries', NEW.owner_type;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_ingredient_library_owner_reference ON ingredient_libraries;

CREATE TRIGGER trg_validate_ingredient_library_owner_reference
    BEFORE INSERT OR UPDATE ON ingredient_libraries
    FOR EACH ROW
    EXECUTE FUNCTION validate_ingredient_library_owner_reference();

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM ingredient_libraries il
        LEFT JOIN app_users u ON il.owner_type = 'user' AND u.id = il.owner_id
        LEFT JOIN organizations o ON il.owner_type = 'org' AND o.id = il.owner_id
        WHERE (il.owner_type = 'user' AND u.id IS NULL)
           OR (il.owner_type = 'org' AND o.id IS NULL)
    ) THEN
        RAISE EXCEPTION 'Existing ingredient_libraries rows reference missing owners';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION cleanup_user_polymorphic_references() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM recipe_permissions
    WHERE principal_type = 'user' AND principal_id = OLD.id;

    DELETE FROM ingredient_libraries
    WHERE owner_type = 'user' AND owner_id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION cleanup_org_polymorphic_references() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM recipe_permissions
    WHERE principal_type = 'org' AND principal_id = OLD.id;

    DELETE FROM ingredient_libraries
    WHERE owner_type = 'org' AND owner_id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cleanup_user_polymorphic_refs ON app_users;
DROP TRIGGER IF EXISTS trg_cleanup_org_polymorphic_refs ON organizations;

CREATE TRIGGER trg_cleanup_user_polymorphic_refs
    AFTER DELETE ON app_users
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_user_polymorphic_references();

CREATE TRIGGER trg_cleanup_org_polymorphic_refs
    AFTER DELETE ON organizations
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_org_polymorphic_references();

-- ============================================================
-- 3) Replace synchronous closure rebuild with queued async rebuild
-- ============================================================
CREATE TABLE IF NOT EXISTS recipe_closure_rebuild_queue (
    singleton BOOLEAN PRIMARY KEY DEFAULT true CHECK (singleton = true),
    queued_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION enqueue_recipe_closure_rebuild() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO recipe_closure_rebuild_queue (singleton, queued_at)
    VALUES (true, now())
    ON CONFLICT (singleton) DO UPDATE SET queued_at = EXCLUDED.queued_at;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Drop synchronous rebuild triggers from migration 016.
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_recipe_delete ON recipes;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_recipe_insert ON recipes;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_step_delete ON recipe_steps;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_step_update ON recipe_steps;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_component_delete ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_component_update ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_component_insert ON recipe_step_components;

DROP FUNCTION IF EXISTS refresh_recipe_closure_after_graph_mutation();

CREATE TRIGGER trg_enqueue_recipe_closure_rebuild_on_component_insert
    AFTER INSERT ON recipe_step_components
    FOR EACH STATEMENT
    EXECUTE FUNCTION enqueue_recipe_closure_rebuild();

CREATE TRIGGER trg_enqueue_recipe_closure_rebuild_on_component_update
    AFTER UPDATE ON recipe_step_components
    FOR EACH STATEMENT
    EXECUTE FUNCTION enqueue_recipe_closure_rebuild();

CREATE TRIGGER trg_enqueue_recipe_closure_rebuild_on_component_delete
    AFTER DELETE ON recipe_step_components
    FOR EACH STATEMENT
    EXECUTE FUNCTION enqueue_recipe_closure_rebuild();

CREATE TRIGGER trg_enqueue_recipe_closure_rebuild_on_step_update
    AFTER UPDATE OF recipe_id ON recipe_steps
    FOR EACH STATEMENT
    EXECUTE FUNCTION enqueue_recipe_closure_rebuild();

CREATE TRIGGER trg_enqueue_recipe_closure_rebuild_on_step_delete
    AFTER DELETE ON recipe_steps
    FOR EACH STATEMENT
    EXECUTE FUNCTION enqueue_recipe_closure_rebuild();

CREATE TRIGGER trg_enqueue_recipe_closure_rebuild_on_recipe_insert
    AFTER INSERT ON recipes
    FOR EACH STATEMENT
    EXECUTE FUNCTION enqueue_recipe_closure_rebuild();

CREATE TRIGGER trg_enqueue_recipe_closure_rebuild_on_recipe_delete
    AFTER DELETE ON recipes
    FOR EACH STATEMENT
    EXECUTE FUNCTION enqueue_recipe_closure_rebuild();

-- Worker entrypoint: rebuild only when queued, then clear queue row.
CREATE OR REPLACE FUNCTION process_recipe_closure_rebuild_queue() RETURNS BOOLEAN AS $$
DECLARE
    did_work BOOLEAN := false;
BEGIN
    IF EXISTS (SELECT 1 FROM recipe_closure_rebuild_queue WHERE singleton = true) THEN
        PERFORM rebuild_recipe_closure_all();
        DELETE FROM recipe_closure_rebuild_queue WHERE singleton = true;
        did_work := true;
    END IF;

    RETURN did_work;
END;
$$ LANGUAGE plpgsql;

-- Ensure initial queue is present so first worker run refreshes closure after deploying this migration.
INSERT INTO recipe_closure_rebuild_queue (singleton, queued_at)
VALUES (true, now())
ON CONFLICT (singleton) DO UPDATE SET queued_at = EXCLUDED.queued_at;
