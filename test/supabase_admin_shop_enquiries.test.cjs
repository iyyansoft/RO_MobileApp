const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  AdminShopEnquiriesError,
  createAdminShopEnquiriesHandler,
  createAdminShopEnquiriesRepository,
} = require('../supabase/functions/_shared/admin_shop_enquiries_core.mjs');

function queryService({enquiries = [], employees = [], errorTable = null} = {}) {
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
              return Promise.resolve({data: enquiries, error: null});
            },
            in(column, values) {
              call.in = [column, values];
              return Promise.resolve({data: employees, error: null});
            },
          };
        },
      };
    },
  };
}

const admin = {id: 'admin-1', email_confirmed_at: 'verified', app_metadata: {role: 'admin'}};

test('inbox returns the Express response fields with employee IDs and bounded explicit reads', async () => {
  const service = queryService({
    enquiries: [{
      id: 'e1', employee_id: 'employee-1', customer_name: 'Customer', company_name: 'Co',
      contact_number: '0000000000', category: 'RO', product_name: 'Membrane',
      required_quantity: 2, remarks: null, status: 'new', created_at: '2026-10-28T10:00:00Z',
      password_hash: 'must-not-be-selected',
    }],
    employees: [{id: 'employee-1', employee_id: 'shop-42'}],
  });
  const result = await createAdminShopEnquiriesRepository(service).listEnquiries();
  assert.deepEqual(result.enquiries[0], {
    id: 'e1', employee_id: 'employee-1', customer_name: 'Customer', company_name: 'Co',
    contact_number: '0000000000', category: 'RO', product_name: 'Membrane',
    required_quantity: 2, remarks: null, status: 'new',
    created_at: '2026-10-28T10:00:00.000Z', submitted_by: 'shop-42',
  });
  assert.equal(service.calls[0].table, 'shop_product_enquiries');
  assert.equal(service.calls[0].columns, 'id,employee_id,customer_name,company_name,contact_number,category,product_name,required_quantity,remarks,status,created_at');
  assert.deepEqual(service.calls[0].range, [0, 499]);
  assert.deepEqual(service.calls[0].orders, [
    ['created_at', {ascending: false}], ['id', {ascending: false}],
  ]);
  assert.equal(service.calls[1].table, 'shop_employees');
  assert.equal(service.calls[1].columns, 'id,employee_id');
  assert.doesNotMatch(service.calls[0].columns, /password|otp|purchase_price/i);
});

test('inbox handles no enquiries without making an unnecessary employee query', async () => {
  const service = queryService();
  const result = await createAdminShopEnquiriesRepository(service).listEnquiries();
  assert.deepEqual(result, {success: true, enquiries: []});
  assert.equal(service.calls.length, 1);
});

test('database failures are sanitized', async () => {
  const service = queryService({errorTable: 'shop_product_enquiries'});
  await assert.rejects(
    createAdminShopEnquiriesRepository(service).listEnquiries(),
    error => error instanceof AdminShopEnquiriesError && error.status === 503 &&
      error.message === 'Shop enquiries are unavailable.' && !error.message.includes('sensitive'),
  );
});

test('handler rejects missing, unverified and client-metadata-only admin claims before reads', async () => {
  let reads = 0;
  const handler = createAdminShopEnquiriesHandler({
    authenticate: async request => {
      const value = request.headers.get('x-test-user');
      return value ? JSON.parse(value) : null;
    },
    repository: {async listEnquiries() { reads++; return {success: true, enquiries: []}; }},
  });
  for (const [user, status] of [
    [null, 401],
    [{id: 'u'}, 401],
    [{id: 'u', email_confirmed_at: 'yes', app_metadata: {role: 'dealer'}, user_metadata: {role: 'admin'}}, 403],
  ]) {
    const response = await handler(new Request('https://local.test/admin-shop-enquiries', {
      method: 'GET', headers: user ? {'x-test-user': JSON.stringify(user)} : {},
    }));
    assert.equal(response.status, status);
  }
  assert.equal(reads, 0);
});

test('only GET is accepted and verified trusted admin can load inbox', async () => {
  let reads = 0;
  const handler = createAdminShopEnquiriesHandler({
    authenticate: async () => admin,
    repository: {async listEnquiries() { reads++; return {success: true, enquiries: []}; }},
  });
  assert.equal((await handler(new Request('https://local.test', {method: 'POST'}))).status, 405);
  const response = await handler(new Request('https://local.test', {method: 'GET'}));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {success: true, enquiries: []});
  assert.equal(reads, 1);
});
