-- Additive client-auth/RLS groundwork for the existing RO app schema.
-- Review and back up before applying manually. This file is NOT run by the app.
-- It does not delete business tables or rows.
BEGIN;

-- This policy/grant migration depends on these existing business tables; do
-- not create shadow copies or continue against an incomplete schema.
DO $$
DECLARE
  v_missing text[];
BEGIN
  SELECT array_agg(required.name) INTO v_missing
  FROM unnest(ARRAY[
    'users','user_addresses','categories','products','cart_items','orders',
    'order_items','rewards_history','support_tickets','otp_codes','payment_sessions',
    'shop_employees','shop_order_assignments','shop_delivery_items',
    'shop_admin_notifications','shop_product_enquiries'
  ]) AS required(name)
  WHERE to_regclass(format('public.%I', required.name)) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Required existing public tables are missing: %', array_to_string(v_missing, ', ');
  END IF;
  IF to_regclass('auth.users') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE EXCEPTION 'Supabase Auth or Storage schema is unavailable';
  END IF;
END;
$$;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS auth_user_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_users_auth_user' AND conrelid = 'public.users'::regclass
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT fk_users_auth_user
      FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uk_users_auth_user_id
  ON public.users (auth_user_id) WHERE auth_user_id IS NOT NULL;

-- Authenticated dealer profile key used by ownership policies below.
CREATE OR REPLACE FUNCTION public.current_dealer_id()
RETURNS varchar
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT u.id FROM public.users AS u WHERE u.auth_user_id = auth.uid() LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.current_dealer_id() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.current_dealer_id() TO authenticated;

-- Called by an authenticated, email-verified Supabase user after sign-in.
-- It links only its own matching email, never overwrites a legacy password hash,
-- and creates a compatible dealer row only when one does not already exist.
CREATE OR REPLACE FUNCTION public.sync_current_dealer_profile()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_auth auth.users%ROWTYPE;
  v_profile public.users%ROWTYPE;
  v_email text;
  v_mobile text;
  v_name text;
  v_company text;
  v_address text;
  v_gst text;
  v_id varchar(64);
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000'; END IF;
  SELECT * INTO v_auth FROM auth.users WHERE id = auth.uid();
  IF NOT FOUND OR v_auth.email_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'Verified email required' USING ERRCODE = '28000';
  END IF;

  v_email := lower(trim(v_auth.email));
  v_mobile := nullif(trim(coalesce(v_auth.raw_user_meta_data->>'mobile', '')), '');
  v_name := coalesce(nullif(trim(v_auth.raw_user_meta_data->>'name'), ''), split_part(v_email, '@', 1));
  v_company := nullif(trim(coalesce(v_auth.raw_user_meta_data->>'companyName', v_auth.raw_user_meta_data->>'businessName', '')), '');
  v_address := nullif(trim(coalesce(v_auth.raw_user_meta_data->>'address', '')), '');
  v_gst := nullif(upper(trim(coalesce(v_auth.raw_user_meta_data->>'gstNumber', ''))), '');

  SELECT * INTO v_profile FROM public.users WHERE auth_user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN
    SELECT * INTO v_profile FROM public.users
      WHERE lower(email::text) = v_email AND auth_user_id IS NULL FOR UPDATE;
    IF FOUND THEN
      UPDATE public.users SET auth_user_id = auth.uid(), email_verified = true
        WHERE id = v_profile.id RETURNING * INTO v_profile;
    ELSE
      IF v_mobile IS NOT NULL AND EXISTS (SELECT 1 FROM public.users WHERE mobile = v_mobile) THEN
        RAISE EXCEPTION 'Mobile number already belongs to another account' USING ERRCODE = '23505';
      END IF;
      v_id := 'auth-' || replace(auth.uid()::text, '-', '');
      INSERT INTO public.users
        (id, auth_user_id, email, mobile, name, password_hash, email_verified,
         business_name, owner_name, address, gst_number, status, is_approved)
      VALUES
        (v_id, auth.uid(), v_email, v_mobile, v_name, '!supabase-auth-managed!', true,
         v_company, v_name, v_address, v_gst, 'pending', false)
      RETURNING * INTO v_profile;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'id', v_profile.id, 'name', v_profile.name, 'email', v_profile.email,
    'mobile', coalesce(v_profile.mobile, ''), 'address', coalesce(v_profile.address, ''),
    'business', coalesce(v_profile.business_name, ''), 'gstNumber', coalesce(v_profile.gst_number, ''),
    'status', v_profile.status, 'isApproved', v_profile.is_approved
  );
