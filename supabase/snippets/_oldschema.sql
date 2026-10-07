-- 1. EXTENSIONS
 
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";   -- uuid_generate_v4()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";    -- gen_random_uuid() fallback
 
-- 2. ENUM TYPES
 
CREATE TYPE prescription_status  AS ENUM ('pending', 'verified', 'rejected');
CREATE TYPE order_status          AS ENUM ('pending', 'confirmed', 'ready', 'completed', 'cancelled');
CREATE TYPE etl_status            AS ENUM ('success', 'failed');
CREATE TYPE user_role             AS ENUM ('customer', 'pharmacist', 'admin');
CREATE TYPE restock_status        AS ENUM ('ordered', 'received', 'cancelled');
 
-- 3. BRANCHES
 
CREATE TABLE IF NOT EXISTS branches (
    branch_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(100) NOT NULL,
    address     VARCHAR(255),
    city        VARCHAR(100) DEFAULT 'Valenzuela City',
    state       VARCHAR(50)  DEFAULT 'Metro Manila',
    zip_code    VARCHAR(20),
    phone       VARCHAR(30),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
 
CREATE TABLE IF NOT EXISTS profiles (
    id          UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    full_name   VARCHAR(150),
    phone       VARCHAR(30),
    role        user_role NOT NULL DEFAULT 'customer',
    branch_id   UUID REFERENCES branches (branch_id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
 
-- Auto-create a profile row when a new Supabase Auth user signs up
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, phone)
    VALUES (
        NEW.id,
        NEW.raw_user_meta_data->>'full_name',
        NEW.raw_user_meta_data->>'phone'
    );
    RETURN NEW;
END;
$$;
 
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();
 
-- Auto-update updated_at on profile changes
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;
 
CREATE TRIGGER profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
 
CREATE TABLE IF NOT EXISTS medicines (
    medicine_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                VARCHAR(150) NOT NULL,
    sku                 VARCHAR(50) UNIQUE,
    unit_price          NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    category            VARCHAR(100),
    requires_rx         BOOLEAN NOT NULL DEFAULT FALSE,
    same_day_available  BOOLEAN NOT NULL DEFAULT TRUE,
    supplier_verified   BOOLEAN NOT NULL DEFAULT TRUE,
    image_url           TEXT,              
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
 
CREATE TRIGGER medicines_updated_at
    BEFORE UPDATE ON medicines
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
 
-- Stock per branch
CREATE TABLE IF NOT EXISTS inventory (
    inventory_id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id       UUID NOT NULL REFERENCES branches (branch_id) ON DELETE CASCADE,
    medicine_id     UUID NOT NULL REFERENCES medicines (medicine_id) ON DELETE CASCADE,
    stock_quantity  INT NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    reorder_level   INT NOT NULL DEFAULT 10,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (branch_id, medicine_id)
);
 
CREATE TRIGGER inventory_updated_at
    BEFORE UPDATE ON inventory
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
 
-- Restock / supplier orders
CREATE TABLE IF NOT EXISTS restock_orders (
    restock_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id       UUID NOT NULL REFERENCES branches (branch_id) ON DELETE CASCADE,
    medicine_id     UUID NOT NULL REFERENCES medicines (medicine_id) ON DELETE CASCADE,
    quantity        INT NOT NULL CHECK (quantity > 0),
    status          restock_status NOT NULL DEFAULT 'ordered',
    ordered_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    received_at     TIMESTAMPTZ,
    notes           TEXT
);
 
CREATE TABLE IF NOT EXISTS orders (
    order_id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    branch_id           UUID NOT NULL REFERENCES branches (branch_id),
    status              order_status NOT NULL DEFAULT 'pending',
    total_amount        NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    prescription_id     UUID,              -- FK added after prescriptions table
    notes               TEXT,
    placed_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ready_at            TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ
);
 
-- Line items inside an order
CREATE TABLE IF NOT EXISTS order_items (
    item_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id        UUID NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
    medicine_id     UUID NOT NULL REFERENCES medicines (medicine_id),
    quantity        INT NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),  -- snapshot at order time
    subtotal        NUMERIC(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED
);
 
-- Refill reminders (per user, per medicine)
CREATE TABLE IF NOT EXISTS refill_reminders (
    reminder_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    medicine_id     UUID NOT NULL REFERENCES medicines (medicine_id) ON DELETE CASCADE,
    last_refill     DATE,
    remind_every_days INT DEFAULT 30,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, medicine_id)
);
 
 

 
CREATE TABLE IF NOT EXISTS prescriptions (
    prescription_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    branch_id           UUID NOT NULL REFERENCES branches (branch_id),
    file_path           TEXT NOT NULL,
    file_name           TEXT,
    ocr_result          JSONB,             -- raw OCR output stored as JSON
    status              prescription_status NOT NULL DEFAULT 'pending',
    reviewed_by         UUID REFERENCES auth.users (id) ON DELETE SET NULL,  -- pharmacist
    reviewed_at         TIMESTAMPTZ,
    rejection_reason    TEXT,
    uploaded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
 
-- Add the FK on orders
ALTER TABLE orders
    ADD CONSTRAINT fk_orders_prescription
    FOREIGN KEY (prescription_id) REFERENCES prescriptions (prescription_id)
    ON DELETE SET NULL;
 
-- Index for admin dashboard queries
CREATE INDEX idx_prescriptions_status     ON prescriptions (status);
CREATE INDEX idx_prescriptions_branch     ON prescriptions (branch_id);
CREATE INDEX idx_prescriptions_user       ON prescriptions (user_id);
 
 

 

CREATE TABLE IF NOT EXISTS sales (
    sale_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id        UUID NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
    branch_id       UUID NOT NULL REFERENCES branches (branch_id),
    medicine_id     UUID NOT NULL REFERENCES medicines (medicine_id),
    quantity        INT NOT NULL,
    unit_price      NUMERIC(10,2) NOT NULL,
    sale_timestamp  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
 
CREATE INDEX idx_sales_branch      ON sales (branch_id);
CREATE INDEX idx_sales_medicine    ON sales (medicine_id);
CREATE INDEX idx_sales_timestamp   ON sales (sale_timestamp DESC);
 
-- ETL run logs
CREATE TABLE IF NOT EXISTS etl_logs (
    log_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    run_timestamp   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status          etl_status NOT NULL,
    message         TEXT
);
 
-- Contact form submissions
CREATE TABLE IF NOT EXISTS contact_messages (
    message_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name       VARCHAR(150) NOT NULL,
    email           VARCHAR(254) NOT NULL,
    phone           VARCHAR(30),
    branch          VARCHAR(50),
    message         TEXT NOT NULL,
    is_read         BOOLEAN NOT NULL DEFAULT FALSE,
    submitted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
 
ALTER TABLE profiles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches           ENABLE ROW LEVEL SECURITY;
ALTER TABLE medicines          ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory          ENABLE ROW LEVEL SECURITY;
ALTER TABLE restock_orders     ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders             ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items        ENABLE ROW LEVEL SECURITY;
ALTER TABLE refill_reminders   ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescriptions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales              ENABLE ROW LEVEL SECURITY;
ALTER TABLE etl_logs           ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_messages   ENABLE ROW LEVEL SECURITY;
 
-- ── Helper: is the current user an admin or pharmacist? ──────────────
CREATE OR REPLACE FUNCTION is_staff()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND role IN ('admin', 'pharmacist')
    );
$$;
 
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND role = 'admin'
    );
$$;
 
-- ── profiles ─────────────────────────────────────────────────────────
CREATE POLICY "Users can view their own profile"
    ON profiles FOR SELECT USING (auth.uid() = id);
 
CREATE POLICY "Users can update their own profile"
    ON profiles FOR UPDATE USING (auth.uid() = id);
 
CREATE POLICY "Admins can view all profiles"
    ON profiles FOR SELECT USING (is_admin());
 
CREATE POLICY "Admins can update any profile"
    ON profiles FOR UPDATE USING (is_admin());
 
-- ── branches (public read, admin write) ──────────────────────────────
CREATE POLICY "Anyone can read branches"
    ON branches FOR SELECT USING (TRUE);
 
CREATE POLICY "Admins can manage branches"
    ON branches FOR ALL USING (is_admin());
 
-- ── medicines (public read, admin write) ─────────────────────────────
CREATE POLICY "Anyone can browse active medicines"
    ON medicines FOR SELECT USING (is_active = TRUE);
 
CREATE POLICY "Admins can manage medicines"
    ON medicines FOR ALL USING (is_admin());
 
-- ── inventory (staff read, admin write) ──────────────────────────────
CREATE POLICY "Staff can view inventory"
    ON inventory FOR SELECT USING (is_staff());
 
CREATE POLICY "Admins can manage inventory"
    ON inventory FOR ALL USING (is_admin());
 
-- ── restock_orders (admin only) ───────────────────────────────────────
CREATE POLICY "Admins manage restock orders"
    ON restock_orders FOR ALL USING (is_admin());
 
-- ── orders ────────────────────────────────────────────────────────────
CREATE POLICY "Customers see their own orders"
    ON orders FOR SELECT USING (auth.uid() = user_id);
 
CREATE POLICY "Customers can place orders"
    ON orders FOR INSERT WITH CHECK (auth.uid() = user_id);
 
CREATE POLICY "Staff can view all orders"
    ON orders FOR SELECT USING (is_staff());
 
CREATE POLICY "Staff can update order status"
    ON orders FOR UPDATE USING (is_staff());
 
-- ── order_items ───────────────────────────────────────────────────────
CREATE POLICY "Customers see their own order items"
    ON order_items FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM orders o
        WHERE o.order_id = order_items.order_id
          AND o.user_id  = auth.uid()
    ));
 
CREATE POLICY "Customers can insert order items"
    ON order_items FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM orders o
        WHERE o.order_id = order_items.order_id
          AND o.user_id  = auth.uid()
    ));
 
