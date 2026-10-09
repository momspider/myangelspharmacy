


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;



COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."inventory_status" AS ENUM (
    'restock',
    'sale',
    'adjustment',
    'return'
);


ALTER TYPE "public"."inventory_status" OWNER TO "postgres";


CREATE TYPE "public"."notification_status" AS ENUM (
    'pending',
    'sent',
    'failed'
);


ALTER TYPE "public"."notification_status" OWNER TO "postgres";


CREATE TYPE "public"."order_status" AS ENUM (
    'pending',
    'confirmed',
    'ready',
    'completed',
    'cancelled'
);


ALTER TYPE "public"."order_status" OWNER TO "postgres";


CREATE TYPE "public"."payment_status" AS ENUM (
    'pending',
    'paid',
    'failed',
    'refunded'
);


ALTER TYPE "public"."payment_status" OWNER TO "postgres";


CREATE TYPE "public"."prescription_status" AS ENUM (
    'pending',
    'verified',
    'declined'
);


ALTER TYPE "public"."prescription_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_user_updated"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."handle_user_updated"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."touch_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."Category" (
    "category_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "category_name" character varying(100) NOT NULL,
    "description" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    
);


ALTER TABLE "public"."Category" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."Customer" (
    "customer_id" "uuid" NOT NULL,
    "full_name" character varying(150) NOT NULL,
    "phone" character varying(30),
    "address" "text",
    "date_registered" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."Customer" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."InventoryLog" (
    "log_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "type" "public"."inventory_status" NOT NULL,
    "quantity" integer NOT NULL,
    "previous_stock" integer NOT NULL,
    "new_stock" integer NOT NULL,
    "log_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "InventoryLog_new_stock_check" CHECK (("new_stock" >= 0)),
    CONSTRAINT "InventoryLog_previous_stock_check" CHECK (("previous_stock" >= 0)),
    CONSTRAINT "InventoryLog_quantity_check" CHECK (("quantity" <> 0))
);


ALTER TABLE "public"."InventoryLog" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."Notification" (
    "notification_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "order_id" "uuid",
    "type_id" "uuid",
    "message" "text" NOT NULL,
    "sent_via" character varying(20) NOT NULL,
    "sent_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "public"."notification_status" DEFAULT 'pending'::"public"."notification_status" NOT NULL,
    CONSTRAINT "Notification_sent_via_check" CHECK ((("sent_via")::"text" = ANY ((ARRAY['email'::character varying, 'sms'::character varying, 'push'::character varying, 'in_app'::character varying])::"text"[])))
);


ALTER TABLE "public"."Notification" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."NotificationType" (
    "notification_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "notification_type" character varying(50) NOT NULL
);


ALTER TABLE "public"."NotificationType" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."Order" (
    "order_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "order_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "public"."order_status" DEFAULT 'pending'::"public"."order_status" NOT NULL,
    "valid_until" timestamp with time zone,
    "total_amount" numeric(10,2) DEFAULT 0 NOT NULL,
    CONSTRAINT "Order_total_amount_check" CHECK (("total_amount" >= (0)::numeric))
);


ALTER TABLE "public"."Order" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."OrderItem" (
    "order_item_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "quantity" integer NOT NULL,
    "unit_price" numeric(10,2) NOT NULL,
    "subtotal" numeric(10,2) GENERATED ALWAYS AS ((("quantity")::numeric * "unit_price")) STORED,
    CONSTRAINT "OrderItem_quantity_check" CHECK (("quantity" > 0)),
    CONSTRAINT "OrderItem_unit_price_check" CHECK (("unit_price" >= (0)::numeric))
);


ALTER TABLE "public"."OrderItem" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."Payment" (
    "payment_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "amount" numeric(10,2) NOT NULL,
    "claim_date" timestamp with time zone,
    "reference_number" character varying(100),
    "status" "public"."payment_status" DEFAULT 'pending'::"public"."payment_status" NOT NULL,
    CONSTRAINT "Payment_amount_check" CHECK (("amount" >= (0)::numeric))
);


ALTER TABLE "public"."Payment" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."Pharmacist" (
    "pharmacist_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL
);


ALTER TABLE "public"."Pharmacist" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."PharmacyStaff" (
    "staff_id" "uuid" NOT NULL,
    "role_id" "uuid" NOT NULL,
    "full_name" character varying(150) NOT NULL,
    "phone" character varying(30),
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."PharmacyStaff" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."Prescription" (
    "prescription_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "pharmacist_id" "uuid",
    "prescription_file" "text" NOT NULL,
    "status" "public"."prescription_status" DEFAULT 'pending'::"public"."prescription_status" NOT NULL,
    "upload_date" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."Prescription" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."Product" (
    "product_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "category_id" "uuid" NOT NULL,
    "name" character varying(200) NOT NULL,
    "description" "text",
    "brand" character varying(100),
    "dosage_form" character varying(50),
    "price" numeric(10,2) NOT NULL,
    "stock_quantity" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "Product_price_check" CHECK (("price" >= (0)::numeric)),
    CONSTRAINT "Product_stock_quantity_check" CHECK (("stock_quantity" >= 0))
);


ALTER TABLE "public"."Product" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."Profiles" (
    "uuid" "uuid" NOT NULL,
    "full_name" character varying(150),
    "phone" character varying(30),
    "role_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."Profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."UserRole" (
    "role_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "role_name" character varying(50) NOT NULL,
    "description" "text"
);


ALTER TABLE "public"."UserRole" OWNER TO "postgres";


ALTER TABLE ONLY "public"."Category"
    ADD CONSTRAINT "Category_category_name_key" UNIQUE ("category_name");



ALTER TABLE ONLY "public"."Category"
    ADD CONSTRAINT "Category_pkey" PRIMARY KEY ("category_id");



ALTER TABLE ONLY "public"."Customer"
    ADD CONSTRAINT "Customer_pkey" PRIMARY KEY ("customer_id");



ALTER TABLE ONLY "public"."InventoryLog"
    ADD CONSTRAINT "InventoryLog_pkey" PRIMARY KEY ("log_id");



ALTER TABLE ONLY "public"."NotificationType"
    ADD CONSTRAINT "NotificationType_notification_type_key" UNIQUE ("notification_type");



ALTER TABLE ONLY "public"."NotificationType"
    ADD CONSTRAINT "NotificationType_pkey" PRIMARY KEY ("notification_id");



ALTER TABLE ONLY "public"."Notification"
    ADD CONSTRAINT "Notification_pkey" PRIMARY KEY ("notification_id");



ALTER TABLE ONLY "public"."OrderItem"
    ADD CONSTRAINT "OrderItem_order_id_product_id_key" UNIQUE ("order_id", "product_id");



ALTER TABLE ONLY "public"."OrderItem"
    ADD CONSTRAINT "OrderItem_pkey" PRIMARY KEY ("order_item_id");



ALTER TABLE ONLY "public"."Order"
    ADD CONSTRAINT "Order_pkey" PRIMARY KEY ("order_id");



ALTER TABLE ONLY "public"."Payment"
    ADD CONSTRAINT "Payment_pkey" PRIMARY KEY ("payment_id");



ALTER TABLE ONLY "public"."Payment"
    ADD CONSTRAINT "Payment_reference_number_key" UNIQUE ("reference_number");



ALTER TABLE ONLY "public"."Pharmacist"
    ADD CONSTRAINT "Pharmacist_pkey" PRIMARY KEY ("pharmacist_id");



ALTER TABLE ONLY "public"."Pharmacist"
    ADD CONSTRAINT "Pharmacist_staff_id_key" UNIQUE ("staff_id");



ALTER TABLE ONLY "public"."PharmacyStaff"
    ADD CONSTRAINT "PharmacyStaff_pkey" PRIMARY KEY ("staff_id");



ALTER TABLE ONLY "public"."Prescription"
    ADD CONSTRAINT "Prescription_pkey" PRIMARY KEY ("prescription_id");



ALTER TABLE ONLY "public"."Product"
    ADD CONSTRAINT "Product_pkey" PRIMARY KEY ("product_id");



ALTER TABLE ONLY "public"."Profiles"
    ADD CONSTRAINT "Profiles_pkey" PRIMARY KEY ("uuid");



ALTER TABLE ONLY "public"."UserRole"
    ADD CONSTRAINT "UserRole_pkey" PRIMARY KEY ("role_id");



ALTER TABLE ONLY "public"."UserRole"
    ADD CONSTRAINT "UserRole_role_name_key" UNIQUE ("role_name");



CREATE OR REPLACE TRIGGER "profiles_updated_at" BEFORE UPDATE ON "public"."Profiles" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



ALTER TABLE ONLY "public"."Customer"
    ADD CONSTRAINT "Customer_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."InventoryLog"
    ADD CONSTRAINT "InventoryLog_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."Product"("product_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."Notification"
    ADD CONSTRAINT "Notification_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."Customer"("customer_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Notification"
    ADD CONSTRAINT "Notification_notification_id_fkey" FOREIGN KEY ("notification_id") REFERENCES "public"."NotificationType"("notification_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."Notification"
    ADD CONSTRAINT "Notification_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."Order"("order_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."Notification"
    ADD CONSTRAINT "Notification_type_id_fkey" FOREIGN KEY ("type_id") REFERENCES "public"."NotificationType"("notification_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."OrderItem"
    ADD CONSTRAINT "OrderItem_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."Order"("order_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."OrderItem"
    ADD CONSTRAINT "OrderItem_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."Product"("product_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."Order"
    ADD CONSTRAINT "Order_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."Customer"("customer_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."Payment"
    ADD CONSTRAINT "Payment_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."Order"("order_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."Pharmacist"
    ADD CONSTRAINT "Pharmacist_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."PharmacyStaff"("staff_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."PharmacyStaff"
    ADD CONSTRAINT "PharmacyStaff_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."UserRole"("role_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."PharmacyStaff"
    ADD CONSTRAINT "PharmacyStaff_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Prescription"
    ADD CONSTRAINT "Prescription_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."Customer"("customer_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."Prescription"
    ADD CONSTRAINT "Prescription_pharmacist_id_fkey" FOREIGN KEY ("pharmacist_id") REFERENCES "public"."Pharmacist"("pharmacist_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."Product"
    ADD CONSTRAINT "Product_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."Category"("category_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."Profiles"
    ADD CONSTRAINT "Profiles_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."UserRole"("role_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."Profiles"
    ADD CONSTRAINT "Profiles_uuid_fkey" FOREIGN KEY ("uuid") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Anyone can browse active products" ON "public"."Product" FOR SELECT TO "authenticated", "anon" USING (("is_active" = true));



CREATE POLICY "Anyone can read active categories" ON "public"."Category" FOR SELECT TO "authenticated", "anon" USING (("is_active" = true));



CREATE POLICY "Authenticated users can read notification types" ON "public"."NotificationType" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read roles" ON "public"."UserRole" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."Category" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Customer" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Customers can add items to their own pending orders" ON "public"."OrderItem" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."Order" "o"
  WHERE (("o"."order_id" = "OrderItem"."order_id") AND ("o"."customer_id" = "auth"."uid"()) AND ("o"."status" = 'pending'::"public"."order_status")))));



CREATE POLICY "Customers can create their own record" ON "public"."Customer" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can place their own orders" ON "public"."Order" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "customer_id") AND ("status" = 'pending'::"public"."order_status")));



CREATE POLICY "Customers can update their own record" ON "public"."Customer" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "customer_id")) WITH CHECK (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can upload their own prescriptions" ON "public"."Prescription" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "customer_id") AND ("status" = 'pending'::"public"."prescription_status") AND ("pharmacist_id" IS NULL)));



CREATE POLICY "Customers can view items of their own orders" ON "public"."OrderItem" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."Order" "o"
  WHERE (("o"."order_id" = "OrderItem"."order_id") AND ("o"."customer_id" = "auth"."uid"())))));



