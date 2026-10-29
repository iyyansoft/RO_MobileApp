-- Local staging migration for dealer Auth linking, profile reads/updates, and
-- saved-address operations. Apply only after 001_catalog_read.sql succeeds on
-- an isolated staging clone. Project-target identity is NOT encoded in SQL;
-- independently verify staging before execution. Never run against production.
--
-- It reuses public.users/public.user_addresses and preserves dealer approval.
-- It does not grant client access to password_hash, auth_user_id, or approval
-- mutation, and does not create or clear business tables.
BEGIN;

DO $$
DECLARE v_missing text[];
BEGIN
  IF to_regclass('public.users') IS NULL OR
     to_regclass('public.user_addresses') IS NULL OR
     to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'Existing users, user_addresses, and Supabase Auth are required';
  END IF;
  SELECT array_agg(required.table_name || '.' || required.column_name ORDER BY required.table_name, required.column_name)
    INTO v_missing
  FROM (VALUES
    ('users','id'), ('users','email'), ('users','mobile'), ('users','name'),
    ('users','password_hash'), ('users','email_verified'), ('users','business_name'),
    ('users','owner_name'), ('users','address'), ('users','gst_number'),
    ('users','status'), ('users','is_approved'), ('users','reward_points'),
    ('user_addresses','id'), ('user_addresses','user_id'), ('user_addresses','label'),
    ('user_addresses','business_name'), ('user_addresses','street'),
    ('user_addresses','city'), ('user_addresses','state'), ('user_addresses','pincode'),
    ('user_addresses','phone'), ('user_addresses','is_default'),
    ('user_addresses','full_name'), ('user_addresses','door_no'),
    ('user_addresses','area'), ('user_addresses','district'),
    ('user_addresses','landmark'), ('user_addresses','address_type'),
    ('user_addresses','gst_number'), ('user_addresses','created_at')
  ) AS required(table_name, column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema='public' AND c.table_name=required.table_name
      AND c.column_name=required.column_name
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Dealer profile/address schema differs; missing columns: %',
      array_to_string(v_missing, ', ');
  END IF;

  -- Do not OR new permissive rules with existing rules. The read-only
  -- production audit found no policies on these tables; require a clean staging
  -- policy state. This file is a one-time migration, not a rerunnable script.
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename IN ('users','user_addresses')
  ) THEN
    RAISE EXCEPTION 'Users/address RLS policies already exist; inspect and reconcile them before this one-time migration';
  END IF;
END;
$$;

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS auth_user_id uuid;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='fk_users_auth_user' AND conrelid='public.users'::regclass
  ) THEN
    ALTER TABLE public.users ADD CONSTRAINT fk_users_auth_user
      FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END;
$$;
CREATE UNIQUE INDEX IF NOT EXISTS uk_users_auth_user_id
  ON public.users(auth_user_id) WHERE auth_user_id IS NOT NULL;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_addresses ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.current_dealer_id()
RETURNS varchar
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public, auth, pg_temp
AS $$
  SELECT u.id
  FROM public.users u
  JOIN auth.users au ON au.id=u.auth_user_id
  WHERE u.auth_user_id=auth.uid() AND au.email_confirmed_at IS NOT NULL
  LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.current_dealer_id() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.current_dealer_id() TO authenticated;

-- An email-verified Auth identity may link only its own matching legacy row.
-- New dealer profiles always start pending; this function never approves them.
CREATE OR REPLACE FUNCTION public.sync_current_dealer_profile()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public, auth, pg_temp
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
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000';
  END IF;
  SELECT * INTO v_auth FROM auth.users WHERE id=auth.uid();
  IF NOT FOUND OR v_auth.email_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'Verified email required' USING ERRCODE='28000';
  END IF;
  v_email := lower(trim(v_auth.email));
  v_mobile := nullif(trim(coalesce(v_auth.raw_user_meta_data->>'mobile','')), '');
  v_name := coalesce(nullif(trim(v_auth.raw_user_meta_data->>'name'),''), split_part(v_email,'@',1));
  v_company := nullif(trim(coalesce(v_auth.raw_user_meta_data->>'companyName', v_auth.raw_user_meta_data->>'businessName','')), '');
  v_address := nullif(trim(coalesce(v_auth.raw_user_meta_data->>'address','')), '');
  v_gst := nullif(upper(trim(coalesce(v_auth.raw_user_meta_data->>'gstNumber',''))), '');

  SELECT * INTO v_profile FROM public.users WHERE auth_user_id=auth.uid() FOR UPDATE;
  IF NOT FOUND THEN
    SELECT * INTO v_profile FROM public.users
    WHERE lower(email::text)=v_email AND auth_user_id IS NULL FOR UPDATE;
    IF FOUND THEN
      UPDATE public.users SET auth_user_id=auth.uid(), email_verified=true
      WHERE id=v_profile.id RETURNING * INTO v_profile;
    ELSE
      IF v_mobile IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.users WHERE mobile=v_mobile
      ) THEN
        RAISE EXCEPTION 'Mobile number already belongs to another account' USING ERRCODE='23505';
      END IF;
      v_id := 'auth-' || replace(auth.uid()::text,'-','');
      INSERT INTO public.users (
        id,auth_user_id,email,mobile,name,password_hash,email_verified,
        business_name,owner_name,address,gst_number,status,is_approved
      ) VALUES (
        v_id,auth.uid(),v_email,v_mobile,v_name,'!supabase-auth-managed!',true,
        v_company,v_name,v_address,v_gst,'pending',false
      ) RETURNING * INTO v_profile;
    END IF;
  END IF;
  RETURN jsonb_build_object(
    'id',v_profile.id,'name',v_profile.name,'email',v_profile.email,
    'mobile',coalesce(v_profile.mobile,''),'address',coalesce(v_profile.address,''),
    'business',coalesce(v_profile.business_name,''),'gstNumber',coalesce(v_profile.gst_number,''),
    'status',v_profile.status,'isApproved',v_profile.is_approved
  );
