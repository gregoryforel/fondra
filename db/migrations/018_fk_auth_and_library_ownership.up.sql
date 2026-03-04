-- Migration 018: fk-backed auth model + closure worker integration support

-- ============================================================
-- 1) Replace polymorphic recipe permissions with FK-backed tables
-- ============================================================
DROP TRIGGER IF EXISTS trg_cleanup_user_polymorphic_refs ON app_users;
DROP TRIGGER IF EXISTS trg_cleanup_org_polymorphic_refs ON organizations;
DROP FUNCTION IF EXISTS cleanup_user_polymorphic_references();
DROP FUNCTION IF EXISTS cleanup_org_polymorphic_references();

DROP TRIGGER IF EXISTS trg_validate_recipe_permission_principal ON recipe_permissions;
DROP FUNCTION IF EXISTS validate_recipe_permission_principal();

CREATE TABLE IF NOT EXISTS recipe_user_permissions (
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'editor', 'viewer')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (recipe_id, user_id)
);

CREATE TABLE IF NOT EXISTS recipe_org_permissions (
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'editor', 'viewer')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (recipe_id, organization_id)
);

CREATE INDEX IF NOT EXISTS idx_recipe_user_permissions_user
    ON recipe_user_permissions (user_id);

CREATE INDEX IF NOT EXISTS idx_recipe_org_permissions_org
    ON recipe_org_permissions (organization_id);

INSERT INTO recipe_user_permissions (recipe_id, user_id, role, created_at)
SELECT rp.recipe_id, rp.principal_id, rp.role, rp.created_at
FROM recipe_permissions rp
JOIN app_users u ON u.id = rp.principal_id
WHERE rp.principal_type = 'user'
ON CONFLICT (recipe_id, user_id) DO NOTHING;

INSERT INTO recipe_org_permissions (recipe_id, organization_id, role, created_at)
SELECT rp.recipe_id, rp.principal_id, rp.role, rp.created_at
FROM recipe_permissions rp
JOIN organizations o ON o.id = rp.principal_id
WHERE rp.principal_type = 'org'
ON CONFLICT (recipe_id, organization_id) DO NOTHING;

DROP INDEX IF EXISTS idx_recipe_permissions_principal;
DROP TABLE IF EXISTS recipe_permissions;

-- ============================================================
-- 2) Refactor ingredient_libraries ownership to FK-backed columns
-- ============================================================
DROP TRIGGER IF EXISTS trg_validate_ingredient_library_owner_reference ON ingredient_libraries;
DROP FUNCTION IF EXISTS validate_ingredient_library_owner_reference();

ALTER TABLE ingredient_libraries
    ADD COLUMN IF NOT EXISTS scope TEXT,
    ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES app_users(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE;

UPDATE ingredient_libraries
SET scope = owner_type,
    user_id = CASE WHEN owner_type = 'user' THEN owner_id ELSE NULL END,
    organization_id = CASE WHEN owner_type = 'org' THEN owner_id ELSE NULL END
WHERE scope IS NULL;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM ingredient_libraries il
        WHERE il.scope IS NULL
           OR il.scope NOT IN ('global', 'user', 'org')
           OR (il.scope = 'global' AND (il.user_id IS NOT NULL OR il.organization_id IS NOT NULL))
           OR (il.scope = 'user' AND (il.user_id IS NULL OR il.organization_id IS NOT NULL))
           OR (il.scope = 'org' AND (il.organization_id IS NULL OR il.user_id IS NOT NULL))
    ) THEN
        RAISE EXCEPTION 'ingredient_libraries contains invalid scope ownership rows';
    END IF;
END;
$$;

ALTER TABLE ingredient_libraries
    ALTER COLUMN scope SET NOT NULL;

ALTER TABLE ingredient_libraries
    ADD CONSTRAINT chk_ingredient_libraries_scope
    CHECK (scope IN ('global', 'user', 'org'));

ALTER TABLE ingredient_libraries
    ADD CONSTRAINT chk_ingredient_libraries_scope_shape
    CHECK (
        (scope = 'global' AND user_id IS NULL AND organization_id IS NULL)
        OR
        (scope = 'user' AND user_id IS NOT NULL AND organization_id IS NULL)
        OR
        (scope = 'org' AND organization_id IS NOT NULL AND user_id IS NULL)
    );

ALTER TABLE ingredient_libraries
    DROP CONSTRAINT IF EXISTS ingredient_libraries_owner_type_owner_id_name_key;
DROP INDEX IF EXISTS idx_ingredient_libraries_owner_name;
DROP INDEX IF EXISTS idx_ingredient_libraries_user;
DROP INDEX IF EXISTS idx_ingredient_libraries_org;

CREATE UNIQUE INDEX idx_ingredient_libraries_unique_global_name
    ON ingredient_libraries (name)
    WHERE scope = 'global';

CREATE UNIQUE INDEX idx_ingredient_libraries_unique_user_name
    ON ingredient_libraries (user_id, name)
    WHERE scope = 'user';

CREATE UNIQUE INDEX idx_ingredient_libraries_unique_org_name
    ON ingredient_libraries (organization_id, name)
    WHERE scope = 'org';

CREATE INDEX idx_ingredient_libraries_user
    ON ingredient_libraries (user_id)
    WHERE scope = 'user';

CREATE INDEX idx_ingredient_libraries_org
    ON ingredient_libraries (organization_id)
    WHERE scope = 'org';

ALTER TABLE ingredient_libraries
    DROP CONSTRAINT IF EXISTS chk_ingredient_libraries_owner_shape;

ALTER TABLE ingredient_libraries
    DROP COLUMN IF EXISTS owner_type,
    DROP COLUMN IF EXISTS owner_id;

-- ============================================================
-- 3) Recreate cleanup triggers for FK-backed auth/ownership tables
-- ============================================================
CREATE OR REPLACE FUNCTION cleanup_user_permission_and_library_refs() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM recipe_user_permissions
    WHERE user_id = OLD.id;

    DELETE FROM ingredient_libraries
    WHERE user_id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION cleanup_org_permission_and_library_refs() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM recipe_org_permissions
    WHERE organization_id = OLD.id;

    DELETE FROM ingredient_libraries
    WHERE organization_id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cleanup_user_permission_and_library_refs
    AFTER DELETE ON app_users
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_user_permission_and_library_refs();

CREATE TRIGGER trg_cleanup_org_permission_and_library_refs
    AFTER DELETE ON organizations
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_org_permission_and_library_refs();