CREATE POLICY "Customers can view payments for their own orders" ON "public"."Payment" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."Order" "o"
  WHERE (("o"."order_id" = "Payment"."order_id") AND ("o"."customer_id" = "auth"."uid"())))));



CREATE POLICY "Customers can view their own notifications" ON "public"."Notification" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can view their own orders" ON "public"."Order" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can view their own prescriptions" ON "public"."Prescription" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can view their own record" ON "public"."Customer" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "customer_id"));



ALTER TABLE "public"."InventoryLog" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Notification" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."NotificationType" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Order" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."OrderItem" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Payment" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Pharmacist" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Pharmacists can view their own record" ON "public"."Pharmacist" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "staff_id"));



ALTER TABLE "public"."PharmacyStaff" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Prescription" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Product" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Staff can view their own record" ON "public"."PharmacyStaff" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "staff_id"));



ALTER TABLE "public"."UserRole" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Users can update their own profile" ON "public"."Profiles" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "uuid")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "uuid"));



CREATE POLICY "Users can view their own profile" ON "public"."Profiles" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "uuid"));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_user_updated"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_user_updated"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."touch_updated_at"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "service_role";


















GRANT ALL ON TABLE "public"."Category" TO "service_role";
GRANT SELECT ON TABLE "public"."Category" TO "anon";
GRANT SELECT ON TABLE "public"."Category" TO "authenticated";



