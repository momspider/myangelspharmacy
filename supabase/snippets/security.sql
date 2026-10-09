-- =====================================================================
-- Schema Security and Auth Hardening
-- Run after the main schema script from "Table Definitions.sql".
--
-- This security layer is designed for the current Profiles-based schema:
--   * one auth-owned profile per user
--   * no separate Customer / Pharmacist / PharmacyStaff tables
--   * role enforcement handled through Profiles.role
--   * sensitive fields are protected by DB triggers and column grants
--
-- Security goals:
--   1. Prevent identity and role escalation.
--   2. Restrict profile mutation to the owning user or service roles.
--   3. Enforce business rules that should never be client-controlled.
--   4. Keep trigger functions non-callable by anonymous/authenticated users.
-- =====================================================================

-- =====================================================================
-- 1. AUTH / PROFILE HELPER FUNCTIONS
-- =====================================================================
CREATE OR REPLACE FUNCTION public.current_user_is_profile_owner(profile_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT auth.uid() = profile_id;
$$;

CREATE OR REPLACE FUNCTION public.user_has_role(required_role public.role_name)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Profiles" p
        WHERE p.id = auth.uid()
          AND p.role = required_role
    );
$$;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Profiles" p
        WHERE p.id = auth.uid()
          AND p.role IN ('owner', 'administrator', 'pharmacist')
    );
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Profiles" p
        WHERE p.id = auth.uid()
          AND p.role IN ('owner', 'administrator')
    );
$$;

-- =====================================================================
-- 2. PROFILE AND USER-OWNERSHIP VALIDATION
-- =====================================================================
CREATE OR REPLACE FUNCTION public.enforce_profile_security()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.id IS NULL THEN
            RAISE EXCEPTION 'Profile id cannot be NULL';
        END IF;

        IF current_user NOT IN ('postgres', 'service_role') AND NEW.id <> auth.uid() THEN
            RAISE EXCEPTION 'Users cannot insert profiles for other accounts';
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.id IS DISTINCT FROM OLD.id THEN
            RAISE EXCEPTION 'Profile identity is immutable';
        END IF;

        IF NEW.created_at IS DISTINCT FROM OLD.created_at AND current_user NOT IN ('postgres', 'service_role') THEN
            RAISE EXCEPTION 'created_at is immutable for regular users';
        END IF;

        IF NEW.role IS DISTINCT FROM OLD.role AND current_user NOT IN ('postgres', 'service_role') THEN
            RAISE EXCEPTION 'Role changes are restricted to trusted service/admin flows';
        END IF;

        IF NEW.is_active IS DISTINCT FROM OLD.is_active AND current_user NOT IN ('postgres', 'service_role') THEN
            RAISE EXCEPTION 'Account activation state is restricted';
        END IF;

        IF current_user NOT IN ('postgres', 'service_role') AND auth.uid() IS DISTINCT FROM NEW.id THEN
            RAISE EXCEPTION 'Users may only update their own profile';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public."Profiles" (id, full_name, phone)
    VALUES (
        NEW.id,
        left(nullif(btrim(NEW.raw_user_meta_data ->> 'full_name'), ''), 150),
        left(nullif(btrim(coalesce(NEW.phone, NEW.raw_user_meta_data ->> 'phone')), ''), 30)
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_user_updated()
RETURNS trigger
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
            phone),
        updated_at = NOW()
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- =====================================================================
-- 3. BUSINESS-RULE GUARDS
-- =====================================================================
CREATE OR REPLACE FUNCTION public.enforce_prescription_security()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.status = 'verified' AND NEW.pharmacist_id IS NULL THEN
        RAISE EXCEPTION 'Verified prescriptions must include a pharmacist';
    END IF;

    IF NEW.pharmacist_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM public."Profiles" p
            WHERE p.id = NEW.pharmacist_id
              AND p.role = 'pharmacist'
        ) THEN
            RAISE EXCEPTION 'Assigned pharmacist must have the pharmacist role';
        END IF;
    END IF;

    IF NEW.customer_id = NEW.pharmacist_id THEN
        RAISE EXCEPTION 'A prescription cannot be assigned to the same user as the customer';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_order_security()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.customer_id IS NULL THEN
        RAISE EXCEPTION 'Orders require a customer profile';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public."Profiles" p
        WHERE p.id = NEW.customer_id
          AND p.role = 'customer'
    ) THEN
        RAISE EXCEPTION 'Order owner must be a customer';
    END IF;

    IF NEW.valid_until IS NOT NULL AND NEW.valid_until <= NEW.order_date THEN
        RAISE EXCEPTION 'valid_until must be later than order_date';
    END IF;

    RETURN NEW;
