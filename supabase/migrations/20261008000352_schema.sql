SET local check_function_bodies = off;

DROP EVENT TRIGGER "ensure_rls";

DROP FUNCTION "public"."rls_auto_enable"();

CREATE TABLE "public"."Category" (
  "category_id"   uuid                   NOT NULL DEFAULT gen_random_uuid(),
  "category_name" character varying(100) NOT NULL,
  "description"   text,
  "is_active"     boolean                NOT NULL DEFAULT true,
  CONSTRAINT "Category_category_name_key" UNIQUE (category_name),
  CONSTRAINT "Category_pkey" PRIMARY KEY (category_id)
);

ALTER TABLE "public"."Category"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."Customer" (
  "customer_id"     uuid                     NOT NULL,
  "full_name"       character varying(150)   NOT NULL,
  "phone"           character varying(30),
  "address"         text,
  "date_registered" timestamp with time zone NOT NULL DEFAULT now(),
  "is_active"       boolean                  NOT NULL DEFAULT true,
  CONSTRAINT "Customer_pkey" PRIMARY KEY (customer_id)
);

ALTER TABLE "public"."Customer"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."Customer" FROM "anon";

CREATE TABLE "public"."InventoryLog" (
  "log_id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "product_id"     uuid                     NOT NULL,
  "quantity"       integer                  NOT NULL,
  "previous_stock" integer                  NOT NULL,
  "new_stock"      integer                  NOT NULL,
  "log_date"       timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "InventoryLog_new_stock_check" CHECK ((new_stock >= 0)),
  CONSTRAINT "InventoryLog_pkey" PRIMARY KEY (log_id),
  CONSTRAINT "InventoryLog_previous_stock_check" CHECK ((previous_stock >= 0)),
  CONSTRAINT "InventoryLog_quantity_check" CHECK ((quantity <> 0))
);

ALTER TABLE "public"."InventoryLog"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."InventoryLog" FROM "anon", "authenticated";

CREATE TABLE "public"."NotificationType" (
  "notification_id"   uuid                  NOT NULL DEFAULT gen_random_uuid(),
  "notification_type" character varying(50) NOT NULL,
  CONSTRAINT "NotificationType_notification_type_key" UNIQUE (notification_type),
  CONSTRAINT "NotificationType_pkey" PRIMARY KEY (notification_id)
);

ALTER TABLE "public"."NotificationType"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."NotificationType" FROM "anon";

CREATE TABLE "public"."Notification" (
  "notification_id" uuid                     NOT NULL,
  "customer_id"     uuid                     NOT NULL,
  "order_id"        uuid,
  "type_id"         uuid,
  "message"         text                     NOT NULL,
  "sent_via"        character varying(20)    NOT NULL,
  "sent_date"       timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "Notification_pkey" PRIMARY KEY (notification_id),
  CONSTRAINT "Notification_sent_via_check"
    CHECK (((sent_via)::text = ANY ((ARRAY['email'::character varying, 'sms'::character varying, 'push'::character varying, 'in_app'::character varying])::text[])))
);

ALTER TABLE "public"."Notification"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."Notification" FROM "anon";

CREATE TABLE "public"."OrderItem" (
  "order_item_id" uuid          NOT NULL DEFAULT gen_random_uuid(),
  "order_id"      uuid          NOT NULL,
  "product_id"    uuid          NOT NULL,
  "quantity"      integer       NOT NULL,
  "unit_price"    numeric(10,2) NOT NULL,
  CONSTRAINT "OrderItem_order_id_product_id_key" UNIQUE (order_id, product_id),
  CONSTRAINT "OrderItem_pkey" PRIMARY KEY (order_item_id),
  CONSTRAINT "OrderItem_quantity_check" CHECK ((quantity > 0)),
  CONSTRAINT "OrderItem_unit_price_check" CHECK ((unit_price >= (0)::numeric))
);

ALTER TABLE "public"."OrderItem"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."OrderItem" FROM "anon";

