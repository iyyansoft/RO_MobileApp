-- Local-only admin order-status RPC. This creates no tables and changes no
-- order data until explicitly called. Review and apply to isolated staging
-- first; never execute against production without separate approval.
BEGIN;

DO $$
DECLARE v_missing text[];
BEGIN
  IF to_regclass('public.orders') IS NULL
     OR to_regclass('public.order_items') IS NULL
     OR to_regclass('public.shop_delivery_items') IS NULL
     OR to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'Admin order status requires the existing orders, order_items, shop_delivery_items, and Auth tables';
  END IF;
  SELECT array_agg(required.table_name || '.' || required.column_name ORDER BY required.table_name, required.column_name)
    INTO v_missing
  FROM (VALUES
    ('orders','order_id'), ('orders','status'),
    ('order_items','order_id'), ('order_items','quantity'),
    ('shop_delivery_items','order_id'), ('shop_delivery_items','order_item_id'),
    ('shop_delivery_items','delivered'), ('shop_delivery_items','delivered_quantity')
  ) AS required(table_name, column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema='public' AND c.table_name=required.table_name
      AND c.column_name=required.column_name
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Admin order status schema differs; missing columns: %', array_to_string(v_missing, ', ');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.ro_admin_update_order_status(
  p_admin_user_id uuid,
  p_order_id varchar,
  p_status varchar
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public, auth, pg_temp
AS $$
DECLARE
  v_status text;
  v_existing_status text;
  v_ordered integer;
  v_delivered integer;
BEGIN
  IF p_admin_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.users au
    WHERE au.id=p_admin_user_id
      AND au.email_confirmed_at IS NOT NULL
      AND au.raw_app_meta_data->>'role'='admin'
  ) THEN
    RAISE EXCEPTION 'Verified administrator required' USING ERRCODE='28000';
  END IF;
  IF p_order_id IS NULL OR length(trim(p_order_id))=0 OR length(trim(p_order_id))>64
     OR p_status IS NULL OR length(trim(p_status))=0 OR length(trim(p_status))>100 THEN
    RAISE EXCEPTION 'Invalid order status request' USING ERRCODE='22023';
  END IF;
  v_status := trim(p_status);

  -- Serialize competing admin updates and block FK-based delivery inserts
  -- while the current delivery state is checked and the order is updated.
  SELECT status INTO v_existing_status
  FROM public.orders WHERE order_id=trim(p_order_id) FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE='P0002';
  END IF;
  PERFORM 1 FROM public.order_items WHERE order_id=trim(p_order_id) FOR UPDATE;

  IF EXISTS (SELECT 1 FROM public.shop_delivery_items WHERE order_id=trim(p_order_id)) THEN
    RAISE EXCEPTION 'Delivery has been submitted by the Shop App. Its status is synchronized from the saved delivery quantities.'
      USING ERRCODE='55000';
  END IF;
  IF lower(v_status)='delivered' THEN
    SELECT COALESCE(sum(oi.quantity),0)::integer,
      COALESCE(sum(COALESCE(d.delivered_quantity, CASE WHEN d.delivered THEN oi.quantity ELSE 0 END)),0)::integer
    INTO v_ordered,v_delivered
    FROM public.order_items oi
    LEFT JOIN public.shop_delivery_items d ON d.order_item_id=oi.id
    WHERE oi.order_id=trim(p_order_id);
    IF v_ordered<>v_delivered THEN
      RAISE EXCEPTION 'An order can be marked Delivered only after every ordered unit is recorded as delivered in the Shop App.'
        USING ERRCODE='55000';
    END IF;
  END IF;

  UPDATE public.orders SET status=v_status WHERE order_id=trim(p_order_id);
  RETURN jsonb_build_object(
    'success',true,
    'message',format('Order #%s status updated to "%s".',trim(p_order_id),v_status),
    'orderId',trim(p_order_id),
    'status',v_status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ro_admin_update_order_status(uuid,varchar,varchar)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_admin_update_order_status(uuid,varchar,varchar)
  TO service_role;

COMMIT;
