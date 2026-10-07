-- =====================================================================
-- Profiles <-> Supabase Auth sync
-- Run AFTER the main pharmacy schema script (needs "Profiles" and
-- "UserRole" to exist).
--
-- What this does:
--   1. Creates a "Profiles" row automatically for every new auth.users row.
--   2. Keeps full_name / phone in sync when the Auth user's metadata changes.
--   3. Maintains Profiles.updated_at.
--   4. Backfills profiles for Auth users that already exist.
--   5. Locks "Profiles" down with RLS policies and column-level grants.
--
-- Deletes need no trigger: Profiles.uuid references auth.users(id)
-- ON DELETE CASCADE.
--
-- Security notes:
--   * role_id is NEVER taken from user-supplied metadata (raw_user_meta_data
--     is editable by the signing-up user). New profiles start with
--     role_id = NULL; roles are assigned only by the service role / an admin.
--   * Trigger functions are SECURITY DEFINER with an empty search_path and
--     fully-qualified names, and are not executable by API roles.
--   * Values are trimmed and truncated to the column lengths so odd
--     metadata can never make a signup fail.
-- =====================================================================


-- =====================================================================
-- 1. TRIGGER FUNCTIONS
-- =====================================================================

-- Create a profile when an Auth user is created
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public."Profiles" (uuid, full_name, phone)
    VALUES (
        NEW.id,
        left(nullif(btrim(NEW.raw_user_meta_data ->> 'full_name'), ''), 150),
        left(nullif(btrim(coalesce(NEW.phone, NEW.raw_user_meta_data ->> 'phone')), ''), 30)
    )
    ON CONFLICT (uuid) DO NOTHING;

    RETURN NEW;
END;
$$;

-- Reflect later metadata / phone changes from Auth into the profile
CREATE OR REPLACE FUNCTION public.handle_user_updated()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    UPDATE public."Profiles"
    SET full_name = coalesce(
            left(nullif(btrim(NEW.raw_user_meta_data ->> 'full_name'), ''), 150),
            full_name),
        phone = coalesce(
            left(nullif(btrim(coalesce(NEW.phone, NEW.raw_user_meta_data ->> 'phone')), ''), 30),
            phone)
    WHERE uuid = NEW.id;

    RETURN NEW;
END;
$$;

-- Keep updated_at current
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


-- =====================================================================
-- 2. TRIGGERS
-- =====================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;
CREATE TRIGGER on_auth_user_updated
    AFTER UPDATE OF raw_user_meta_data, phone ON auth.users
    FOR EACH ROW
    WHEN (
        OLD.raw_user_meta_data IS DISTINCT FROM NEW.raw_user_meta_data
        OR OLD.phone IS DISTINCT FROM NEW.phone
    )
    EXECUTE FUNCTION public.handle_user_updated();

DROP TRIGGER IF EXISTS profiles_updated_at ON public."Profiles";
CREATE TRIGGER profiles_updated_at
    BEFORE UPDATE ON public."Profiles"
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_updated_at();


-- =====================================================================
-- 3. FUNCTION PRIVILEGES
--    Supabase grants EXECUTE on new public functions to API roles by
--    default; trigger functions have no reason to be callable by them.
-- =====================================================================

REVOKE ALL ON FUNCTION public.handle_new_user()     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_user_updated() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.touch_updated_at()    FROM PUBLIC, anon, authenticated;


-- =====================================================================
-- 4. BACKFILL (existing Auth users without a profile; safe to re-run)
-- =====================================================================

INSERT INTO public."Profiles" (uuid, full_name, phone)
SELECT
    u.id,
    left(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''), 150),
    left(nullif(btrim(coalesce(u.phone, u.raw_user_meta_data ->> 'phone')), ''), 30)
FROM auth.users u
ON CONFLICT (uuid) DO NOTHING;


-- =====================================================================
-- 5. ROW-LEVEL SECURITY + PRIVILEGES FOR "Profiles"
--    No INSERT or DELETE policy for API roles: rows are created by the
--    trigger and removed by the cascade from auth.users.
-- =====================================================================

ALTER TABLE public."Profiles" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own profile" ON public."Profiles";
CREATE POLICY "Users can view their own profile"
    ON public."Profiles" FOR SELECT TO authenticated
    USING ((SELECT auth.uid()) = uuid);

DROP POLICY IF EXISTS "Users can update their own profile" ON public."Profiles";
CREATE POLICY "Users can update their own profile"
    ON public."Profiles" FOR UPDATE TO authenticated
    USING ((SELECT auth.uid()) = uuid)
    WITH CHECK ((SELECT auth.uid()) = uuid);

REVOKE ALL ON public."Profiles" FROM anon, authenticated;
GRANT SELECT ON public."Profiles" TO authenticated;

-- Users may edit only their own name and phone; role_id, created_at and
-- updated_at cannot be changed from the client (no privilege escalation).
GRANT UPDATE (full_name, phone) ON public."Profiles" TO authenticated;