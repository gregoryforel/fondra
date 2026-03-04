-- Migration 010: schema foundations for growth
-- Adds i18n coverage, locale constraints, revisioning hooks, collaboration,
-- step equipment/media modeling, and trigram search indexes.

-- ============================================================
-- 1) Locale format constraints
-- ============================================================
ALTER TABLE app_users
    ADD CONSTRAINT chk_app_users_preferred_locale_format
    CHECK (preferred_locale ~ '^[a-z]{2}(-[A-Z]{2})?$');

ALTER TABLE recipes
    ADD CONSTRAINT chk_recipes_source_locale_format
    CHECK (source_locale ~ '^[a-z]{2}(-[A-Z]{2})?$');

ALTER TABLE recipe_translations
    ADD CONSTRAINT chk_recipe_translations_locale_format
    CHECK (locale ~ '^[a-z]{2}(-[A-Z]{2})?$');

ALTER TABLE ingredient_translations
    ADD CONSTRAINT chk_ingredient_translations_locale_format
    CHECK (locale ~ '^[a-z]{2}(-[A-Z]{2})?$');

ALTER TABLE step_translations
    ADD CONSTRAINT chk_step_translations_locale_format
    CHECK (locale ~ '^[a-z]{2}(-[A-Z]{2})?$');

-- ============================================================
-- 2) i18n coverage for taxonomy-like entities
-- ============================================================
CREATE TABLE tag_translations (
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    locale TEXT NOT NULL,
    name TEXT NOT NULL,
    PRIMARY KEY (tag_id, locale),
    CONSTRAINT chk_tag_translations_locale_format
        CHECK (locale ~ '^[a-z]{2}(-[A-Z]{2})?$')
);

CREATE TABLE allergen_translations (
    allergen_id UUID NOT NULL REFERENCES allergens(id) ON DELETE CASCADE,
    locale TEXT NOT NULL,
    name TEXT NOT NULL,
    PRIMARY KEY (allergen_id, locale),
    CONSTRAINT chk_allergen_translations_locale_format
        CHECK (locale ~ '^[a-z]{2}(-[A-Z]{2})?$')
);

CREATE TABLE diet_flag_translations (
    diet_flag_id UUID NOT NULL REFERENCES diet_flags(id) ON DELETE CASCADE,
    locale TEXT NOT NULL,
    name TEXT NOT NULL,
    PRIMARY KEY (diet_flag_id, locale),
    CONSTRAINT chk_diet_flag_translations_locale_format
        CHECK (locale ~ '^[a-z]{2}(-[A-Z]{2})?$')
);

CREATE TABLE nutrient_translations (
    nutrient_id UUID NOT NULL REFERENCES nutrients(id) ON DELETE CASCADE,
    locale TEXT NOT NULL,
    name TEXT NOT NULL,
    PRIMARY KEY (nutrient_id, locale),
    CONSTRAINT chk_nutrient_translations_locale_format
        CHECK (locale ~ '^[a-z]{2}(-[A-Z]{2})?$')
);

CREATE TABLE unit_translations (
    unit_id UUID NOT NULL REFERENCES units(id) ON DELETE CASCADE,
    locale TEXT NOT NULL,
    name TEXT NOT NULL,
    name_plural TEXT NOT NULL,
    PRIMARY KEY (unit_id, locale),
    CONSTRAINT chk_unit_translations_locale_format
        CHECK (locale ~ '^[a-z]{2}(-[A-Z]{2})?$')
);

-- ============================================================
-- 3) Revisioning hook for compiled provenance
-- ============================================================
CREATE TABLE recipe_revisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    revision_no INT NOT NULL,
    created_by UUID REFERENCES app_users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (recipe_id, revision_no)
);

ALTER TABLE compiled_recipes
    ADD COLUMN compiled_from_revision_id UUID REFERENCES recipe_revisions(id);

-- ============================================================
-- 4) Collaboration foundation
-- ============================================================
CREATE TABLE recipe_memberships (
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'editor', 'viewer')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (recipe_id, user_id)
);

CREATE INDEX idx_recipe_memberships_user ON recipe_memberships (user_id, role);

-- ============================================================
-- 5) Prep/equipment/media support
-- ============================================================
CREATE TABLE step_equipment (
    step_id UUID NOT NULL REFERENCES recipe_steps(id) ON DELETE CASCADE,
    equipment_name TEXT NOT NULL,
    PRIMARY KEY (step_id, equipment_name)
);

CREATE TABLE recipe_media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('photo', 'video')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_recipe_media_recipe ON recipe_media (recipe_id, kind);

-- ============================================================
-- 6) Trigram indexes for search
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX idx_recipes_title_trgm
    ON recipes USING GIN (title gin_trgm_ops);

CREATE INDEX idx_recipes_description_trgm
    ON recipes USING GIN (description gin_trgm_ops);

CREATE INDEX idx_ingredients_name_trgm
    ON ingredients USING GIN (name gin_trgm_ops);