CREATE POLICY "Staff can view all order items"
    ON order_items FOR SELECT USING (is_staff());
 
-- ── refill_reminders ─────────────────────────────────────────────────
CREATE POLICY "Users manage their own reminders"
    ON refill_reminders FOR ALL USING (auth.uid() = user_id);
 
-- ── prescriptions ────────────────────────────────────────────────────
CREATE POLICY "Customers can upload prescriptions"
    ON prescriptions FOR INSERT WITH CHECK (auth.uid() = user_id);
 
CREATE POLICY "Customers can view their own prescriptions"
    ON prescriptions FOR SELECT USING (auth.uid() = user_id);
 
CREATE POLICY "Staff can view all prescriptions"
    ON prescriptions FOR SELECT USING (is_staff());
 
CREATE POLICY "Staff can update prescription status"
    ON prescriptions FOR UPDATE USING (is_staff());
 
-- ── sales (staff read only) ───────────────────────────────────────────
CREATE POLICY "Staff can view sales"
    ON sales FOR SELECT USING (is_staff());
 
CREATE POLICY "Admins can manage sales"
    ON sales FOR ALL USING (is_admin());
 
-- ── etl_logs (admin only) ────────────────────────────────────────────
CREATE POLICY "Admins can view ETL logs"
    ON etl_logs FOR ALL USING (is_admin());
 
