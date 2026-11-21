// Reward points: code deployed BEFORE migration 010 (today's live
// database). Separate file: the sandbox replaces db.js for its process.
const test = require('node:test');
const assert = require('node:assert/strict');
const { startSandbox } = require('../scripts/local_sandbox.cjs');

// Code deployed before migration 010 (today's live database): the previous
// 5% whole-point behaviour continues unchanged and claims are not offered.
test('before the migration: previous behaviour, checkout keeps working', async t => {
  const legacy = await startSandbox({ port: 0, quiet: true, migrated: false });
  t.after(() => legacy.close());
  const url = `http://localhost:${legacy.port}`;
  const call = async (method, path, body, token) => {
    const res = await fetch(url + path, {
      method,
      headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: res.status, body: await res.json() };
  };
  const { email: ae, password: ap } = legacy.credentials.admin;
  const adminToken = (await call('POST', '/api/admin/login', { email: ae, password: ap })).body.token;
  const email = 'legacy.reward@example.test';
  await call('POST', '/api/auth/signup', { name: 'Legacy Dealer', email, mobile: '9000000002', password: 'legacy-pass-123', confirmPassword: 'legacy-pass-123', companyName: 'Legacy Traders', address: '2 Test Road, Chennai 600001' });
  await call('POST', '/api/admin/set-status', { email, status: 'approved' }, adminToken);
  const login = await call('POST', '/api/auth/login', { identifier: email, password: 'legacy-pass-123' });
  const token = login.body.token || login.body.user.token;
  const placed = await call('POST', '/api/user/orders/create', {
    email, paymentMethod: 'Cash on Delivery',
    deliveryAddress: { line1: '2 Test Road', city: 'Chennai', pincode: '600001' },
    items: [{ id: 'SAMPLE_RO_MEM_75', quantity: 1 }],
  }, token);
  assert.equal(placed.status, 200, JSON.stringify(placed.body));
  assert.equal(placed.body.pointsEarned, Math.floor(Number(placed.body.order.grandTotal) * 0.05));
  const r = (await call('GET', `/api/user/rewards?email=${encodeURIComponent(email)}`, undefined, token)).body;
  assert.equal(r.availablePoints, placed.body.pointsEarned);
  assert.equal(r.history.length, 1);
  assert.equal(r.history[0].status, 'credited');
  assert.equal(r.canClaim, false);
  assert.equal((await call('POST', '/api/user/rewards/claim', { points: 1 }, token)).status, 503);
  assert.deepEqual((await call('GET', '/api/admin/reward-claims', undefined, adminToken)).body.claims, []);
  const cancel = await call('PUT', `/api/admin/orders/${placed.body.order.orderId}/status`, { status: 'Cancelled' }, adminToken);
  assert.equal(cancel.status, 200, 'cancelling still works (rewards untouched, as before)');
});
