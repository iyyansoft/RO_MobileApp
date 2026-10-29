-- Local staging migration: dealer-owned order/history reads and support-ticket
-- creation. Order/checkout/payment writes stay on Express.
-- Prerequisites: 002_dealer_profile_addresses.sql; auth_user_id is linked.
-- Project-target identity is NOT encoded in SQL; independently verify staging.
BEGIN;
DO $$
DECLARE v_missing text[];
BEGIN
  IF to_regclass('public.orders') IS NULL OR to_regclass('public.order_items') IS NULL OR
     to_regclass('public.rewards_history') IS NULL OR to_regclass('public.support_tickets') IS NULL OR
     to_regprocedure('public.current_dealer_id()') IS NULL OR
     to_regprocedure('auth.uid()') IS NULL OR to_regprocedure('auth.jwt()') IS NULL THEN
    RAISE EXCEPTION 'Order-history stage requires existing tables and linked-dealer helper';
  END IF;
  SELECT array_agg(required.table_name || '.' || required.column_name ORDER BY required.table_name,required.column_name)
    INTO v_missing
  FROM (VALUES
    ('orders','order_id'),('orders','user_id'),('orders','user_email'),
    ('orders','user_name'),('orders','user_business'),('orders','subtotal'),
    ('orders','discount'),('orders','gst'),('orders','delivery_fee'),
    ('orders','grand_total'),('orders','with_gst'),('orders','payment_status'),
    ('orders','payment_method'),('orders','billing_address'),('orders','company_name'),
    ('orders','gstin'),('orders','pan_number'),('orders','same_as_delivery'),
    ('orders','delivery_address'),('orders','delivery_note'),('orders','status'),
    ('orders','invoice_number'),('orders','created_at'),
    ('order_items','id'),('order_items','order_id'),('order_items','product_id'),
    ('order_items','product_name'),('order_items','brand'),('order_items','unit_price'),
    ('order_items','quantity'),('order_items','moq'),('order_items','img_src'),('order_items','sku'),
    ('rewards_history','user_id'),('rewards_history','id'),('rewards_history','order_id'),
    ('rewards_history','order_amount'),('rewards_history','points_earned'),('rewards_history','created_at'),
    ('support_tickets','id'),('support_tickets','user_id'),('support_tickets','user_email'),
    ('support_tickets','subject'),('support_tickets','message'),('support_tickets','status'),
    ('support_tickets','created_at')
  ) AS required(table_name,column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema='public' AND c.table_name=required.table_name
      AND c.column_name=required.column_name
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Order-history schema is incompatible; missing columns: %',array_to_string(v_missing,', ');
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
    AND tablename IN ('orders','order_items','rewards_history','support_tickets')) THEN
    RAISE EXCEPTION 'Dealer-history RLS policies already exist; inspect and reconcile them before this one-time migration';
  END IF;
END;
$$;

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rewards_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

-- Legacy order/ticket rows may have a NULL user_id. Do not authorize their
-- email fallback from a client-editable/unverified JWT email claim. Resolve it
-- from the Auth record and require email confirmation instead.
CREATE OR REPLACE FUNCTION public.current_verified_auth_email()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=auth,pg_temp AS $$
  SELECT lower(au.email::text)
  FROM auth.users au
  WHERE au.id=auth.uid() AND au.email_confirmed_at IS NOT NULL
  LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.current_verified_auth_email() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.current_verified_auth_email() TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='orders' AND policyname='ro_orders_self_read') THEN
    CREATE POLICY ro_orders_self_read ON public.orders FOR SELECT TO authenticated
      USING (user_id=public.current_dealer_id() OR
        (user_id IS NULL AND public.current_verified_auth_email() IS NOT NULL
          AND lower(user_email::text)=public.current_verified_auth_email()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='order_items' AND policyname='ro_order_items_self_read') THEN
    CREATE POLICY ro_order_items_self_read ON public.order_items FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM public.orders o WHERE o.order_id=order_items.order_id AND
        (o.user_id=public.current_dealer_id() OR (o.user_id IS NULL AND
          public.current_verified_auth_email() IS NOT NULL
          AND lower(o.user_email::text)=public.current_verified_auth_email()))));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='rewards_history' AND policyname='ro_rewards_self_read') THEN
    CREATE POLICY ro_rewards_self_read ON public.rewards_history FOR SELECT TO authenticated
      USING (user_id=public.current_dealer_id());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='support_tickets' AND policyname='ro_support_self_read') THEN
    CREATE POLICY ro_support_self_read ON public.support_tickets FOR SELECT TO authenticated
      USING (user_id=public.current_dealer_id() OR (user_id IS NULL AND
        public.current_verified_auth_email() IS NOT NULL
        AND lower(user_email::text)=public.current_verified_auth_email()));
  END IF;
END;
$$;

REVOKE ALL PRIVILEGES ON TABLE public.orders,public.order_items,
  public.rewards_history,public.support_tickets FROM PUBLIC,anon,authenticated;
GRANT SELECT (order_id,user_id,user_email,user_name,user_business,subtotal,discount,gst,
  delivery_fee,grand_total,with_gst,payment_status,payment_method,billing_address,company_name,
  gstin,pan_number,same_as_delivery,delivery_address,delivery_note,status,
  invoice_number,created_at) ON public.orders TO authenticated;
GRANT SELECT (id,order_id,product_id,product_name,brand,unit_price,quantity,moq,img_src,sku)
  ON public.order_items TO authenticated;
GRANT SELECT (user_id,id,order_id,order_amount,points_earned,created_at)
  ON public.rewards_history TO authenticated;
GRANT SELECT (id,user_id,user_email,subject,message,status,created_at)
  ON public.support_tickets TO authenticated;

DO $$
DECLARE v_sequence text;
BEGIN
  v_sequence := pg_get_serial_sequence('public.support_tickets','id');
  IF v_sequence IS NOT NULL THEN
    EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM PUBLIC,anon,authenticated',v_sequence::regclass);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.ro_create_support_ticket(p_subject varchar,p_message text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,auth,pg_temp AS $$
DECLARE v_dealer_id varchar; v_email text; v_ticket_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT email INTO v_email FROM auth.users WHERE id=auth.uid() AND email_confirmed_at IS NOT NULL;
  IF v_email IS NULL THEN RAISE EXCEPTION 'Verified email required' USING ERRCODE='28000'; END IF;
  v_dealer_id := public.current_dealer_id();
  IF v_dealer_id IS NULL THEN RAISE EXCEPTION 'Dealer profile required' USING ERRCODE='28000'; END IF;
  IF p_subject IS NULL OR length(trim(p_subject))=0 OR length(p_subject)>255 OR
     p_message IS NULL OR length(trim(p_message))=0 OR length(p_message)>10000 THEN
    RAISE EXCEPTION 'Invalid support ticket' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.support_tickets(user_id,user_email,subject,message)
    VALUES(v_dealer_id,lower(v_email),trim(p_subject),p_message)
    RETURNING id INTO v_ticket_id;
  RETURN v_ticket_id;
END;
$$;
REVOKE ALL ON FUNCTION public.ro_create_support_ticket(varchar,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ro_create_support_ticket(varchar,text) TO authenticated;
COMMIT;
