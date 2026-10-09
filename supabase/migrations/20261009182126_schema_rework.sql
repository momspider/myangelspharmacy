SET local check_function_bodies = off;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "service_role";

REVOKE ALL ON SCHEMA "public" FROM "anon";

REVOKE ALL ON SCHEMA "public" FROM "authenticated";

REVOKE ALL ON SCHEMA "public" FROM "pg_database_owner";

REVOKE ALL ON SCHEMA "public" FROM "service_role";

REVOKE ALL ON TABLE "public"."Category" FROM "service_role";

REVOKE ALL ON TABLE "public"."InventoryLog" FROM "service_role";

REVOKE ALL ON TABLE "public"."Notification" FROM "service_role";

REVOKE ALL ON TABLE "public"."NotificationType" FROM "service_role";

REVOKE ALL ON TABLE "public"."Order" FROM "service_role";

REVOKE ALL ON TABLE "public"."OrderItem" FROM "service_role";

REVOKE ALL ON TABLE "public"."Payment" FROM "service_role";

REVOKE ALL ON TABLE "public"."Prescription" FROM "service_role";

COMMENT ON SCHEMA "public" IS NULL;

DROP POLICY "Customers can view their own notifications" ON "public"."Notification";

DROP POLICY "Customers can place their own orders" ON "public"."Order";

DROP POLICY "Customers can view their own orders" ON "public"."Order";

DROP POLICY "Customers can add items to their own pending orders" ON "public"."OrderItem";

DROP POLICY "Customers can view items of their own orders" ON "public"."OrderItem";

DROP POLICY "Customers can view payments for their own orders" ON "public"."Payment";

DROP POLICY "Customers can upload their own prescriptions" ON "public"."Prescription";

DROP POLICY "Customers can view their own prescriptions" ON "public"."Prescription";

DROP POLICY "Users can update their own profile" ON "public"."Profiles";

DROP POLICY "Users can view their own profile" ON "public"."Profiles";

ALTER TABLE "public"."Customer"
  DROP CONSTRAINT "Customer_customer_id_fkey";

ALTER TABLE "public"."Notification"
  DROP CONSTRAINT "Notification_customer_id_fkey";

ALTER TABLE "public"."Notification"
  DROP CONSTRAINT "Notification_notification_id_fkey";

ALTER TABLE "public"."Notification"
  DROP CONSTRAINT "Notification_sent_via_check";

ALTER TABLE "public"."Notification"
  DROP CONSTRAINT "Notification_type_id_fkey";

ALTER TABLE "public"."NotificationType"
  DROP CONSTRAINT "NotificationType_notification_type_key";

ALTER TABLE "public"."NotificationType"
  DROP CONSTRAINT "NotificationType_pkey";

ALTER TABLE "public"."Order"
  DROP CONSTRAINT "Order_customer_id_fkey";

ALTER TABLE "public"."Pharmacist"
  DROP CONSTRAINT "Pharmacist_staff_id_fkey";

ALTER TABLE "public"."PharmacyStaff"
  DROP CONSTRAINT "PharmacyStaff_role_id_fkey";

ALTER TABLE "public"."PharmacyStaff"
  DROP CONSTRAINT "PharmacyStaff_staff_id_fkey";

ALTER TABLE "public"."Prescription"
  DROP CONSTRAINT "Prescription_customer_id_fkey";

ALTER TABLE "public"."Prescription"
  DROP CONSTRAINT "Prescription_pharmacist_id_fkey";

ALTER TABLE "public"."Profiles"
  DROP CONSTRAINT "Profiles_pkey";

ALTER TABLE "public"."Profiles"
  DROP CONSTRAINT "Profiles_role_id_fkey";

ALTER TABLE "public"."Profiles"
  DROP CONSTRAINT "Profiles_uuid_fkey";

ALTER TABLE "public"."Notification"
  DROP COLUMN "customer_id";

ALTER TABLE "public"."Notification"
  DROP COLUMN "type_id";

ALTER TABLE "public"."NotificationType"
  DROP COLUMN "notification_id";

