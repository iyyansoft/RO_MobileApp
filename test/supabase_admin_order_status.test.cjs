const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  AdminOrderStatusError,
  createAdminOrderStatusHandler,
  createAdminOrderStatusRepository,
} = require('../supabase/functions/_shared/admin_order_status_core.mjs');

const admin = {id: 'admin-uuid', email_confirmed_at: '2026-10-01T00:00:00Z', app_metadata: {role: 'admin'}};

function makeRequest(body, {user = admin, method = 'POST'} = {}) {
  return new Request('https://local.test/admin-order-status', {
    method,
    headers: {
      ...(user ? {'x-test-user': JSON.stringify(user)} : {}),
      ...(body === undefined ? {} : {'content-type': 'application/json'}),
    },
    ...(body === undefined || method !== 'POST' ? {} : {body: JSON.stringify(body)}),
  });
}

test('status mutation requires a verified trusted admin before calling the repository', async () => {
  let writes = 0;
  const handler = createAdminOrderStatusHandler({
    authenticate: async request => JSON.parse(request.headers.get('x-test-user') ?? 'null'),
    repository: {async setStatus() { writes++; return {success: true}; }},
  });
  assert.equal((await handler(makeRequest({orderId: 'o1', status: 'Shipped'}, {user: null}))).status, 401);
  assert.equal((await handler(makeRequest({orderId: 'o1', status: 'Shipped'}, {user: {...admin, email_confirmed_at: null}}))).status, 401);
  assert.equal((await handler(makeRequest({orderId: 'o1', status: 'Shipped'}, {user: {...admin, app_metadata: {role: 'dealer'}, user_metadata: {role: 'admin'}}}))).status, 403);
  assert.equal(writes, 0);
});

test('handler validates order payload, method and request size', async () => {
  let writes = 0;
  const handler = createAdminOrderStatusHandler({
    authenticate: async () => admin,
    repository: {async setStatus() { writes++; return {success: true}; }},
  });
  for (const body of [null, {}, {orderId: '', status: 'Shipped'}, {orderId: 'o1', status: ' '}]) {
    assert.equal((await handler(makeRequest(body))).status, 400);
  }
  assert.equal((await handler(makeRequest(undefined, {method: 'GET'}))).status, 405);
  const tooLarge = new Request('https://local.test/admin-order-status', {
    method: 'POST', headers: {'content-length': '9000'}, body: '{}',
  });
  assert.equal((await handler(tooLarge)).status, 413);
  const largeAuthorized = new Request('https://local.test/admin-order-status', {
    method: 'POST', headers: {'content-length': '9000', 'x-test-user': JSON.stringify(admin)}, body: '{}',
  });
  assert.equal((await handler(largeAuthorized)).status, 413);
  assert.equal(writes, 0);
});

test('repository calls only the restricted transactional RPC and maps safe errors', async () => {
  const calls = [];
  const service = {async rpc(name, args) {
    calls.push([name, args]);
    return {data: {success: true, orderId: args.p_order_id, status: args.p_status}, error: null};
  }};
  const result = await createAdminOrderStatusRepository(service).setStatus({
    adminUserId: admin.id, orderId: 'RO-1', status: 'Shipped',
  });
  assert.deepEqual(result, {success: true, orderId: 'RO-1', status: 'Shipped'});
  assert.deepEqual(calls, [['ro_admin_update_order_status', {
    p_admin_user_id: admin.id, p_order_id: 'RO-1', p_status: 'Shipped',
  }]]);
  for (const [code, status] of [['P0002', 404], ['55000', 409], ['22023', 400], ['28000', 403], ['XX000', 503]]) {
    const repository = createAdminOrderStatusRepository({rpc: async () => ({data: null, error: {code, message: 'private database text'}})});
    await assert.rejects(repository.setStatus({adminUserId: admin.id, orderId: 'RO-1', status: 'Shipped'}), error =>
      error instanceof AdminOrderStatusError && error.status === status && !error.message.includes('private database text'));
  }
});

test('local SQL draft is additive and limits RPC execution to server role', () => {
  const draft = fs.readFileSync(path.join(__dirname, '..', 'supabase/drafts/unreconciled/20261028_admin_order_status.sql'), 'utf8');
  assert.match(draft, /CREATE OR REPLACE FUNCTION public\.ro_admin_update_order_status/);
  assert.match(draft, /FOR UPDATE/);
  assert.match(draft, /raw_app_meta_data->>'role'='admin'/);
  assert.match(draft, /REVOKE ALL ON FUNCTION[\s\S]*FROM PUBLIC, anon, authenticated/);
  assert.match(draft, /GRANT EXECUTE ON FUNCTION[\s\S]*TO service_role/);
  assert.doesNotMatch(draft, /CREATE TABLE|DROP TABLE|TRUNCATE|DELETE FROM/i);
});
