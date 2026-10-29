export class AdminOrderStatusError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const response = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: {...cors, 'Content-Type': 'application/json'},
});

function isVerifiedAdmin(user) {
  return Boolean(user?.id && user.email_confirmed_at && user.app_metadata?.role === 'admin');
}

function validateInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new AdminOrderStatusError(400, 'Invalid order status request.');
  }
  const orderId = String(body.orderId ?? '').trim();
  const status = String(body.status ?? 'Processing').trim();
  if (!orderId || orderId.length > 64 || /[\u0000-\u001f\u007f]/.test(orderId) ||
      !status || status.length > 100 || /[\u0000-\u001f\u007f]/.test(status)) {
    throw new AdminOrderStatusError(400, 'Enter a valid order ID and status.');
  }
  return {orderId, status};
}

export function createAdminOrderStatusRepository(service) {
  return {
    async setStatus({adminUserId, orderId, status}) {
      const {data, error} = await service.rpc('ro_admin_update_order_status', {
        p_admin_user_id: adminUserId,
        p_order_id: orderId,
        p_status: status,
      });
      if (error) {
        if (error.code === 'P0002') throw new AdminOrderStatusError(404, 'Order not found.');
        if (error.code === '55000') {
          const safeConflicts = new Set([
            'Delivery has been submitted by the Shop App. Its status is synchronized from the saved delivery quantities.',
            'An order can be marked Delivered only after every ordered unit is recorded as delivered in the Shop App.',
          ]);
          throw new AdminOrderStatusError(409, safeConflicts.has(error.message)
            ? error.message : 'Order status conflicts with saved delivery records.');
        }
        if (error.code === '22023') throw new AdminOrderStatusError(400, 'Enter a valid order ID and status.');
        if (error.code === '28000') throw new AdminOrderStatusError(403, 'A verified administrator account is required.');
        throw new AdminOrderStatusError(503, 'Order status could not be saved.');
      }
      if (!data || data.success !== true || data.orderId !== orderId || data.status !== status) {
        throw new AdminOrderStatusError(503, 'Order status could not be saved.');
      }
      return data;
    },
  };
}

export function createAdminOrderStatusHandler({authenticate, repository}) {
  return async request => {
    if (request.method === 'OPTIONS') return response({ok: true});
    if (request.method !== 'POST') return response({success: false, error: 'Method not allowed.'}, 405);
    try {
      const user = await authenticate(request);
      if (!user?.id || !user.email_confirmed_at) {
        throw new AdminOrderStatusError(401, 'A verified sign-in is required.');
      }
      if (!isVerifiedAdmin(user)) {
        throw new AdminOrderStatusError(403, 'A verified administrator account is required.');
      }
      const declaredLength = Number(request.headers.get('content-length') ?? 0);
      if (declaredLength > 8 * 1024) throw new AdminOrderStatusError(413, 'The request is too large.');
      let body;
      try {
        const raw = await request.text();
        if (new TextEncoder().encode(raw).byteLength > 8 * 1024) {
          throw new AdminOrderStatusError(413, 'The request is too large.');
        }
        body = JSON.parse(raw);
      } catch (error) {
        if (error instanceof AdminOrderStatusError) throw error;
        throw new AdminOrderStatusError(400, 'Invalid order status request.');
      }
      const input = validateInput(body);
      const result = await repository.setStatus({adminUserId: user.id, ...input});
      return response(result);
    } catch (error) {
      const status = error instanceof AdminOrderStatusError ? error.status : 500;
      const message = error instanceof AdminOrderStatusError ? error.message : 'Order status could not be saved.';
      console.error('[SUPABASE ADMIN ORDER STATUS]', `HTTP_${status}`);
      return response({success: false, error: message}, status);
    }
  };
}
