const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  AdminStatsError,
  createAdminStatsHandler,
  createAdminStatsRepository,
} = require('../supabase/functions/_shared/admin_stats_core.mjs');

function fakeService(pages, failures = {}) {
  const calls = [];
  return {
    calls,
    from(table) {
      return {
        select(columns) {
          const call = {table, columns};
          calls.push(call);
          return {
            range(from, to) {
              call.range = [from, to];
              if (failures[table]) return Promise.resolve({data: null, error: {message: 'private db detail'}});
              return Promise.resolve({data: pages[table]?.shift() ?? [], error: null});
            },
          };
        },
      };
    },
  };
}

test('dashboard statistics match Express fields and case-insensitive status rules', async () => {
  const service = fakeService({
    users: [[{status: 'pending'}, {status: 'APPROVED'}, {status: 'Rejected'}, {status: null}]],
    products: [[{status: null}, {status: 'INACTIVE'}, {status: 'active'}]],
    categories: [[{id: 'c1'}, {id: 'c2'}]],
    orders: [[{grand_total: '12.50'}, {grand_total: '0.10'}, {grand_total: '0.20'}, {grand_total: null}]],
  });
  const result = await createAdminStatsRepository(service).loadDashboardStats();
  assert.deepEqual(result, {
    success: true,
    stats: {
      totalUsers: 4, pendingUsers: 1, approvedUsers: 1, rejectedUsers: 1,
      totalProducts: 3, activeProducts: 2, inactiveProducts: 1,
      totalCategories: 2, totalOrders: 4, totalRevenue: 12.8,
    },
  });
  assert.deepEqual(service.calls.map(call => [call.table, call.columns]).sort(), [
    ['categories', 'id'], ['orders', 'grand_total'], ['products', 'status'], ['users', 'status'],
  ]);
  assert.ok(service.calls.every(call => !/email|password|purchase|payment_id|token/i.test(call.columns)));
});

test('dashboard reads all pages and rejects datasets above the safe processing limit', async () => {
  const rows = Array.from({length: 500}, (_, index) => ({status: index % 2 ? 'pending' : 'approved'}));
  const service = fakeService({users: [rows, [{status: 'pending'}]]});
  const result = await createAdminStatsRepository(service).loadDashboardStats();
  assert.equal(result.stats.totalUsers, 501);
  assert.deepEqual(service.calls.filter(call => call.table === 'users').map(call => call.range), [[0, 499], [500, 999]]);

  // Build a deterministic service whose users endpoint always reports a full page.
  const bounded = {
    from(table) {
      return {select() {
        return {range() {
          return Promise.resolve({
            data: table === 'users' ? Array.from({length: 500}, () => ({status: 'pending'})) : [],
            error: null,
          });
        }};
      }};
    },
  };
  await assert.rejects(
    createAdminStatsRepository(bounded).loadDashboardStats(),
    error => error instanceof AdminStatsError && error.status === 503 &&
      error.message === 'Dashboard dataset exceeds the supported summary limit.',
  );
});

test('database errors are sanitized and never leak database messages', async () => {
  const service = fakeService({}, {orders: true});
  await assert.rejects(
    createAdminStatsRepository(service).loadDashboardStats(),
    error => error instanceof AdminStatsError && error.status === 503 &&
      error.message === 'Dashboard statistics could not be loaded.',
  );
});

test('only a confirmed trusted admin can access statistics', async () => {
  let reads = 0;
  const handler = createAdminStatsHandler({
    authenticate: async request => JSON.parse(request.headers.get('x-test-user') || 'null'),
    repository: {async loadDashboardStats() { reads++; return {success: true, stats: {}}; }},
  });
  for (const [user, status] of [
    [null, 401],
    [{id: 'a', app_metadata: {role: 'admin'}}, 401],
    [{id: 'a', email_confirmed_at: 'yes', app_metadata: {role: 'dealer'}, user_metadata: {role: 'admin'}}, 403],
  ]) {
    const response = await handler(new Request('https://local.test/stats', {
      method: 'GET', headers: user ? {'x-test-user': JSON.stringify(user)} : {},
    }));
    assert.equal(response.status, status);
  }
  assert.equal(reads, 0);
  const success = await handler(new Request('https://local.test/stats', {
    method: 'GET', headers: {'x-test-user': JSON.stringify({
      id: 'admin', email_confirmed_at: 'yes', app_metadata: {role: 'admin'},
    })},
  }));
  assert.equal(success.status, 200);
  assert.equal(reads, 1);
});

test('method errors do not query the database', async () => {
  let reads = 0;
  const handler = createAdminStatsHandler({
    authenticate: async () => ({id: 'admin', email_confirmed_at: 'yes', app_metadata: {role: 'admin'}}),
    repository: {async loadDashboardStats() { reads++; return {success: true, stats: {}}; }},
  });
  assert.equal((await handler(new Request('https://local.test/stats', {method: 'POST'}))).status, 405);
  assert.equal(reads, 0);
});
