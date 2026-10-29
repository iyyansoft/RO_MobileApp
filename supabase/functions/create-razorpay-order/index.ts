import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { quoteCheckout } from '../_shared/checkout_core.mjs';
import {
  approvedDealerId, authenticatedUser, errorResponse, HttpError, jsonResponse,
  postBody, requiredRequestId, razorpayRequest, safeRpcError, serviceClient, validateShopRoute,
} from '../_shared/checkout_http.ts';

serve(async request => {
  if (request.method === 'OPTIONS') return jsonResponse({ ok: true });
  if (request.method !== 'POST') return jsonResponse({ success: false, error: 'Method not allowed.' }, 405);
  try {
    const authUser = await authenticatedUser(request);
    const body = await postBody(request);
    const requestId = requiredRequestId(body.requestId);
    const checkout = body.checkout;
    if (!checkout || typeof checkout !== 'object' || Array.isArray(checkout)) throw new HttpError(400, 'Invalid checkout request.');
    const service = serviceClient();
    const dealerId = await approvedDealerId(service, authUser.id);
    const rawItems = (checkout as Record<string, unknown>).items;
    if (!Array.isArray(rawItems) || rawItems.length === 0) throw new HttpError(400, 'Add products before checkout.');
    const productIds = [...new Set(rawItems.map(item => String((item as Record<string, unknown>)?.id ?? '')).filter(Boolean))];
    const { data: products, error: productError } = await service.from('products')
      .select('id,name,brand,price,img,stock_quantity,status')
      .in('id', productIds);
    if (productError) throw new HttpError(503, 'Products could not be verified for checkout.');
    const { data: dealer, error: dealerError } = await service.from('users').select('business_name').eq('id', dealerId).single();
    if (dealerError) throw new HttpError(503, 'Dealer profile could not be verified.');
    const profile = { id: dealerId, status: 'approved', is_approved: true, email_verified: true, business_name: dealer.business_name };
    const quote = quoteCheckout(checkout, products ?? [], profile);
    if (quote.paymentMethod !== 'Razorpay') throw new HttpError(400, 'Select Razorpay to start online payment.');
    await validateShopRoute(service);

    const { data: existing, error: existingError } = await service.rpc('ro_get_checkout_session', {
      p_auth_user_id: authUser.id,
      p_request_id: requestId,
    });
    if (existingError) throw new HttpError(503, 'Checkout session could not be checked.');
    if (existing?.status === 'completed') throw new HttpError(409, 'This checkout has already been completed.');
    if (existing?.gatewayOrderId) {
      const { data: fingerprint, error: fingerprintError } = await service.rpc('ro_checkout_fingerprint', { p_payload: checkout });
      if (fingerprintError || fingerprint !== existing.requestFingerprint) {
        throw new HttpError(409, 'Checkout details changed. Refresh and start a new checkout.');
      }
      return jsonResponse({ success: true, order: {
        id: existing.gatewayOrderId, amount: existing.amountPaise, currency: 'INR',
        key: Deno.env.get('RAZORPAY_KEY_ID'),
      } });
    }

    const gateway = await razorpayRequest('orders', 'POST', {
      amount: Math.round(quote.grandTotal * 100), currency: 'INR',
      receipt: requestId.replaceAll('-', ''), notes: { checkout_request_id: requestId },
    });
    const gatewayId = String(gateway.id ?? '');
    const amount = Number(gateway.amount);
    if (!gatewayId || amount !== Math.round(quote.grandTotal * 100) || gateway.currency !== 'INR') {
      throw new HttpError(502, 'Razorpay returned an invalid checkout order.');
    }
    const { data: registered, error: registerError } = await service.rpc('ro_register_razorpay_checkout', {
      p_auth_user_id: authUser.id,
      p_request_id: requestId,
      p_payload: checkout,
      p_gateway_order_id: gatewayId,
      p_amount_paise: amount,
    });
    if (registerError) throw new HttpError(409, safeRpcError(registerError, 'Checkout changed while payment was starting. Refresh and retry.'));
    return jsonResponse({ success: true, order: {
      id: registered.gatewayOrderId, amount: registered.amountPaise, currency: 'INR',
      key: Deno.env.get('RAZORPAY_KEY_ID'),
    } });
  } catch (error) { return errorResponse(error); }
});
