// Reward points v2 (rewards.js + migration 010): 2.5% with decimals, one
// credit per order, reversal on cancellation, Rs 1,00,000 cumulative Free
// Claim threshold, claims approved/rejected by the admin.
// Runs the real server on an isolated in-memory PostgreSQL; never touches
// the live database.
const test = require('node:test');
const assert = require('node:assert/strict');
const { startSandbox } = require('../scripts/local_sandbox.cjs');
const { rewardPointsFor, creditOrderReward } = require('../rewards');

test('2.5% points, exact decimals', () => {
  const cases = [
    [500, 12.5], [1000, 25], [10000, 250], [100000, 2500],
    [511, 12.78], // 12.775 -> half-up
    [1, 0.03], [0.4, 0.01], [790, 19.75], [17460, 436.5], [50850, 1271.25],
    [0, 0], [-50, 0], ['1000', 25], [null, 0],
  ];
  for (const [amount, points] of cases) assert.equal(rewardPointsFor(amount), points, `₹${amount}`);
});

let sandbox; let base; const state = {};
async function http(method, url, body, token) {
  const res = await fetch(base + url, {
    method,
    headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}
const dealer = (m, u, b) => http(m, u, b, state.dealerToken);
const admin = (m, u, b) => http(m, u, b, state.adminToken);
const rewards = async () => (await dealer('GET', `/api/user/rewards?email=${encodeURIComponent(state.email)}`)).body;
const order = async quantity => {
  const res = await dealer('POST', '/api/user/orders/create', {
    email: state.email, paymentMethod: 'Cash on Delivery',
    deliveryAddress: { line1: '1 Test Road', city: 'Chennai', pincode: '600001' },
    items: [{ id: 'SAMPLE_RO_MEM_75', quantity }],
    // Values the app might send are ignored by the server.
    grandTotal: 99999999, pointsEarned: 99999,
  });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  return res.body;
};

test('ledger over HTTP', async t => {
  sandbox = await startSandbox({ port: 0, quiet: true });
  base = `http://localhost:${sandbox.port}`;
  t.after(() => sandbox.close());

  const { email: adminEmail, password: adminPassword } = sandbox.credentials.admin;
  state.adminToken = (await http('POST', '/api/admin/login', { email: adminEmail, password: adminPassword })).body.token;
  state.email = 'reward.dealer@example.test';
  const account = { name: 'Reward Dealer', email: state.email, mobile: '9000000001', password: 'reward-pass-123', confirmPassword: 'reward-pass-123', companyName: 'Reward Traders', address: '1 Test Road, Chennai 600001' };
  assert.equal((await http('POST', '/api/auth/signup', account)).status, 200);
  assert.equal((await admin('POST', '/api/admin/set-status', { email: state.email, status: 'approved' })).status, 200);
  const login = await http('POST', '/api/auth/login', { identifier: state.email, password: 'reward-pass-123' });
  state.dealerToken = login.body.token || login.body.user.token;
  state.userId = login.body.user.id;

  await t.test('new dealer: zero, locked, full ₹1,00,000 to go', async () => {
    const r = await rewards();
    assert.equal(r.availablePoints, 0);
    assert.equal(r.freeClaimUnlocked, false);
    assert.equal(r.remainingForFreeClaim, 100000);
    assert.equal(r.freeClaimThreshold, 100000);
  });

  await t.test('checkout credits 2.5% of the server total, with decimals, once', async () => {
    const placed = await order(1);
    const total = Number(placed.order.grandTotal);
    assert.ok(total > 0 && total < 99999999, 'server-quoted total, not the client value');
    assert.equal(placed.pointsEarned, rewardPointsFor(total));
    state.firstOrder = placed.order.orderId; state.firstPoints = placed.pointsEarned; state.firstTotal = total;
    const r = await rewards();
    assert.equal(r.availablePoints, rewardPointsFor(total));
    assert.equal(r.totalPointsEarned, rewardPointsFor(total));
    assert.equal(r.eligiblePurchaseAmount, total);
    assert.equal(r.history[0].orderId, state.firstOrder);
    assert.equal(r.history[0].status, 'credited');
    assert.ok(r.history[0].orderDate);
    // A second credit for the same order is ignored (unique per order).
    const conn = await sandbox.pool.getConnection();
    try { assert.equal(await creditOrderReward(conn, { userId: state.userId, orderId: state.firstOrder, amount: total }), 0); }
    finally { conn.release(); }
    assert.equal((await rewards()).availablePoints, rewardPointsFor(total));
  });

  await t.test('cancel reverses points and eligible amount; un-cancel reinstates once', async () => {
    const cancel = await admin('PUT', `/api/admin/orders/${state.firstOrder}/status`, { status: 'Cancelled' });
    assert.equal(cancel.status, 200, JSON.stringify(cancel.body));
    let r = await rewards();
    assert.equal(r.availablePoints, 0);
    assert.equal(r.totalPointsEarned, 0);
    assert.equal(r.eligiblePurchaseAmount, 0);
    assert.equal(r.history.find(h => h.type === 'earned').status, 'reversed');
    // Cancelling again changes nothing.
    await admin('PUT', `/api/admin/orders/${state.firstOrder}/status`, { status: 'Cancelled' });
    assert.equal((await rewards()).availablePoints, 0);
    assert.equal((await admin('PUT', `/api/admin/orders/${state.firstOrder}/status`, { status: 'Processing & Dispatched' })).status, 200);
    r = await rewards();
    assert.equal(r.availablePoints, state.firstPoints);
    assert.equal(r.eligiblePurchaseAmount, state.firstTotal);
  });

  await t.test('below ₹1,00,000 a claim is refused', async () => {
    const claim = await dealer('POST', '/api/user/rewards/claim', { points: 1 });
    assert.equal(claim.status, 403);
    assert.match(claim.body.error, /Free Claim unlocks after ₹1,00,000/);
    assert.equal((await http('POST', '/api/user/rewards/claim', { points: 1 })).status, 401, 'needs a session');
  });

  await t.test('cumulative purchases reaching ₹1,00,000 unlock Free Claim', async () => {
    // Earlier purchases (legacy-style row, as already stored in production).
    const prior = 100000 - state.firstTotal - 0.01;
    await sandbox.pool.query(`INSERT INTO rewards_history (user_id, order_id, order_amount, points_earned) VALUES (?, NULL, ?, ?)`, [state.userId, prior, 2000]);
    await sandbox.pool.query('UPDATE users SET reward_points = reward_points + 2000 WHERE id = ?', [state.userId]);
    let r = await rewards();
    assert.equal(r.freeClaimUnlocked, false, '1 paisa short');
    assert.equal(r.remainingForFreeClaim, 0.01);
    assert.equal((await dealer('POST', '/api/user/rewards/claim', { points: 1 })).status, 403);
    await order(1);
    r = await rewards();
    assert.equal(r.freeClaimUnlocked, true);
    assert.equal(r.remainingForFreeClaim, 0);
    assert.equal(r.freeClaimProgress, 1);
    assert.equal(r.canClaim, true);
    state.balance = r.availablePoints;
    assert.equal(r.availableValue, r.availablePoints, '1 point = ₹1');
  });

  await t.test('claims: validated, held as pending, approve / reject', async () => {
    for (const points of [0, -5, 'abc', 1.005, state.balance + 1]) {
      const bad = await dealer('POST', '/api/user/rewards/claim', { points });
      assert.ok([400, 409].includes(bad.status), `${points}: ${bad.status}`);
    }
    const first = await dealer('POST', '/api/user/rewards/claim', { points: 100.5, userId: state.userId });
    assert.equal(first.status, 200, JSON.stringify(first.body));
    let r = await rewards();
    assert.equal(r.availablePoints, Math.round((state.balance - 100.5) * 100) / 100);
    assert.equal(r.pendingRedemption, 100.5);
    const second = await dealer('POST', '/api/user/rewards/claim', { points: 50 });
    const claims = (await admin('GET', '/api/admin/reward-claims')).body.claims;
    assert.equal(claims.filter(c => c.status === 'pending').length, 2);
    assert.equal((await http('GET', '/api/admin/reward-claims')).status, 401);
    assert.equal((await admin('PUT', `/api/admin/reward-claims/${first.body.claim.id}`, { status: 'approved' })).status, 200);
    assert.equal((await admin('PUT', `/api/admin/reward-claims/${first.body.claim.id}`, { status: 'rejected' })).status, 409, 'decided once');
    assert.equal((await admin('PUT', `/api/admin/reward-claims/${second.body.claim.id}`, { status: 'rejected' })).status, 200);
    r = await rewards();
    assert.equal(r.totalPointsRedeemed, 100.5);
    assert.equal(r.pendingRedemption, 0);
    assert.equal(r.availablePoints, Math.round((state.balance - 100.5) * 100) / 100, 'rejected points returned');
    const claimRows = r.history.filter(h => h.type === 'redeemed');
    assert.deepEqual(claimRows.map(h => h.status).sort(), ['approved', 'rejected']);
  });

  await t.test('balance always equals the ledger', async () => {
    const [[row]] = await sandbox.pool.query(
      `SELECT u.reward_points AS balance,
              (SELECT SUM(points_earned) - SUM(CASE WHEN status IN ('pending','approved') THEN points_redeemed ELSE 0 END)
                 FROM rewards_history WHERE user_id = u.id) AS ledger
         FROM users u WHERE u.id = ?`, [state.userId]);
    assert.equal(Number(row.balance), Number(row.ledger));
  });
});

