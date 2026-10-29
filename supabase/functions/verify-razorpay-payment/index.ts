import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { completedCheckoutReplay, validateRazorpayPayment } from '../_shared/checkout_core.mjs';
import { definitiveFinalizeFailure, findMatchingRefund, refundRecordState } from '../_shared/checkout_refund_core.mjs';
import {
  approvedDealerId, authenticatedUser, errorResponse, HttpError, jsonResponse,
  postBody, requiredRequestId, razorpayRequest, safeRpcError, serviceClient, verifySignature,
} from '../_shared/checkout_http.ts';

function refundReason(message: string): string | null {
  if (message.startsWith('Not enough stock for ')) return 'stock_changed';
  if (message.startsWith('A product is no longer available')) return 'product_unavailable';
  if (message.startsWith('Dealer account is not approved')) return 'dealer_not_approved';
  if (message.startsWith('Configured default shop') || message.startsWith('Order cannot be routed:')) return 'shop_route_invalid';
  return null;
}

async function reconcileCapturedPayment(
  service: ReturnType<typeof serviceClient>,
  authUserId: string,
  requestId: string,
  gatewayOrderId: string,
  paymentId: string,
  amountPaise: number,
  reasonCode: string,
): Promise<string> {
  const { data: record, error: openError } = await service.rpc('ro_open_checkout_refund_reconciliation', {
    p_auth_user_id: authUserId,
    p_request_id: requestId,
    p_gateway_order_id: gatewayOrderId,
    p_payment_id: paymentId,
    p_amount_paise: amountPaise,
    p_reason_code: reasonCode,
  });
  if (openError || !record) throw new HttpError(503, 'Payment was captured, but refund tracking could not be saved. Do not pay again; contact support.');

  // Always check the provider before retrying a refund. A timeout can occur
  // after Razorpay accepted the first request but before this function saved it.
  let providerRefunds: Record<string, unknown>;
  try {
    providerRefunds = await razorpayRequest(`payments/${encodeURIComponent(paymentId)}/refunds`);
  } catch {
    if (record.state === 'pending') {
      await service.rpc('ro_set_checkout_refund_state', {
        p_payment_id: paymentId, p_state: 'needs_review', p_safe_error_code: 'provider_lookup_failed',
      });
    }
    throw new HttpError(503, 'Payment was captured. Refund status could not be verified; do not pay again and contact support.');
  }
  const priorRefund = findMatchingRefund(providerRefunds, { amountPaise, paymentId });
  if (priorRefund) {
    const state = refundRecordState(String(priorRefund.status));
    const { error } = await service.rpc('ro_set_checkout_refund_state', {
      p_payment_id: paymentId,
      p_state: state,
      p_refund_id: String(priorRefund.id ?? ''),
      p_provider_status: String(priorRefund.status),
    });
    if (error) throw new HttpError(503, 'Razorpay has a refund record, but its status could not be saved. Do not pay again; contact support.');
    return state;
  }

  if (record.state !== 'pending') {
    await service.rpc('ro_set_checkout_refund_state', {
      p_payment_id: paymentId, p_state: 'needs_review', p_safe_error_code: 'provider_refund_not_found',
    });
    throw new HttpError(503, 'Payment was captured, but its refund needs manual reconciliation. Do not pay again; contact support.');
  }
  const { data: claim, error: claimError } = await service.rpc('ro_claim_checkout_refund', { p_payment_id: paymentId });
  if (claimError || !claim) throw new HttpError(503, 'Payment was captured; refund processing needs reconciliation. Do not pay again; contact support.');
  if (claim.claimed !== true) {
    throw new HttpError(503, 'Payment was captured and refund processing is in progress. Do not pay again.');
  }

  try {
    const created = await razorpayRequest(`payments/${encodeURIComponent(paymentId)}/refund`, 'POST', {
      amount: amountPaise,
      notes: { checkout_request_id: requestId, reconciliation: 'order_finalization_failed' },
    });
    const matched = findMatchingRefund([created], { amountPaise, paymentId });
    if (!matched) throw new Error('provider_refund_mismatch');
    const state = refundRecordState(String(matched.status));
    const { error } = await service.rpc('ro_set_checkout_refund_state', {
      p_payment_id: paymentId,
      p_state: state,
      p_refund_id: String(matched.id ?? ''),
      p_provider_status: String(matched.status),
    });
    if (error) throw new Error('reconciliation_write_failed');
    return state;
  } catch {
    // Never blindly repeat a refund POST. The next attempt first queries
    // Razorpay and records a manual-review state if no matching refund exists.
    await service.rpc('ro_set_checkout_refund_state', {
      p_payment_id: paymentId, p_state: 'needs_review', p_safe_error_code: 'refund_outcome_unknown',
    });
    throw new HttpError(503, 'Payment was captured; refund outcome needs reconciliation. Do not pay again; contact support.');
  }
}