GRANT ALL ON TABLE "public"."Customer" TO "service_role";
GRANT SELECT ON TABLE "public"."Customer" TO "authenticated";



GRANT INSERT("customer_id") ON TABLE "public"."Customer" TO "authenticated";



GRANT INSERT("full_name"),UPDATE("full_name") ON TABLE "public"."Customer" TO "authenticated";



GRANT INSERT("phone"),UPDATE("phone") ON TABLE "public"."Customer" TO "authenticated";



GRANT INSERT("address"),UPDATE("address") ON TABLE "public"."Customer" TO "authenticated";



GRANT ALL ON TABLE "public"."InventoryLog" TO "service_role";



GRANT ALL ON TABLE "public"."Notification" TO "service_role";
GRANT SELECT ON TABLE "public"."Notification" TO "authenticated";



GRANT ALL ON TABLE "public"."NotificationType" TO "service_role";
GRANT SELECT ON TABLE "public"."NotificationType" TO "authenticated";



GRANT ALL ON TABLE "public"."Order" TO "service_role";
GRANT SELECT ON TABLE "public"."Order" TO "authenticated";



GRANT INSERT("customer_id") ON TABLE "public"."Order" TO "authenticated";



GRANT INSERT("valid_until") ON TABLE "public"."Order" TO "authenticated";



