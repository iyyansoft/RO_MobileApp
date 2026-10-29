const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  AdminShopNotificationsError,
  createAdminShopNotificationsHandler,
  createAdminShopNotificationsRepository,
} = require('../supabase/functions/_shared/admin_shop_notifications_core.mjs');

function queryService({notifications = [], employees = [], errorTable = null} = {}) {
  const calls = [];
  return {
    calls,
    from(table) {
      const call = {table};
      calls.push(call);
      return {
        select(columns) {
          call.columns = columns;
          return {
            order(column, options) {
              (call.orders ??= []).push([column, options]);
              return this;
            },
            range(from, to) {
              call.range = [from, to];
              if (table === errorTable) return Promise.resolve({data: null, error: {message: 'sensitive db detail'}});
              return Promise.resolve({data: notifications, error: null});
            },
            in(column, values) {
              call.in = [column, values];
              if (table === errorTable) return Promise.resolve({data: null, error: {message: 'sensitive db detail'}});
              return Promise.resolve({data: employees, error: null});
            },
          };
        },
      };
    },
  };
}

const admin = {id: 'admin-1', email_confirmed_at: 'verified', app_metadata: {role: 'admin'}};

test('inbox matches Express notification fields and employee labels with bounded explicit reads', async () => {
  const service = queryService({
    notifications: [{
      id: 'n1', order_id: 'RO-123', employee_id: 'employee-1', notification_type: 'partial_delivery',
      message: 'Partial delivery recorded.', refund_amount: '650.00', created_at: '2026-10-28T10:00:00Z',
      read_at: null, password_hash: 'must-not-be-selected',
    }],
    employees: [{id: 'employee-1', employee_id: 'shop-42', full_name: 'Sam'}],
  });
  const result = await createAdminShopNotificationsRepository(service).listNotifications();
  assert.deepEqual(result.notifications[0], {
    id: 'n1', order_id: 'RO-123', notification_type: 'partial_delivery',
    message: 'Partial delivery recorded.', refund_amount: '650.00',
    created_at: '2026-10-28T10:00:00.000Z', read_at: null,
    employee_id: 'shop-42', full_name: 'Sam',
  });
  assert.equal(service.calls[0].table, 'shop_admin_notifications');
  assert.equal(service.calls[0].columns, 'id,order_id,employee_id,notification_type,message,refund_amount,created_at,read_at');
  assert.deepEqual(service.calls[0].range, [0, 249]);
  assert.deepEqual(service.calls[0].orders, [
    ['created_at', {ascending: false}], ['id', {ascending: false}],
  ]);
  assert.equal(service.calls[1].table, 'shop_employees');
  assert.equal(service.calls[1].columns, 'id,employee_id,full_name');
  assert.doesNotMatch(service.calls[0].columns, /password|otp|purchase_price/i);
});

test('empty inbox performs no unnecessary employee query', async () => {
  const service = queryService();
  assert.deepEqual(
    await createAdminShopNotificationsRepository(service).listNotifications(),
    {success: true, notifications: []},
  );
  assert.equal(service.calls.length, 1);
});

test('notification and employee database failures are sanitized', async () => {
  for (const errorTable of ['shop_admin_notifications', 'shop_employees']) {
    const service = queryService({
      notifications: [{id: 'n1', employee_id: 'employee-1'}],
      errorTable,
    });
    await assert.rejects(
      createAdminShopNotificationsRepository(service).listNotifications(),
      error => error instanceof AdminShopNotificationsError && error.status === 503 &&
        error.message === 'Shop delivery notifications are unavailable.' && !error.message.includes('sensitive'),
    );
  }
});

test('handler rejects missing, unverified and client-metadata-only admins before reads', async () => {
  let reads = 0;
  const handler = createAdminShopNotificationsHandler({
    authenticate: async request => {
      const value = request.headers.get('x-test-user');
      return value ? JSON.parse(value) : null;
    },
    repository: {async listNotifications() { reads++; return {success: true, notifications: []}; }},
  });
  for (const [user, status] of [
    [null, 401],
    [{id: 'u'}, 401],
    [{id: 'u', email_confirmed_at: 'yes', app_metadata: {role: 'dealer'}, user_metadata: {role: 'admin'}}, 403],
  ]) {
    const response = await handler(new Request('https://local.test/admin-shop-notifications', {
      method: 'GET', headers: user ? {'x-test-user': JSON.stringify(user)} : {},
    }));
    assert.equal(response.status, status);
  }
  assert.equal(reads, 0);
});

test('only GET is accepted and a verified trusted admin can read notifications', async () => {
  let reads = 0;
  const handler = createAdminShopNotificationsHandler({
    authenticate: async () => admin,
    repository: {async listNotifications() { reads++; return {success: true, notifications: []}; }},
  });
  assert.equal((await handler(new Request('https://local.test', {method: 'POST'}))).status, 405);
  const response = await handler(new Request('https://local.test', {method: 'GET'}));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {success: true, notifications: []});
  assert.equal(reads, 1);
});
