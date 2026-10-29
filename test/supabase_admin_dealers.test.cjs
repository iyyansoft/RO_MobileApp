const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  AdminDealersError,
  createAdminDealersHandler,
  createAdminDealersRepository,
} = require('../supabase/functions/_shared/admin_dealers_core.mjs');

function serviceFor(pages) {
  const calls = [];
  return {
    calls,
    from(table) {
      assert.equal(table, 'users');
      return {
        select(columns) {
          calls.push({columns});
          return {
            order(column, options) {
              calls.at(-1).order = [column, options];
              return {
                range(from, to) {
                  calls.at(-1).range = [from, to];
                  const page = pages.shift() ?? [];
                  return Promise.resolve({data: page, error: null});
                },
              };
            },
          };
        },
      };
    },
  };
}

const verifiedAdmin = {
  id: 'admin-auth-id',
  email_confirmed_at: '2026-10-01T00:00:00Z',
  app_metadata: {role: 'admin'},
};

test('dealer list uses an explicit safe projection and preserves the Express response shape', async () => {
  const service = serviceFor([[
    {
      id: 'dealer-1', name: null, owner_name: 'Dealer One', email: 'one@example.test',
      mobile: '9876543210', address: 'Main Street', business_name: 'One Co',
      status: 'approved', is_approved: false, created_at: '2026-10-20T10:00:00Z',
      password_hash: 'must-not-be-selected', gst_number: 'private',
    },
  ]]);
  const result = await createAdminDealersRepository(service).listDealers();
  assert.equal(result.success, true);
  assert.equal(result.count, 1);
  assert.deepEqual(result.dealers[0], {
    id: 'dealer-1', name: 'Dealer One', email: 'one@example.test', mobile: '9876543210',
    address: 'Main Street', business: 'One Co', status: 'approved', isApproved: true,
    authMethod: 'Password/OTP', createdAt: '2026-10-20T10:00:00.000Z',
  });
  assert.match(service.calls[0].columns, /^id,name,owner_name,email,mobile,address,business_name,status,is_approved,created_at$/);
  assert.doesNotMatch(service.calls[0].columns, /password|gst|reward|auth_user_id/i);
  assert.deepEqual(service.calls[0].order, ['created_at', {ascending: false}]);
});

test('dealer list paginates all rows without silently stopping at the API page limit', async () => {
  const first = Array.from({length: 500}, (_, index) => ({id: `d-${index}`, email: `d${index}@example.test`}));
  const second = [{id: 'd-500', email: 'd500@example.test'}];
  const service = serviceFor([first, second]);
  const result = await createAdminDealersRepository(service).listDealers();
  assert.equal(result.count, 501);
  assert.deepEqual(service.calls.map(call => call.range), [[0, 499], [500, 999]]);
});

test('database failures return sanitized errors and do not expose query details', async () => {
  const service = {
    from() {
      return {select() { return {order() { return {range: async () => ({data: null, error: {message: 'secret details'}})}; }}; }};
    },
  };
  await assert.rejects(
    createAdminDealersRepository(service).listDealers(),
    error => error instanceof AdminDealersError && error.status === 503 &&
      error.message === 'Dealer data could not be loaded.',
  );
});

test('handler rejects anonymous, unverified, and client-metadata-only administrators before querying', async () => {
  let calls = 0;
  const handler = createAdminDealersHandler({
    authenticate: async request => {
      const raw = request.headers.get('x-test-user');
      return raw ? JSON.parse(raw) : null;
    },
    repository: {async listDealers() { calls++; return {success: true, count: 0, dealers: []}; }},
  });
  for (const [user, expected] of [
    [null, 401],
    [{id: 'a', app_metadata: {role: 'admin'}}, 401],
    [{id: 'a', email_confirmed_at: 'verified', app_metadata: {role: 'dealer'}, user_metadata: {role: 'admin'}}, 403],
  ]) {
    const response = await handler(new Request('https://local.test/admin-dealers', {
      method: 'GET',
      headers: {
        authorization: 'Bearer test',
        ...(user ? {'x-test-user': JSON.stringify(user)} : {}),
      },
    }));
    assert.ok([401, 403].includes(response.status));
    assert.equal(response.status, expected);
  }
  assert.equal(calls, 0);
});

test('handler serves dealer data only on GET after verified trusted admin authorization', async () => {
  let calls = 0;
  const handler = createAdminDealersHandler({
    authenticate: async () => verifiedAdmin,
    repository: {async listDealers() { calls++; return {success: true, count: 0, dealers: []}; }},
  });
  const methodDenied = await handler(new Request('https://local.test/admin-dealers', {method: 'POST'}));
  assert.equal(methodDenied.status, 405);
  const success = await handler(new Request('https://local.test/admin-dealers', {method: 'GET'}));
  assert.equal(success.status, 200);
  assert.deepEqual(await success.json(), {success: true, count: 0, dealers: []});
  assert.equal(calls, 1);
});