CREATE TABLE "public"."Order" (
  "order_id"     uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "customer_id"  uuid                     NOT NULL,
  "order_date"   timestamp with time zone NOT NULL DEFAULT now(),
  "valid_until"  timestamp with time zone,
  "total_amount" numeric(10,2)            NOT NULL DEFAULT 0,
  CONSTRAINT "Order_pkey" PRIMARY KEY (order_id),
  CONSTRAINT "Order_total_amount_check" CHECK ((total_amount >= (0)::numeric))
);

ALTER TABLE "public"."Order"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."Order" FROM "anon";

CREATE TABLE "public"."Payment" (
  "payment_id"       uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "order_id"         uuid                     NOT NULL,
  "amount"           numeric(10,2)            NOT NULL,
  "claim_date"       timestamp with time zone,
  "reference_number" character varying(100),
  CONSTRAINT "Payment_amount_check" CHECK ((amount >= (0)::numeric)),
  CONSTRAINT "Payment_pkey" PRIMARY KEY (payment_id),
  CONSTRAINT "Payment_reference_number_key" UNIQUE (reference_number)
);

ALTER TABLE "public"."Payment"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."Payment" FROM "anon";

CREATE TABLE "public"."Pharmacist" (
  "pharmacist_id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "staff_id"      uuid NOT NULL,
  CONSTRAINT "Pharmacist_pkey" PRIMARY KEY (pharmacist_id),
  CONSTRAINT "Pharmacist_staff_id_key" UNIQUE (staff_id)
);

ALTER TABLE "public"."Pharmacist"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."Pharmacist" FROM "anon";

CREATE TABLE "public"."PharmacyStaff" (
  "staff_id"  uuid                   NOT NULL,
  "role_id"   uuid                   NOT NULL,
  "full_name" character varying(150) NOT NULL,
  "phone"     character varying(30),
  "is_active" boolean                NOT NULL DEFAULT true,
  CONSTRAINT "PharmacyStaff_pkey" PRIMARY KEY (staff_id)
);

ALTER TABLE "public"."PharmacyStaff"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."PharmacyStaff" FROM "anon";

CREATE TABLE "public"."Prescription" (
  "prescription_id"   uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "customer_id"       uuid                     NOT NULL,
  "pharmacist_id"     uuid,
  "prescription_file" text                     NOT NULL,
  "upload_date"       timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "Prescription_pkey" PRIMARY KEY (prescription_id)
);

ALTER TABLE "public"."Prescription"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."Prescription" FROM "anon";

CREATE TABLE "public"."Product" (
  "product_id"     uuid                   NOT NULL DEFAULT gen_random_uuid(),
  "category_id"    uuid                   NOT NULL,
  "name"           character varying(200) NOT NULL,
  "description"    text,
  "brand"          character varying(100),
  "dosage_form"    character varying(50),
  "price"          numeric(10,2)          NOT NULL,
  "stock_quantity" integer                NOT NULL DEFAULT 0,
  "is_active"      boolean                NOT NULL DEFAULT true,
  CONSTRAINT "Product_pkey" PRIMARY KEY (product_id),
  CONSTRAINT "Product_price_check" CHECK ((price >= (0)::numeric)),
  CONSTRAINT "Product_stock_quantity_check" CHECK ((stock_quantity >= 0))
);

ALTER TABLE "public"."Product"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."Profiles" (
  "uuid"       uuid                     NOT NULL,
  "full_name"  character varying(150),
  "phone"      character varying(30),
  "role_id"    uuid,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "Profiles_pkey" PRIMARY KEY (uuid)
);

ALTER TABLE "public"."Profiles"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."Profiles" FROM "anon";

CREATE TABLE "public"."UserRole" (
  "role_id"     uuid                  NOT NULL DEFAULT gen_random_uuid(),
  "role_name"   character varying(50) NOT NULL,
  "description" text,
  CONSTRAINT "UserRole_pkey" PRIMARY KEY (role_id),
  CONSTRAINT "UserRole_role_name_key" UNIQUE (role_name)
);

ALTER TABLE "public"."UserRole"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."UserRole" FROM "anon";

ALTER TABLE "public"."OrderItem"
  ADD COLUMN "subtotal" numeric(10,2) GENERATED ALWAYS AS (((quantity)::numeric * unit_price)) STORED;

