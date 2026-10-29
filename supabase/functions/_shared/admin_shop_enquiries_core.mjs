export class AdminShopEnquiriesError extends Error {
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

const ENQUIRY_COLUMNS = 'id,employee_id,customer_name,company_name,contact_number,category,product_name,required_quantity,remarks,status,created_at';

export function isVerifiedAdmin(user) {
  return Boolean(
    user?.id && user.email_confirmed_at && user.app_metadata?.role === 'admin',
  );
}

function toIsoOrNull(value) {
  if (value == null || value === '') return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

export function createAdminShopEnquiriesRepository(service) {
  return {
    async listEnquiries() {
      const {data, error} = await service.from('shop_product_enquiries')
        .select(ENQUIRY_COLUMNS)
        .order('created_at', {ascending: false})
        .order('id', {ascending: false})
        .range(0, 499);
      if (error) {
        throw new AdminShopEnquiriesError(503, 'Shop enquiries are unavailable.');
      }
      const rows = data ?? [];
      const employeeIds = [...new Set(rows.map(row => row.employee_id).filter(Boolean).map(String))];
      const submittedBy = new Map();
      for (let start = 0; start < employeeIds.length; start += 200) {
        const {data: employees, error: employeeError} = await service.from('shop_employees')
          .select('id,employee_id')
          .in('id', employeeIds.slice(start, start + 200));
        if (employeeError) {
          throw new AdminShopEnquiriesError(503, 'Shop enquiries are unavailable.');
        }
        for (const employee of employees ?? []) {
          submittedBy.set(String(employee.id), employee.employee_id ?? null);
        }
      }
      const enquiries = rows.map(row => ({
        id: row.id,
        employee_id: row.employee_id ?? null,
        customer_name: row.customer_name,
        company_name: row.company_name,
        contact_number: row.contact_number,
        category: row.category,
        product_name: row.product_name,
        required_quantity: row.required_quantity,
        remarks: row.remarks ?? null,
        status: row.status,
        created_at: toIsoOrNull(row.created_at),
        submitted_by: row.employee_id == null
          ? null
          : submittedBy.get(String(row.employee_id)) ?? null,
      }));
      return {success: true, enquiries};
    },
  };
}

export function createAdminShopEnquiriesHandler({authenticate, repository}) {
  return async request => {
    if (request.method === 'OPTIONS') return response({ok: true});
    if (request.method !== 'GET') {
      return response({success: false, error: 'Method not allowed.'}, 405);
    }
    try {
      const user = await authenticate(request);
      if (!user?.id || !user.email_confirmed_at) {
        throw new AdminShopEnquiriesError(401, 'A verified sign-in is required.');
      }
      if (!isVerifiedAdmin(user)) {
        throw new AdminShopEnquiriesError(403, 'A verified administrator account is required.');
      }
      return response(await repository.listEnquiries());
    } catch (error) {
      const status = error instanceof AdminShopEnquiriesError ? error.status : 500;
      const message = error instanceof AdminShopEnquiriesError
        ? error.message
        : 'Shop enquiries are unavailable.';
      console.error('[SUPABASE ADMIN SHOP ENQUIRIES]', `HTTP_${status}`);
      return response({success: false, error: message}, status);
    }
  };
}
