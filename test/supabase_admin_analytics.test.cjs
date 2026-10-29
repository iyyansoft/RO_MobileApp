const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  AdminAnalyticsError,
  createAdminAnalyticsHandler,
  createAdminAnalyticsRepository,
} = require('../supabase/functions/_shared/admin_analytics_core.mjs');

function fakeService(tables, failures = {}) {
  const calls = [];
  return {
    calls,
    from(table) {
      return {
        select(columns) {
          const call = {table, columns, ids: null};
          calls.push(call);
          const query = {
            in(column, ids) { call.in = [column, ids]; return query; },
            async range(from, to) {
              call.range = [from, to];
              if (failures[table]) return {data: null, error: {message: 'private database detail'}};
              let rows = tables[table] ?? [];
              if (call.in) rows = rows.filter(row => call.in[1].includes(String(row[call.in[0]])));
              return {data: rows.slice(from, to + 1), error: null};
            },
          };
          return query;
        },
      };
    },
  };
}

const fixedNow = () => new Date('2026-10-27T12:00:00.000Z');

test('analytics preserves the Express response contract and computes actual read-only metrics', async () => {
  const service = fakeService({
    orders: [
      {order_id: 'today', grand_total: '100.25', status: 'Processing', created_at: '2026-10-27T08:00:00Z'},
      {order_id: 'cancelled', grand_total: '900', status: 'Cancelled', created_at: '2026-10-27T09:00:00Z'},
      {order_id: 'month', grand_total: '50', status: 'Delivered', created_at: '2026-10-03T08:00:00Z'},
    ],
    order_items: [
      {order_id: 'today', product_id: 'p1', sku: 'M-1', product_name: 'Membrane', brand: 'RO', unit_price: '25.05', quantity: 2, img_src: '/m.png'},
      {order_id: 'cancelled', product_id: 'p2', sku: 'F-1', product_name: 'Filter', brand: 'Filters', unit_price: 10, quantity: 100, img_src: '/f.png'},
      {order_id: 'month', product_id: 'p1', sku: 'M-1', product_name: 'Membrane', brand: 'RO', unit_price: 25, quantity: 1, img_src: '/m.png'},
    ],
    products: [
      {id: 'p1', sku: 'M-1', name: 'Membrane', category_key: 'ro', img: '/m.png', stock_quantity: 2, min_stock: 5},
      {id: 'p2', sku: 'F-1', name: 'Filter', category_key: 'filter', img: '/f.png', stock_quantity: 20, min_stock: 5},
    ],
  });
  const result = await createAdminAnalyticsRepository(service, {clock: fixedNow}).getAnalytics('daily');
  assert.equal(result.success, true);
  assert.deepEqual(result.revenue, {
    todayRevenue: 100.25,
    monthRevenue: 150.25,
    totalRevenue: 150.25,
    totalOrders: 3,
    avgOrderValue: 75,
  });
  assert.equal(result.chart.labels.length, 7);
  assert.equal(result.chart.revenueData.at(-1), 100.25);
  assert.equal(result.chart.orderCountData.at(-1), 1);
  assert.deepEqual(result.topProducts, [{
    id: 'p1', name: 'Membrane', category: 'RO', img: '/m.png', unitsSold: 3, totalRevenue: 75.1,
  }]);
  assert.deepEqual(result.lowStock, [{
    id: 'p1', sku: 'M-1', name: 'Membrane', category: 'ro', img: '/m.png', stock: 2, minStock: 5,
  }]);
  assert.ok(service.calls.every(call => !/email|password|purchase|payment_id|token/i.test(call.columns)));
});

test('analytics supports all chart periods and treats unknown period as yearly', async () => {
  for (const period of ['daily', 'weekly', 'monthly', 'yearly', 'unexpected']) {
    const service = fakeService({orders: [], order_items: [], products: []});
    const result = await createAdminAnalyticsRepository(service, {clock: fixedNow}).getAnalytics(period);
    assert.equal(result.success, true);
    assert.equal(result.chart.labels.length, period === 'daily' ? 7 : period === 'weekly' ? 4 : period === 'monthly' ? 6 : 3);
  }
});

test('database errors are sanitized and malformed monetary/date values fail closed', async () => {
  const service = fakeService({}, {orders: true});
  await assert.rejects(createAdminAnalyticsRepository(service).getAnalytics(), error =>
    error instanceof AdminAnalyticsError && error.status === 503 && error.message === 'Analytics could not be generated.');
  const malformed = fakeService({orders: [{order_id: 'o', grand_total: 'NaN', status: 'Processing', created_at: 'bad'}], products: [], order_items: []});
  await assert.rejects(createAdminAnalyticsRepository(malformed).getAnalytics(), AdminAnalyticsError);
});

test('only a verified admin may access analytics and unsupported methods do not read data', async () => {
  let reads = 0;
  const handler = createAdminAnalyticsHandler({
    authenticate: async request => JSON.parse(request.headers.get('x-test-user') || 'null'),
    repository: {async getAnalytics() { reads++; return {success: true, revenue: {}, chart: {}}; }},
  });
  for (const [user, expected] of [
    [null, 401],
    [{id: 'admin', app_metadata: {role: 'admin'}}, 401],
    [{id: 'dealer', email_confirmed_at: 'yes', app_metadata: {role: 'dealer'}, user_metadata: {role: 'admin'}}, 403],
  ]) {
    const response = await handler(new Request('https://local.test/analytics', {
      method: 'GET', headers: user ? {'x-test-user': JSON.stringify(user)} : {},
    }));
    assert.equal(response.status, expected);
  }
  assert.equal(reads, 0);
  const admin = {id: 'admin', email_confirmed_at: 'yes', app_metadata: {role: 'admin'}};
  const post = await handler(new Request('https://local.test/analytics', {
    method: 'POST', headers: {'x-test-user': JSON.stringify(admin)},
  }));
  assert.equal(post.status, 405);
  assert.equal(reads, 0);
  const get = await handler(new Request('https://local.test/analytics?period=monthly', {
    method: 'GET', headers: {'x-test-user': JSON.stringify(admin)},
  }));
  assert.equal(get.status, 200);
  assert.equal(reads, 1);
});
