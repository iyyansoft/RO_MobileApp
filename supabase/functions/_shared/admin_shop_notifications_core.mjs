export class AdminShopNotificationsError extends Error {
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

const NOTIFICATION_COLUMNS = 'id,order_id,employee_id,notification_type,message,refund_amount,created_at,read_at';

export function isVerifiedShopNotificationsAdmin(user) {
  return Boolean(
    user?.id && user.email_confirmed_at && user.app_metadata?.role === 'admin',
  );
}

function toIsoOrNull(value) {
  if (value == null || value === '') return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

export function createAdminShopNotificationsRepository(service) {
  return {
    async listNotifications() {
      const {data, error} = await service.from('shop_admin_notifications')
        .select(NOTIFICATION_COLUMNS)
        .order('created_at', {ascending: false})
        .order('id', {ascending: false})
        .range(0, 249);
      if (error) {
        throw new AdminShopNotificationsError(503, 'Shop delivery notifications are unavailable.');
      }
      const rows = data ?? [];
      const employeeIds = [...new Set(rows.map(row => row.employee_id).filter(Boolean).map(String))];
      const employeesById = new Map();
      for (let start = 0; start < employeeIds.length; start += 200) {
        const {data: employees, error: employeeError} = await service.from('shop_employees')
          .select('id,employee_id,full_name')
          .in('id', employeeIds.slice(start, start + 200));
        if (employeeError) {
          throw new AdminShopNotificationsError(503, 'Shop delivery notifications are unavailable.');
        }
        for (const employee of employees ?? []) {
          employeesById.set(String(employee.id), employee);
        }
      }
      const notifications = rows.map(row => {
        const employee = row.employee_id == null ? null : employeesById.get(String(row.employee_id));
        return {
          id: row.id,
          order_id: row.order_id,
          notification_type: row.notification_type,
          message: row.message,
          refund_amount: row.refund_amount,
          created_at: toIsoOrNull(row.created_at),
          read_at: toIsoOrNull(row.read_at),
          employee_id: employee?.employee_id ?? null,
          full_name: employee?.full_name ?? null,
        };
      });
      return {success: true, notifications};
    },
  };
}

export function createAdminShopNotificationsHandler({authenticate, repository}) {
  return async request => {
    if (request.method === 'OPTIONS') return response({ok: true});
    if (request.method !== 'GET') {
      return response({success: false, error: 'Method not allowed.'}, 405);
    }
    try {
      const user = await authenticate(request);
      if (!user?.id || !user.email_confirmed_at) {
        throw new AdminShopNotificationsError(401, 'A verified sign-in is required.');
      }
      if (!isVerifiedShopNotificationsAdmin(user)) {
        throw new AdminShopNotificationsError(403, 'A verified administrator account is required.');
      }
      return response(await repository.listNotifications());
    } catch (error) {
      const status = error instanceof AdminShopNotificationsError ? error.status : 500;
      const message = error instanceof AdminShopNotificationsError
        ? error.message
        : 'Shop delivery notifications are unavailable.';
      console.error('[SUPABASE ADMIN SHOP NOTIFICATIONS]', `HTTP_${status}`);
      return response({success: false, error: message}, status);
    }
  };
}
