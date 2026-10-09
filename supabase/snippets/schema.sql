CREATE SCHEMA IF NOT EXISTS public;

-- =====================================================================
-- Pharmacy System Schema (PostgreSQL / Supabase)
-- Notes:
--   * Single-branch system (no Branches table).
--   * All user-specific records are exposed through a single Profiles table keyed
--     by auth.users.id. Customer / pharmacist / staff differentiation is handled
--     through the Profiles.role column and service-managed access.
--   * All foreign keys are declared inline inside each CREATE TABLE IF NOT EXISTS.
--   * Column-level checks and trigger-based safeguards are used to prevent bad
--     data before it reaches the database.
-- =====================================================================

-- =====================================================================
-- ENUMERATIONS
-- =====================================================================
CREATE TYPE inventory_status AS ENUM ('restock', 'sale', 'adjustment', 'return');

CREATE TYPE role_name AS ENUM (
    'owner',
    'administrator',
    'customer',
    'pharmacist'
);

CREATE TYPE order_status AS ENUM (
    'pending',
    'confirmed',
    'ready',
    'completed',
    'cancelled'
);

CREATE TYPE prescription_status AS ENUM ('pending', 'verified', 'declined');

CREATE TYPE payment_status AS ENUM ('pending', 'paid', 'failed', 'refunded');

CREATE TYPE notification_status AS ENUM ('pending', 'sent', 'failed');

