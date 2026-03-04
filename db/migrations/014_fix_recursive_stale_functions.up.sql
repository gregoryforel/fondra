-- Migration 014: fix stale propagation functions to use recursive CTEs correctly

CREATE OR REPLACE FUNCTION mark_ancestors_stale_from_recipe_rows_new() RETURNS TRIGGER AS $$
BEGIN
    WITH RECURSIVE changed AS (
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

CREATE OR REPLACE FUNCTION mark_ancestors_stale_from_step_rows_new() RETURNS TRIGGER AS $$
BEGIN
    WITH RECURSIVE changed AS (
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
    WITH RECURSIVE changed AS (
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
    WITH RECURSIVE changed AS (
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

CREATE OR REPLACE FUNCTION mark_ancestors_stale_from_component_rows_new() RETURNS TRIGGER AS $$
BEGIN
    WITH RECURSIVE changed AS (
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
    WITH RECURSIVE changed AS (
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
    WITH RECURSIVE changed AS (
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
