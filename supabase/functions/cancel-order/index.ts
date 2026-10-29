import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import {
  authenticatedUser, errorResponse, HttpError, jsonResponse, postBody,
  safeRpcError, serviceClient,
} from '../_shared/checkout_http.ts';

// COD-only pre-fulfillment cancellation. Paid orders require a verified
// Razorpay refund workflow and are intentionally rejected by the database RPC.
serve(async request => {
  if (request.method === 'OPTIONS') return jsonResponse({ ok: true });
  if (request.method !== 'POST') return jsonResponse({ success: false, error: 'Method not allowed.' }, 405);
  try {
    const authUser = await authenticatedUser(request);
    const body = await postBody(request);
    const orderId = String(body.orderId ?? '').trim();
    if (!orderId || orderId.length > 64) throw new HttpError(400, 'Order cancellation request is invalid.');
    const { data, error } = await serviceClient().rpc('ro_cancel_checkout_order', {
      p_auth_user_id: authUser.id,
      p_order_id: orderId,
    });
    if (error) {
      const status = error.code === '42501' ? 403 : 409;
      throw new HttpError(status, safeRpcError(error, 'Order could not be cancelled.'));
    }
    return jsonResponse(data);
  } catch (error) { return errorResponse(error); }
});
