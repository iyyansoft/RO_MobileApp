// Bulk Orders code on today's database (before migration 011): normal
// shopping is unchanged and bulk requests are refused. Separate file: the
// sandbox replaces db.js for its process.
const test = require('node:test');
const assert = require('node:assert/strict');
const { startSandbox } = require('../scripts/local_sandbox.cjs');

test('before migration 011: normal cart unchanged, bulk refused', async t => {
  const sb = await startSandbox({ port: 0, quiet: true, migrated: false });
  t.after(() => sb.close());
  const base = `http://localhost:${sb.port}`;
  const http = async (method, url, body, token) => {
    const r = await fetch(base + url, { method, headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: body ? JSON.stringify(body) : undefined });
    return { status: r.status, body: await r.json() };
  };
  const admin = (await http('POST', '/api/admin/login', sb.credentials.admin)).body.token;
  const email = 'bulk.legacy@example.test';
  await http('POST', '/api/auth/signup', { name: 'Legacy Bulk', email, mobile: '9000000004', password: 'legacy-bulk-123', confirmPassword: 'legacy-bulk-123', companyName: 'Legacy', address: '4 Test Road, Chennai 600001' });
  await http('POST', '/api/admin/set-status', { email, status: 'approved' }, admin);
  const login = await http('POST', '/api/auth/login', { identifier: email, password: 'legacy-bulk-123' });
  const token = login.body.token || login.body.user.token;
  const userId = login.body.user.id;

  const products = (await http('GET', '/api/products')).body.products;
  assert.ok(products.length > 0);
  assert.ok(products.every(p => p.bulk_price === null), 'no bulk offers before the migration');
  const bulk = await http('POST', '/api/cart/add', { userId, productId: 'SAMPLE_RO_MEM_75', quantity: 42, purchaseMode: 'bulk' }, token);
  assert.equal(bulk.status, 503);
  const normal = await http('POST', '/api/cart/add', { userId, productId: 'SAMPLE_RO_MEM_75', quantity: 1 }, token);
  assert.equal(normal.status, 200, JSON.stringify(normal.body));
  assert.equal(normal.body.items[0].purchase_mode, 'normal');
  assert.equal((await http('PUT', '/api/cart/update', { userId, productId: 'SAMPLE_RO_MEM_75', quantity: 2 }, token)).status, 200);
  const order = await http('POST', '/api/user/orders/create', {
    email, paymentMethod: 'Cash on Delivery', deliveryAddress: { line1: '4 Test Road', city: 'Chennai', pincode: '600001' },
    items: [{ id: 'SAMPLE_RO_MEM_75', quantity: 2 }],
  }, token);
  assert.equal(order.status, 200, JSON.stringify(order.body));
  const refused = await http('POST', '/api/user/orders/create', {
    email, paymentMethod: 'Cash on Delivery', deliveryAddress: { line1: '4 Test Road', city: 'Chennai', pincode: '600001' },
    items: [{ id: 'SAMPLE_RO_MEM_75', quantity: 42, purchaseMode: 'bulk' }],
  }, token);
  assert.notEqual(refused.status, 200, 'bulk checkout refused before the migration');
});
