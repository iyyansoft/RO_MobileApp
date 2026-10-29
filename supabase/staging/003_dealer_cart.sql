-- Local staging migration: dealer cart reads/deletes plus stock-checked,
-- idempotent RPC writes.
-- Prerequisites: 002_dealer_profile_addresses.sql and a linked, verified Auth
-- dealer profile. Project-target identity is NOT encoded in SQL; independently
-- verify staging before execution. Checkout/order creation remains on Express.
BEGIN;
DO $$
DECLARE v_missing text[];
BEGIN
  IF to_regclass('public.cart_items') IS NULL OR to_regclass('public.products') IS NULL OR
     to_regprocedure('public.current_dealer_id()') IS NULL THEN
    RAISE EXCEPTION 'Cart stage requires existing tables and current_dealer_id()';
  END IF;
  SELECT array_agg(required.table_name || '.' || required.column_name ORDER BY required.table_name,required.column_name)
    INTO v_missing
  FROM (VALUES
    ('cart_items','user_id'),('cart_items','product_id'),('cart_items','quantity'),('cart_items','updated_at'),
    ('products','id'),('products','status'),('products','stock_quantity')
  ) AS required(table_name,column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema='public' AND c.table_name=required.table_name
      AND c.column_name=required.column_name
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Existing cart/product schema is incompatible; missing columns: %',array_to_string(v_missing,', ');
  END IF;
  -- The add RPC's ON CONFLICT relies on a real, non-partial unique key with
  -- this exact order. Do not infer or create it on an existing data set.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class t ON t.oid=i.indrelid
    JOIN pg_namespace n ON n.oid=t.relnamespace
    JOIN LATERAL (
      SELECT array_agg(a.attname::text ORDER BY k.ordinality) AS column_names
      FROM unnest(i.indkey) WITH ORDINALITY AS k(attnum,ordinality)
      JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.attnum
      WHERE k.ordinality<=i.indnkeyatts
    ) key_columns ON true
    WHERE n.nspname='public' AND t.relname='cart_items'
      AND i.indisunique AND i.indisvalid AND i.indisready
      AND i.indpred IS NULL AND i.indnkeyatts=2
      AND key_columns.column_names=ARRAY['user_id','product_id']::text[]
  ) THEN
    RAISE EXCEPTION 'Cart requires an existing non-partial unique index on (user_id, product_id); inspect and reconcile before staging';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN ('ro_add_cart_item','ro_update_cart_item')
  ) THEN
    RAISE EXCEPTION 'Cart RPC names already exist; inspect their signatures and privileges before this one-time migration';
  END IF;
  IF to_regclass('public.ro_cart_add_requests') IS NOT NULL THEN
    RAISE EXCEPTION 'Cart request ledger already exists; inspect and reconcile before this one-time migration';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='cart_items') THEN
    RAISE EXCEPTION 'Cart RLS policies already exist; inspect and reconcile them before this one-time migration';
  END IF;
END;
$$;

ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
    AND tablename='cart_items' AND policyname='ro_cart_self_read') THEN
    CREATE POLICY ro_cart_self_read ON public.cart_items FOR SELECT TO authenticated
      USING (user_id=public.current_dealer_id());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
    AND tablename='cart_items' AND policyname='ro_cart_self_delete') THEN
    CREATE POLICY ro_cart_self_delete ON public.cart_items FOR DELETE TO authenticated
      USING (user_id=public.current_dealer_id());
  END IF;
END;
$$;
REVOKE ALL PRIVILEGES ON TABLE public.cart_items FROM PUBLIC, anon, authenticated;
GRANT SELECT (user_id,product_id,quantity) ON public.cart_items TO authenticated;
GRANT DELETE ON public.cart_items TO authenticated;

