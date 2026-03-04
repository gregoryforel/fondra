-- Migration 008 down: Reverse data model fixes

-- Drop stale cascade triggers
DROP TRIGGER IF EXISTS trg_stale_on_recipe_change ON recipes;
DROP TRIGGER IF EXISTS trg_stale_on_step_change ON recipe_steps;
DROP TRIGGER IF EXISTS trg_stale_on_component_change ON recipe_step_components;
DROP FUNCTION IF EXISTS mark_ancestors_stale();

-- Drop density partial unique index
DROP INDEX IF EXISTS idx_ingredient_densities_null_notes;

-- Drop per-entity translation tables and restore EAV
DROP TABLE IF EXISTS step_translations CASCADE;
DROP TABLE IF EXISTS ingredient_translations CASCADE;
DROP TABLE IF EXISTS recipe_translations CASCADE;

CREATE TABLE translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type TEXT NOT NULL,
    entity_id UUID,
    field_name TEXT NOT NULL,
    locale TEXT NOT NULL,
    value TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(entity_type, entity_id, field_name, locale)
);
CREATE INDEX idx_translations_lookup ON translations(entity_type, entity_id, locale);

-- Drop tags
DROP INDEX IF EXISTS idx_compiled_tags;
ALTER TABLE compiled_recipes DROP COLUMN IF EXISTS compiled_tags;
DROP TABLE IF EXISTS recipe_tags CASCADE;
DROP TABLE IF EXISTS tags CASCADE;

-- Drop yield columns
ALTER TABLE recipes DROP COLUMN IF EXISTS yield_unit_id;
ALTER TABLE recipes DROP COLUMN IF EXISTS yield_amount;