END;
$$;
REVOKE ALL ON FUNCTION public.sync_current_dealer_profile() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sync_current_dealer_profile() TO authenticated;

-- Hide purchase_price behind a client-safe view. Use the view for all client
-- catalog reads; privileged admin reads remain in the trusted backend.
CREATE OR REPLACE VIEW public.catalog_products
WITH (security_invoker = false)
AS
SELECT p.id, p.category_id, p.category_key, c.title AS category_name,
       p.sku, p.name, p.brand, p.price, p.price AS dealer_price, p.mrp,
       p.moq, p.badge, p.rating, p.img, p.description, p.description AS desc,
       p.specs_json AS specs, p.features_json AS features, p.applications,
       p.stock_quantity, p.min_stock, p.status, p.created_at
FROM public.products AS p
LEFT JOIN public.categories AS c ON c.id = p.category_id
WHERE p.status <> 'inactive';
REVOKE ALL ON public.catalog_products FROM PUBLIC, anon, authenticated;

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rewards_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_sessions ENABLE ROW LEVEL SECURITY;
-- Shop/admin data remains server-only until employee/admin Auth identities and
-- their Edge Function authorization paths are implemented and tested.
ALTER TABLE public.shop_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_order_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_delivery_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_admin_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_product_enquiries ENABLE ROW LEVEL SECURITY;

-- Fail closed if another policy exists on an affected table. Permissive RLS
-- policies are ORed together, so an unreviewed policy could defeat the rules
-- below. The live audit found no policies on these tables or storage.objects.
DO $$
DECLARE
  v_policy record;
BEGIN
  SELECT schemaname, tablename, policyname INTO v_policy
  FROM pg_policies
  WHERE (schemaname = 'public' AND tablename = ANY (ARRAY[
      'categories','products','users','user_addresses','cart_items','orders',
      'order_items','rewards_history','support_tickets','otp_codes','payment_sessions',
      'shop_employees','shop_order_assignments','shop_delivery_items',
      'shop_admin_notifications','shop_product_enquiries'
    ]) AND policyname <> ALL (ARRAY[
      'ro_categories_read','ro_products_active_read','ro_users_self_read',
      'ro_users_self_update','ro_addresses_self_read','ro_addresses_self_delete','ro_cart_self_read',
      'ro_cart_self_delete','ro_orders_self_read','ro_order_items_self_read',
      'ro_rewards_self_read','ro_support_self_read'
    ]))
    OR (schemaname = 'storage' AND tablename = 'objects'
      AND policyname NOT IN ('ro_product_images_public_read','ro_product_images_admin_write'))
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Unreviewed RLS policy %.%.% exists; review it before applying this migration',
      v_policy.schemaname, v_policy.tablename, v_policy.policyname;
  END IF;
END;
$$;

-- Create a new image bucket only if absent. Existing bucket configuration is
-- never silently changed by this migration and must be reviewed separately.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('ro-product-images', 'ro-product-images', true, 5242880,
  ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM storage.buckets
    WHERE id = 'ro-product-images' AND public = true
      AND file_size_limit IS NOT NULL AND file_size_limit <= 5242880
      AND allowed_mime_types IS NOT NULL
      AND allowed_mime_types @> ARRAY['image/jpeg','image/png','image/webp']
      AND allowed_mime_types <@ ARRAY['image/jpeg','image/png','image/webp']
  ) THEN
    RAISE EXCEPTION 'Existing ro-product-images bucket configuration is incompatible; review it before continuing';
  END IF;
END;
$$;

