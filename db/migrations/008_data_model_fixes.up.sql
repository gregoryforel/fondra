-- Migration 008: Data model fixes
-- Fix 2: yield columns, Fix 5: tags, Fix 6: per-entity translations,
-- Bonus: density uniqueness, Fix 4: stale cascade trigger

-- ============================================================
-- 1a. Yield columns on recipes (Fix 2)
-- ============================================================
ALTER TABLE recipes
    ADD COLUMN yield_amount NUMERIC,
    ADD COLUMN yield_unit_id UUID REFERENCES units(id);

-- Back-fill: copy servings into yield_amount so existing data stays valid
UPDATE recipes SET yield_amount = servings WHERE yield_amount IS NULL;

-- ============================================================
-- 1b. Tags tables (Fix 5)
-- ============================================================
CREATE TABLE tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('cuisine','meal_type','difficulty','course','technique','season')),
    UNIQUE(name, category),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE recipe_tags (
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (recipe_id, tag_id)
);

ALTER TABLE compiled_recipes ADD COLUMN compiled_tags TEXT[] NOT NULL DEFAULT '{}';
CREATE INDEX idx_compiled_tags ON compiled_recipes USING GIN (compiled_tags);

-- ============================================================
-- 1c. Replace EAV translations with per-entity tables (Fix 6)
-- ============================================================
DROP TABLE IF EXISTS translations CASCADE;

CREATE TABLE recipe_translations (
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    locale TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    PRIMARY KEY (recipe_id, locale)
);

CREATE TABLE ingredient_translations (
    ingredient_id UUID NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
    locale TEXT NOT NULL,
    name TEXT NOT NULL,
    PRIMARY KEY (ingredient_id, locale)
);

CREATE TABLE step_translations (
    step_id UUID NOT NULL REFERENCES recipe_steps(id) ON DELETE CASCADE,
    locale TEXT NOT NULL,
    instruction TEXT NOT NULL,
    PRIMARY KEY (step_id, locale)
);

-- ============================================================
-- 1d. Partial unique index for densities (Bonus)
-- ============================================================
CREATE UNIQUE INDEX idx_ingredient_densities_null_notes
    ON ingredient_densities(ingredient_id) WHERE notes IS NULL;

-- ============================================================
-- 1e. Stale cascade trigger (Fix 4)
-- ============================================================

-- Mark a recipe and all its ancestors as stale when its data changes.
CREATE OR REPLACE FUNCTION mark_ancestors_stale() RETURNS TRIGGER AS $$
DECLARE
    changed_recipe_id UUID;
BEGIN
    -- Determine which recipe was affected
    IF TG_TABLE_NAME = 'recipes' THEN
        changed_recipe_id := COALESCE(NEW.id, OLD.id);
    ELSIF TG_TABLE_NAME = 'recipe_steps' THEN
        changed_recipe_id := COALESCE(NEW.recipe_id, OLD.recipe_id);
    ELSIF TG_TABLE_NAME = 'recipe_step_components' THEN
        -- Look up the recipe_id from the step
        SELECT rs.recipe_id INTO changed_recipe_id
        FROM recipe_steps rs
        WHERE rs.id = COALESCE(NEW.step_id, OLD.step_id);
    END IF;

    IF changed_recipe_id IS NULL THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    -- Walk DAG upward: mark this recipe and all ancestors as stale
    WITH RECURSIVE ancestors AS (
        SELECT changed_recipe_id AS recipe_id
        UNION
        SELECT rs.recipe_id
        FROM ancestors a
        JOIN recipe_step_components rsc ON rsc.sub_recipe_id = a.recipe_id
        JOIN recipe_steps rs ON rs.id = rsc.step_id
    )
    UPDATE compiled_recipes
    SET is_stale = true
    WHERE recipe_id IN (SELECT recipe_id FROM ancestors);

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_stale_on_component_change
    AFTER INSERT OR UPDATE OR DELETE ON recipe_step_components
    FOR EACH ROW EXECUTE FUNCTION mark_ancestors_stale();

CREATE TRIGGER trg_stale_on_step_change
    AFTER INSERT OR UPDATE OR DELETE ON recipe_steps
    FOR EACH ROW EXECUTE FUNCTION mark_ancestors_stale();

CREATE TRIGGER trg_stale_on_recipe_change
    AFTER UPDATE OF servings, yield_amount ON recipes
    FOR EACH ROW EXECUTE FUNCTION mark_ancestors_stale();
