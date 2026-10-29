-- Local, additive draft only. Do not apply to hosted Supabase without review.
-- It deliberately creates no Auth identities and makes no shop/order assignments.
-- An administrator must securely link each existing employee Auth identity and
-- assign orders before the function can accept a delivery.
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.orders') IS NULL OR to_regclass('public.order_items') IS NULL
     OR to_regclass('public.shop_employees') IS NULL
     OR to_regclass('public.shop_delivery_items') IS NULL
     OR to_regclass('public.shop_admin_notifications') IS NULL THEN
    RAISE EXCEPTION 'Shop delivery draft requires the existing order and shop tables';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_employees' AND column_name='id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_employees' AND column_name='shop_name')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_employees' AND column_name='active')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_delivery_items' AND column_name='order_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_delivery_items' AND column_name='order_item_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_delivery_items' AND column_name='delivered')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_delivery_items' AND column_name='delivered_quantity')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_delivery_items' AND column_name='undelivered_quantity')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_delivery_items' AND column_name='delivered_amount')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_delivery_items' AND column_name='refund_amount')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_delivery_items' AND column_name='refund_status')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_delivery_items' AND column_name='recorded_by')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_delivery_items' AND column_name='delivered_at')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shop_delivery_items' AND column_name='updated_at') THEN
    RAISE EXCEPTION 'Shop delivery draft does not match the audited shop table contract';
  END IF;
  IF EXISTS (SELECT required.column_name FROM (VALUES
      ('order_id'),('employee_id'),('notification_type'),('message'),('refund_amount'),('created_at'),('read_at')
    ) AS required(column_name)
    WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public'
      AND c.table_name='shop_admin_notifications' AND c.column_name=required.column_name)) THEN
    RAISE EXCEPTION 'Shop admin notifications lack the order_id contract';
  END IF;
END $$;

-- Nullable link: existing employee credentials/rows are preserved and are not
-- automatically promoted to Supabase Auth. A trusted admin provisioning flow
-- must set this value after creating and verifying the matching Auth user.
ALTER TABLE public.shop_employees
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT;
CREATE UNIQUE INDEX IF NOT EXISTS uk_shop_employees_auth_user
  ON public.shop_employees(auth_user_id) WHERE auth_user_id IS NOT NULL;

-- Additive assignment relation. No existing order is silently assigned.
CREATE TABLE IF NOT EXISTS public.shop_order_assignments (
  order_id varchar(64) PRIMARY KEY REFERENCES public.orders(order_id) ON DELETE CASCADE,
  shop_name varchar(191) NOT NULL,
  assigned_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  assigned_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (btrim(shop_name) <> '')
);
CREATE INDEX IF NOT EXISTS idx_shop_order_assignments_shop
  ON public.shop_order_assignments(lower(shop_name),assigned_at DESC);
ALTER TABLE public.shop_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_order_assignments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.shop_employees,public.shop_order_assignments FROM PUBLIC,anon,authenticated;
GRANT ALL ON TABLE public.shop_employees,public.shop_order_assignments TO service_role;

ALTER TABLE public.shop_delivery_items
  ADD COLUMN IF NOT EXISTS delivery_confirmed boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX IF NOT EXISTS uk_shop_delivery_items_order_item
  ON public.shop_delivery_items(order_item_id);
CREATE INDEX IF NOT EXISTS idx_shop_delivery_items_order
  ON public.shop_delivery_items(order_id,order_item_id);
ALTER TABLE public.shop_delivery_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.shop_delivery_items FROM PUBLIC,anon,authenticated;
GRANT ALL ON TABLE public.shop_delivery_items TO service_role;
ALTER TABLE public.shop_admin_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.shop_admin_notifications FROM PUBLIC,anon,authenticated;
GRANT ALL ON TABLE public.shop_admin_notifications TO service_role;