ALTER TABLE "public"."NotificationType"
  DROP COLUMN "notification_type";

ALTER TABLE "public"."Profiles"
  DROP COLUMN "role_id";

ALTER TABLE "public"."Profiles"
  DROP COLUMN "uuid";

DROP TABLE "public"."Customer";

DROP TABLE "public"."Pharmacist";

DROP TABLE "public"."PharmacyStaff";

DROP TABLE "public"."UserRole";

ALTER TABLE "public"."Category"
  ADD COLUMN "created_at" timestamp WITH time zone NOT NULL DEFAULT now();

ALTER TABLE "public"."Category"
  ADD COLUMN "updated_at" timestamp WITH time zone NOT NULL DEFAULT now();

ALTER TABLE "public"."Notification"
  ADD COLUMN "user_id" uuid NOT NULL;

ALTER TABLE "public"."Notification"
  ADD COLUMN "notification_type_id" uuid NOT NULL;

ALTER TABLE "public"."NotificationType"
  ADD COLUMN "notification_type_id" uuid NOT NULL DEFAULT gen_random_uuid();

ALTER TABLE "public"."NotificationType"
  ADD COLUMN "notification_type_name" character varying(50) NOT NULL;

ALTER TABLE "public"."Product"
  ADD COLUMN "same_day" boolean NOT NULL DEFAULT true;

ALTER TABLE "public"."Product"
  ADD COLUMN "requires_rx" boolean NOT NULL DEFAULT false;

ALTER TABLE "public"."Product"
  ADD COLUMN "img_path" text NOT NULL;

ALTER TABLE "public"."Product"
  ADD COLUMN "date_registered" timestamp WITH time zone NOT NULL DEFAULT now();

ALTER TABLE "public"."Profiles"
  ADD COLUMN "id" uuid NOT NULL;

ALTER TABLE "public"."Profiles"
  ADD COLUMN "is_active" boolean NOT NULL DEFAULT true;

ALTER TABLE "public"."Product"
  ALTER COLUMN "brand" SET NOT NULL;

ALTER TABLE "public"."Product"
  ALTER COLUMN "dosage_form" SET NOT NULL;

ALTER TABLE "public"."Profiles"
  ALTER COLUMN "full_name" SET NOT NULL;

ALTER TABLE "public"."Notification"
  ALTER COLUMN "notification_id" SET DEFAULT gen_random_uuid();

ALTER TABLE "public"."Product"
  ALTER COLUMN "brand" SET DEFAULT 'Generic'::character varying;

CREATE TYPE "public"."role_name" AS ENUM (
  'owner',
  'administrator',
  'customer',
  'pharmacist'
);

ALTER TABLE "public"."Profiles"
  ADD COLUMN "role" public.role_name NOT NULL DEFAULT 'customer'::public.role_name;

CREATE OR REPLACE FUNCTION public.current_user_is_profile_owner (
  profile_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
    SELECT auth.uid() = profile_id;
$function$;

REVOKE ALL ON FUNCTION "public"."current_user_is_profile_owner"(uuid) FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.enforce_order_security()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

REVOKE ALL ON FUNCTION "public"."enforce_order_security"() FROM PUBLIC, "anon", "authenticated", "service_role";

CREATE OR REPLACE FUNCTION public.enforce_prescription_security()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

REVOKE ALL ON FUNCTION "public"."enforce_prescription_security"() FROM PUBLIC, "anon", "authenticated", "service_role";

CREATE OR REPLACE FUNCTION public.enforce_profile_security()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

REVOKE ALL ON FUNCTION "public"."enforce_profile_security"() FROM PUBLIC, "anon", "authenticated", "service_role";

CREATE OR REPLACE FUNCTION public.handle_new_user()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

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
            phone),
        updated_at = NOW()
    WHERE id = NEW.id;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_admin()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public."Profiles" p
        WHERE p.id = auth.uid()
          AND p.role IN ('owner', 'administrator')
    );
$function$;

