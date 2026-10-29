export class AdminShopEmployeesError extends Error {
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

const EMPLOYEE_COLUMNS = 'id,employee_id,shop_name,full_name,active,created_at';
const PAGE_SIZE = 500;

export function isVerifiedShopEmployeesAdmin(user) {
  return Boolean(
    user?.id && user.email_confirmed_at && user.app_metadata?.role === 'admin',
  );
}

function toIsoOrNull(value) {
  if (value == null || value === '') return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

export function createAdminShopEmployeesRepository(service) {
  return {
    async listEmployees() {
      const employees = [];
      for (let from = 0; ; from += PAGE_SIZE) {
        const {data, error} = await service.from('shop_employees')
          .select(EMPLOYEE_COLUMNS)
          .order('created_at', {ascending: false})
          .order('id', {ascending: false})
          .range(from, from + PAGE_SIZE - 1);
        if (error) {
          throw new AdminShopEmployeesError(503, 'Employee list is unavailable.');
        }
        const rows = data ?? [];
        employees.push(...rows.map(row => ({
          id: row.id,
          employee_id: row.employee_id,
          shop_name: row.shop_name,
          full_name: row.full_name,
          active: row.active === true,
          created_at: toIsoOrNull(row.created_at),
        })));
        if (rows.length < PAGE_SIZE) break;
      }
      return {success: true, employees};
    },
  };
}

export function createAdminShopEmployeesHandler({authenticate, repository}) {
  return async request => {
    if (request.method === 'OPTIONS') return response({ok: true});
    if (request.method !== 'GET') {
      return response({success: false, error: 'Method not allowed.'}, 405);
    }
    try {
      const user = await authenticate(request);
      if (!user?.id || !user.email_confirmed_at) {
        throw new AdminShopEmployeesError(401, 'A verified sign-in is required.');
      }
      if (!isVerifiedShopEmployeesAdmin(user)) {
        throw new AdminShopEmployeesError(403, 'A verified administrator account is required.');
      }
      return response(await repository.listEmployees());
    } catch (error) {
      const status = error instanceof AdminShopEmployeesError ? error.status : 500;
      const message = error instanceof AdminShopEmployeesError
        ? error.message
        : 'Employee list is unavailable.';
      console.error('[SUPABASE ADMIN SHOP EMPLOYEES]', `HTTP_${status}`);
      return response({success: false, error: message}, status);
    }
  };
}