-- =====================================================================
-- LOOKUP TABLES
-- =====================================================================
CREATE TABLE IF NOT EXISTS "Category" (
    category_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_name VARCHAR(100) NOT NULL UNIQUE CHECK (btrim(category_name) <> ''),
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS "NotificationType" (
    notification_type_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_type_name VARCHAR(50) NOT NULL UNIQUE CHECK (btrim(notification_type_name) <> '')
);

-- =====================================================================
-- PROFILES TABLE
-- =====================================================================
CREATE TABLE IF NOT EXISTS "Profiles" (
    id UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    full_name VARCHAR(150) NOT NULL CHECK (btrim(full_name) <> ''),
    phone VARCHAR(30) CHECK (phone IS NULL OR length(btrim(phone)) BETWEEN 7 AND 30),
    role role_name NOT NULL DEFAULT 'customer',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =====================================================================
-- CATALOG
-- =====================================================================
CREATE TABLE IF NOT EXISTS "Product" (
    product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id UUID NOT NULL REFERENCES "Category" (category_id) ON DELETE RESTRICT,
    name VARCHAR(200) NOT NULL CHECK (btrim(name) <> ''),
    description TEXT,
    same_day BOOLEAN NOT NULL DEFAULT TRUE,
    requires_rx BOOLEAN NOT NULL DEFAULT FALSE,
    brand VARCHAR(100) NOT NULL DEFAULT 'Generic' CHECK (btrim(brand) <> ''),
    dosage_form VARCHAR(50) NOT NULL CHECK (btrim(dosage_form) <> ''),
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    stock_quantity INT NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    img_path TEXT NOT NULL CHECK (btrim(img_path) <> ''),
    date_registered TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS "InventoryLog" (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES "Product" (product_id) ON DELETE RESTRICT,
    type inventory_status NOT NULL,
    quantity INT NOT NULL CHECK (quantity <> 0),
    previous_stock INT NOT NULL CHECK (previous_stock >= 0),
    new_stock INT NOT NULL CHECK (new_stock >= 0),
    log_date TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =====================================================================
-- PRESCRIPTIONS, ORDERS, PAYMENTS
-- =====================================================================
CREATE TABLE IF NOT EXISTS "Prescription" (
    prescription_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES "Profiles" (id) ON DELETE RESTRICT,
    pharmacist_id UUID REFERENCES "Profiles" (id) ON DELETE SET NULL,
    prescription_file TEXT NOT NULL CHECK (btrim(prescription_file) <> ''),
    status prescription_status NOT NULL DEFAULT 'pending',
    upload_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (status <> 'verified' OR pharmacist_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS "Order" (
    order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES "Profiles" (id) ON DELETE RESTRICT,
    order_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status order_status NOT NULL DEFAULT 'pending',
    valid_until TIMESTAMPTZ,
    total_amount NUMERIC(10, 2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    CHECK (valid_until IS NULL OR valid_until > order_date)
);

CREATE TABLE IF NOT EXISTS "OrderItem" (
    order_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES "Order" (order_id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES "Product" (product_id) ON DELETE RESTRICT,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    subtotal NUMERIC(10, 2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    UNIQUE (order_id, product_id)
);

CREATE TABLE IF NOT EXISTS "Payment" (
    payment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES "Order" (order_id) ON DELETE RESTRICT,
    amount NUMERIC(10, 2) NOT NULL CHECK (amount >= 0),
    claim_date TIMESTAMPTZ,
    reference_number VARCHAR(100) UNIQUE CHECK (reference_number IS NULL OR btrim(reference_number) <> ''),
    status payment_status NOT NULL DEFAULT 'pending'
);

-- =====================================================================
-- NOTIFICATIONS
-- =====================================================================
CREATE TABLE IF NOT EXISTS "Notification" (
    notification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES "Profiles" (id) ON DELETE CASCADE,
    order_id UUID REFERENCES "Order" (order_id) ON DELETE SET NULL,
    notification_type_id UUID NOT NULL REFERENCES "NotificationType" (notification_type_id) ON DELETE RESTRICT,
    message TEXT NOT NULL CHECK (btrim(message) <> ''),
    sent_via VARCHAR(20) NOT NULL CHECK (sent_via IN ('email', 'sms', 'push', 'in_app')),
    sent_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status notification_status NOT NULL DEFAULT 'pending'
);

-- =====================================================================
-- AUTH / PROFILE SYNC
-- =====================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
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
            phone),
        updated_at = NOW()
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$;

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

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_user_updated() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.touch_updated_at() FROM PUBLIC, anon, authenticated;

-- =====================================================================
--ROW-LEVEL SECURITY
-- =====================================================================
ALTER TABLE "Profiles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Category" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "NotificationType" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Product" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "InventoryLog" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Prescription" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Order" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "OrderItem" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Payment" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Notification" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile" ON "Profiles"
    FOR SELECT TO authenticated
    USING ((SELECT auth.uid()) = id);

CREATE POLICY "Users can update their own profile" ON "Profiles"
    FOR UPDATE TO authenticated
    USING ((SELECT auth.uid()) = id)
    WITH CHECK ((SELECT auth.uid()) = id);

CREATE POLICY "Anyone can read active categories" ON "Category"
    FOR SELECT TO anon, authenticated
    USING (is_active = TRUE);

CREATE POLICY "Authenticated users can read notification types" ON "NotificationType"
    FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY "Anyone can browse active products" ON "Product"
    FOR SELECT TO anon, authenticated
    USING (is_active = TRUE);

CREATE POLICY "Users can view their own prescriptions" ON "Prescription"
    FOR SELECT TO authenticated
    USING (auth.uid() = customer_id);

CREATE POLICY "Users can upload their own prescriptions" ON "Prescription"
    FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid() = customer_id
        AND status = 'pending'
        AND pharmacist_id IS NULL
    );

CREATE POLICY "Users can view their own orders" ON "Order"
    FOR SELECT TO authenticated
    USING (auth.uid() = customer_id);

CREATE POLICY "Users can place their own orders" ON "Order"
    FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid() = customer_id
        AND status = 'pending'
    );

CREATE POLICY "Users can view items of their own orders" ON "OrderItem"
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM "Order" o
            WHERE o.order_id = "OrderItem".order_id
              AND o.customer_id = auth.uid()
        )
    );

CREATE POLICY "Users can add items to their own pending orders" ON "OrderItem"
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM "Order" o
            WHERE o.order_id = "OrderItem".order_id
              AND o.customer_id = auth.uid()
              AND o.status = 'pending'
        )
    );

CREATE POLICY "Users can view payments for their own orders" ON "Payment"
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM "Order" o
            WHERE o.order_id = "Payment".order_id
              AND o.customer_id = auth.uid()
        )
    );

CREATE POLICY "Users can view their own notifications" ON "Notification"
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

-- =====================================================================
-- PRIVILEGES
-- =====================================================================
REVOKE ALL ON "Category", "NotificationType", "Profiles", "Product", "InventoryLog", "Prescription", "Order", "OrderItem", "Payment", "Notification" FROM anon, authenticated;

GRANT SELECT ON "Category", "Product" TO anon, authenticated;
GRANT SELECT ON "NotificationType", "Payment", "Notification" TO authenticated;
GRANT SELECT ON "Profiles" TO authenticated;
GRANT UPDATE (full_name, phone) ON "Profiles" TO authenticated;
GRANT SELECT ON "Prescription", "Order", "OrderItem" TO authenticated;
GRANT INSERT (customer_id, prescription_file) ON "Prescription" TO authenticated;
GRANT INSERT (customer_id, valid_until, total_amount) ON "Order" TO authenticated;
GRANT INSERT (order_id, product_id, quantity, unit_price) ON "OrderItem" TO authenticated;