REVOKE ALL ON FUNCTION "public"."is_admin"() FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.is_staff()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public."Profiles" p
        WHERE p.id = auth.uid()
          AND p.role IN ('owner', 'administrator', 'pharmacist')
    );
$function$;

REVOKE ALL ON FUNCTION "public"."is_staff"() FROM PUBLIC, "anon", "authenticated";

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

CREATE OR REPLACE FUNCTION public.user_has_role (
  required_role public.role_name
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public."Profiles" p
        WHERE p.id = auth.uid()
          AND p.role = required_role
    );
$function$;

REVOKE ALL ON FUNCTION "public"."user_has_role"(public.role_name) FROM PUBLIC, "anon", "authenticated";

ALTER TABLE "public"."Category"
  ADD CONSTRAINT "Category_category_name_check" CHECK ((btrim((category_name)::text) <> ''::text));

ALTER TABLE "public"."Notification"
  ADD CONSTRAINT "Notification_message_check" CHECK ((btrim(message) <> ''::text));

ALTER TABLE "public"."Notification"
  ADD CONSTRAINT "Notification_sent_via_check"
    CHECK (((sent_via)::text = ANY ((ARRAY['email'::character varying, 'sms'::character varying, 'push'::character varying, 'in_app'::character varying])::text[])));

ALTER TABLE "public"."NotificationType"
  ADD CONSTRAINT "NotificationType_notification_type_name_check" CHECK ((btrim((notification_type_name)::text) <> ''::text));

ALTER TABLE "public"."NotificationType"
  ADD CONSTRAINT "NotificationType_notification_type_name_key" UNIQUE (notification_type_name);

ALTER TABLE "public"."NotificationType"
  ADD CONSTRAINT "NotificationType_pkey" PRIMARY KEY (notification_type_id);

ALTER TABLE "public"."Notification"
  ADD CONSTRAINT "Notification_notification_type_id_fkey" FOREIGN KEY (notification_type_id) REFERENCES public."NotificationType"(notification_type_id) ON DELETE RESTRICT;

ALTER TABLE "public"."Order"
  ADD CONSTRAINT "Order_check" CHECK (((valid_until IS NULL) OR (valid_until > order_date)));

ALTER TABLE "public"."Payment"
  ADD CONSTRAINT "Payment_reference_number_check" CHECK (((reference_number IS NULL) OR (btrim((reference_number)::text) <> ''::text)));

ALTER TABLE "public"."Prescription"
  ADD CONSTRAINT "Prescription_check" CHECK (((status <> 'verified'::public.prescription_status) OR (pharmacist_id IS NOT NULL)));

ALTER TABLE "public"."Prescription"
  ADD CONSTRAINT "Prescription_prescription_file_check" CHECK ((btrim(prescription_file) <> ''::text));

ALTER TABLE "public"."Product"
  ADD CONSTRAINT "Product_brand_check" CHECK ((btrim((brand)::text) <> ''::text));

ALTER TABLE "public"."Product"
  ADD CONSTRAINT "Product_dosage_form_check" CHECK ((btrim((dosage_form)::text) <> ''::text));

ALTER TABLE "public"."Product"
  ADD CONSTRAINT "Product_img_path_check" CHECK ((btrim(img_path) <> ''::text));

ALTER TABLE "public"."Product"
  ADD CONSTRAINT "Product_name_check" CHECK ((btrim((name)::text) <> ''::text));

ALTER TABLE "public"."Profiles"
  ADD CONSTRAINT "Profiles_full_name_check" CHECK ((btrim((full_name)::text) <> ''::text));

ALTER TABLE "public"."Profiles"
  ADD CONSTRAINT "Profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."Profiles"
  ADD CONSTRAINT "Profiles_phone_check" CHECK (((phone IS NULL) OR ((length(btrim((phone)::text)) >= 7) AND (length(btrim((phone)::text)) <= 30))));

ALTER TABLE "public"."Profiles"
  ADD CONSTRAINT "Profiles_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."Notification"
  ADD CONSTRAINT "Notification_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public."Profiles"(id) ON DELETE CASCADE;

