-- Local draft only. Apply to an isolated staging project after review and
-- explicit approval. This adds an idempotency ledger and a service-only RPC;
-- it never drops or clears existing product/category data.
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.products') IS NULL OR to_regclass('public.categories') IS NULL OR
     to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'Bulk product import requires existing products/categories and Supabase Auth';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.admin_bulk_import_requests (
  admin_user_id uuid NOT NULL,
  request_hash varchar(64) NOT NULL,
  response_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_admin_bulk_import_requests PRIMARY KEY (admin_user_id, request_hash),
  CONSTRAINT ck_admin_bulk_import_request_hash CHECK (request_hash ~ '^[a-f0-9]{64}$')
);

ALTER TABLE public.admin_bulk_import_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.admin_bulk_import_requests FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.ro_admin_bulk_import_products(
  p_admin_user_id uuid,
  p_request_hash varchar,
  p_products jsonb,
  p_initial_skipped jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_cached jsonb;
  v_response jsonb;
  v_row jsonb;
  v_product public.products%ROWTYPE;
  v_imported jsonb := '[]'::jsonb;
  v_skipped jsonb := coalesce(p_initial_skipped, '[]'::jsonb);
  v_seen_skus text[] := ARRAY[]::text[];
  v_sku text;
  v_product_index integer := 0;
  v_stock numeric;
  v_min_stock numeric;
  v_price numeric;
  v_purchase_price numeric;
  v_mrp numeric;
  v_constraint_name text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_admin_user_id
      AND email_confirmed_at IS NOT NULL
      AND coalesce(raw_app_meta_data->>'role', '') = 'admin'
  ) THEN
    RAISE EXCEPTION 'Verified administrator required' USING ERRCODE = '42501';
  END IF;
  IF p_request_hash IS NULL OR p_request_hash !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'Bulk import request fingerprint is invalid';
  END IF;
  IF p_products IS NULL OR jsonb_typeof(p_products) IS DISTINCT FROM 'array' OR
     jsonb_array_length(p_products) < 1 OR jsonb_array_length(p_products) > 200 THEN
    RAISE EXCEPTION 'Bulk import must contain between 1 and 200 validated products';
  END IF;
  IF p_initial_skipped IS NULL OR jsonb_typeof(p_initial_skipped) IS DISTINCT FROM 'array' OR
     jsonb_array_length(p_initial_skipped) > 200 THEN
    RAISE EXCEPTION 'Bulk import validation result is invalid';
  END IF;

  -- Serialize retries of identical batches. The ledger and product inserts
  -- commit in the same PostgreSQL transaction, so a failed batch is retryable.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_admin_user_id::text || ':' || p_request_hash, 0));
  SELECT response_json INTO v_cached FROM public.admin_bulk_import_requests
    WHERE admin_user_id = p_admin_user_id AND request_hash = p_request_hash;
  IF FOUND THEN
    RETURN v_cached || jsonb_build_object('replayed', true);
  END IF;

  FOR v_row IN SELECT value FROM jsonb_array_elements(p_products) AS rows(value) LOOP
    v_product_index := v_product_index + 1;
    IF jsonb_typeof(v_row) <> 'object' THEN
      RAISE EXCEPTION 'Validated product row % is malformed', v_product_index;
    END IF;

    v_sku := upper(btrim(coalesce(v_row->>'sku', '')));
    IF coalesce(v_row->>'id', '') = '' OR char_length(v_row->>'id') > 64 OR
       coalesce(v_row->>'name', '') = '' OR char_length(v_row->>'name') > 512 OR
       v_sku !~ '^[A-Z0-9][A-Z0-9._/-]{0,63}$' OR
       coalesce(v_row->>'category_id', '') = '' OR coalesce(v_row->>'category_key', '') = '' OR
       char_length(coalesce(v_row->>'brand', '')) > 255 OR
       char_length(coalesce(v_row->>'moq', '')) > 64 OR
       char_length(coalesce(v_row->>'badge', '')) > 64 OR
       char_length(coalesce(v_row->>'rating', '')) > 64 OR
       coalesce(v_row->>'status', '') NOT IN ('active', 'inactive') THEN
      RAISE EXCEPTION 'Validated product row % contains invalid text fields', v_product_index;
    END IF;
    IF jsonb_typeof(v_row->'price') <> 'number' OR
       jsonb_typeof(v_row->'purchase_price') <> 'number' OR
       jsonb_typeof(v_row->'mrp') <> 'number' OR
       jsonb_typeof(v_row->'stock_quantity') <> 'number' OR
       jsonb_typeof(v_row->'min_stock') <> 'number' THEN
      RAISE EXCEPTION 'Validated product row % contains invalid numeric fields', v_product_index;
    END IF;
    v_price := (v_row->>'price')::numeric;
    v_purchase_price := (v_row->>'purchase_price')::numeric;
    v_mrp := (v_row->>'mrp')::numeric;
    v_stock := (v_row->>'stock_quantity')::numeric;
    v_min_stock := (v_row->>'min_stock')::numeric;
    IF v_price <= 0 OR v_price > 99999999.99 OR
       v_purchase_price < 0 OR v_purchase_price > 99999999.99 OR
       v_mrp <= 0 OR v_mrp > 99999999.99 OR
       v_price * 100 <> trunc(v_price * 100) OR
       v_purchase_price * 100 <> trunc(v_purchase_price * 100) OR
       v_mrp * 100 <> trunc(v_mrp * 100) OR
       v_stock < 0 OR v_stock > 2147483647 OR v_stock <> trunc(v_stock) OR
       v_min_stock < 0 OR v_min_stock > 2147483647 OR v_min_stock <> trunc(v_min_stock) THEN
      RAISE EXCEPTION 'Validated product row % contains an out-of-range price or stock value', v_product_index;
    END IF;
    IF jsonb_typeof(v_row->'specs_json') IS DISTINCT FROM 'object' OR
       jsonb_typeof(v_row->'features_json') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'Validated product row % contains invalid specifications or features', v_product_index;
    END IF;

    IF v_sku = ANY(v_seen_skus) THEN
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'sku', v_sku, 'reason', 'Duplicate SKU appears more than once in this import.'
      ));
      CONTINUE;
    END IF;
    v_seen_skus := array_append(v_seen_skus, v_sku);

    IF NOT EXISTS (
      SELECT 1 FROM public.categories
      WHERE id = v_row->>'category_id' AND key_name = v_row->>'category_key'
    ) THEN
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'sku', v_sku, 'reason', 'The selected category no longer exists.'
      ));
      CONTINUE;
    END IF;
    IF EXISTS (SELECT 1 FROM public.products WHERE lower(sku) = lower(v_sku)) THEN
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'sku', v_sku, 'reason', format('Duplicate SKU "%s" already exists in database.', v_sku)
      ));
      CONTINUE;
    END IF;

    BEGIN
      INSERT INTO public.products (
        id, category_id, category_key, sku, name, brand, purchase_price, price, mrp,
        moq, badge, rating, img, description, specs_json, features_json,
        applications, status, stock_quantity, min_stock
      ) VALUES (
        v_row->>'id', v_row->>'category_id', v_row->>'category_key', v_sku,
        v_row->>'name', v_row->>'brand', v_purchase_price, v_price, v_mrp,
        v_row->>'moq', nullif(v_row->>'badge', ''), nullif(v_row->>'rating', ''),
        nullif(v_row->>'img', ''), nullif(v_row->>'description', ''),
        (v_row->'specs_json')::json, (v_row->'features_json')::json,
        nullif(v_row->>'applications', ''), v_row->>'status', v_stock::integer, v_min_stock::integer
      ) RETURNING * INTO v_product;
      v_imported := v_imported || jsonb_build_array(to_jsonb(v_product));
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
      IF v_constraint_name <> 'uk_products_sku' THEN
        RAISE;
      END IF;
      -- A concurrent single-product create can win after the pre-check. Skip
      -- only that SKU; no existing row is overwritten and the batch continues.
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'sku', v_sku, 'reason', format('Duplicate SKU "%s" already exists in database.', v_sku)
      ));
    END;
  END LOOP;

  v_response := jsonb_build_object(
    'importedCount', jsonb_array_length(v_imported),
    'skippedCount', jsonb_array_length(v_skipped),
    'imported', v_imported,
    'skipped', v_skipped,
    'replayed', false
  );
  INSERT INTO public.admin_bulk_import_requests(admin_user_id, request_hash, response_json)
    VALUES (p_admin_user_id, p_request_hash, v_response);
  RETURN v_response;
END;
$$;

REVOKE ALL ON FUNCTION public.ro_admin_bulk_import_products(uuid, varchar, jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_admin_bulk_import_products(uuid, varchar, jsonb, jsonb)
  TO service_role;

COMMIT;