CREATE TYPE "public"."inventory_status" AS ENUM (
  'restock',
  'sale',
  'adjustment',
  'return'
);

ALTER TABLE "public"."InventoryLog"
  ADD COLUMN "type" public.inventory_status NOT NULL;

CREATE TYPE "public"."notification_status" AS ENUM (
  'pending',
  'sent',
  'failed'
);

ALTER TABLE "public"."Notification"
  ADD COLUMN "status" public.notification_status NOT NULL DEFAULT 'pending'::public.notification_status;

CREATE TYPE "public"."order_status" AS ENUM (
  'pending',
  'confirmed',
  'ready',
  'completed',
  'cancelled'
);

ALTER TABLE "public"."Order"
  ADD COLUMN "status" public.order_status NOT NULL DEFAULT 'pending'::public.order_status;

CREATE TYPE "public"."payment_status" AS ENUM (
  'pending',
  'paid',
  'failed',
  'refunded'
);

ALTER TABLE "public"."Payment"
  ADD COLUMN "status" public.payment_status NOT NULL DEFAULT 'pending'::public.payment_status;

CREATE TYPE "public"."prescription_status" AS ENUM (
  'pending',
  'verified',
  'declined'
);

ALTER TABLE "public"."Prescription"
  ADD COLUMN "status" public.prescription_status NOT NULL DEFAULT 'pending'::public.prescription_status;

CREATE OR REPLACE FUNCTION public.handle_new_user()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.handle_user_updated()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

REVOKE ALL ON FUNCTION "public"."handle_user_updated"() FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.touch_updated_at()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."touch_updated_at"() FROM PUBLIC, "anon", "authenticated";

ALTER TABLE "public"."Customer"
  ADD CONSTRAINT "Customer_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."Notification"
  ADD CONSTRAINT "Notification_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES public."Customer"(customer_id) ON DELETE CASCADE;

ALTER TABLE "public"."Notification"
  ADD CONSTRAINT "Notification_notification_id_fkey" FOREIGN KEY (notification_id) REFERENCES public."NotificationType"(notification_id) ON DELETE RESTRICT;

ALTER TABLE "public"."Notification"
  ADD CONSTRAINT "Notification_type_id_fkey" FOREIGN KEY (type_id) REFERENCES public."NotificationType"(notification_id) ON DELETE RESTRICT;

ALTER TABLE "public"."Order"
  ADD CONSTRAINT "Order_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES public."Customer"(customer_id) ON DELETE RESTRICT;

ALTER TABLE "public"."Notification"
  ADD CONSTRAINT "Notification_order_id_fkey" FOREIGN KEY (order_id) REFERENCES public."Order"(order_id) ON DELETE SET NULL;

ALTER TABLE "public"."OrderItem"
  ADD CONSTRAINT "OrderItem_order_id_fkey" FOREIGN KEY (order_id) REFERENCES public."Order"(order_id) ON DELETE CASCADE;

ALTER TABLE "public"."Payment"
  ADD CONSTRAINT "Payment_order_id_fkey" FOREIGN KEY (order_id) REFERENCES public."Order"(order_id) ON DELETE RESTRICT;

ALTER TABLE "public"."Pharmacist"
  ADD CONSTRAINT "Pharmacist_staff_id_fkey" FOREIGN KEY (staff_id) REFERENCES public."PharmacyStaff"(staff_id) ON DELETE CASCADE;

