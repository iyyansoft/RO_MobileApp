export class DealerApprovalError extends Error {
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
  headers: { ...cors, 'Content-Type': 'application/json' },
});

export function isVerifiedAdmin(user) {
  return Boolean(
    user?.id && user.email_confirmed_at && user.app_metadata?.role === 'admin',
  );
}

function databaseFailure(error) {
  if (error?.code === 'PGRST116') {
    throw new DealerApprovalError(409, 'The dealer identifier is ambiguous. Use the exact dealer ID.');
  }
  throw new DealerApprovalError(503, 'Dealer status could not be saved.');
}

export function createAdminDealerApprovalRepository(service) {
  return {
    async setDealerStatus({ identifier, status }) {
      const raw = identifier.trim();
      const candidates = new Map();
      const lookups = [
        () => service.from('users').select('id,email').eq('id', raw).limit(2),
      ];
      const email = raw.toLowerCase();
      if (/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
        lookups.push(() => service.from('users').select('id,email').eq('email', email).limit(2));
      }
      if (/^\d{10}$/.test(raw)) {
        lookups.push(() => service.from('users').select('id,email').eq('mobile', raw).limit(2));
      }
      for (const query of lookups) {
        const { data, error } = await query();
        if (error) databaseFailure(error);
        for (const row of data ?? []) {
          if (row) candidates.set(String(row.id), { id: String(row.id), email: String(row.email ?? '') });
        }
      }
      if (candidates.size === 0) throw new DealerApprovalError(404, 'Dealer not found.');
      if (candidates.size > 1) {
        throw new DealerApprovalError(409, 'The dealer identifier is ambiguous. Use the exact dealer ID.');
      }
      const dealer = [...candidates.values()][0];
      const approved = status === 'approved';
      const { data, error } = await service.from('users')
        .update({ status, is_approved: approved })
        .eq('id', dealer.id)
        .select('id,email,status,is_approved')
        .maybeSingle();
      if (error) databaseFailure(error);
      if (!data) throw new DealerApprovalError(404, 'Dealer not found.');
      return {
        message: `Dealer status updated to ${status}`,
        user: {
          email: String(data.email ?? dealer.email),
          status: String(data.status),
          isApproved: data.is_approved === true,
        },
      };
    },
  };
}

function validateInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new DealerApprovalError(400, 'Invalid dealer status request.');
  }
  const identifier = String(body.identifier ?? body.email ?? '').trim();
  const status = String(body.status ?? '').trim().toLowerCase();
  if (!identifier || identifier.length > 320 || /[\u0000-\u001f\u007f]/.test(identifier)) {
    throw new DealerApprovalError(400, 'Enter a valid dealer identifier.');
  }
  if (!['approved', 'pending', 'rejected'].includes(status)) {
    throw new DealerApprovalError(400, 'Select a valid dealer status.');
  }
  return { identifier, status };
}

export function createAdminDealerApprovalHandler({ authenticate, repository }) {
  return async request => {
    if (request.method === 'OPTIONS') return response({ ok: true });
    if (request.method !== 'POST') {
      return response({ success: false, error: 'Method not allowed.' }, 405);
    }
    try {
      const user = await authenticate(request);
      if (!user?.id || !user.email_confirmed_at) {
        throw new DealerApprovalError(401, 'A verified sign-in is required.');
      }
      if (!isVerifiedAdmin(user)) {
        throw new DealerApprovalError(403, 'A verified administrator account is required.');
      }
      const length = Number(request.headers.get('content-length') ?? 0);
      if (length > 16 * 1024) throw new DealerApprovalError(413, 'The request is too large.');
      let body;
      try {
        const raw = await request.text();
        if (new TextEncoder().encode(raw).byteLength > 16 * 1024) {
          throw new DealerApprovalError(413, 'The request is too large.');
        }
        body = JSON.parse(raw);
      } catch (error) {
        if (error instanceof DealerApprovalError) throw error;
        throw new DealerApprovalError(400, 'Invalid dealer status request.');
      }
      const input = validateInput(body);
      const result = await repository.setDealerStatus(input);
      return response({ success: true, ...result });
    } catch (error) {
      const status = error instanceof DealerApprovalError ? error.status : 500;
      const message = error instanceof DealerApprovalError
        ? error.message
        : 'Dealer status could not be saved.';
      console.error('[SUPABASE ADMIN DEALER APPROVAL]', `HTTP_${status}`);
      return response({ success: false, error: message }, status);
    }
  };
}
