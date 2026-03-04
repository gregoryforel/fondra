-- Migration 011: yield consistency and statement-level stale batching

-- ============================================================
-- 1) Yield consistency
-- ============================================================
ALTER TABLE recipes
    ADD CONSTRAINT chk_recipes_yield_pair
    CHECK (
        (yield_amount IS NULL AND yield_unit_id IS NULL) OR
        (yield_amount IS NOT NULL AND yield_unit_id IS NOT NULL)
    );

-- ============================================================
-- 2) Statement-level stale propagation for recipe graph changes
-- ============================================================
-- Replace row-level stale triggers from migration 008.
DROP TRIGGER IF EXISTS trg_stale_on_component_change ON recipe_step_components;
DROP TRIGGER IF EXISTS trg_stale_on_step_change ON recipe_steps;
DROP TRIGGER IF EXISTS trg_stale_on_recipe_change ON recipes;

-- Updates all ancestors for changed recipe ids from NEW rows.
CREATE OR REPLACE FUNCTION mark_ancestors_stale_from_recipe_rows_new() RETURNS TRIGGER AS $$
BEGIN
    WITH changed AS (
        SELECT DISTINCT id AS recipe_id FROM new_rows
    ), ancestors AS (
        SELECT recipe_id FROM changed
        UNION
        SELECT rs.recipe_id
        FROM ancestors a
        JOIN recipe_step_components rsc ON rsc.sub_recipe_id = a.recipe_id
        JOIN recipe_steps rs ON rs.id = rsc.step_id
    )
    UPDATE compiled_recipes
    SET is_stale = true
    WHERE recipe_id IN (SELECT recipe_id FROM ancestors);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Updates all ancestors for changed recipe ids from NEW and OLD step rows.
CREATE OR REPLACE FUNCTION mark_ancestors_stale_from_step_rows_new() RETURNS TRIGGER AS $$
BEGIN
    WITH changed AS (
        SELECT DISTINCT recipe_id FROM new_rows
    ), ancestors AS (
        SELECT recipe_id FROM changed
        UNION
        SELECT rs.recipe_id
        FROM ancestors a
        JOIN recipe_step_components rsc ON rsc.sub_recipe_id = a.recipe_id
        JOIN recipe_steps rs ON rs.id = rsc.step_id
    )
    UPDATE compiled_recipes
    SET is_stale = true
    WHERE recipe_id IN (SELECT recipe_id FROM ancestors);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mark_ancestors_stale_from_step_rows_old() RETURNS TRIGGER AS $$
BEGIN
    WITH changed AS (
        SELECT DISTINCT recipe_id FROM old_rows
    ), ancestors AS (
        SELECT recipe_id FROM changed
        UNION
        SELECT rs.recipe_id
        FROM ancestors a
        JOIN recipe_step_components rsc ON rsc.sub_recipe_id = a.recipe_id
        JOIN recipe_steps rs ON rs.id = rsc.step_id
    )
    UPDATE compiled_recipes
    SET is_stale = true
    WHERE recipe_id IN (SELECT recipe_id FROM ancestors);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mark_ancestors_stale_from_step_rows_both() RETURNS TRIGGER AS $$
BEGIN
    WITH changed AS (
        SELECT DISTINCT recipe_id FROM new_rows
        UNION
        SELECT DISTINCT recipe_id FROM old_rows
    ), ancestors AS (
        SELECT recipe_id FROM changed
        UNION
        SELECT rs.recipe_id
        FROM ancestors a
        JOIN recipe_step_components rsc ON rsc.sub_recipe_id = a.recipe_id
        JOIN recipe_steps rs ON rs.id = rsc.step_id
    )
    UPDATE compiled_recipes
    SET is_stale = true
    WHERE recipe_id IN (SELECT recipe_id FROM ancestors);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Updates all ancestors for changed recipe ids inferred from NEW and OLD component rows.
