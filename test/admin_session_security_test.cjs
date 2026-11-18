// Admin sessions survive restarts; login lockout and rate limits.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { createAdminAuth } = require('../admin_auth');
const { rateLimit } = require('../rate_limit');

const config = { email: 'Admin@Example.test', password: 'correct horse battery staple', secret: 'session-secret' };

test('a session issued before a restart is still valid after it', () => {
  const before = createAdminAuth(config);
  const token = before.issue();
  const afterRestart = createAdminAuth(config); // new process, no shared memory
  assert.equal(afterRestart.verify(token).email, 'admin@example.test');
});

test('sessions expire, can be revoked, and end when the admin password changes', () => {
  let clock = 1_000_000;
  const auth = createAdminAuth({ ...config, ttlMs: 60_000, now: () => clock });
  const token = auth.issue();
  assert.ok(auth.verify(token));
  clock += 60_001;
  assert.equal(auth.verify(token), null, 'expired');

  clock = 1_000_000;
  const second = auth.issue();
  assert.equal(auth.revoke(second), true);
  assert.equal(auth.verify(second), null, 'logged out');

  const fresh = createAdminAuth(config).issue();
  assert.equal(createAdminAuth({ ...config, password: 'new password' }).verify(fresh), null, 'password changed');
  assert.equal(createAdminAuth({ ...config, secret: 'other' }).verify(fresh), null, 'different secret');
});

test('tampered, foreign and legacy tokens are rejected', () => {
  const auth = createAdminAuth(config);
  const token = auth.issue();
  const [prefix, payload, signature] = token.split('.');
  const forged = Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(payload, 'base64url')), exp: Date.now() + 1e9 })).toString('base64url');
  assert.equal(auth.verify(`${prefix}.${forged}.${signature}`), null);
  assert.equal(auth.verify(`${prefix}.${payload}.${signature.slice(0, -2)}xx`), null);
  assert.equal(auth.verify('RO_ADMIN_SECURE_1_abc'), null);
  assert.equal(auth.verify(''), null);
});

test('password check is exact and case-insensitive only for the email', () => {
  const auth = createAdminAuth(config);
  assert.equal(Boolean(auth.checkPassword(' admin@example.TEST ', config.password)), true);
  assert.equal(Boolean(auth.checkPassword('admin@example.test', 'Correct horse battery staple')), false);
  assert.equal(Boolean(auth.checkPassword('other@example.test', config.password)), false);
});

test('five failures lock the account for 15 minutes', () => {
  let clock = 0;
  const auth = createAdminAuth({ ...config, now: () => clock });
  for (let i = 0; i < 4; i++) auth.recordFailure('k');
  assert.equal(auth.lockedFor('k'), 0);
  auth.recordFailure('k');
  assert.ok(auth.lockedFor('k') > 14 * 60 * 1000);
  clock += 15 * 60 * 1000 + 1;
  assert.equal(auth.lockedFor('k'), 0);
});

test('rate limiter answers 429 after the limit and resets with the window', () => {
  let clock = 0;
  const limiter = rateLimit({ windowMs: 1000, max: 3, now: () => clock });
  const run = () => {
    const res = { code: 200, headers: {}, setHeader(k, v) { this.headers[k] = v; }, status(c) { this.code = c; return this; }, json(b) { this.body = b; return this; } };
    let passed = false;
    limiter({ ip: '1.2.3.4' }, res, () => { passed = true; });
    return { passed, res };
  };
  assert.deepEqual([run(), run(), run()].map(r => r.passed), [true, true, true]);
  const blocked = run();
  assert.equal(blocked.passed, false);
  assert.equal(blocked.res.code, 429);
  assert.ok(blocked.res.headers['Retry-After']);
  clock += 1001;
  assert.equal(run().passed, true);
});

test('real /api/admin/login: lockout, signed session, logout', async () => {
  const root = path.join(__dirname, '..');
  process.env.PORT = '0';
  process.env.ADMIN_EMAIL = 'admin@test.local';
  process.env.ADMIN_PASSWORD = 'right-password';
  const dbPath = require.resolve(path.join(root, 'db'));
  require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: { pool: { query: async () => [[]], end: async () => {} }, testConnection: async () => true } };
  const log = console.log, warn = console.warn;
  console.log = () => {}; console.warn = () => {};
  const { server } = require(path.join(root, 'server.js'));
  if (!server.listening) await new Promise(r => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const login = (password, ip) => fetch(`${base}/api/admin/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'admin@test.local', password }),
  });
  try {
    const ok = await login('right-password');
    assert.equal(ok.status, 200);
    const { token } = await ok.json();
    assert.match(token, /^roadm1\./);
    const session = await fetch(`${base}/api/admin/session`, { headers: { Authorization: `Bearer ${token}` } });
    assert.equal(session.status, 200);

    for (let i = 0; i < 5; i++) assert.equal((await login('wrong')).status, 401);
    const locked = await login('right-password');
    assert.equal(locked.status, 429, 'locked even with the right password');
    assert.match((await locked.json()).error, /Too many failed sign-in attempts/);

    // Existing session keeps working; logout revokes it.
    assert.equal((await fetch(`${base}/api/admin/session`, { headers: { Authorization: `Bearer ${token}` } })).status, 200);
    await fetch(`${base}/api/admin/logout`, { method: 'POST', headers: { Authorization: `Bearer ${token}` } });
    assert.equal((await fetch(`${base}/api/admin/session`, { headers: { Authorization: `Bearer ${token}` } })).status, 401);
  } finally {
    console.log = log; console.warn = warn;
    server.closeAllConnections?.();
    await new Promise(r => server.close(r));
  }
});