GRANT INSERT("total_amount") ON TABLE "public"."Order" TO "authenticated";



GRANT ALL ON TABLE "public"."OrderItem" TO "service_role";
GRANT SELECT ON TABLE "public"."OrderItem" TO "authenticated";



GRANT INSERT("order_id") ON TABLE "public"."OrderItem" TO "authenticated";



GRANT INSERT("product_id") ON TABLE "public"."OrderItem" TO "authenticated";



GRANT INSERT("quantity") ON TABLE "public"."OrderItem" TO "authenticated";



GRANT INSERT("unit_price") ON TABLE "public"."OrderItem" TO "authenticated";



GRANT ALL ON TABLE "public"."Payment" TO "service_role";
GRANT SELECT ON TABLE "public"."Payment" TO "authenticated";



GRANT ALL ON TABLE "public"."Pharmacist" TO "service_role";
GRANT SELECT ON TABLE "public"."Pharmacist" TO "authenticated";



GRANT ALL ON TABLE "public"."PharmacyStaff" TO "service_role";
GRANT SELECT ON TABLE "public"."PharmacyStaff" TO "authenticated";



GRANT ALL ON TABLE "public"."Prescription" TO "service_role";
GRANT SELECT ON TABLE "public"."Prescription" TO "authenticated";



GRANT INSERT("customer_id") ON TABLE "public"."Prescription" TO "authenticated";



GRANT INSERT("prescription_file") ON TABLE "public"."Prescription" TO "authenticated";



GRANT ALL ON TABLE "public"."Product" TO "service_role";
GRANT SELECT ON TABLE "public"."Product" TO "anon";
GRANT SELECT ON TABLE "public"."Product" TO "authenticated";



GRANT ALL ON TABLE "public"."Profiles" TO "service_role";
GRANT SELECT ON TABLE "public"."Profiles" TO "authenticated";



GRANT UPDATE("full_name") ON TABLE "public"."Profiles" TO "authenticated";



GRANT UPDATE("phone") ON TABLE "public"."Profiles" TO "authenticated";



GRANT ALL ON TABLE "public"."UserRole" TO "service_role";
GRANT SELECT ON TABLE "public"."UserRole" TO "authenticated";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































