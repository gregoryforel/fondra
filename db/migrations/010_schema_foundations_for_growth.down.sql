-- Migration 010 down: revert schema foundations for growth

-- Drop trigram indexes and extension-dependent objects
DROP INDEX IF EXISTS idx_ingredients_name_trgm;
DROP INDEX IF EXISTS idx_recipes_description_trgm;
DROP INDEX IF EXISTS idx_recipes_title_trgm;

-- Drop media/equipment tables
DROP INDEX IF EXISTS idx_recipe_media_recipe;
DROP TABLE IF EXISTS recipe_media CASCADE;
DROP TABLE IF EXISTS step_equipment CASCADE;

-- Drop collaboration tables
DROP INDEX IF EXISTS idx_recipe_memberships_user;
DROP TABLE IF EXISTS recipe_memberships CASCADE;

-- Drop revisioning
ALTER TABLE compiled_recipes
    DROP COLUMN IF EXISTS compiled_from_revision_id;
DROP TABLE IF EXISTS recipe_revisions CASCADE;

-- Drop taxonomy translation tables
DROP TABLE IF EXISTS unit_translations CASCADE;
DROP TABLE IF EXISTS nutrient_translations CASCADE;
DROP TABLE IF EXISTS diet_flag_translations CASCADE;
DROP TABLE IF EXISTS allergen_translations CASCADE;
DROP TABLE IF EXISTS tag_translations CASCADE;

-- Drop locale constraints
ALTER TABLE step_translations
    DROP CONSTRAINT IF EXISTS chk_step_translations_locale_format;

ALTER TABLE ingredient_translations
    DROP CONSTRAINT IF EXISTS chk_ingredient_translations_locale_format;

ALTER TABLE recipe_translations
    DROP CONSTRAINT IF EXISTS chk_recipe_translations_locale_format;

ALTER TABLE recipes
    DROP CONSTRAINT IF EXISTS chk_recipes_source_locale_format;

ALTER TABLE app_users
    DROP CONSTRAINT IF EXISTS chk_app_users_preferred_locale_format;