-- A durable COD collection ledger prevents a retry from recording cash twice.
-- No payment row is inserted unless an authenticated employee explicitly
-- attests collection on a fully delivered COD order.
CREATE TABLE IF NOT EXISTS public.shop_cash_collections (
  order_id varchar(64) PRIMARY KEY REFERENCES public.orders(order_id) ON DELETE RESTRICT,
  employee_id bigint NOT NULL REFERENCES public.shop_employees(id) ON DELETE RESTRICT,
  auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  amount numeric(10,2) NOT NULL CHECK (amount >= 0),
  collected_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE public.shop_cash_collections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.shop_cash_collections FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.shop_cash_collections TO service_role;

CREATE OR REPLACE FUNCTION public.ro_submit_shop_delivery(
  p_auth_user_id uuid, p_order_id text, p_mode text, p_items jsonb,
  p_cash_collected boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_employee public.shop_employees%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_item record;
  v_req jsonb;
  v_prev public.shop_delivery_items%ROWTYPE;
  v_qty integer;
  v_confirmed boolean;
  v_ordered integer := 0;
  v_original numeric(12,2) := 0;
  v_delivered integer := 0;
  v_delivered_value numeric(12,2) := 0;
  v_adjustment numeric(12,2) := 0;
  v_cod boolean;
  v_cash boolean := false;
  v_status text;
  v_seen integer := 0;
BEGIN
  IF p_auth_user_id IS NULL OR coalesce(trim(p_order_id),'')='' OR
     coalesce(p_mode,'') NOT IN ('submit','confirm') OR coalesce(jsonb_typeof(p_items),'')<>'array' OR
     jsonb_array_length(p_items)=0 OR (p_mode='submit' AND coalesce(p_cash_collected,false)) THEN
    RAISE EXCEPTION 'Delivery request is invalid';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users au WHERE au.id=p_auth_user_id
    AND au.email_confirmed_at IS NOT NULL
    AND au.raw_app_meta_data->>'role'='shop_employee') THEN
    RAISE EXCEPTION 'Verified employee Auth account required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_employee FROM public.shop_employees
    WHERE auth_user_id=p_auth_user_id AND active=true FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active Shop Employee identity is not linked' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_order FROM public.orders WHERE order_id=trim(p_order_id) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='P0002'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.shop_order_assignments a
    WHERE a.order_id=v_order.order_id AND lower(a.shop_name)=lower(v_employee.shop_name)) THEN
    RAISE EXCEPTION 'Order is not assigned to this employee shop' USING ERRCODE='42501';
  END IF;

  SELECT count(*)::integer INTO v_seen
    FROM jsonb_array_elements(p_items) AS x(item)
    WHERE jsonb_typeof(x.item)='object' AND x.item ? 'orderItemId'
      AND jsonb_typeof(x.item->'deliveryConfirmed')='boolean'
      AND jsonb_typeof(x.item->'deliveredQuantity')='number'
      AND (x.item->>'deliveredQuantity') ~ '^(0|[1-9][0-9]*)$';
  IF v_seen<>jsonb_array_length(p_items) OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_items) AS x(item)
    GROUP BY (x.item->>'orderItemId') HAVING count(*)<>1
  ) THEN RAISE EXCEPTION 'Each order item needs one explicit quantity and delivery status'; END IF;

  FOR v_item IN SELECT id,quantity,unit_price FROM public.order_items
    WHERE order_id=v_order.order_id ORDER BY id FOR UPDATE
  LOOP
    SELECT x.item INTO v_req FROM jsonb_array_elements(p_items) AS x(item)
      WHERE x.item->>'orderItemId'=v_item.id::text;
    IF v_req IS NULL THEN RAISE EXCEPTION 'Delivery update must include every order item'; END IF;
    v_original := v_original+(v_item.quantity*v_item.unit_price);
    v_qty := (v_req->>'deliveredQuantity')::integer;
    v_confirmed := (v_req->>'deliveryConfirmed')::boolean;
    IF v_qty<0 OR v_qty>v_item.quantity OR (v_confirmed AND v_qty=0) THEN
      RAISE EXCEPTION 'Delivered quantity is outside the order-item bounds';
    END IF;
    SELECT * INTO v_prev FROM public.shop_delivery_items WHERE order_item_id=v_item.id FOR UPDATE;
    IF FOUND AND v_prev.refund_status='refunded' AND
       (v_qty<>v_prev.delivered_quantity OR NOT v_confirmed) THEN
      RAISE EXCEPTION 'A processed refund prevents changing delivered quantities';
    END IF;
    IF FOUND AND v_prev.delivery_confirmed AND (NOT v_confirmed OR v_qty<v_prev.delivered_quantity) THEN
      RAISE EXCEPTION 'A confirmed delivery cannot be unchecked or reduced';
    END IF;
    IF p_mode='submit' THEN
      v_confirmed := coalesce(v_prev.delivery_confirmed,false);
    END IF;
    IF v_confirmed THEN
      v_delivered := v_delivered+v_qty;
      v_delivered_value := v_delivered_value+(v_qty*v_item.unit_price);
    END IF;
    v_ordered := v_ordered+v_item.quantity;
    v_adjustment := v_adjustment+((v_item.quantity-CASE WHEN v_confirmed THEN v_qty ELSE 0 END)*v_item.unit_price);

    INSERT INTO public.shop_delivery_items
      (order_item_id,order_id,delivered,delivered_quantity,undelivered_quantity,
       delivered_amount,refund_amount,refund_status,recorded_by,delivered_at,updated_at,delivery_confirmed)
    VALUES (v_item.id,v_order.order_id,(v_confirmed AND v_qty=v_item.quantity),v_qty,
      v_item.quantity-CASE WHEN v_confirmed THEN v_qty ELSE 0 END,
      CASE WHEN v_confirmed THEN round(v_qty*v_item.unit_price,2) ELSE 0 END,
      round((v_item.quantity-CASE WHEN v_confirmed THEN v_qty ELSE 0 END)*v_item.unit_price,2),
      CASE WHEN v_confirmed AND v_qty<v_item.quantity THEN 'pending_admin_review'
           WHEN v_confirmed THEN 'not_required' ELSE 'not_required' END,
      v_employee.id,CASE WHEN v_confirmed THEN coalesce(v_prev.delivered_at,CURRENT_TIMESTAMP) ELSE NULL END,
      CURRENT_TIMESTAMP,v_confirmed)
    ON CONFLICT (order_item_id) DO UPDATE SET
      delivered=EXCLUDED.delivered,delivered_quantity=EXCLUDED.delivered_quantity,
      undelivered_quantity=EXCLUDED.undelivered_quantity,delivered_amount=EXCLUDED.delivered_amount,
      refund_amount=EXCLUDED.refund_amount,
      refund_status=CASE WHEN shop_delivery_items.refund_status='refunded' AND EXCLUDED.refund_amount>0
        THEN shop_delivery_items.refund_status ELSE EXCLUDED.refund_status END,
      recorded_by=EXCLUDED.recorded_by,
      delivered_at=CASE WHEN EXCLUDED.delivery_confirmed THEN coalesce(shop_delivery_items.delivered_at,CURRENT_TIMESTAMP) ELSE NULL END,
      updated_at=CURRENT_TIMESTAMP,delivery_confirmed=EXCLUDED.delivery_confirmed;
  END LOOP;

  IF v_ordered=0 THEN RAISE EXCEPTION 'Order has no products'; END IF;
  SELECT coalesce(sum(oi.quantity),0)::integer INTO v_ordered FROM public.order_items oi WHERE oi.order_id=v_order.order_id;
  SELECT coalesce(sum(d.delivered_quantity) FILTER (WHERE d.delivery_confirmed),0)::integer,
         coalesce(sum(d.refund_amount),0)::numeric(12,2),
         coalesce(sum(d.delivered_amount),0)::numeric(12,2)
    INTO v_delivered,v_adjustment,v_delivered_value
    FROM public.shop_delivery_items d WHERE d.order_id=v_order.order_id;
  IF p_mode='confirm' AND v_delivered=0 THEN RAISE EXCEPTION 'Confirm at least one delivered product'; END IF;
  v_status := CASE WHEN v_delivered=v_ordered THEN 'Delivered'
                   WHEN v_delivered>0 THEN 'Partially Delivered' ELSE 'Pending' END;
  v_cod := lower(trim(coalesce(v_order.payment_method,''))) IN ('cod','cash on delivery');
  IF coalesce(p_cash_collected,false) AND (NOT v_cod OR v_delivered<>v_ordered) THEN
    RAISE EXCEPTION 'Cash can be recorded only for a fully delivered COD order';
  END IF;
  IF coalesce(p_cash_collected,false) THEN
    IF lower(coalesce(v_order.payment_status,''))='paid' AND NOT EXISTS (
      SELECT 1 FROM public.shop_cash_collections WHERE order_id=v_order.order_id
    ) THEN RAISE EXCEPTION 'COD payment is already marked paid; verify the collection record before retrying'; END IF;
    INSERT INTO public.shop_cash_collections(order_id,employee_id,auth_user_id,amount)
      VALUES(v_order.order_id,v_employee.id,p_auth_user_id,coalesce(v_order.grand_total,0))
      ON CONFLICT(order_id) DO NOTHING;
    IF NOT EXISTS(SELECT 1 FROM public.shop_cash_collections c WHERE c.order_id=v_order.order_id
      AND c.employee_id=v_employee.id AND c.auth_user_id=p_auth_user_id
      AND c.amount=coalesce(v_order.grand_total,0)) THEN
      RAISE EXCEPTION 'Cash collection was already recorded by another operation';
    END IF;
    UPDATE public.orders SET payment_status='paid' WHERE order_id=v_order.order_id;
    v_cash := true;
  ELSE
    v_cash := v_cod AND EXISTS(SELECT 1 FROM public.shop_cash_collections c WHERE c.order_id=v_order.order_id);
  END IF;
  UPDATE public.orders SET status=v_status WHERE order_id=v_order.order_id;
  IF p_mode='confirm' AND v_adjustment>0 AND v_delivered<v_ordered THEN
    DELETE FROM public.shop_admin_notifications WHERE order_id=v_order.order_id;
    INSERT INTO public.shop_admin_notifications(order_id,employee_id,notification_type,message,refund_amount,created_at)
      VALUES(v_order.order_id,v_employee.id,
        CASE WHEN v_delivered=0 THEN 'undelivered_refund' ELSE 'partial_delivery' END,
        CASE WHEN v_delivered=0 THEN 'Undelivered order' ELSE 'Partial delivery' END||' recorded for order '||v_order.order_id||'. Refund pending review.',
        v_adjustment,CURRENT_TIMESTAMP);
  ELSIF v_status='Delivered' THEN
    DELETE FROM public.shop_admin_notifications WHERE order_id=v_order.order_id;
  END IF;
  RETURN jsonb_build_object('success',true,'status',v_status,'paymentStatus',
    CASE WHEN v_cash THEN 'paid' ELSE v_order.payment_status END,'cashCollected',v_cash,
    'orderedQuantity',v_ordered,'deliveredQuantity',v_delivered,
    'undeliveredQuantity',v_ordered-v_delivered,'deliveredValue',round(v_delivered_value,2),
    'refundAmount',round(v_adjustment,2),'originalOrderValue',round(v_original,2));
END;
$$;

REVOKE ALL ON FUNCTION public.ro_submit_shop_delivery(uuid,text,text,jsonb,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ro_submit_shop_delivery(uuid,text,text,jsonb,boolean) TO service_role;
COMMIT;
