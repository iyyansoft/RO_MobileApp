-- Local draft only. Adds a private, idempotent audit/recovery record for a
-- captured Razorpay payment that cannot be finalized into an order.
-- Do not execute against the live project without separate review/approval.
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.checkout_sessions') IS NULL THEN
    RAISE EXCEPTION 'Checkout refund reconciliation requires checkout_sessions';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.checkout_refund_reconciliations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  request_id uuid NOT NULL,
  gateway_order_id varchar(100) NOT NULL,
  payment_id varchar(100) NOT NULL UNIQUE,
  amount_paise bigint NOT NULL CHECK (amount_paise > 0),
  reason_code varchar(40) NOT NULL CHECK (reason_code IN (
    'stock_changed','product_unavailable','dealer_not_approved','shop_route_invalid'
  )),
  state varchar(20) NOT NULL DEFAULT 'pending' CHECK (state IN (
    'pending','processing','submitted','refunded','needs_review'
  )),
  razorpay_refund_id varchar(100),
  provider_status varchar(24),
  safe_error_code varchar(40),
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (auth_user_id, request_id, payment_id)
);
CREATE INDEX IF NOT EXISTS idx_checkout_refund_reconciliations_state_created
  ON public.checkout_refund_reconciliations (state, created_at);
ALTER TABLE public.checkout_refund_reconciliations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.checkout_refund_reconciliations FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.checkout_refund_reconciliations TO service_role;

CREATE OR REPLACE FUNCTION public.ro_open_checkout_refund_reconciliation(
  p_auth_user_id uuid, p_request_id uuid, p_gateway_order_id text,
  p_payment_id text, p_amount_paise bigint, p_reason_code text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_session public.checkout_sessions%ROWTYPE;
  v_record public.checkout_refund_reconciliations%ROWTYPE;
BEGIN
  IF p_auth_user_id IS NULL OR p_request_id IS NULL OR
     coalesce(p_gateway_order_id,'')='' OR coalesce(p_payment_id,'')='' OR
     p_amount_paise <= 0 OR p_reason_code NOT IN (
       'stock_changed','product_unavailable','dealer_not_approved','shop_route_invalid'
     ) THEN
    RAISE EXCEPTION 'Payment reconciliation request is invalid';
  END IF;
  SELECT * INTO v_session FROM public.checkout_sessions
    WHERE auth_user_id=p_auth_user_id AND request_id=p_request_id FOR UPDATE;
  IF NOT FOUND OR v_session.status <> 'razorpay_pending' OR
     v_session.gateway_order_id IS DISTINCT FROM p_gateway_order_id OR
     v_session.amount_paise IS DISTINCT FROM p_amount_paise OR
     v_session.order_id IS NOT NULL THEN
    RAISE EXCEPTION 'Captured payment does not match an unfinished checkout';
  END IF;

  INSERT INTO public.checkout_refund_reconciliations
    (auth_user_id,request_id,gateway_order_id,payment_id,amount_paise,reason_code)
  VALUES (p_auth_user_id,p_request_id,p_gateway_order_id,p_payment_id,p_amount_paise,p_reason_code)
  ON CONFLICT (payment_id) DO NOTHING;
  SELECT * INTO v_record FROM public.checkout_refund_reconciliations
    WHERE payment_id=p_payment_id FOR UPDATE;
  IF v_record.auth_user_id <> p_auth_user_id OR v_record.request_id <> p_request_id OR
     v_record.gateway_order_id <> p_gateway_order_id OR v_record.amount_paise <> p_amount_paise THEN
    RAISE EXCEPTION 'Payment is already associated with another reconciliation';
  END IF;
  RETURN jsonb_build_object('state',v_record.state,'paymentId',v_record.payment_id,
    'amountPaise',v_record.amount_paise,'razorpayRefundId',v_record.razorpay_refund_id,
    'providerStatus',v_record.provider_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.ro_claim_checkout_refund(p_payment_id text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_record public.checkout_refund_reconciliations%ROWTYPE; v_claimed boolean := false;
BEGIN
  SELECT * INTO v_record FROM public.checkout_refund_reconciliations
    WHERE payment_id=p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment reconciliation was not found'; END IF;
  IF v_record.state='pending' THEN
    UPDATE public.checkout_refund_reconciliations SET state='processing',updated_at=CURRENT_TIMESTAMP
      WHERE payment_id=p_payment_id RETURNING * INTO v_record;
    v_claimed := true;
  END IF;
  RETURN jsonb_build_object('claimed',v_claimed,'state',v_record.state,
    'amountPaise',v_record.amount_paise,'paymentId',v_record.payment_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.ro_set_checkout_refund_state(
  p_payment_id text, p_state text, p_refund_id text DEFAULT NULL,
  p_provider_status text DEFAULT NULL, p_safe_error_code text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_record public.checkout_refund_reconciliations%ROWTYPE;
BEGIN
  IF p_state NOT IN ('submitted','refunded','needs_review') THEN
    RAISE EXCEPTION 'Payment reconciliation state is invalid';
  END IF;
  IF p_provider_status IS NOT NULL AND p_provider_status NOT IN ('created','pending','processed') THEN
    RAISE EXCEPTION 'Payment provider status is invalid';
  END IF;
  UPDATE public.checkout_refund_reconciliations SET state=p_state,
    razorpay_refund_id=coalesce(p_refund_id,razorpay_refund_id),
    provider_status=coalesce(p_provider_status,provider_status),
    safe_error_code=coalesce(left(nullif(p_safe_error_code,''),40),safe_error_code),updated_at=CURRENT_TIMESTAMP
  WHERE payment_id=p_payment_id RETURNING * INTO v_record;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment reconciliation was not found'; END IF;
  RETURN jsonb_build_object('state',v_record.state,'paymentId',v_record.payment_id,
    'razorpayRefundId',v_record.razorpay_refund_id,'providerStatus',v_record.provider_status);
END;
$$;

REVOKE ALL ON FUNCTION public.ro_open_checkout_refund_reconciliation(uuid,uuid,text,text,bigint,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ro_claim_checkout_refund(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ro_set_checkout_refund_state(text,text,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_open_checkout_refund_reconciliation(uuid,uuid,text,text,bigint,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ro_claim_checkout_refund(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ro_set_checkout_refund_state(text,text,text,text,text) TO service_role;

COMMIT;