DO $$
BEGIN
  DROP POLICY IF EXISTS ro_categories_read ON public.categories;
  DROP POLICY IF EXISTS ro_products_active_read ON public.products;
  DROP POLICY IF EXISTS ro_users_self_read ON public.users;
  DROP POLICY IF EXISTS ro_users_self_update ON public.users;
  DROP POLICY IF EXISTS ro_addresses_self_read ON public.user_addresses;
  DROP POLICY IF EXISTS ro_addresses_self_delete ON public.user_addresses;
  DROP POLICY IF EXISTS ro_cart_self_read ON public.cart_items;
  DROP POLICY IF EXISTS ro_cart_self_delete ON public.cart_items;
  DROP POLICY IF EXISTS ro_orders_self_read ON public.orders;
  DROP POLICY IF EXISTS ro_order_items_self_read ON public.order_items;
  DROP POLICY IF EXISTS ro_rewards_self_read ON public.rewards_history;
  DROP POLICY IF EXISTS ro_support_self_read ON public.support_tickets;

  CREATE POLICY ro_categories_read ON public.categories
    FOR SELECT TO anon, authenticated USING (true);
  CREATE POLICY ro_products_active_read ON public.products
    FOR SELECT TO anon, authenticated USING (status <> 'inactive');
  CREATE POLICY ro_users_self_read ON public.users
    FOR SELECT TO authenticated USING (auth_user_id = auth.uid());
  CREATE POLICY ro_users_self_update ON public.users
    FOR UPDATE TO authenticated USING (auth_user_id = auth.uid())
    WITH CHECK (auth_user_id = auth.uid());

  CREATE POLICY ro_addresses_self_read ON public.user_addresses
    FOR SELECT TO authenticated USING (user_id = public.current_dealer_id());
  CREATE POLICY ro_addresses_self_delete ON public.user_addresses
    FOR DELETE TO authenticated USING (user_id = public.current_dealer_id());

  CREATE POLICY ro_cart_self_read ON public.cart_items
    FOR SELECT TO authenticated USING (user_id = public.current_dealer_id());
  CREATE POLICY ro_cart_self_delete ON public.cart_items
    FOR DELETE TO authenticated USING (user_id = public.current_dealer_id());

  CREATE POLICY ro_orders_self_read ON public.orders
    FOR SELECT TO authenticated USING (
      user_id = public.current_dealer_id()
      OR (user_id IS NULL AND auth.jwt()->>'email' IS NOT NULL
        AND lower(user_email::text) = lower(auth.jwt()->>'email'))
    );
  CREATE POLICY ro_order_items_self_read ON public.order_items
    FOR SELECT TO authenticated USING (
      EXISTS (
        SELECT 1 FROM public.orders AS o
        WHERE o.order_id = order_items.order_id
          AND (o.user_id = public.current_dealer_id()
            OR (o.user_id IS NULL AND auth.jwt()->>'email' IS NOT NULL
              AND lower(o.user_email::text) = lower(auth.jwt()->>'email')))
      )
    );
  CREATE POLICY ro_rewards_self_read ON public.rewards_history
    FOR SELECT TO authenticated USING (user_id = public.current_dealer_id());
  CREATE POLICY ro_support_self_read ON public.support_tickets
    FOR SELECT TO authenticated USING (
      user_id = public.current_dealer_id()
      OR (user_id IS NULL AND auth.jwt()->>'email' IS NOT NULL
        AND lower(user_email::text) = lower(auth.jwt()->>'email'))
    );

  DROP POLICY IF EXISTS ro_product_images_public_read ON storage.objects;
  DROP POLICY IF EXISTS ro_product_images_admin_write ON storage.objects;
  CREATE POLICY ro_product_images_public_read ON storage.objects
    FOR SELECT TO anon, authenticated USING (bucket_id = 'ro-product-images');
  CREATE POLICY ro_product_images_admin_write ON storage.objects
    FOR ALL TO authenticated
    USING (bucket_id = 'ro-product-images'
      AND auth.jwt()->'app_metadata'->>'role' = 'admin')
    WITH CHECK (bucket_id = 'ro-product-images'
      AND auth.jwt()->'app_metadata'->>'role' = 'admin');
END $$;

-- Remove inherited table privileges first, including PUBLIC. Sensitive OTP,
-- payment-session, order, and reward writes remain server-side only.
REVOKE ALL ON public.users, public.products, public.categories, public.user_addresses,
  public.cart_items, public.orders, public.order_items, public.rewards_history,
  public.support_tickets, public.otp_codes, public.payment_sessions,
  public.shop_employees, public.shop_order_assignments, public.shop_delivery_items,
  public.shop_admin_notifications, public.shop_product_enquiries
  FROM PUBLIC, anon, authenticated;