-- A request ledger makes retries of an ambiguous client request safe. It is
-- inaccessible to API roles and is written atomically with the cart mutation.
-- A failed stock check rolls the ledger insert back too.
CREATE TABLE public.ro_cart_add_requests (
  user_id varchar(64) NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  product_id varchar(64) NOT NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id,request_id)
);
REVOKE ALL PRIVILEGES ON TABLE public.ro_cart_add_requests FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.ro_add_cart_item(
  p_product_id varchar,p_quantity integer,p_request_id uuid
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public, pg_temp AS $$
DECLARE
  v_dealer_id varchar;
  v_stock numeric;
  v_status varchar;
  v_saved_quantity integer;
  v_request_product varchar;
  v_request_quantity integer;
  v_new_request uuid;
BEGIN
  v_dealer_id := public.current_dealer_id();
  IF v_dealer_id IS NULL THEN RAISE EXCEPTION 'Dealer profile required' USING ERRCODE='28000'; END IF;
  IF p_product_id IS NULL OR length(trim(p_product_id))=0 OR p_quantity IS NULL OR p_quantity<1
    OR p_request_id IS NULL THEN
    RAISE EXCEPTION 'Invalid cart item' USING ERRCODE='22023';
  END IF;

  INSERT INTO public.ro_cart_add_requests(user_id,request_id,product_id,quantity)
    VALUES(v_dealer_id,p_request_id,trim(p_product_id),p_quantity)
    ON CONFLICT(user_id,request_id) DO NOTHING
    RETURNING request_id INTO v_new_request;
  IF v_new_request IS NULL THEN
    SELECT product_id,quantity INTO v_request_product,v_request_quantity
      FROM public.ro_cart_add_requests
      WHERE user_id=v_dealer_id AND request_id=p_request_id
      FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cart retry could not be resolved' USING ERRCODE='40001'; END IF;
    IF v_request_product<>trim(p_product_id) OR v_request_quantity<>p_quantity THEN
      RAISE EXCEPTION 'Cart request ID was reused with different contents' USING ERRCODE='22023';
    END IF;
    RETURN;
  END IF;

  SELECT stock_quantity,status INTO v_stock,v_status
    FROM public.products WHERE id=p_product_id FOR UPDATE;
  IF NOT FOUND OR v_status='inactive' THEN RAISE EXCEPTION 'Product is unavailable' USING ERRCODE='P0002'; END IF;
  INSERT INTO public.cart_items(user_id,product_id,quantity)
  VALUES(v_dealer_id,p_product_id,p_quantity)
  ON CONFLICT(user_id,product_id) DO UPDATE
    SET quantity=public.cart_items.quantity+EXCLUDED.quantity,updated_at=CURRENT_TIMESTAMP
    WHERE public.cart_items.quantity+EXCLUDED.quantity<=v_stock
  RETURNING quantity INTO v_saved_quantity;
  IF NOT FOUND OR v_saved_quantity>v_stock THEN
    RAISE EXCEPTION 'Requested quantity exceeds available stock' USING ERRCODE='23514';
  END IF;
  RETURN;
END;
$$;
REVOKE ALL ON FUNCTION public.ro_add_cart_item(varchar,integer,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_add_cart_item(varchar,integer,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.ro_update_cart_item(p_product_id varchar,p_quantity integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public, pg_temp AS $$
DECLARE v_dealer_id varchar; v_stock numeric; v_status varchar;
BEGIN
  v_dealer_id := public.current_dealer_id();
  IF v_dealer_id IS NULL THEN RAISE EXCEPTION 'Dealer profile required' USING ERRCODE='28000'; END IF;
  IF p_product_id IS NULL OR length(trim(p_product_id))=0 OR p_quantity IS NULL OR p_quantity<1 THEN
    RAISE EXCEPTION 'Invalid cart quantity' USING ERRCODE='22023';
  END IF;
  SELECT stock_quantity,status INTO v_stock,v_status
    FROM public.products WHERE id=p_product_id FOR UPDATE;
  IF NOT FOUND OR v_status='inactive' THEN RAISE EXCEPTION 'Product is unavailable' USING ERRCODE='P0002'; END IF;
  IF p_quantity>v_stock THEN RAISE EXCEPTION 'Requested quantity exceeds available stock' USING ERRCODE='23514'; END IF;
  UPDATE public.cart_items SET quantity=p_quantity,updated_at=CURRENT_TIMESTAMP
  WHERE user_id=v_dealer_id AND product_id=p_product_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Cart item was not found' USING ERRCODE='P0002'; END IF;
  RETURN;
END;
$$;
REVOKE ALL ON FUNCTION public.ro_update_cart_item(varchar,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_update_cart_item(varchar,integer) TO authenticated;
COMMIT;