END;
$$;

-- =====================================================================
-- 4. TRIGGERS
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

DROP TRIGGER IF EXISTS profiles_security_guard ON public."Profiles";
CREATE TRIGGER profiles_security_guard
    BEFORE INSERT OR UPDATE ON public."Profiles"
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_profile_security();

DROP TRIGGER IF EXISTS prescription_security_guard ON public."Prescription";
CREATE TRIGGER prescription_security_guard
    BEFORE INSERT OR UPDATE OF status, customer_id, pharmacist_id ON public."Prescription"
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_prescription_security();

DROP TRIGGER IF EXISTS order_security_guard ON public."Order";
CREATE TRIGGER order_security_guard
    BEFORE INSERT OR UPDATE OF customer_id, order_date, valid_until, status ON public."Order"
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_order_security();

-- =====================================================================
-- 5. FUNCTION PRIVILEGES
--    Trigger helpers are intentionally not callable by API roles.
-- =====================================================================
REVOKE ALL ON FUNCTION public.current_user_is_profile_owner(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.user_has_role(public.role_name) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_staff() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_profile_security() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_prescription_security() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_order_security() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_user_updated() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.touch_updated_at() FROM PUBLIC, anon, authenticated;

GRANT ALL ON FUNCTION public.current_user_is_profile_owner(uuid) TO service_role;
GRANT ALL ON FUNCTION public.user_has_role(public.role_name) TO service_role;
GRANT ALL ON FUNCTION public.is_staff() TO service_role;
GRANT ALL ON FUNCTION public.is_admin() TO service_role;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;
GRANT ALL ON FUNCTION public.handle_user_updated() TO service_role;
GRANT ALL ON FUNCTION public.touch_updated_at() TO service_role;

GRANT SELECT ON public."Profiles" TO service_role;
GRANT SELECT ON public."Product" TO service_role;

-- =====================================================================
-- 6. PROFILE RLS / POLICY HARDENING
-- =====================================================================
ALTER TABLE public."Profiles" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own profile" ON public."Profiles";
CREATE POLICY "Users can view their own profile"
    ON public."Profiles"
    FOR SELECT TO authenticated
    USING (public.current_user_is_profile_owner(id));

DROP POLICY IF EXISTS "Users can update their own profile" ON public."Profiles";
CREATE POLICY "Users can update their own profile"
    ON public."Profiles"
    FOR UPDATE TO authenticated
    USING (public.current_user_is_profile_owner(id))
    WITH CHECK (public.current_user_is_profile_owner(id));

-- Note: PostgreSQL row-level policies cannot reference NEW/OLD directly.
-- Immutable profile fields (id, role, created_at, is_active) are protected by
-- the "profiles_security_guard" trigger in this script rather than by the RLS
-- policy expression itself.

DROP POLICY IF EXISTS "Users cannot delete profiles" ON public."Profiles";
CREATE POLICY "Users cannot delete profiles"
    ON public."Profiles"
    FOR DELETE TO authenticated
    USING (FALSE);

REVOKE ALL ON public."Profiles" FROM anon, authenticated;
GRANT SELECT ON public."Profiles" TO authenticated;
GRANT UPDATE (full_name, phone) ON public."Profiles" TO authenticated;

-- =====================================================================
-- 7. BACKFILL EXISTING AUTH USERS
-- =====================================================================
INSERT INTO public."Profiles" (id, full_name, phone)
SELECT
    u.id,
    left(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''), 150),
    left(nullif(btrim(coalesce(u.phone, u.raw_user_meta_data ->> 'phone')), ''), 30)
FROM auth.users u
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- 8. SECURITY NOTES
-- =====================================================================
--   * User metadata is never trusted for role assignment.
--   * The database remains the enforcement point for identity and business rules.
--   * This script intentionally blocks clients from mutating immutable fields,
--     and only allows service/admin flows to adjust sensitive profile state.
-- =====================================================================