ALTER TABLE "public"."PharmacyStaff"
  ADD CONSTRAINT "PharmacyStaff_staff_id_fkey" FOREIGN KEY (staff_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."Prescription"
  ADD CONSTRAINT "Prescription_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES public."Customer"(customer_id) ON DELETE RESTRICT;

ALTER TABLE "public"."Prescription"
  ADD CONSTRAINT "Prescription_pharmacist_id_fkey" FOREIGN KEY (pharmacist_id) REFERENCES public."Pharmacist"(pharmacist_id) ON DELETE SET NULL;

ALTER TABLE "public"."Product"
  ADD CONSTRAINT "Product_category_id_fkey" FOREIGN KEY (category_id) REFERENCES public."Category"(category_id) ON DELETE RESTRICT;

ALTER TABLE "public"."InventoryLog"
  ADD CONSTRAINT "InventoryLog_product_id_fkey" FOREIGN KEY (product_id) REFERENCES public."Product"(product_id) ON DELETE RESTRICT;

ALTER TABLE "public"."OrderItem"
  ADD CONSTRAINT "OrderItem_product_id_fkey" FOREIGN KEY (product_id) REFERENCES public."Product"(product_id) ON DELETE RESTRICT;

ALTER TABLE "public"."Profiles"
  ADD CONSTRAINT "Profiles_uuid_fkey" FOREIGN KEY (uuid) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."PharmacyStaff"
  ADD CONSTRAINT "PharmacyStaff_role_id_fkey" FOREIGN KEY (role_id) REFERENCES public."UserRole"(role_id) ON DELETE RESTRICT;

ALTER TABLE "public"."Profiles"
  ADD CONSTRAINT "Profiles_role_id_fkey" FOREIGN KEY (role_id) REFERENCES public."UserRole"(role_id) ON DELETE RESTRICT;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER on_auth_user_updated
  AFTER UPDATE OF raw_user_meta_data, phone ON auth.users
  FOR EACH ROW
  WHEN (((old.raw_user_meta_data IS DISTINCT FROM new.raw_user_meta_data) OR (old.phone IS DISTINCT FROM new.phone)))
  EXECUTE FUNCTION public.handle_user_updated();

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public."Profiles"
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_updated_at();

CREATE POLICY "Anyone can read active categories" ON "public"."Category"
  FOR SELECT
  TO "anon", "authenticated"
  USING ((is_active = true));

CREATE POLICY "Customers can create their own record" ON "public"."Customer"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((auth.uid() = customer_id));

CREATE POLICY "Customers can update their own record" ON "public"."Customer"
  FOR UPDATE
  TO "authenticated"
  USING ((auth.uid() = customer_id))
  WITH CHECK ((auth.uid() = customer_id));

CREATE POLICY "Customers can view their own record" ON "public"."Customer"
  FOR SELECT
  TO "authenticated"
  USING ((auth.uid() = customer_id));

CREATE POLICY "Customers can view their own notifications" ON "public"."Notification"
  FOR SELECT
  TO "authenticated"
  USING ((auth.uid() = customer_id));

CREATE POLICY "Authenticated users can read notification types" ON "public"."NotificationType"
  FOR SELECT
  TO "authenticated"
  USING (true);

CREATE POLICY "Customers can place their own orders" ON "public"."Order"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((auth.uid() = customer_id) AND (status = 'pending'::public.order_status)));

CREATE POLICY "Customers can view their own orders" ON "public"."Order"
  FOR SELECT
  TO "authenticated"
  USING ((auth.uid() = customer_id));

CREATE POLICY "Customers can add items to their own pending orders" ON "public"."OrderItem"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((EXISTS ( SELECT 1
   FROM public."Order" o
  WHERE ((o.order_id = "OrderItem".order_id) AND (o.customer_id = auth.uid()) AND (o.status = 'pending'::public.order_status)))));

CREATE POLICY "Customers can view items of their own orders" ON "public"."OrderItem"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM public."Order" o
  WHERE ((o.order_id = "OrderItem".order_id) AND (o.customer_id = auth.uid())))));

CREATE POLICY "Customers can view payments for their own orders" ON "public"."Payment"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM public."Order" o
  WHERE ((o.order_id = "Payment".order_id) AND (o.customer_id = auth.uid())))));

CREATE POLICY "Pharmacists can view their own record" ON "public"."Pharmacist"
  FOR SELECT
  TO "authenticated"
  USING ((auth.uid() = staff_id));

CREATE POLICY "Staff can view their own record" ON "public"."PharmacyStaff"
  FOR SELECT
  TO "authenticated"
  USING ((auth.uid() = staff_id));