DO $$
DECLARE
  v_table text;
  v_column record;
  v_relation regclass;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'users','products','categories','user_addresses','cart_items','orders',
    'order_items','rewards_history','support_tickets','otp_codes','payment_sessions',
    'shop_employees','shop_order_assignments','shop_delivery_items',
    'shop_admin_notifications','shop_product_enquiries'
  ] LOOP
    v_relation := format('public.%I', v_table)::regclass;
    FOR v_column IN
      SELECT attname FROM pg_attribute
      WHERE attrelid = v_relation AND attnum > 0 AND NOT attisdropped
    LOOP
      EXECUTE format(
        'REVOKE SELECT (%1$I), INSERT (%1$I), UPDATE (%1$I), REFERENCES (%1$I) ON TABLE public.%2$I FROM PUBLIC, anon, authenticated',
        v_column.attname, v_table
      );
    END LOOP;
  END LOOP;
END;
$$;
GRANT SELECT ON public.categories TO anon, authenticated;
GRANT SELECT ON public.catalog_products TO anon, authenticated;
GRANT SELECT (id, email, mobile, name, business_name, owner_name, address,
  gst_number, status, is_approved, email_verified, reward_points, created_at, updated_at)
  ON public.users TO authenticated;
GRANT UPDATE (name, mobile, business_name, owner_name, address, gst_number) ON public.users TO authenticated;
GRANT SELECT, DELETE ON public.user_addresses TO authenticated;
GRANT SELECT, DELETE ON public.cart_items TO authenticated;
GRANT SELECT ON public.orders, public.order_items, public.rewards_history TO authenticated;
GRANT SELECT ON public.support_tickets TO authenticated;

-- Identity sequences are not client-writable. SECURITY DEFINER functions use
-- owner privileges for their internal inserts; clients get no direct sequence
-- privileges and cannot consume IDs or insert into server-owned ledgers.
DO $$
DECLARE
  v_table text;
  v_sequence text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'cart_items','order_items','rewards_history','support_tickets','otp_codes',
    'shop_admin_notifications'
  ] LOOP
    v_sequence := pg_get_serial_sequence(format('public.%I', v_table), 'id');
    IF v_sequence IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM PUBLIC, anon, authenticated', v_sequence::regclass);
    END IF;
  END LOOP;
END;
$$;

