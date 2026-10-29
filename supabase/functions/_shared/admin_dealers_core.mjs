export class AdminDealersError extends Error {
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

export function createAdminDealersRepository(service) {
  return {
    async listDealers() {
      const dealers = [];
      const pageSize = 500;
      for (let offset = 0; ; offset += pageSize) {
        const {data, error} = await service.from('users')
          .select('id,name,owner_name,email,mobile,address,business_name,status,is_approved,created_at')
          .order('created_at', {ascending: false})
          .range(offset, offset + pageSize - 1);
        if (error) {
          throw new AdminDealersError(503, 'Dealer data could not be loaded.');
        }
        const rows = data ?? [];
        if (dealers.length + rows.length > 20000) {
          throw new AdminDealersError(503, 'Dealer list exceeds the supported limit.');
        }
        for (const user of rows) {
          const status = String(user.status || 'approved');
          const createdAt = user.created_at == null
            ? null
            : new Date(user.created_at).toISOString();
          dealers.push({
            id: user.id,
            name: user.name || user.owner_name || null,
            email: user.email,
            mobile: user.mobile || '',
            address: user.address || '',
            business: user.business_name || '',
            status,
            isApproved: user.is_approved === true || status === 'approved',
            authMethod: 'Password/OTP',
            createdAt,
          });
        }
        if (rows.length < pageSize) break;
      }
      return {success: true, count: dealers.length, dealers};
    },
  };
}

export function createAdminDealersHandler({authenticate, repository}) {
  return async request => {
    if (request.method === 'OPTIONS') return response({ok: true});
    if (request.method !== 'GET') {
      return response({success: false, error: 'Method not allowed.'}, 405);
    }
    try {
      const user = await authenticate(request);
      if (!user?.id || !user.email_confirmed_at) {
        throw new AdminDealersError(401, 'A verified sign-in is required.');
      }
      if (!isVerifiedAdmin(user)) {
        throw new AdminDealersError(403, 'A verified administrator account is required.');
      }
      return response(await repository.listDealers());
    } catch (error) {
      const status = error instanceof AdminDealersError ? error.status : 500;
      const message = error instanceof AdminDealersError
        ? error.message
        : 'Dealer data could not be loaded.';
      console.error('[SUPABASE ADMIN DEALERS]', `HTTP_${status}`);
      return response({success: false, error: message}, status);
    }
  };
}