END;
$$;
REVOKE ALL ON FUNCTION public.sync_current_dealer_profile() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sync_current_dealer_profile() TO authenticated;

-- The preflight requires no existing policies on these target tables. This
-- one-time stage must not be replayed after a successful commit.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='ro_users_self_read') THEN
    CREATE POLICY ro_users_self_read ON public.users FOR SELECT TO authenticated
      USING (auth_user_id=auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_addresses' AND policyname='ro_addresses_self_read') THEN
    CREATE POLICY ro_addresses_self_read ON public.user_addresses FOR SELECT TO authenticated
      USING (user_id=public.current_dealer_id());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_addresses' AND policyname='ro_addresses_self_delete') THEN
    CREATE POLICY ro_addresses_self_delete ON public.user_addresses FOR DELETE TO authenticated
      USING (user_id=public.current_dealer_id());
  END IF;
END;
$$;

REVOKE ALL PRIVILEGES ON TABLE public.users, public.user_addresses
  FROM PUBLIC, anon, authenticated;
DO $$
DECLARE v_table text; v_columns text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['users','user_addresses'] LOOP
    SELECT string_agg(format('%I',column_name),', ' ORDER BY ordinal_position)
      INTO v_columns FROM information_schema.columns
      WHERE table_schema='public' AND table_name=v_table;
    IF v_columns IS NOT NULL THEN
      EXECUTE format('REVOKE ALL PRIVILEGES (%s) ON TABLE public.%I FROM PUBLIC, anon, authenticated',v_columns,v_table);
    END IF;
  END LOOP;
END;
$$;
GRANT SELECT (id,email,mobile,name,business_name,owner_name,address,gst_number,
  status,is_approved,email_verified,reward_points,created_at,updated_at)
  ON public.users TO authenticated;
GRANT SELECT, DELETE ON public.user_addresses TO authenticated;

-- Profile writes go through an owner-derived RPC. A direct PostgREST UPDATE
-- would need broader SELECT access for RLS/RETURNING and can expose private
-- user columns. This function accepts only dealer-editable fields.
CREATE OR REPLACE FUNCTION public.ro_update_current_dealer_profile(
  p_name text,p_mobile text,p_business_name text,p_address text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public, auth, pg_temp AS $$
DECLARE v_dealer_id varchar(64); v_name text; v_mobile text;
BEGIN
  v_dealer_id := public.current_dealer_id();
  IF v_dealer_id IS NULL THEN
    RAISE EXCEPTION 'Verified dealer profile required' USING ERRCODE='28000';
  END IF;
  v_name := trim(coalesce(p_name,''));
  v_mobile := regexp_replace(coalesce(p_mobile,''),'\D','','g');
  IF v_name='' OR length(v_name)>128 OR v_mobile !~ '^[0-9]{10}$'
     OR length(coalesce(p_business_name,''))>191
     OR length(coalesce(p_address,''))>10000 THEN
    RAISE EXCEPTION 'Enter valid profile details' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.users u
      WHERE u.mobile=v_mobile AND u.id<>v_dealer_id) THEN
    RAISE EXCEPTION 'Mobile number already belongs to another account' USING ERRCODE='23505';
  END IF;
  UPDATE public.users SET name=v_name, owner_name=v_name, mobile=v_mobile,
    business_name=nullif(trim(p_business_name),''), address=trim(coalesce(p_address,''))
  WHERE id=v_dealer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dealer profile was not found' USING ERRCODE='P0002';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.ro_update_current_dealer_profile(text,text,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_update_current_dealer_profile(text,text,text,text)
  TO authenticated;

-- Address insert/update/default changes are owner-derived and serialized by
-- SECURITY DEFINER functions. No direct client write is granted.
CREATE OR REPLACE FUNCTION public.ro_set_default_dealer_address(p_address_id varchar)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public, pg_temp AS $$
DECLARE v_dealer_id varchar;
BEGIN
  v_dealer_id := public.current_dealer_id();
  IF v_dealer_id IS NULL THEN RAISE EXCEPTION 'Dealer profile required' USING ERRCODE='28000'; END IF;
  PERFORM 1 FROM public.users WHERE id=v_dealer_id FOR UPDATE;
  PERFORM 1 FROM public.user_addresses WHERE user_id=v_dealer_id AND id=p_address_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Address was not found' USING ERRCODE='P0002'; END IF;
  UPDATE public.user_addresses SET is_default=false WHERE user_id=v_dealer_id AND is_default;
  UPDATE public.user_addresses SET is_default=true WHERE user_id=v_dealer_id AND id=p_address_id;
END;
$$;
REVOKE ALL ON FUNCTION public.ro_set_default_dealer_address(varchar) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_set_default_dealer_address(varchar) TO authenticated;

CREATE OR REPLACE FUNCTION public.ro_save_dealer_address(
  p_id varchar,p_label varchar,p_business_name varchar,p_street text,
  p_city varchar,p_state varchar,p_pincode varchar,p_phone varchar,
  p_full_name varchar,p_door_no varchar,p_area varchar,p_district varchar,
  p_landmark varchar,p_address_type varchar,p_gst_number varchar,p_make_default boolean
) RETURNS varchar LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public, pg_temp AS $$
DECLARE v_dealer_id varchar; v_saved_id varchar;
BEGIN
  v_dealer_id := public.current_dealer_id();
  IF v_dealer_id IS NULL THEN RAISE EXCEPTION 'Dealer profile required' USING ERRCODE='28000'; END IF;
  IF p_id IS NULL OR length(trim(p_id))=0 OR length(p_id)>64
    OR p_full_name IS NULL OR length(trim(p_full_name))=0
    OR p_phone IS NULL OR p_phone !~ '^[0-9]{10}$'
    OR p_street IS NULL OR length(trim(p_street))=0
    OR p_city IS NULL OR length(trim(p_city))=0
    OR p_state IS NULL OR length(trim(p_state))=0
    OR p_pincode IS NULL OR p_pincode !~ '^[0-9]{6}$'
    OR length(coalesce(p_gst_number,''))>64 THEN
    RAISE EXCEPTION 'Enter a complete address with valid phone and PIN code' USING ERRCODE='22023';
  END IF;
  PERFORM 1 FROM public.users WHERE id=v_dealer_id FOR UPDATE;
  INSERT INTO public.user_addresses (
    id,user_id,label,business_name,street,city,state,pincode,phone,is_default,
    full_name,door_no,area,district,landmark,address_type,gst_number
  ) VALUES (
    trim(p_id),v_dealer_id,coalesce(nullif(trim(p_label),''),'Office'),
    nullif(trim(p_business_name),''),trim(p_street),trim(p_city),trim(p_state),
    trim(p_pincode),trim(p_phone),false,trim(p_full_name),nullif(trim(p_door_no),''),
    nullif(trim(p_area),''),coalesce(nullif(trim(p_district),''),trim(p_city)),
    nullif(trim(p_landmark),''),coalesce(nullif(trim(p_address_type),''),'Office'),
    nullif(upper(trim(p_gst_number)),'')
  ) ON CONFLICT (id) DO UPDATE SET
    label=EXCLUDED.label,business_name=EXCLUDED.business_name,
    street=EXCLUDED.street,city=EXCLUDED.city,state=EXCLUDED.state,
    pincode=EXCLUDED.pincode,phone=EXCLUDED.phone,full_name=EXCLUDED.full_name,
    door_no=EXCLUDED.door_no,area=EXCLUDED.area,district=EXCLUDED.district,
    landmark=EXCLUDED.landmark,address_type=EXCLUDED.address_type,
    gst_number=EXCLUDED.gst_number
  WHERE public.user_addresses.user_id=v_dealer_id
  RETURNING id INTO v_saved_id;
  IF v_saved_id IS NULL THEN RAISE EXCEPTION 'Address was not found for this dealer' USING ERRCODE='42501'; END IF;
  IF coalesce(p_make_default,false) THEN
    UPDATE public.user_addresses SET is_default=false
      WHERE user_id=v_dealer_id AND is_default AND id<>v_saved_id;
    UPDATE public.user_addresses SET is_default=true
      WHERE user_id=v_dealer_id AND id=v_saved_id;
  END IF;
  RETURN v_saved_id;
END;
$$;
REVOKE ALL ON FUNCTION public.ro_save_dealer_address(
  varchar,varchar,varchar,text,varchar,varchar,varchar,varchar,
  varchar,varchar,varchar,varchar,varchar,varchar,varchar,boolean
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_save_dealer_address(
  varchar,varchar,varchar,text,varchar,varchar,varchar,varchar,
  varchar,varchar,varchar,varchar,varchar,varchar,varchar,boolean
) TO authenticated;

COMMIT;
