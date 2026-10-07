CREATE SCHEMA IF NOT EXISTS public;

-- =====================================================================
-- Pharmacy System Schema (PostgreSQL / Supabase)
-- Source: ERD-bulahan-caronon-galvez-naquita
-- Notes:
--   * Single-branch system (no Branches table).
--   * Customer and PharmacyStaff are keyed by Supabase Auth UIDs
--     (auth.users.id). Email and credentials live in Supabase Auth only.
--   * All foreign keys are declared inline inside each CREATE TABLE IF NOT EXISTS.
--   * No triggers, functions, or procedures.
--   * Table names follow the ERD (PascalCase, quoted); columns are snake_case.
-- =====================================================================


-- =====================================================================
-- ENUMERATIONS
-- =====================================================================
CREATE TYPE inventory_status AS ENUM ('restock', 'sale', 'adjustment', 'return');
CREATE TYPE order_status AS ENUM ('pending', 'confirmed', 'ready', 'completed', 'cancelled');
CREATE TYPE prescription_status AS ENUM ('pending', 'verified', 'declined');
CREATE TYPE payment_status AS ENUM ('pending', 'paid', 'failed', 'refunded');
CREATE TYPE notification_status AS ENUM ('pending', 'sent', 'failed');


-- =====================================================================
-- 1. LOOKUP TABLES
-- =====================================================================

CREATE TABLE IF NOT EXISTS "UserRole" (
    role_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_name    VARCHAR(50)  NOT NULL UNIQUE,
    description  TEXT
);

