const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  AdminShopEmployeesError,
  createAdminShopEmployeesHandler,
  createAdminShopEmployeesRepository,
} = require('../supabase/functions/_shared/admin_shop_employees_core.mjs');

const admin = {id: 'admin-1', email_confirmed_at: 'verified', app_metadata: {role: 'admin'}};

function queryService({pages = [[]], errorPage = -1} = {}) {
  const calls = [];
  return {
    calls,
    from(table) {
      assert.equal(table, 'shop_employees');
      const call = {table, orders: []};
      calls.push(call);
      return {
        select(columns) {
          call.columns = columns;
          return {
            order(column, options) {
              call.orders.push([column, options]);
              return this;
            },
            range(from, to) {
              call.from = from;
              call.to = to;
              const page = calls.indexOf(call);
              if (page === errorPage) return Promise.resolve({data: null, error: {message: 'private query details'}});
              return Promise.resolve({data: pages[page] ?? [], error: null});
            },
          };
        },
      };
    },
  };
}

test('employee list matches Express fields and never selects password hashes', async () => {
  const service = queryService({pages: [[{
    id: 'employee-1', employee_id: 'SHOP-1', shop_name: 'RO Shop',
    full_name: 'Alex', active: true, created_at: '2026-10-28T10:00:00Z',
    password_hash: 'must-not-be-selected',
  }]]});
  const result = await createAdminShopEmployeesRepository(service).listEmployees();
  assert.deepEqual(result.employees[0], {
    id: 'employee-1', employee_id: 'SHOP-1', shop_name: 'RO Shop',
    full_name: 'Alex', active: true, created_at: '2026-10-28T10:00:00.000Z',
  });
  assert.equal(service.calls[0].columns, 'id,employee_id,shop_name,full_name,active,created_at');
  assert.deepEqual([service.calls[0].from, service.calls[0].to], [0, 499]);
});

test('employee list paginates without silently truncating at one PostgREST page', async () => {
  const firstPage = Array.from({length: 500}, (_, index) => ({
    id: `id-${index}`, employee_id: `SHOP-${index}`, shop_name: 'RO Shop',
    full_name: `Employee ${index}`, active: true, created_at: '2026-10-28T10:00:00Z',
  }));
  const secondPage = [{
    id: 'id-last', employee_id: 'SHOP-LAST', shop_name: 'RO Shop',
    full_name: 'Last', active: false, created_at: '2026-10-27T10:00:00Z',
  }];
  const service = queryService({pages: [firstPage, secondPage]});
  const result = await createAdminShopEmployeesRepository(service).listEmployees();
  assert.equal(result.employees.length, 501);
  assert.deepEqual(service.calls.map(call => [call.from, call.to]), [[0, 499], [500, 999]]);
});

test('employee list database errors are sanitized', async () => {
  const service = queryService({errorPage: 0});
  await assert.rejects(
    createAdminShopEmployeesRepository(service).listEmployees(),
    error => error instanceof AdminShopEmployeesError && error.status === 503 &&
      error.message === 'Employee list is unavailable.' && !error.message.includes('private'),
  );
});

test('handler denies anonymous, unverified and client-role-only users before queries', async () => {
  let reads = 0;
  const handler = createAdminShopEmployeesHandler({
    authenticate: async request => {
      const value = request.headers.get('x-test-user');
      return value ? JSON.parse(value) : null;
    },
    repository: {async listEmployees() { reads++; return {success: true, employees: []}; }},
  });
  for (const [user, status] of [
    [null, 401],
    [{id: 'u'}, 401],
    [{id: 'u', email_confirmed_at: 'verified', app_metadata: {role: 'dealer'}, user_metadata: {role: 'admin'}}, 403],
  ]) {
    const response = await handler(new Request('https://local.test', {
      method: 'GET', headers: user ? {'x-test-user': JSON.stringify(user)} : {},
    }));
    assert.equal(response.status, status);
  }
  assert.equal(reads, 0);
});

test('only GET is supported and a verified trusted admin can read employees', async () => {
  let reads = 0;
  const handler = createAdminShopEmployeesHandler({
    authenticate: async () => admin,
    repository: {async listEmployees() { reads++; return {success: true, employees: []}; }},
  });
  assert.equal((await handler(new Request('https://local.test', {method: 'DELETE'}))).status, 405);
  const response = await handler(new Request('https://local.test', {method: 'GET'}));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {success: true, employees: []});
  assert.equal(reads, 1);
});
