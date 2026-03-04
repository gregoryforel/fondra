-- Down Migration 018: fk-backed auth model + ownership refactor rollback

-- ============================================================
-- 3) Drop cleanup triggers/functions for split permission tables
-- ============================================================
DROP TRIGGER IF EXISTS trg_cleanup_user_permission_and_library_refs ON app_users;
DROP TRIGGER IF EXISTS trg_cleanup_org_permission_and_library_refs ON organizations;
DROP FUNCTION IF EXISTS cleanup_user_permission_and_library_refs();
DROP FUNCTION IF EXISTS cleanup_org_permission_and_library_refs();

-- ============================================================
-- 2) Restore polymorphic ingredient_libraries ownership
-- ============================================================
ALTER TABLE ingredient_libraries
    ADD COLUMN IF NOT EXISTS owner_type TEXT,
    ADD COLUMN IF NOT EXISTS owner_id UUID;

UPDATE ingredient_libraries
SET owner_type = scope,
    owner_id = CASE
        WHEN scope = 'user' THEN user_id
        WHEN scope = 'org' THEN organization_id
        ELSE NULL
    END;

ALTER TABLE ingredient_libraries
    ALTER COLUMN owner_type SET NOT NULL;

ALTER TABLE ingredient_libraries
    ADD CONSTRAINT chk_ingredient_libraries_owner_shape
    CHECK (
        (owner_type = 'global' AND owner_id IS NULL)
        OR
        (owner_type IN ('user', 'org') AND owner_id IS NOT NULL)
    );

DROP INDEX IF EXISTS idx_ingredient_libraries_unique_global_name;
DROP INDEX IF EXISTS idx_ingredient_libraries_unique_user_name;
DROP INDEX IF EXISTS idx_ingredient_libraries_unique_org_name;
DROP INDEX IF EXISTS idx_ingredient_libraries_user;
DROP INDEX IF EXISTS idx_ingredient_libraries_org;

ALTER TABLE ingredient_libraries
    ADD CONSTRAINT ingredient_libraries_owner_type_owner_id_name_key
    UNIQUE (owner_type, owner_id, name);

ALTER TABLE ingredient_libraries
    DROP CONSTRAINT IF EXISTS chk_ingredient_libraries_scope_shape,
    DROP CONSTRAINT IF EXISTS chk_ingredient_libraries_scope;

ALTER TABLE ingredient_libraries
    DROP COLUMN IF EXISTS organization_id,
    DROP COLUMN IF EXISTS user_id,
    DROP COLUMN IF EXISTS scope;

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

CREATE TRIGGER trg_validate_ingredient_library_owner_reference
    BEFORE INSERT OR UPDATE ON ingredient_libraries
    FOR EACH ROW
    EXECUTE FUNCTION validate_ingredient_library_owner_reference();

-- ============================================================
-- 1) Restore polymorphic recipe_permissions model
-- ============================================================
CREATE TABLE recipe_permissions (
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    principal_type TEXT NOT NULL CHECK (principal_type IN ('user', 'org')),
    principal_id UUID NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('owner', 'editor', 'viewer')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (recipe_id, principal_type, principal_id)
);

CREATE INDEX idx_recipe_permissions_principal
    ON recipe_permissions (principal_type, principal_id);

INSERT INTO recipe_permissions (recipe_id, principal_type, principal_id, role, created_at)
SELECT rup.recipe_id, 'user', rup.user_id, rup.role, rup.created_at
FROM recipe_user_permissions rup
ON CONFLICT (recipe_id, principal_type, principal_id) DO NOTHING;

INSERT INTO recipe_permissions (recipe_id, principal_type, principal_id, role, created_at)
SELECT rop.recipe_id, 'org', rop.organization_id, rop.role, rop.created_at
FROM recipe_org_permissions rop
ON CONFLICT (recipe_id, principal_type, principal_id) DO NOTHING;

DROP INDEX IF EXISTS idx_recipe_user_permissions_user;
DROP INDEX IF EXISTS idx_recipe_org_permissions_org;
DROP TABLE IF EXISTS recipe_user_permissions;
DROP TABLE IF EXISTS recipe_org_permissions;

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

CREATE TRIGGER trg_validate_recipe_permission_principal
    BEFORE INSERT OR UPDATE ON recipe_permissions
    FOR EACH ROW
    EXECUTE FUNCTION validate_recipe_permission_principal();

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

CREATE TRIGGER trg_cleanup_user_polymorphic_refs
    AFTER DELETE ON app_users
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_user_polymorphic_references();

CREATE TRIGGER trg_cleanup_org_polymorphic_refs
    AFTER DELETE ON organizations
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_org_polymorphic_references();