-- ── contact_messages (public insert, admin read) ──────────────────────
CREATE POLICY "Anyone can submit a contact message"
    ON contact_messages FOR INSERT WITH CHECK (TRUE);
 
CREATE POLICY "Admins can read contact messages"
    ON contact_messages FOR SELECT USING (is_admin());
 
CREATE POLICY "Admins can update contact messages"
    ON contact_messages FOR UPDATE USING (is_admin());
 
 
 
-- Branches
INSERT INTO branches (name, address, city, zip_code) VALUES
    ('Punturin Branch', '[Street Address], Punturin', 'Valenzuela City', '1442'),
    ('Malinta Branch',  '[Street Address], Malinta',  'Valenzuela City', '1458')
ON CONFLICT DO NOTHING;
 

INSERT INTO medicines (name, sku, unit_price, category, requires_rx, same_day_available, image_url) VALUES
    ('Amlodipine + Losartan', 'SKU-001', 28.50, 'Cardiovascular',  TRUE,  TRUE,  'assets/amlodipinelosartan.jpg'),
    ('Amoxicillin',           'SKU-002', 18.00, 'Antibiotics',     TRUE,  FALSE, 'assets/amoxicillin.jpg'),
    ('Biogesic (Paracetamol)','SKU-003',  8.00, 'Pain Relief',     FALSE, TRUE,  'assets/biogesic.jpg'),
    ('Caltrate Advance',      'SKU-004', 52.00, 'Supplements',     FALSE, TRUE,  'assets/caltrateadvance.jpg'),
    ('Ibuprofen',             'SKU-005', 12.00, 'Pain Relief',     FALSE, TRUE,  'assets/ibuprofen.jpg'),
    ('Impodex',               'SKU-006', 35.00, 'General',         FALSE, TRUE,  'assets/impodex.jpg'),
    ('Metformin 500mg',       'SKU-007', 12.00, 'Diabetes',        TRUE,  TRUE,  NULL)
ON CONFLICT (sku) DO NOTHING;