CREATE POLICY "Customers can upload their own prescriptions" ON "public"."Prescription"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((auth.uid() = customer_id) AND (status = 'pending'::public.prescription_status) AND (pharmacist_id IS NULL)));

CREATE POLICY "Customers can view their own prescriptions" ON "public"."Prescription"
  FOR SELECT
  TO "authenticated"
  USING ((auth.uid() = customer_id));

CREATE POLICY "Anyone can browse active products" ON "public"."Product"
  FOR SELECT
  TO "anon", "authenticated"
  USING ((is_active = true));

CREATE POLICY "Users can update their own profile" ON "public"."Profiles"
  FOR UPDATE
  TO "authenticated"
  USING ((( SELECT auth.uid() AS uid) = uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = uuid));

CREATE POLICY "Users can view their own profile" ON "public"."Profiles"
  FOR SELECT
  TO "authenticated"
  USING ((( SELECT auth.uid() AS uid) = uuid));

CREATE POLICY "Authenticated users can read roles" ON "public"."UserRole"
  FOR SELECT
  TO "authenticated"
  USING (true);

REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."handle_new_user"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."handle_new_user"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."handle_user_updated"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."handle_user_updated"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."handle_user_updated"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."touch_updated_at"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."touch_updated_at"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."touch_updated_at"() TO "service_role";

REVOKE ALL ON TABLE "public"."Category" FROM "anon";

GRANT SELECT ON TABLE "public"."Category" TO "anon";

REVOKE ALL ON TABLE "public"."Category" FROM "authenticated";

GRANT SELECT ON TABLE "public"."Category" TO "authenticated";

REVOKE ALL ON TABLE "public"."Category" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Category" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Category" TO "service_role";

REVOKE ALL ON TABLE "public"."Customer" FROM "authenticated";

REVOKE ALL ("address") ON TABLE "public"."Customer" FROM "authenticated";

GRANT INSERT ("address"), UPDATE ("address") ON TABLE "public"."Customer" TO "authenticated";

REVOKE ALL ("customer_id") ON TABLE "public"."Customer" FROM "authenticated";

GRANT INSERT ("customer_id") ON TABLE "public"."Customer" TO "authenticated";

REVOKE ALL ("full_name") ON TABLE "public"."Customer" FROM "authenticated";

GRANT INSERT ("full_name"), UPDATE ("full_name") ON TABLE "public"."Customer" TO "authenticated";

REVOKE ALL ("phone") ON TABLE "public"."Customer" FROM "authenticated";

GRANT INSERT ("phone"), UPDATE ("phone") ON TABLE "public"."Customer" TO "authenticated";

GRANT SELECT ON TABLE "public"."Customer" TO "authenticated";

REVOKE ALL ON TABLE "public"."Customer" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Customer" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Customer" TO "service_role";

REVOKE ALL ON TABLE "public"."InventoryLog" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."InventoryLog" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."InventoryLog" TO "service_role";

REVOKE ALL ON TABLE "public"."Notification" FROM "authenticated";

GRANT SELECT ON TABLE "public"."Notification" TO "authenticated";

REVOKE ALL ON TABLE "public"."Notification" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Notification" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Notification" TO "service_role";

REVOKE ALL ON TABLE "public"."NotificationType" FROM "authenticated";

GRANT SELECT ON TABLE "public"."NotificationType" TO "authenticated";

REVOKE ALL ON TABLE "public"."NotificationType" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."NotificationType" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."NotificationType" TO "service_role";

REVOKE ALL ON TABLE "public"."Order" FROM "authenticated";

REVOKE ALL ("customer_id") ON TABLE "public"."Order" FROM "authenticated";

GRANT INSERT ("customer_id") ON TABLE "public"."Order" TO "authenticated";

REVOKE ALL ("total_amount") ON TABLE "public"."Order" FROM "authenticated";

GRANT INSERT ("total_amount") ON TABLE "public"."Order" TO "authenticated";

REVOKE ALL ("valid_until") ON TABLE "public"."Order" FROM "authenticated";

GRANT INSERT ("valid_until") ON TABLE "public"."Order" TO "authenticated";

GRANT SELECT ON TABLE "public"."Order" TO "authenticated";

