const { test } = require('node:test');
const assert = require('node:assert/strict');
const install = require('../order_checkout');
const { createDealerToken } = require('../checkout_service');
function setup(failWrite = false, assignmentAvailable = true, shopNames = ['Test Shop']) {
  const routes = {}, writes = []; let committed = false, rollback = false;
  let existingOrder = null;
  const assignments = new Map();
  const user = { id: 'dealer', email: 'dealer@example.test', name: 'Dealer' };
  const conn = { beginTransaction: async () => {}, commit: async () => { committed = true; }, rollback: async () => { rollback = true; }, release: () => {},
    query: async (sql, values) => {
      if (sql.startsWith('SELECT * FROM products')) return [[{ id: 'ro', name: 'RO', price: 900, stock_quantity: 5 }]];
      if (sql.includes("to_regclass('public.shop_order_assignments')")) return [[{ available: assignmentAvailable }]];
      if (sql.startsWith('SELECT shop_name FROM shop_order_assignments')) return [[...(assignments.has(values[0]) ? [{ shop_name: assignments.get(values[0]) }] : [])]];
      if (sql.startsWith('SELECT order_id, payment_status FROM orders')) return [[existingOrder && existingOrder.order_id === values[0] ? existingOrder : null].filter(Boolean)];
      if (sql.startsWith('SELECT shop_name FROM shop_employees')) return [shopNames.map(shop_name => ({ shop_name }))];
      if (sql.includes('INSERT INTO shop_order_assignments')) { assignments.set(values[0], values[1]); writes.push([sql, values]); return [{ affectedRows: 1 }]; }
      if (failWrite) throw Object.assign(Error('PostgreSQL insert failed'), {code: typeof failWrite === 'string' ? failWrite : 'ER_DATA_TOO_LONG'});
      if (sql.startsWith('INSERT INTO orders')) existingOrder = { order_id: values[0], payment_status: values[21] };
      writes.push([sql, values]); return [{ affectedRows: 1 }];
    } };
  install({ post: (route, fn) => routes[route] = fn }, { getConnection: async () => conn }, 'secret', async () => user);
  const call = async (body, token = createDealerToken(user, 'secret')) => {
    const res = { code: 200, status(code) { this.code = code; return this; }, json(data) { this.body = data; return this; } };
    await routes['/api/user/orders/create']({ headers: { authorization: `Bearer ${token}` }, body: { email: user.email, ...body } }, res); return res;
  };
  return { call, writes, state: () => ({ committed, rollback }) };
}
const checkout = { items: [{ id: 'ro', quantity: 1, numericPrice: 1 }], grandTotal: 1, withGst: false, paymentMethod: 'Cash on Delivery', deliveryAddress: { address: 'Saved street' } };
test('COD order uses canonical Dealer Price and returns success after PostgreSQL commit', async () => {
  const api = setup(); const res = await api.call(checkout);
  assert.equal(res.code, 200); assert.equal(res.body.order.grandTotal, 1060); assert.equal(res.body.order.gst, 0); assert.equal(res.body.order.paymentStatus, 'due_on_delivery');
  assert.deepEqual(api.state(), { committed: true, rollback: false });
});
test('COD checkout retry with the same request key returns the saved order without duplicate writes', async () => {
  const api = setup();
  const request = { ...checkout, checkoutRequestId: '8f1ef83b-78a7-42e6-a865-98cba879bbf0' };
  const first = await api.call(request);
  const second = await api.call(request);
  assert.equal(first.code, 200);
  assert.equal(second.code, 200);
  assert.equal(second.body.idempotent, true);
  assert.equal(second.body.order.orderId, first.body.order.orderId);
  assert.equal(api.writes.filter(([sql]) => sql.startsWith('INSERT INTO orders')).length, 1);
  assert.equal(api.writes.filter(([sql]) => sql.includes('INSERT INTO shop_order_assignments')).length, 1);
});
test('COD checkout still commits if optional shop assignment storage is absent', async () => {
  const api = setup(false, false);
  const res = await api.call(checkout);
  assert.equal(res.code, 200);
  assert.equal(res.body.success, true);
  assert.equal(res.body.assignedShopName, 'Test Shop');
  assert.equal(api.writes.some(([sql]) => sql.includes('INSERT INTO shop_order_assignments')), false);
});
test('checkout refuses to silently save an order that cannot be routed among multiple shops', async () => {
  const api = setup(false, false, ['North Shop', 'South Shop']);
  const res = await api.call(checkout);
  assert.equal(res.code, 503);
  assert.match(res.body.error, /cannot be routed/i);
  assert.deepEqual(api.state(), { committed: false, rollback: true });
});
test('database write failure rolls back without returning an order or JSON success', async () => {
  const api = setup(true); const res = await api.call(checkout);
  assert.equal(res.code, 500); assert.equal(res.body.success, false); assert.equal(res.body.code, 'ER_DATA_TOO_LONG'); assert.deepEqual(api.state(), { committed: false, rollback: true });
});
test('checkout identifies connection, credential and schema failures accurately', async () => {
  for (const [code, message] of [['ECONNREFUSED', 'unavailable'], ['ER_ACCESS_DENIED_ERROR', 'credentials'], ['ER_BAD_FIELD_ERROR', 'schema']]) {
    const api = setup(code); const res = await api.call(checkout);
    assert.equal(res.code, 503); assert.equal(res.body.code, code); assert.ok(res.body.error.includes(message)); assert.equal(api.state().committed, false);
  }
});
test('invalid login, invalid GST and old payment methods cannot create orders', async () => {
  const api = setup(); assert.equal((await api.call(checkout, 'forged')).code, 401);
  assert.equal((await api.call({ ...checkout, withGst: true })).code, 400);
  assert.equal((await api.call({ ...checkout, paymentMethod: 'UPI' })).code, 400);
  assert.equal(api.writes.length, 0);
});
