const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export class ShopDeliveryError extends Error {
  constructor(status, message) {
    super(message);
    this.name = 'ShopDeliveryError';
    this.status = status;
  }
}

export function createShopDeliveryHandler({ authenticate, submit }) {
  return async request => {
    if (request.method === 'OPTIONS') return response({ ok: true });
    if (request.method !== 'POST') return response({ success: false, error: 'Method not allowed.' }, 405);
    try {
      const user = await authenticate(request);
      if (!user) throw new ShopDeliveryError(401, 'Sign in again to submit delivery details.');
      if (!user.email_confirmed_at || user.app_metadata?.role !== 'shop_employee') {
        throw new ShopDeliveryError(403, 'An active, verified Shop Employee account is required.');
      }
      const raw = await request.text();
      if (raw.length > 128 * 1024) throw new ShopDeliveryError(413, 'Delivery request is too large.');
      let body;
      try { body = JSON.parse(raw); } catch { throw new ShopDeliveryError(400, 'Delivery request is invalid.'); }
      if (!body || typeof body !== 'object' || Array.isArray(body)) {
        throw new ShopDeliveryError(400, 'Delivery request is invalid.');
      }
      const orderId = typeof body.orderId === 'string' ? body.orderId.trim() : '';
      const mode = body.mode;
      const items = body.items;
      if (!orderId || orderId.length > 64 || !['submit', 'confirm'].includes(mode) ||
          !Array.isArray(items) || items.length < 1 || items.length > 500 ||
          (body.cashCollected !== undefined && typeof body.cashCollected !== 'boolean')) {
        throw new ShopDeliveryError(400, 'Delivery request is invalid.');
      }
      const seen = new Set();
      const cleanItems = items.map(item => {
        if (!item || typeof item !== 'object' || Array.isArray(item) ||
            !Number.isSafeInteger(item.orderItemId) || item.orderItemId <= 0 ||
            !Number.isSafeInteger(item.deliveredQuantity) || item.deliveredQuantity < 0 ||
            item.deliveredQuantity > 2_147_483_647 ||
            typeof item.deliveryConfirmed !== 'boolean' || seen.has(item.orderItemId)) {
          throw new ShopDeliveryError(400, 'Each product needs one whole Actual Qty and an explicit Delivered selection.');
        }
        seen.add(item.orderItemId);
        return {
          orderItemId: item.orderItemId,
          deliveredQuantity: item.deliveredQuantity,
          deliveryConfirmed: item.deliveryConfirmed,
        };
      });
      if (mode === 'submit' && body.cashCollected === true) {
        throw new ShopDeliveryError(400, 'Cash collection can only be confirmed with delivery.');
      }
      const result = await submit({
        authUserId: user.id,
        orderId,
        mode,
        items: cleanItems,
        cashCollected: body.cashCollected === true,
      });
      return response({ success: true, delivery: result });
    } catch (error) {
      const status = error instanceof ShopDeliveryError ? error.status : mapRpcStatus(error);
      const message = error instanceof ShopDeliveryError ? error.message : safeRpcMessage(error);
      return response({ success: false, error: message }, status);
    }
  };
}

export function createShopDeliveryRepository(service) {
  return async ({ authUserId, orderId, mode, items, cashCollected }) => {
    const { data, error } = await service.rpc('ro_submit_shop_delivery', {
      p_auth_user_id: authUserId,
      p_order_id: orderId,
      p_mode: mode,
      p_items: items,
      p_cash_collected: cashCollected,
    });
    if (error) throw error;
    return data;
  };
}

function mapRpcStatus(error) {
  if (error?.code === '42501') return 403;
  if (error?.code === 'P0002') return 404;
  if (['22023', '22P02', '22003', '23514'].includes(error?.code)) return 400;
  if (error?.code === 'P0001') return 409;
  return 503;
}

function safeRpcMessage(error) {
  const code = String(error?.code ?? '');
  if (code === '42501') return 'The employee is not authorized for this order.';
  if (code === 'P0002') return 'Order not found.';
  if (['22023', '22P02', '22003', '23514'].includes(code)) return 'Delivery details are invalid.';
  if (code === 'P0001') return 'Delivery conflicts with saved order data. Verify quantities and retry.';
  return 'Delivery details could not be saved. Please retry.';
}

function response(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