ALTER TABLE "public"."Order"
  ADD CONSTRAINT "Order_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES public."Profiles"(id) ON DELETE RESTRICT;

ALTER TABLE "public"."Prescription"
  ADD CONSTRAINT "Prescription_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES public."Profiles"(id) ON DELETE RESTRICT;

ALTER TABLE "public"."Prescription"
  ADD CONSTRAINT "Prescription_pharmacist_id_fkey" FOREIGN KEY (pharmacist_id) REFERENCES public."Profiles"(id) ON DELETE SET NULL;

CREATE TRIGGER order_security_guard
  BEFORE INSERT OR UPDATE OF customer_id, order_date, valid_until, status ON public."Order"
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_order_security();

CREATE TRIGGER prescription_security_guard
  BEFORE INSERT OR UPDATE OF status, customer_id, pharmacist_id ON public."Prescription"
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_prescription_security();

CREATE TRIGGER profiles_security_guard
  BEFORE INSERT OR UPDATE ON public."Profiles"
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_profile_security();

CREATE POLICY "Users can view their own notifications" ON "public"."Notification"
  FOR SELECT
  TO "authenticated"
  USING ((auth.uid() = user_id));

CREATE POLICY "Users can place their own orders" ON "public"."Order"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((auth.uid() = customer_id) AND (status = 'pending'::public.order_status)));

CREATE POLICY "Users can view their own orders" ON "public"."Order"
  FOR SELECT
  TO "authenticated"
  USING ((auth.uid() = customer_id));

CREATE POLICY "Users can add items to their own pending orders" ON "public"."OrderItem"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((EXISTS ( SELECT 1
   FROM public."Order" o
  WHERE ((o.order_id = "OrderItem".order_id) AND (o.customer_id = auth.uid()) AND (o.status = 'pending'::public.order_status)))));

CREATE POLICY "Users can view items of their own orders" ON "public"."OrderItem"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM public."Order" o
  WHERE ((o.order_id = "OrderItem".order_id) AND (o.customer_id = auth.uid())))));

CREATE POLICY "Users can view payments for their own orders" ON "public"."Payment"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM public."Order" o
  WHERE ((o.order_id = "Payment".order_id) AND (o.customer_id = auth.uid())))));

CREATE POLICY "Users can upload their own prescriptions" ON "public"."Prescription"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((auth.uid() = customer_id) AND (status = 'pending'::public.prescription_status) AND (pharmacist_id IS NULL)));

CREATE POLICY "Users can view their own prescriptions" ON "public"."Prescription"
  FOR SELECT
  TO "authenticated"
  USING ((auth.uid() = customer_id));

CREATE POLICY "Users can update their own profile" ON "public"."Profiles"
  FOR UPDATE
  TO "authenticated"
  USING (public.current_user_is_profile_owner(id))
  WITH CHECK (public.current_user_is_profile_owner(id));

CREATE POLICY "Users can view their own profile" ON "public"."Profiles"
  FOR SELECT
  TO "authenticated"
  USING (public.current_user_is_profile_owner(id));

CREATE POLICY "Users cannot delete profiles" ON "public"."Profiles"
  FOR DELETE
  TO "authenticated"
  USING (false);

GRANT EXECUTE ON FUNCTION "public"."current_user_is_profile_owner"(uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."is_admin"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."is_staff"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."user_has_role"(public.role_name) TO "service_role";

REVOKE ALL ON SCHEMA "public" FROM PUBLIC;

GRANT CREATE, USAGE ON SCHEMA "public" TO PUBLIC;

REVOKE ALL ON SCHEMA "public" FROM "postgres";

GRANT CREATE, USAGE ON SCHEMA "public" TO "postgres";

REVOKE ALL ON TABLE "public"."Product" FROM "service_role";

GRANT SELECT ON TABLE "public"."Product" TO "service_role";

REVOKE ALL ON TABLE "public"."Profiles" FROM "service_role";

GRANT SELECT ON TABLE "public"."Profiles" TO "service_role";