CREATE TABLE IF NOT EXISTS "Category" (
    category_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_name  VARCHAR(100) NOT NULL UNIQUE,
    description    TEXT,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS "NotificationType" (
    notification_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_type  VARCHAR(50) NOT NULL UNIQUE
);


-- =====================================================================
-- PROFILES TABLE (for exposing users from Supabase Auth)
-- =====================================================================
CREATE TABLE IF NOT EXISTS "Profiles" (
    uuid        UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    full_name   VARCHAR(150),
    phone       VARCHAR(30),
    role_id     UUID
                    REFERENCES "UserRole" (role_id) ON DELETE RESTRICT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =====================================================================
-- 2. USERS (linked to Supabase Auth)
-- =====================================================================

CREATE TABLE IF NOT EXISTS "Customer" (
    customer_id      UUID PRIMARY KEY
                         REFERENCES auth.users (id) ON DELETE CASCADE,
    full_name        VARCHAR(150) NOT NULL,
    phone            VARCHAR(30),
    address          TEXT,
    date_registered  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active        BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS "PharmacyStaff" (
    staff_id   UUID PRIMARY KEY
                   REFERENCES auth.users (id) ON DELETE CASCADE,
    role_id    UUID NOT NULL
                   REFERENCES "UserRole" (role_id) ON DELETE RESTRICT,
    full_name  VARCHAR(150) NOT NULL,
    phone      VARCHAR(30),
    is_active  BOOLEAN NOT NULL DEFAULT TRUE
);

-- Subtype of PharmacyStaff
CREATE TABLE IF NOT EXISTS "Pharmacist" (
    pharmacist_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id       UUID NOT NULL UNIQUE
                       REFERENCES "PharmacyStaff" (staff_id) ON DELETE CASCADE
);


-- =====================================================================
-- 3. CATALOG
-- =====================================================================

CREATE TABLE IF NOT EXISTS "Product" (
    product_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id     UUID NOT NULL
                        REFERENCES "Category" (category_id) ON DELETE RESTRICT,
    name            VARCHAR(200) NOT NULL,
    description     TEXT,
    brand           VARCHAR(100),
    dosage_form     VARCHAR(50),
    price           NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    stock_quantity  INT NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS "InventoryLog" (
    log_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id      UUID NOT NULL
                        REFERENCES "Product" (product_id) ON DELETE RESTRICT,
    type            inventory_status NOT NULL,
    quantity        INT NOT NULL CHECK (quantity <> 0),
    previous_stock  INT NOT NULL CHECK (previous_stock >= 0),
    new_stock       INT NOT NULL CHECK (new_stock >= 0),
    log_date        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =====================================================================
-- 4. PRESCRIPTIONS, ORDERS, PAYMENTS
-- =====================================================================

CREATE TABLE IF NOT EXISTS "Prescription" (
    prescription_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id        UUID NOT NULL
                           REFERENCES "Customer" (customer_id) ON DELETE RESTRICT,
    pharmacist_id      UUID
                           REFERENCES "Pharmacist" (pharmacist_id) ON DELETE SET NULL,
    prescription_file  TEXT NOT NULL,   -- Supabase Storage object path
    status             prescription_status NOT NULL DEFAULT 'pending',
    upload_date        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS "Order" (
    order_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id   UUID NOT NULL
                      REFERENCES "Customer" (customer_id) ON DELETE RESTRICT,
    order_date    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status        order_status NOT NULL DEFAULT 'pending',
    valid_until   TIMESTAMPTZ,
    total_amount  NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0)
);

CREATE TABLE IF NOT EXISTS "OrderItem" (
    order_item_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id       UUID NOT NULL
                       REFERENCES "Order" (order_id) ON DELETE CASCADE,
    product_id     UUID NOT NULL
                       REFERENCES "Product" (product_id) ON DELETE RESTRICT,
    quantity       INT NOT NULL CHECK (quantity > 0),
    unit_price     NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    subtotal       NUMERIC(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    UNIQUE (order_id, product_id)
);

CREATE TABLE IF NOT EXISTS "Payment" (
    payment_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id          UUID NOT NULL
                          REFERENCES "Order" (order_id) ON DELETE RESTRICT,
    amount            NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    claim_date        TIMESTAMPTZ,
    reference_number  VARCHAR(100) UNIQUE,
    status            payment_status NOT NULL DEFAULT 'pending'
);


-- =====================================================================
-- 5. NOTIFICATIONS
-- =====================================================================

-- notification_id is both the PK and the FK to NotificationType
-- ("is a type of" relationship in the ERD; type_id removed).
CREATE TABLE IF NOT EXISTS "Notification" (
    notification_id  UUID PRIMARY KEY
                         REFERENCES "NotificationType" (notification_id) ON DELETE RESTRICT,
    customer_id      UUID NOT NULL
                         REFERENCES "Customer" (customer_id) ON DELETE CASCADE,
    order_id         UUID
                         REFERENCES "Order" (order_id) ON DELETE SET NULL,
    type_id          UUID
                         REFERENCES "NotificationType" (notification_id) ON DELETE RESTRICT,
    message          TEXT NOT NULL,
    sent_via         VARCHAR(20) NOT NULL
                         CHECK (sent_via IN ('email', 'sms', 'push', 'in_app')),
    sent_date        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status           notification_status NOT NULL DEFAULT 'pending'
);


-- =====================================================================
-- 6. ROW-LEVEL SECURITY
-- =====================================================================

ALTER TABLE "Profiles"         ENABLE ROW LEVEL SECURITY;
ALTER TABLE "UserRole"         ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Category"         ENABLE ROW LEVEL SECURITY;
ALTER TABLE "NotificationType" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Customer"         ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PharmacyStaff"    ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Pharmacist"       ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Product"          ENABLE ROW LEVEL SECURITY;
ALTER TABLE "InventoryLog"     ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Prescription"     ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Order"            ENABLE ROW LEVEL SECURITY;
ALTER TABLE "OrderItem"        ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Payment"          ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Notification"     ENABLE ROW LEVEL SECURITY;

-- Tables with no policy below ("InventoryLog") are inaccessible to
-- anon/authenticated clients; only the service role (bypasses RLS) can use them.
-- Staff-wide policies are intentionally deferred (see notes).

-- ── Lookup tables ────────────────────────────────────────────────────
CREATE POLICY "Authenticated users can read roles"
    ON "UserRole" FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY "Anyone can read active categories"
    ON "Category" FOR SELECT TO anon, authenticated
    USING (is_active = TRUE);

CREATE POLICY "Authenticated users can read notification types"
    ON "NotificationType" FOR SELECT TO authenticated
    USING (TRUE);

-- ── Customer ─────────────────────────────────────────────────────────
CREATE POLICY "Customers can view their own record"
    ON "Customer" FOR SELECT TO authenticated
    USING (auth.uid() = customer_id);

CREATE POLICY "Customers can create their own record"
    ON "Customer" FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = customer_id);

CREATE POLICY "Customers can update their own record"
    ON "Customer" FOR UPDATE TO authenticated
    USING (auth.uid() = customer_id)
    WITH CHECK (auth.uid() = customer_id);

-- ── PharmacyStaff / Pharmacist (read-only to the owner) ──────────────
CREATE POLICY "Staff can view their own record"
    ON "PharmacyStaff" FOR SELECT TO authenticated
    USING (auth.uid() = staff_id);

CREATE POLICY "Pharmacists can view their own record"
    ON "Pharmacist" FOR SELECT TO authenticated
    USING (auth.uid() = staff_id);

-- ── Product (public catalog) ─────────────────────────────────────────
CREATE POLICY "Anyone can browse active products"
    ON "Product" FOR SELECT TO anon, authenticated
    USING (is_active = TRUE);

-- ── Prescription ─────────────────────────────────────────────────────
CREATE POLICY "Customers can view their own prescriptions"
    ON "Prescription" FOR SELECT TO authenticated
    USING (auth.uid() = customer_id);

CREATE POLICY "Customers can upload their own prescriptions"
    ON "Prescription" FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid() = customer_id
        AND status = 'pending'
        AND pharmacist_id IS NULL
    );

-- ── Order ────────────────────────────────────────────────────────────
CREATE POLICY "Customers can view their own orders"
    ON "Order" FOR SELECT TO authenticated
    USING (auth.uid() = customer_id);

CREATE POLICY "Customers can place their own orders"
    ON "Order" FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = customer_id AND status = 'pending');

-- ── OrderItem (access follows the parent order) ──────────────────────
CREATE POLICY "Customers can view items of their own orders"
    ON "OrderItem" FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM "Order" o
        WHERE o.order_id = "OrderItem".order_id
          AND o.customer_id = auth.uid()
    ));

CREATE POLICY "Customers can add items to their own pending orders"
    ON "OrderItem" FOR INSERT TO authenticated
    WITH CHECK (EXISTS (
        SELECT 1 FROM "Order" o
        WHERE o.order_id = "OrderItem".order_id
          AND o.customer_id = auth.uid()
          AND o.status = 'pending'
    ));

-- ── Payment (read-only to the order owner) ───────────────────────────
CREATE POLICY "Customers can view payments for their own orders"
    ON "Payment" FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM "Order" o
        WHERE o.order_id = "Payment".order_id
          AND o.customer_id = auth.uid()
    ));

