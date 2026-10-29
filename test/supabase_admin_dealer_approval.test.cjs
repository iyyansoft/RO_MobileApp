const test = require('node:test');
const assert = require('node:assert/strict');

const verifiedAdmin = {
  id: 'admin-user-1',
  email_confirmed_at: '2026-10-01T00:00:00Z',
  app_metadata: { role: 'admin' },
};

function request(body, { method = 'POST', user = 'admin' } = {}) {
  return new Request('https://local.test/admin-dealer-approval', {
    method,
    headers: {
      'content-type': 'application/json',
      ...(user ? { 'x-test-user': user } : {}),
    },
    ...(method === 'POST' ? { body: JSON.stringify(body) } : {}),
  });
}

async function handlerFor({ userFor = () => verifiedAdmin, setDealerStatus } = {}) {
  const { createAdminDealerApprovalHandler } = await import(
    '../supabase/functions/_shared/admin_dealer_approval_core.mjs'
  );
  return createAdminDealerApprovalHandler({
    authenticate: async req => userFor(req.headers.get('x-test-user')),
    repository: { setDealerStatus },
  });
}

function mockPostgrest(resolve) {
  const calls = [];
  return {
    calls,
    from(table) {
      const query = {
        table,
        operation: 'select',
        columns: '*',
        filters: [],
        values: null,
        select(columns) { this.columns = columns; return this; },
        eq(column, value) { this.filters.push([column, value]); return this; },
        limit(value) { this.limitValue = value; return this; },
        update(values) { this.operation = 'update'; this.values = values; return this; },
        maybeSingle() { calls.push(this); return Promise.resolve(resolve(this)); },
        then(onFulfilled, onRejected) {
          calls.push(this);
          return Promise.resolve(resolve(this)).then(onFulfilled, onRejected);
        },
      };
      return query;
    },
  };
}

test('dealer approval requires a verified trusted admin before any database call', async () => {
  let writes = 0;
  const handler = await handlerFor({
    userFor: role => role === 'dealer'
      ? { ...verifiedAdmin, app_metadata: { role: 'dealer' } }
      : role === 'unverified'
        ? { ...verifiedAdmin, email_confirmed_at: null }
        : role === 'admin' ? verifiedAdmin : null,
    setDealerStatus: async () => { writes += 1; },
  });
  assert.equal((await handler(request({ identifier: 'dealer@example.test', status: 'approved' }, { user: null }))).status, 401);
  assert.equal((await handler(request({ identifier: 'dealer@example.test', status: 'approved' }, { user: 'unverified' }))).status, 401);
  assert.equal((await handler(request({ identifier: 'dealer@example.test', status: 'approved', role: 'admin' }, { user: 'dealer' }))).status, 403);
  assert.equal(writes, 0);
});

test('only an explicit validated admin request can set approved, pending, or rejected', async () => {
  const calls = [];
  const handler = await handlerFor({
    setDealerStatus: async input => {
      calls.push(input);
      return {
        message: `Dealer status updated to ${input.status}`,
        user: { email: input.identifier, status: input.status, isApproved: input.status === 'approved' },
      };
    },
  });
  for (const status of ['approved', 'pending', 'rejected']) {
    const response = await handler(request({
      identifier: 'dealer@example.test',
      status,
      is_approved: true,
    }));
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.success, true);
    assert.equal(body.user.status, status);
    assert.equal(body.user.isApproved, status === 'approved');
  }
  assert.deepEqual(calls.map(call => call.status), ['approved', 'pending', 'rejected']);
});

test('malformed or client-escalated approval input is rejected before writes', async () => {
  let writes = 0;
  const handler = await handlerFor({
    setDealerStatus: async () => { writes += 1; },
  });
  for (const body of [
    { identifier: '', status: 'approved' },
    { identifier: 'x'.repeat(321), status: 'approved' },
    { identifier: 'dealer@example.test', status: 'owner' },
  ]) {
    assert.equal((await handler(request(body))).status, 400);
  }
  assert.equal(writes, 0);
});