serve(async request => {
  if (request.method === 'OPTIONS') return jsonResponse({ ok: true });
  if (request.method !== 'POST') return jsonResponse({ success: false, error: 'Method not allowed.' }, 405);
  try {
    const authUser = await authenticatedUser(request);
    const body = await postBody(request);
    const requestId = requiredRequestId(body.requestId);
    const checkout = body.checkout;
    if (!checkout || typeof checkout !== 'object' || Array.isArray(checkout)) throw new HttpError(400, 'Invalid checkout request.');
    const gatewayOrderId = String(body.razorpay_order_id ?? '');
    const paymentId = String(body.razorpay_payment_id ?? '');
    const signature = String(body.razorpay_signature ?? '');
    if (!gatewayOrderId || !paymentId || !signature) throw new HttpError(400, 'Payment confirmation is incomplete.');
    const service = serviceClient();
    await approvedDealerId(service, authUser.id);
    const { data: session, error: sessionError } = await service.from('checkout_sessions')
      .select('gateway_order_id,amount_paise,status,order_id,payment_id,request_fingerprint')
      .eq('auth_user_id', authUser.id).eq('request_id', requestId).maybeSingle();
    if (sessionError || !session) throw new HttpError(400, 'Payment checkout was not found.');
    const { data: fingerprint, error: fingerprintError } = await service.rpc('ro_checkout_fingerprint', { p_payload: checkout });
    if (fingerprintError || fingerprint !== session.request_fingerprint) {
      throw new HttpError(409, 'Checkout details changed. Retry with the original checkout information.');
    }
    let replay: { orderId: string; paymentStatus: string } | null;
    try { replay = completedCheckoutReplay(session, paymentId); }
    catch (error) { throw new HttpError(409, error instanceof Error ? error.message : 'A different payment already completed this checkout.'); }
    if (replay) {
      return jsonResponse({ success: true, idempotent: true, order: replay });
    }
    if (session.gateway_order_id !== gatewayOrderId || !Number.isSafeInteger(Number(session.amount_paise))) {
      throw new HttpError(400, 'Payment does not match this checkout.');
    }
    const { data: priorRecovery, error: recoveryReadError } = await service
      .from('checkout_refund_reconciliations')
      .select('state')
      .eq('auth_user_id', authUser.id)
      .eq('request_id', requestId)
      .eq('payment_id', paymentId)
      .maybeSingle();
    if (recoveryReadError) throw new HttpError(503, 'Payment recovery status could not be checked. Do not pay again; retry or contact support.');
    if (priorRecovery) {
      if (priorRecovery.state === 'refunded') {
        throw new HttpError(409, 'This payment has already been refunded; it cannot be used to place an order.');
      }
      if (priorRecovery.state === 'submitted') {
        throw new HttpError(409, 'A refund is pending with Razorpay; this payment cannot be used to place an order.');
      }
      throw new HttpError(503, 'This captured payment is under refund reconciliation; do not pay again and contact support.');
    }
    await verifySignature(gatewayOrderId, paymentId, signature);
    let payment = await razorpayRequest(`payments/${encodeURIComponent(paymentId)}`);
    const paymentStatus = validateRazorpayPayment(payment, {
      paymentId, gatewayOrderId, amountPaise: session.amount_paise,
    });
    if (paymentStatus === 'authorized') {
      payment = await razorpayRequest(`payments/${encodeURIComponent(paymentId)}/capture`, 'POST', {
        amount: Number(session.amount_paise), currency: 'INR',
      });
    }
    if (validateRazorpayPayment(payment, {
      paymentId, gatewayOrderId, amountPaise: session.amount_paise,
    }) !== 'captured') throw new HttpError(409, 'Payment has not been captured. Retry verification before placing another order.');
    const { data, error } = await service.rpc('ro_finalize_checkout', {
      p_auth_user_id: authUser.id,
      p_request_id: requestId,
      p_payload: checkout,
      p_gateway_order_id: gatewayOrderId,
      p_payment_id: paymentId,
      p_shop_default_name: Deno.env.get('SHOP_DEFAULT_NAME') ?? null,
    });
    if (error) {
      const safe = safeRpcError(error, 'Payment was confirmed, but order finalization needs retry. Do not pay again; retry order confirmation.');
      if (definitiveFinalizeFailure(error.code, safe)) {
        const reason = refundReason(safe);
        if (!reason) throw new HttpError(503, 'Payment was captured, but order finalization was rejected. Do not pay again; contact support.');
        const refundState = await reconcileCapturedPayment(
          service, authUser.id, requestId, gatewayOrderId, paymentId,
          Number(session.amount_paise), reason,
        );
        if (refundState === 'refunded') {
          throw new HttpError(409, 'Payment was captured, the order could not be completed, and the refund was processed.');
        }
        if (refundState === 'submitted') {
          throw new HttpError(409, 'Payment was captured, the order could not be completed, and a refund is pending with Razorpay.');
        }
        throw new HttpError(503, 'Payment was captured; refund reconciliation is required. Do not pay again; contact support.');
      }
      throw new HttpError(503, safe);
    }
    return jsonResponse(data);
  } catch (error) { return errorResponse(error); }
});