-- ── Notification (read-only to the recipient) ────────────────────────
CREATE POLICY "Customers can view their own notifications"
    ON "Notification" FOR SELECT TO authenticated
    USING (auth.uid() = customer_id);


-- =====================================================================
-- 7. PRIVILEGES (definition-based security)
--    Supabase grants broad access to anon/authenticated by default;
--    revoke it and grant only what the policies above are meant to use.
-- =====================================================================

REVOKE ALL ON
    "UserRole", "Category", "NotificationType", "Customer", "PharmacyStaff",
    "Pharmacist", "Product", "InventoryLog", "Prescription", "Order",
    "OrderItem", "Payment", "Notification"
FROM anon, authenticated;

-- Public catalog
GRANT SELECT ON "Category", "Product" TO anon, authenticated;

-- Read-only for signed-in users (rows limited by RLS)
GRANT SELECT ON
    "UserRole", "NotificationType", "PharmacyStaff", "Pharmacist",
    "Payment", "Notification"
TO authenticated;

-- Customer: self-service, restricted columns only
GRANT SELECT ON "Customer" TO authenticated;
GRANT INSERT (customer_id, full_name, phone, address) ON "Customer" TO authenticated;
GRANT UPDATE (full_name, phone, address)              ON "Customer" TO authenticated;

-- Prescription / Order / OrderItem: customers may read and create, not edit
GRANT SELECT ON "Prescription", "Order", "OrderItem" TO authenticated;
GRANT INSERT (customer_id, prescription_file)                  ON "Prescription" TO authenticated;
GRANT INSERT (customer_id, valid_until, total_amount)          ON "Order"        TO authenticated;
GRANT INSERT (order_id, product_id, quantity, unit_price)      ON "OrderItem"    TO authenticated;