-- Ticket inserts derive identity from the signed Auth session. The client
-- cannot choose user_id, user_email, status, or the identity sequence value.
CREATE OR REPLACE FUNCTION public.ro_create_support_ticket(
  p_subject varchar,
  p_message text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_dealer_id varchar;
  v_email text;
  v_email_confirmed_at timestamptz;
  v_ticket_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;
  SELECT email, email_confirmed_at INTO v_email, v_email_confirmed_at
    FROM auth.users WHERE id = auth.uid();
  IF v_email IS NULL OR v_email_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'Verified email required' USING ERRCODE = '28000';
  END IF;
  v_dealer_id := public.current_dealer_id();
  IF v_dealer_id IS NULL THEN
    RAISE EXCEPTION 'Dealer profile required' USING ERRCODE = '28000';
  END IF;
  IF p_subject IS NULL OR length(trim(p_subject)) = 0 OR length(p_subject) > 255
     OR p_message IS NULL OR length(trim(p_message)) = 0 OR length(p_message) > 10000 THEN
    RAISE EXCEPTION 'Invalid support ticket' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.support_tickets (user_id, user_email, subject, message)
    VALUES (v_dealer_id, lower(v_email), trim(p_subject), p_message)
    RETURNING id INTO v_ticket_id;
  RETURN v_ticket_id;
END;
$$;
REVOKE ALL ON FUNCTION public.ro_create_support_ticket(varchar, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_create_support_ticket(varchar, text)
  TO authenticated;

-- Atomic, dealer-scoped cart mutations. These RPCs avoid read/modify/write
-- races and enforce current stock without trusting quantities from the app.
CREATE OR REPLACE FUNCTION public.ro_add_cart_item(
  p_product_id varchar,
  p_quantity integer
)
RETURNS public.cart_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dealer_id varchar;
  v_stock integer;
  v_status varchar;
  v_cart_item public.cart_items%ROWTYPE;
BEGIN
  v_dealer_id := public.current_dealer_id();
  IF v_dealer_id IS NULL THEN RAISE EXCEPTION 'Dealer profile required' USING ERRCODE = '28000'; END IF;
  IF p_product_id IS NULL OR length(trim(p_product_id)) = 0 OR p_quantity IS NULL OR p_quantity < 1 THEN
    RAISE EXCEPTION 'Invalid cart item' USING ERRCODE = '22023';
  END IF;
  SELECT stock_quantity, status INTO v_stock, v_status
    FROM public.products WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND OR v_status = 'inactive' THEN
    RAISE EXCEPTION 'Product is unavailable' USING ERRCODE = 'P0002';
  END IF;
  INSERT INTO public.cart_items (user_id, product_id, quantity)
    VALUES (v_dealer_id, p_product_id, p_quantity)
    ON CONFLICT (user_id, product_id) DO UPDATE
      SET quantity = public.cart_items.quantity + EXCLUDED.quantity,
          updated_at = CURRENT_TIMESTAMP
      WHERE public.cart_items.quantity + EXCLUDED.quantity <= v_stock
    RETURNING * INTO v_cart_item;
  IF NOT FOUND THEN RAISE EXCEPTION 'Requested quantity exceeds available stock' USING ERRCODE = '23514'; END IF;
  IF v_cart_item.quantity > v_stock THEN
    RAISE EXCEPTION 'Requested quantity exceeds available stock' USING ERRCODE = '23514';
  END IF;
  RETURN v_cart_item;
END;
$$;
REVOKE ALL ON FUNCTION public.ro_add_cart_item(varchar, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_add_cart_item(varchar, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.ro_update_cart_item(
  p_product_id varchar,
  p_quantity integer
)
RETURNS public.cart_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dealer_id varchar;
  v_stock integer;
  v_status varchar;
  v_cart_item public.cart_items%ROWTYPE;
BEGIN
  v_dealer_id := public.current_dealer_id();
  IF v_dealer_id IS NULL THEN RAISE EXCEPTION 'Dealer profile required' USING ERRCODE = '28000'; END IF;
  IF p_product_id IS NULL OR length(trim(p_product_id)) = 0 OR p_quantity IS NULL OR p_quantity < 1 THEN
    RAISE EXCEPTION 'Invalid cart quantity' USING ERRCODE = '22023';
  END IF;
  SELECT stock_quantity, status INTO v_stock, v_status
    FROM public.products WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND OR v_status = 'inactive' THEN
    RAISE EXCEPTION 'Product is unavailable' USING ERRCODE = 'P0002';
  END IF;
  IF p_quantity > v_stock THEN
    RAISE EXCEPTION 'Requested quantity exceeds available stock' USING ERRCODE = '23514';
  END IF;
  UPDATE public.cart_items SET quantity = p_quantity, updated_at = CURRENT_TIMESTAMP
    WHERE user_id = v_dealer_id AND product_id = p_product_id
    RETURNING * INTO v_cart_item;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cart item was not found' USING ERRCODE = 'P0002'; END IF;
  RETURN v_cart_item;
END;
$$;
REVOKE ALL ON FUNCTION public.ro_update_cart_item(varchar, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_update_cart_item(varchar, integer) TO authenticated;

-- Setting a default address is one transaction and can only affect the
-- address belonging to the authenticated dealer profile.
CREATE OR REPLACE FUNCTION public.ro_set_default_dealer_address(p_address_id varchar)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dealer_id varchar;
BEGIN
  v_dealer_id := public.current_dealer_id();
  IF v_dealer_id IS NULL THEN RAISE EXCEPTION 'Dealer profile required' USING ERRCODE = '28000'; END IF;
  -- Serialize changes for this dealer so concurrent calls cannot leave two
  -- addresses marked as default.
  PERFORM 1 FROM public.users WHERE id = v_dealer_id FOR UPDATE;
  PERFORM 1 FROM public.user_addresses
    WHERE user_id = v_dealer_id AND id = p_address_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Address was not found' USING ERRCODE = 'P0002'; END IF;
  UPDATE public.user_addresses SET is_default = false WHERE user_id = v_dealer_id AND is_default;
  UPDATE public.user_addresses SET is_default = true WHERE user_id = v_dealer_id AND id = p_address_id;
END;
$$;
REVOKE ALL ON FUNCTION public.ro_set_default_dealer_address(varchar) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_set_default_dealer_address(varchar) TO authenticated;

-- Insert/update an address without granting the client direct writes to
-- ownership or is_default columns. The owner row lock also serializes the
-- optional default-address change with explicit default-selection calls.
CREATE OR REPLACE FUNCTION public.ro_save_dealer_address(
  p_id varchar,
  p_label varchar,
  p_business_name varchar,
  p_street text,
  p_city varchar,
  p_state varchar,
  p_pincode varchar,
  p_phone varchar,
  p_full_name varchar,
  p_door_no varchar,
  p_area varchar,
  p_district varchar,
  p_landmark varchar,
  p_address_type varchar,
  p_gst_number varchar,
  p_make_default boolean
)
RETURNS varchar
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dealer_id varchar;
  v_saved_id varchar;
BEGIN
  v_dealer_id := public.current_dealer_id();
  IF v_dealer_id IS NULL THEN RAISE EXCEPTION 'Dealer profile required' USING ERRCODE = '28000'; END IF;
  IF p_id IS NULL OR length(trim(p_id)) = 0 OR length(p_id) > 64
     OR p_full_name IS NULL OR length(trim(p_full_name)) = 0
     OR p_phone IS NULL OR p_phone !~ '^[0-9]{10}$'
     OR p_street IS NULL OR length(trim(p_street)) = 0
     OR p_city IS NULL OR length(trim(p_city)) = 0
     OR p_state IS NULL OR length(trim(p_state)) = 0
     OR p_pincode IS NULL OR p_pincode !~ '^[0-9]{6}$' THEN
    RAISE EXCEPTION 'Enter a complete address with valid phone and PIN code' USING ERRCODE = '22023';
  END IF;

  PERFORM 1 FROM public.users WHERE id = v_dealer_id FOR UPDATE;
  INSERT INTO public.user_addresses (
    id, user_id, label, business_name, street, city, state, pincode, phone,
    is_default, full_name, door_no, area, district, landmark, address_type, gst_number
  ) VALUES (
    trim(p_id), v_dealer_id, coalesce(nullif(trim(p_label), ''), 'Office'),
    nullif(trim(p_business_name), ''), trim(p_street), trim(p_city), trim(p_state),
    trim(p_pincode), trim(p_phone), false, trim(p_full_name),
    nullif(trim(p_door_no), ''), nullif(trim(p_area), ''),
    coalesce(nullif(trim(p_district), ''), trim(p_city)),
    nullif(trim(p_landmark), ''), coalesce(nullif(trim(p_address_type), ''), 'Office'),
    nullif(upper(trim(p_gst_number)), '')
  )
  ON CONFLICT (id) DO UPDATE SET
    label = EXCLUDED.label,
    business_name = EXCLUDED.business_name,
    street = EXCLUDED.street,
    city = EXCLUDED.city,
    state = EXCLUDED.state,
    pincode = EXCLUDED.pincode,
    phone = EXCLUDED.phone,
    full_name = EXCLUDED.full_name,
    door_no = EXCLUDED.door_no,
    area = EXCLUDED.area,
    district = EXCLUDED.district,
    landmark = EXCLUDED.landmark,
    address_type = EXCLUDED.address_type,
    gst_number = EXCLUDED.gst_number
  WHERE public.user_addresses.user_id = v_dealer_id
  RETURNING id INTO v_saved_id;

  IF v_saved_id IS NULL THEN
    RAISE EXCEPTION 'Address was not found for this dealer' USING ERRCODE = '42501';
  END IF;
  IF coalesce(p_make_default, false) THEN
    UPDATE public.user_addresses SET is_default = false
      WHERE user_id = v_dealer_id AND is_default AND id <> v_saved_id;
    UPDATE public.user_addresses SET is_default = true
      WHERE user_id = v_dealer_id AND id = v_saved_id;
  END IF;
  RETURN v_saved_id;
END;
$$;
REVOKE ALL ON FUNCTION public.ro_save_dealer_address(
  varchar, varchar, varchar, text, varchar, varchar, varchar, varchar,
  varchar, varchar, varchar, varchar, varchar, varchar, varchar, boolean
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_save_dealer_address(
  varchar, varchar, varchar, text, varchar, varchar, varchar, varchar,
  varchar, varchar, varchar, varchar, varchar, varchar, varchar, boolean
) TO authenticated;

COMMIT;
