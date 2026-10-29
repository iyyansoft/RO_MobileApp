import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import {
  authenticatedUser, errorResponse, HttpError, jsonResponse, postBody,
  requiredRequestId, safeRpcError, serviceClient,
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
    if ((checkout as Record<string, unknown>).paymentMethod !== 'Cash on Delivery') {
      throw new HttpError(400, 'Select Cash on Delivery to place this order.');
    }
    const service = serviceClient();
    const { data, error } = await service.rpc('ro_finalize_checkout', {
      p_auth_user_id: authUser.id,
      p_request_id: requestId,
      p_payload: checkout,
      p_gateway_order_id: null,
      p_payment_id: null,
      p_shop_default_name: Deno.env.get('SHOP_DEFAULT_NAME') ?? null,
    });
    if (error) throw new HttpError(400, safeRpcError(error, 'Order could not be saved.'));
    return jsonResponse(data);
  } catch (error) { return errorResponse(error); }
});