REVOKE ALL ON TABLE "public"."Order" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Order" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Order" TO "service_role";

REVOKE ALL ON TABLE "public"."OrderItem" FROM "authenticated";

REVOKE ALL ("order_id") ON TABLE "public"."OrderItem" FROM "authenticated";

GRANT INSERT ("order_id") ON TABLE "public"."OrderItem" TO "authenticated";

REVOKE ALL ("product_id") ON TABLE "public"."OrderItem" FROM "authenticated";

GRANT INSERT ("product_id") ON TABLE "public"."OrderItem" TO "authenticated";

REVOKE ALL ("quantity") ON TABLE "public"."OrderItem" FROM "authenticated";

GRANT INSERT ("quantity") ON TABLE "public"."OrderItem" TO "authenticated";

REVOKE ALL ("unit_price") ON TABLE "public"."OrderItem" FROM "authenticated";

GRANT INSERT ("unit_price") ON TABLE "public"."OrderItem" TO "authenticated";

GRANT SELECT ON TABLE "public"."OrderItem" TO "authenticated";

REVOKE ALL ON TABLE "public"."OrderItem" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."OrderItem" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."OrderItem" TO "service_role";

REVOKE ALL ON TABLE "public"."Payment" FROM "authenticated";

GRANT SELECT ON TABLE "public"."Payment" TO "authenticated";

REVOKE ALL ON TABLE "public"."Payment" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Payment" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Payment" TO "service_role";

REVOKE ALL ON TABLE "public"."Pharmacist" FROM "authenticated";

GRANT SELECT ON TABLE "public"."Pharmacist" TO "authenticated";

REVOKE ALL ON TABLE "public"."Pharmacist" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Pharmacist" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Pharmacist" TO "service_role";

REVOKE ALL ON TABLE "public"."PharmacyStaff" FROM "authenticated";

GRANT SELECT ON TABLE "public"."PharmacyStaff" TO "authenticated";

REVOKE ALL ON TABLE "public"."PharmacyStaff" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."PharmacyStaff" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."PharmacyStaff" TO "service_role";

REVOKE ALL ON TABLE "public"."Prescription" FROM "authenticated";

REVOKE ALL ("customer_id") ON TABLE "public"."Prescription" FROM "authenticated";

GRANT INSERT ("customer_id") ON TABLE "public"."Prescription" TO "authenticated";

REVOKE ALL ("prescription_file") ON TABLE "public"."Prescription" FROM "authenticated";

GRANT INSERT ("prescription_file") ON TABLE "public"."Prescription" TO "authenticated";

GRANT SELECT ON TABLE "public"."Prescription" TO "authenticated";

REVOKE ALL ON TABLE "public"."Prescription" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Prescription" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Prescription" TO "service_role";

REVOKE ALL ON TABLE "public"."Product" FROM "anon";

GRANT SELECT ON TABLE "public"."Product" TO "anon";

REVOKE ALL ON TABLE "public"."Product" FROM "authenticated";

GRANT SELECT ON TABLE "public"."Product" TO "authenticated";

REVOKE ALL ON TABLE "public"."Product" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Product" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Product" TO "service_role";

REVOKE ALL ON TABLE "public"."Profiles" FROM "authenticated";

REVOKE ALL ("full_name") ON TABLE "public"."Profiles" FROM "authenticated";

GRANT UPDATE ("full_name") ON TABLE "public"."Profiles" TO "authenticated";

REVOKE ALL ("phone") ON TABLE "public"."Profiles" FROM "authenticated";

GRANT UPDATE ("phone") ON TABLE "public"."Profiles" TO "authenticated";

GRANT SELECT ON TABLE "public"."Profiles" TO "authenticated";

REVOKE ALL ON TABLE "public"."Profiles" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Profiles" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."Profiles" TO "service_role";

REVOKE ALL ON TABLE "public"."UserRole" FROM "authenticated";

GRANT SELECT ON TABLE "public"."UserRole" TO "authenticated";

REVOKE ALL ON TABLE "public"."UserRole" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."UserRole" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."UserRole" TO "service_role";