CREATE OR REPLACE FUNCTION mark_ancestors_stale_from_component_rows_new() RETURNS TRIGGER AS $$
BEGIN
    WITH changed AS (
        SELECT DISTINCT rs.recipe_id
        FROM new_rows n
        JOIN recipe_steps rs ON rs.id = n.step_id
    ), ancestors AS (
        SELECT recipe_id FROM changed
        UNION
        SELECT rs.recipe_id
        FROM ancestors a
        JOIN recipe_step_components rsc ON rsc.sub_recipe_id = a.recipe_id
        JOIN recipe_steps rs ON rs.id = rsc.step_id
    )
    UPDATE compiled_recipes
    SET is_stale = true
    WHERE recipe_id IN (SELECT recipe_id FROM ancestors);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mark_ancestors_stale_from_component_rows_old() RETURNS TRIGGER AS $$
BEGIN
    WITH changed AS (
        SELECT DISTINCT rs.recipe_id
        FROM old_rows o
        JOIN recipe_steps rs ON rs.id = o.step_id
    ), ancestors AS (
        SELECT recipe_id FROM changed
        UNION
        SELECT rs.recipe_id
        FROM ancestors a
        JOIN recipe_step_components rsc ON rsc.sub_recipe_id = a.recipe_id
        JOIN recipe_steps rs ON rs.id = rsc.step_id
    )
    UPDATE compiled_recipes
    SET is_stale = true
    WHERE recipe_id IN (SELECT recipe_id FROM ancestors);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mark_ancestors_stale_from_component_rows_both() RETURNS TRIGGER AS $$
BEGIN
    WITH changed AS (
        SELECT DISTINCT rs.recipe_id
        FROM new_rows n
        JOIN recipe_steps rs ON rs.id = n.step_id
        UNION
        SELECT DISTINCT rs.recipe_id
        FROM old_rows o
        JOIN recipe_steps rs ON rs.id = o.step_id
    ), ancestors AS (
        SELECT recipe_id FROM changed
        UNION
        SELECT rs.recipe_id
        FROM ancestors a
        JOIN recipe_step_components rsc ON rsc.sub_recipe_id = a.recipe_id
        JOIN recipe_steps rs ON rs.id = rsc.step_id
    )
    UPDATE compiled_recipes
    SET is_stale = true
    WHERE recipe_id IN (SELECT recipe_id FROM ancestors);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_stale_on_recipe_change_stmt
    AFTER UPDATE ON recipes
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
    EXECUTE FUNCTION mark_ancestors_stale_from_recipe_rows_new();

CREATE TRIGGER trg_stale_on_step_insert_stmt
    AFTER INSERT ON recipe_steps
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
    EXECUTE FUNCTION mark_ancestors_stale_from_step_rows_new();

CREATE TRIGGER trg_stale_on_step_update_stmt
    AFTER UPDATE ON recipe_steps
    REFERENCING NEW TABLE AS new_rows OLD TABLE AS old_rows
    FOR EACH STATEMENT
    EXECUTE FUNCTION mark_ancestors_stale_from_step_rows_both();

CREATE TRIGGER trg_stale_on_step_delete_stmt
    AFTER DELETE ON recipe_steps
    REFERENCING OLD TABLE AS old_rows
    FOR EACH STATEMENT
    EXECUTE FUNCTION mark_ancestors_stale_from_step_rows_old();

CREATE TRIGGER trg_stale_on_component_insert_stmt
    AFTER INSERT ON recipe_step_components
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
    EXECUTE FUNCTION mark_ancestors_stale_from_component_rows_new();

CREATE TRIGGER trg_stale_on_component_update_stmt
    AFTER UPDATE ON recipe_step_components
    REFERENCING NEW TABLE AS new_rows OLD TABLE AS old_rows
    FOR EACH STATEMENT
    EXECUTE FUNCTION mark_ancestors_stale_from_component_rows_both();

CREATE TRIGGER trg_stale_on_component_delete_stmt
    AFTER DELETE ON recipe_step_components
    REFERENCING OLD TABLE AS old_rows
    FOR EACH STATEMENT
    EXECUTE FUNCTION mark_ancestors_stale_from_component_rows_old();
