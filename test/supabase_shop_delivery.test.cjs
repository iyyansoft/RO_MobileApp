const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  createShopDeliveryHandler, createShopDeliveryRepository,
} = require('../supabase/functions/_shared/shop_delivery_core.mjs');

const employee = {
  id: 'auth-employee',
  email_confirmed_at: '2026-10-01T00:00:00Z',
  app_metadata: { role: 'shop_employee' },
  user_metadata: { role: 'admin', shopName: 'untrusted client metadata' },
};

function post(body, authorization = 'Bearer employee-token') {
  return new Request('http://local/functions/v1/shop-delivery', {
    method: 'POST',
    headers: authorization ? { Authorization: authorization, 'Content-Type': 'application/json' } : { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

test('delivery Edge handler rejects unauthorized, unverified and dealer identities before database access', async () => {
  let submits = 0;
  const handler = createShopDeliveryHandler({
    authenticate: async () => null,
    submit: async () => { submits += 1; },
  });
  assert.equal((await handler(post({ orderId: 'O-1', mode: 'confirm', items: [] }))).status, 401);

  for (const user of [
    { ...employee, email_confirmed_at: null },
    { ...employee, app_metadata: { role: 'dealer' } },
  ]) {
    const denied = createShopDeliveryHandler({ authenticate: async () => user, submit: async () => { submits += 1; } });
    assert.equal((await denied(post({ orderId: 'O-1', mode: 'confirm', items: [] }))).status, 403);
  }
  assert.equal(submits, 0);
});

test('delivery request validates explicit independent item statuses and sends only allow-listed fields', async () => {
  let received;
  const handler = createShopDeliveryHandler({
    authenticate: async () => employee,
    submit: async value => { received = value; return { status: 'Partially Delivered' }; },
  });
  const response = await handler(post({
    orderId: ' O-1 ', mode: 'confirm', cashCollected: false, shopName: 'attacker',
    items: [
      { orderItemId: 4, deliveredQuantity: 1, deliveryConfirmed: true, dealerPrice: 0.01 },
      { orderItemId: 5, deliveredQuantity: 0, deliveryConfirmed: false },
    ],
  }));
  assert.equal(response.status, 200);
  assert.deepEqual(received, {
    authUserId: 'auth-employee', orderId: 'O-1', mode: 'confirm', cashCollected: false,
    items: [
      { orderItemId: 4, deliveredQuantity: 1, deliveryConfirmed: true },
      { orderItemId: 5, deliveredQuantity: 0, deliveryConfirmed: false },
    ],
  });
});

test('delivery handler rejects missing status, duplicate items, invalid quantities and cash during draft submission', async () => {
  const handler = createShopDeliveryHandler({ authenticate: async () => employee, submit: async () => ({}) });
  const invalid = [
    { orderId: 'O-1', mode: 'confirm', items: [{ orderItemId: 1, deliveredQuantity: 1 }] },
    { orderId: 'O-1', mode: 'confirm', items: [
      { orderItemId: 1, deliveredQuantity: 1, deliveryConfirmed: true },
      { orderItemId: 1, deliveredQuantity: 1, deliveryConfirmed: true },
    ] },
    { orderId: 'O-1', mode: 'confirm', items: [{ orderItemId: 1, deliveredQuantity: -1, deliveryConfirmed: false }] },
    { orderId: 'O-1', mode: 'confirm', items: [{ orderItemId: 1, deliveredQuantity: 2147483648, deliveryConfirmed: false }] },
    { orderId: 'O-1', mode: 'submit', cashCollected: true,
      items: [{ orderItemId: 1, deliveredQuantity: 1, deliveryConfirmed: false }] },
  ];
  for (const body of invalid) assert.equal((await handler(post(body))).status, 400);
});

test('delivery repository calls only the privileged server RPC with the verified Auth identity', async () => {
  let call;
  const repository = createShopDeliveryRepository({
    rpc: async (name, args) => { call = { name, args }; return { data: { success: true }, error: null }; },
  });
  await repository({ authUserId: 'auth-employee', orderId: 'O-1', mode: 'confirm',
    cashCollected: true, items: [{ orderItemId: 4, deliveredQuantity: 1, deliveryConfirmed: true }] });
  assert.equal(call.name, 'ro_submit_shop_delivery');
  assert.equal(call.args.p_auth_user_id, 'auth-employee');
  assert.equal(call.args.p_cash_collected, true);
  assert.equal(Object.hasOwn(call.args, 'p_shop_name'), false);
});

test('delivery handler maps authorization and order conflicts without exposing database detail', async () => {
  for (const [code, expectedStatus] of [['42501', 403], ['P0002', 404], ['P0001', 409], ['XX000', 503]]) {
    const handler = createShopDeliveryHandler({
      authenticate: async () => employee,
      submit: async () => { throw { code, message: 'internal SQL text' }; },
    });
    const response = await handler(post({ orderId: 'O-1', mode: 'confirm',
      items: [{ orderItemId: 1, deliveredQuantity: 1, deliveryConfirmed: true }] }));
    const body = await response.json();
    assert.equal(response.status, expectedStatus);
    assert.ok(!body.error.includes('internal SQL text'));
  }
});