test('method, missing-dealer, and unexpected database failures are handled safely', async () => {
  const { DealerApprovalError } = await import('../supabase/functions/_shared/admin_dealer_approval_core.mjs');
  const missing = await handlerFor({
    setDealerStatus: async () => { throw new DealerApprovalError(404, 'Dealer not found.'); },
  });
  assert.equal((await missing(request(null, { method: 'GET' }))).status, 405);
  const notFound = await missing(request({ identifier: 'missing@example.test', status: 'approved' }));
  assert.equal(notFound.status, 404);

  const failed = await handlerFor({
    setDealerStatus: async () => { throw new Error('private database detail'); },
  });
  const response = await failed(request({ identifier: 'dealer@example.test', status: 'approved' }));
  assert.equal(response.status, 500);
  assert.doesNotMatch(JSON.stringify(await response.json()), /private database detail/);
});

test('PostgREST adapter resolves a single dealer and writes only approval columns', async () => {
  const { createAdminDealerApprovalRepository } = await import(
    '../supabase/functions/_shared/admin_dealer_approval_core.mjs'
  );
  const service = mockPostgrest(query => {
    const filter = query.filters[0];
    if (query.operation === 'update') {
      return {
        data: { id: 'dealer-1', email: 'dealer@example.test', status: 'approved', is_approved: true },
        error: null,
      };
    }
    if (filter[0] === 'email') {
      return { data: [{ id: 'dealer-1', email: 'dealer@example.test' }], error: null };
    }
    return { data: [], error: null };
  });
  const repository = createAdminDealerApprovalRepository(service);
  const result = await repository.setDealerStatus({
    identifier: 'DEALER@example.test',
    status: 'approved',
  });
  assert.equal(result.user.status, 'approved');
  assert.equal(result.user.isApproved, true);
  const update = service.calls.find(call => call.operation === 'update');
  assert.deepEqual(update.values, { status: 'approved', is_approved: true });
  assert.deepEqual(update.filters, [['id', 'dealer-1']]);
  assert.equal(update.columns, 'id,email,status,is_approved');
});

test('PostgREST adapter rejects ambiguous and missing dealer identifiers without updating', async () => {
  const { createAdminDealerApprovalRepository, DealerApprovalError } = await import(
    '../supabase/functions/_shared/admin_dealer_approval_core.mjs'
  );
  const ambiguous = mockPostgrest(query => {
    const filter = query.filters[0];
    if (filter[0] === 'id') return { data: [{ id: 'dealer@example.test', email: 'other@example.test' }], error: null };
    if (filter[0] === 'email') return { data: [{ id: 'dealer-1', email: 'dealer@example.test' }], error: null };
    return { data: [], error: null };
  });
  const ambiguousRepo = createAdminDealerApprovalRepository(ambiguous);
  await assert.rejects(
    ambiguousRepo.setDealerStatus({ identifier: 'dealer@example.test', status: 'approved' }),
    error => error instanceof DealerApprovalError && error.status === 409,
  );
  assert.equal(ambiguous.calls.some(call => call.operation === 'update'), false);

  const missing = mockPostgrest(() => ({ data: [], error: null }));
  const missingRepo = createAdminDealerApprovalRepository(missing);
  await assert.rejects(
    missingRepo.setDealerStatus({ identifier: 'missing@example.test', status: 'approved' }),
    error => error instanceof DealerApprovalError && error.status === 404,
  );
  assert.equal(missing.calls.some(call => call.operation === 'update'), false);
});

test('Supabase dealer approval stays opt-in and only uses existing users status columns', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const root = path.join(__dirname, '..');
  const config = fs.readFileSync(path.join(root, 'lib/core/supabase/supabase_config.dart'), 'utf8');
  const edge = fs.readFileSync(path.join(root, 'supabase/functions/admin-dealer-approval/index.ts'), 'utf8');
  const core = fs.readFileSync(path.join(root, 'supabase/functions/_shared/admin_dealer_approval_core.mjs'), 'utf8');
  assert.match(config, /USE_SUPABASE_ADMIN_DEALER_APPROVAL[\s\S]*defaultValue:\s*false/);
  assert.match(edge, /client\.auth\.getUser\(token\)/);
  assert.match(edge, /SERVICE_ROLE_KEY/);
  assert.match(core, /user\.app_metadata\?\.role === 'admin'/);
  assert.match(core, /update\(\{ status, is_approved: approved \}\)/);
  assert.doesNotMatch(`${edge}\n${core}`, /CREATE TABLE|ALTER TABLE|DROP TABLE|TRUNCATE/i);
});
