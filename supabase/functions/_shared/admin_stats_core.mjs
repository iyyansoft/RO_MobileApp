export class AdminStatsError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

const response = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: {...cors, 'Content-Type': 'application/json'},
});

export function isVerifiedAdmin(user) {
  return Boolean(
    user?.id && user.email_confirmed_at && user.app_metadata?.role === 'admin',
  );
}

async function readAll(service, table, columns) {
  const rows = [];
  const pageSize = 500;
  for (let offset = 0; ; offset += pageSize) {
    const {data, error} = await service.from(table)
      .select(columns)
      .range(offset, offset + pageSize - 1);
    if (error) throw new AdminStatsError(503, 'Dashboard statistics could not be loaded.');
    const page = data ?? [];
    if (rows.length + page.length > 50000) {
      throw new AdminStatsError(503, 'Dashboard dataset exceeds the supported summary limit.');
    }
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }
}

export function createAdminStatsRepository(service) {
  return {
    async loadDashboardStats() {
      const [users, products, categories, orders] = await Promise.all([
        readAll(service, 'users', 'status'),
        readAll(service, 'products', 'status'),
        readAll(service, 'categories', 'id'),
        readAll(service, 'orders', 'grand_total'),
      ]);
      const countStatus = (rows, target) => rows.filter(row =>
        String(row.status ?? '').toLowerCase() === target).length;
      const inactiveProducts = products.filter(row =>
        String(row.status ?? 'active').toLowerCase() === 'inactive').length;
      const totalRevenuePaise = orders.reduce((sum, row) => {
        const value = Number(row.grand_total ?? 0);
        if (!Number.isFinite(value)) {
          throw new AdminStatsError(503, 'Dashboard statistics could not be loaded.');
        }
        // Order totals are currency values stored to two decimal places. Sum
        // integer paise to avoid binary floating-point drift across many rows.
        return sum + BigInt(Math.round(value * 100));
      }, 0n);
      return {
        success: true,
        stats: {
          totalUsers: users.length,
          pendingUsers: countStatus(users, 'pending'),
          approvedUsers: countStatus(users, 'approved'),
          rejectedUsers: countStatus(users, 'rejected'),
          totalProducts: products.length,
          activeProducts: products.length - inactiveProducts,
          inactiveProducts,
          totalCategories: categories.length,
          totalOrders: orders.length,
          totalRevenue: Number(totalRevenuePaise) / 100,
        },
      };
    },
  };
}

export function createAdminStatsHandler({authenticate, repository}) {
  return async request => {
    if (request.method === 'OPTIONS') return response({ok: true});
    if (request.method !== 'GET') {
      return response({success: false, error: 'Method not allowed.'}, 405);
    }
    try {
      const user = await authenticate(request);
      if (!user?.id || !user.email_confirmed_at) {
        throw new AdminStatsError(401, 'A verified sign-in is required.');
      }
      if (!isVerifiedAdmin(user)) {
        throw new AdminStatsError(403, 'A verified administrator account is required.');
      }
      return response(await repository.loadDashboardStats());
    } catch (error) {
      const status = error instanceof AdminStatsError ? error.status : 500;
      const message = error instanceof AdminStatsError
        ? error.message
        : 'Dashboard statistics could not be loaded.';
      console.error('[SUPABASE ADMIN STATS]', `HTTP_${status}`);
      return response({success: false, error: message}, status);
    }
  };
}
