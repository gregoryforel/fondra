-- Migration 016: close remaining data-model correctness gaps

-- ============================================================
-- 1) Enforce sub-recipe component unit compatibility with sub-recipe yield
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_subrecipe_unit_matches_yield() RETURNS TRIGGER AS $$
DECLARE
    v_yield_unit_id UUID;
    v_yield_amount NUMERIC;
BEGIN
    IF NEW.sub_recipe_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT yield_unit_id, yield_amount
    INTO v_yield_unit_id, v_yield_amount
    FROM recipes
    WHERE id = NEW.sub_recipe_id;

    IF v_yield_amount IS NULL OR v_yield_unit_id IS NULL THEN
        RAISE EXCEPTION 'Sub-recipe % must define both yield_amount and yield_unit_id', NEW.sub_recipe_id;
    END IF;

    IF NEW.unit_id <> v_yield_unit_id THEN
        RAISE EXCEPTION 'Sub-recipe component unit_id (%) must match sub-recipe yield_unit_id (%)',
            NEW.unit_id, v_yield_unit_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_enforce_subrecipe_unit_matches_yield ON recipe_step_components;

CREATE TRIGGER trg_enforce_subrecipe_unit_matches_yield
    BEFORE INSERT OR UPDATE OF sub_recipe_id, unit_id ON recipe_step_components
    FOR EACH ROW
    EXECUTE FUNCTION enforce_subrecipe_unit_matches_yield();

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM recipe_step_components rsc
        JOIN recipes sr ON sr.id = rsc.sub_recipe_id
        WHERE rsc.sub_recipe_id IS NOT NULL
          AND (
              sr.yield_amount IS NULL
              OR sr.yield_unit_id IS NULL
              OR rsc.unit_id <> sr.yield_unit_id
          )
    ) THEN
        RAISE EXCEPTION 'Existing sub-recipe component rows violate yield unit compatibility';
    END IF;
END;
$$;

-- ============================================================
-- 2) Invalidate compiled cache when taxonomy/unit names change
-- ============================================================
CREATE OR REPLACE FUNCTION mark_all_compiled_recipes_stale() RETURNS TRIGGER AS $$
BEGIN
    UPDATE compiled_recipes
    SET is_stale = true;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_stale_on_allergen_rename ON allergens;
DROP TRIGGER IF EXISTS trg_stale_on_diet_flag_rename ON diet_flags;
DROP TRIGGER IF EXISTS trg_stale_on_unit_rename ON units;

CREATE TRIGGER trg_stale_on_allergen_rename
    AFTER UPDATE OF name ON allergens
    FOR EACH ROW
    EXECUTE FUNCTION mark_all_compiled_recipes_stale();

CREATE TRIGGER trg_stale_on_diet_flag_rename
    AFTER UPDATE OF name ON diet_flags
    FOR EACH ROW
    EXECUTE FUNCTION mark_all_compiled_recipes_stale();

CREATE TRIGGER trg_stale_on_unit_rename
    AFTER UPDATE OF name, name_plural ON units
    FOR EACH ROW
    EXECUTE FUNCTION mark_all_compiled_recipes_stale();

-- ============================================================
-- 3) Enforce principal referential integrity for recipe_permissions
-- ============================================================
CREATE OR REPLACE FUNCTION validate_recipe_permission_principal() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.principal_type = 'user' THEN
        IF NOT EXISTS (SELECT 1 FROM app_users u WHERE u.id = NEW.principal_id) THEN
            RAISE EXCEPTION 'Invalid user principal_id % in recipe_permissions', NEW.principal_id;
        END IF;
    ELSIF NEW.principal_type = 'org' THEN
        IF NOT EXISTS (SELECT 1 FROM organizations o WHERE o.id = NEW.principal_id) THEN
            RAISE EXCEPTION 'Invalid org principal_id % in recipe_permissions', NEW.principal_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'Unknown principal_type % in recipe_permissions', NEW.principal_type;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_recipe_permission_principal ON recipe_permissions;

CREATE TRIGGER trg_validate_recipe_permission_principal
    BEFORE INSERT OR UPDATE ON recipe_permissions
    FOR EACH ROW
    EXECUTE FUNCTION validate_recipe_permission_principal();

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM recipe_permissions rp
        LEFT JOIN app_users u
            ON rp.principal_type = 'user'
           AND u.id = rp.principal_id
        LEFT JOIN organizations o
            ON rp.principal_type = 'org'
           AND o.id = rp.principal_id
        WHERE (rp.principal_type = 'user' AND u.id IS NULL)
           OR (rp.principal_type = 'org' AND o.id IS NULL)
    ) THEN
        RAISE EXCEPTION 'Existing recipe_permissions rows reference missing principals';
    END IF;
END;
$$;

-- ============================================================
-- 4) Enforce ingredient library owner invariants
-- ============================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM ingredient_libraries il
        WHERE (il.owner_type = 'global' AND il.owner_id IS NOT NULL)
           OR (il.owner_type IN ('user', 'org') AND il.owner_id IS NULL)
    ) THEN
        RAISE EXCEPTION 'Existing ingredient_libraries rows violate owner invariants';
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_ingredient_libraries_owner_shape'
          AND conrelid = 'ingredient_libraries'::regclass
    ) THEN
        ALTER TABLE ingredient_libraries
            ADD CONSTRAINT chk_ingredient_libraries_owner_shape
            CHECK (
                (owner_type = 'global' AND owner_id IS NULL)
                OR
                (owner_type IN ('user', 'org') AND owner_id IS NOT NULL)
            );
    END IF;
END;
$$;

-- ============================================================
-- 5) Keep recipe_closure maintained from DAG mutations
-- ============================================================
CREATE OR REPLACE FUNCTION rebuild_recipe_closure_all() RETURNS VOID AS $$
BEGIN
    TRUNCATE TABLE recipe_closure;

    INSERT INTO recipe_closure (ancestor_recipe_id, descendant_recipe_id, depth)
    WITH RECURSIVE edges AS (
        SELECT DISTINCT rs.recipe_id AS ancestor_recipe_id, rsc.sub_recipe_id AS descendant_recipe_id
        FROM recipe_step_components rsc
        JOIN recipe_steps rs ON rs.id = rsc.step_id
        WHERE rsc.sub_recipe_id IS NOT NULL
    ), walk AS (
        SELECT r.id AS ancestor_recipe_id, r.id AS descendant_recipe_id, 0 AS depth
        FROM recipes r

        UNION ALL

        SELECT w.ancestor_recipe_id, e.descendant_recipe_id, w.depth + 1
        FROM walk w
        JOIN edges e ON e.ancestor_recipe_id = w.descendant_recipe_id
    ), collapsed AS (
        SELECT ancestor_recipe_id, descendant_recipe_id, MIN(depth) AS depth
        FROM walk
        GROUP BY ancestor_recipe_id, descendant_recipe_id
    )
    SELECT ancestor_recipe_id, descendant_recipe_id, depth
    FROM collapsed;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION refresh_recipe_closure_after_graph_mutation() RETURNS TRIGGER AS $$
BEGIN
    PERFORM rebuild_recipe_closure_all();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_component_insert ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_component_update ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_component_delete ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_step_update ON recipe_steps;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_step_delete ON recipe_steps;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_recipe_insert ON recipes;
DROP TRIGGER IF EXISTS trg_refresh_recipe_closure_on_recipe_delete ON recipes;

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

-- Build/refresh closure once at migration time.
SELECT rebuild_recipe_closure_all();
