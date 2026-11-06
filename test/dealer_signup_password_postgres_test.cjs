const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const crypto = require('node:crypto');
const bcrypt = require('bcryptjs');
const { PGlite } = require('@electric-sql/pglite');
const { citext } = require('@electric-sql/pglite/contrib/citext');
const { toPostgresPlaceholders, adaptResult, normalizeDatabaseError } = require('../db');
const { validGstin, createDealerToken, verifyDealerToken } = require('../checkout_service');
const { createEmailSender } = require('../email_provider');
const { verifyEmployeeToken } = require('../shop_service');

test('PostgreSQL: signup, verify email, sign in with saved password, restore and reject invalid credentials', async () => {
  // In-memory PostgreSQL only. Never reads a database URL or makes a DB network call.
  const db = new PGlite({ extensions: { citext } });
  const source = fs.readFileSync(require.resolve('../server'), 'utf8');
  const routes = new Map();
  let delivered, failAddressInsert = false, failOtpPersistence = false, rejectEmail = false;
  const emailSender = createEmailSender({
    env: { BREVO_API_KEY: 'isolated-test-key', BREVO_SENDER_EMAIL: 'sender@example.test' },
    fetchImpl: async (url, options) => {
      assert.equal(url, 'https://api.brevo.com/v3/smtp/email');
      const body = JSON.parse(options.body);
      delivered = { text: body.textContent };
      return { ok: !rejectEmail, status: rejectEmail ? 401 : 201 };
    },
  });
  const query = async (sql, values = []) => {
    if (failAddressInsert && sql.startsWith('INSERT INTO user_addresses')) throw new Error('Test address failure');
    if (failOtpPersistence && sql.startsWith('WITH removed AS')) throw new Error('Test OTP write failure');
    try {
      const result = await db.query(toPostgresPlaceholders(sql), Array.from(values));
      return adaptResult({ ...result, command: sql.trim().split(/\s/)[0].toUpperCase(), rowCount: result.affectedRows });
    } catch (error) { throw normalizeDatabaseError(error); }
  };
  const context = vm.createContext({
    app: { post: (path, handler) => routes.set(path, handler), get: (path, handler) => routes.set(path, handler) },
    console: { log() {}, error() {} }, crypto, Buffer, bcrypt, validGstin, createDealerToken, verifyDealerToken,
    SESSION_SECRET: 'isolated-postgres-test-secret', memoryOtps: new Map(),
    isDatabaseTrue: value => value === true || value === 1 || value === '1',
    isValidEmailAddress: email => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email),
    hashOtp: (email, code) => crypto.createHmac('sha256', 'isolated-test-only').update(email + ':' + code).digest('hex'),
    logEmailFailure() {},
    sendTransactionalEmail: emailSender,
    parseAddressString: () => ({ city: '', state: '', pincode: '' }),
    pool: { query, getConnection: async () => ({
      query, beginTransaction: () => db.exec('BEGIN'), commit: () => db.exec('COMMIT'),
      rollback: () => db.exec('ROLLBACK'), release() {},
    }) },
  });
  try {
    await db.exec(fs.readFileSync(require.resolve('../supabase_migration.sql'), 'utf8'));
    vm.runInContext(source.slice(source.indexOf("app.get('/api/auth/config'"), source.indexOf("app.get('/api/auth/session'")), context);
    vm.runInContext(source.slice(source.indexOf('async function findAuthUserByEmailOrMobile('), source.indexOf('// REST API ENDPOINTS')), context);
    vm.runInContext(source.slice(source.indexOf("app.get('/api/auth/session'"), source.indexOf('// Exchange a verified Supabase Auth JWT')), context);
    vm.runInContext(source.slice(source.indexOf("app.post('/api/auth/send-otp'"), source.indexOf('// 5. Google Sign-In Endpoint')), context);
    const call = async (path, body = {}, token = '') => {
      const res = { code: 200, status(code) { this.code = code; return this; }, json(body) { this.body = body; return this; } };
      await routes.get('/api/auth/' + path)({ body, headers: { authorization: token ? `Bearer ${token}` : '' } }, res);
      return res;
    };
    // The deployment diagnostic must describe the behavior exercised below.
    context.process = { env: {} };
    const policy = (await call('config')).body.dealerPasswordLogin;
    assert.equal(policy.requiresAdminApproval, false);
    assert.equal(policy.requiresEmailVerification, true);
    const signup = { name: 'New Dealer', email: 'NewDealer@example.test', mobile: '9876543210',
      companyName: 'Test Business', address: 'Test address', password: 'Exact Password 123!', confirmPassword: 'Exact Password 123!' };

    assert.equal((await call('signup', { ...signup, confirmPassword: 'mismatch' })).code, 400);
    assert.equal((await call('signup', { ...signup, password: 'short', confirmPassword: 'short' })).code, 400);
    const created = await call('signup', signup);
    assert.equal(created.code, 200);
    assert.equal(created.body.requiresEmailVerification, true);
    assert.equal(created.body.token, undefined);
    const saved = (await db.query('SELECT * FROM users WHERE email=$1', ['newdealer@example.test'])).rows[0];
    assert.equal(saved.name, signup.name);
    assert.equal(saved.business_name, signup.companyName);
    assert.equal(saved.email_verified, false);
    assert.equal(saved.is_approved, false);
    assert.notEqual(saved.password_hash, signup.password);
    assert.equal(await bcrypt.compare(signup.password, saved.password_hash), true);
    assert.equal((await db.query('SELECT user_id FROM user_addresses')).rows[0].user_id, saved.id);

    const credentials = { identifier: ' NewDealer@EXAMPLE.test ', password: signup.password };
    assert.equal((await call('login', credentials)).code, 403);
    assert.equal((await call('signup', signup)).code, 409);
    assert.equal((await call('signup', { ...signup, email: 'other@example.test' })).code, 409);
    assert.equal((await call('send-otp', { email: signup.email })).code, 200);
    const otp = delivered.text.match(/\b\d{6}\b/)[0];
    assert.equal((await call('verify-otp', { email: signup.email, otp: '000000' })).code, 400);
    const verified = await call('verify-otp', { email: signup.email, otp });
    assert.equal(verified.code, 200);
    assert.equal((await db.query('SELECT email_verified FROM users WHERE id=$1', [saved.id])).rows[0].email_verified, true);
    assert.equal((await call('verify-otp', { email: signup.email, otp })).code, 400);

    const login = await call('login', credentials);
    assert.equal(login.code, 200);
    assert.equal(login.body.user.id, saved.id);
    assert.equal(login.body.user.status, 'pending');
    assert.equal(login.body.user.isApproved, false);
    assert.equal(verifyDealerToken(login.body.token, context.SESSION_SECRET).id, saved.id);
    assert.equal(login.body.user.passwordHash, undefined);
    const afterLogin = (await db.query('SELECT status,is_approved,password_hash FROM users WHERE id=$1', [saved.id])).rows[0];
    assert.equal(afterLogin.status, 'pending');
    assert.equal(afterLogin.is_approved, false, 'login does not silently approve the dealer');
    assert.equal(afterLogin.password_hash, saved.password_hash, 'login compares the saved bcrypt hash without rewriting it');
    const adminContext = vm.createContext({ activeAdminTokens: new Set() });
    vm.runInContext(source.slice(source.indexOf('function requireAdminAuth('), source.indexOf('// Shop Employee routes')), adminContext);
    const adminResponse = { code: 200, status(code) { this.code = code; return this; }, json() { return this; } };
    let grantedAdminAccess = false;
    adminContext.requireAdminAuth({ headers: { authorization: `Bearer ${login.body.token}` } }, adminResponse,
      () => { grantedAdminAccess = true; });
    assert.equal(adminResponse.code, 401);
    assert.equal(grantedAdminAccess, false, 'a real dealer session cannot authorize an admin request');
    assert.equal(verifyEmployeeToken(login.body.token, context.SESSION_SECRET), null,
      'a dealer token cannot become an employee token, even with the same signing secret');
    assert.equal((await call('session', {}, login.body.token)).code, 200);
    assert.equal((await call('session', {}, `${login.body.token}tampered`)).code, 401);
    assert.equal((await call('login', { ...credentials, password: 'wrong' })).code, 400);
    assert.equal((await call('login', { ...credentials, password: signup.password + ' ' })).code, 400);
    const forgedApproval = await call('login', { ...credentials, password: 'wrong', isApproved: true, status: 'approved', role: 'admin' });
    assert.equal(forgedApproval.code, 400, 'client approval flags cannot bypass bcrypt');
    assert.equal((await call('login', { identifier: '+91 98765-43210', password: signup.password })).code, 200);

    // Email digits must never select the dealer with the matching phone number.
    assert.equal((await call('login', { identifier: '9876543210@unknown.test', password: signup.password })).code, 400);
    assert.equal((await call('login', { identifier: "x' OR TRUE--@unknown.test", password: signup.password })).code, 400);

    async function issue() {
      context.memoryOtps.clear();
      await db.query("UPDATE otp_codes SET created_at=CURRENT_TIMESTAMP - INTERVAL '31 seconds'");
      assert.equal((await call('send-otp', { email: signup.email })).code, 200);
      return delivered.text.match(/\b\d{6}\b/)[0];
    }
    const afterRestart = await issue();
    context.memoryOtps.clear();
    assert.equal((await call('send-otp', { email: signup.email })).code, 429, 'cooldown survives restart');
    assert.equal((await call('verify-otp', { email: signup.email, otp: afterRestart })).code, 200, 'verification survives restart');

    const expiring = await issue();
    await db.query("UPDATE otp_codes SET expires_at=CURRENT_TIMESTAMP - INTERVAL '1 second'");
    assert.equal((await call('verify-otp', { email: signup.email, otp: expiring })).code, 400);

    const locked = await issue();
    for (let attempt = 0; attempt < 5; attempt++) {
      assert.equal((await call('verify-otp', { email: signup.email, otp: '000000' })).code, 400);
    }
    context.memoryOtps.clear();
    assert.equal((await call('verify-otp', { email: signup.email, otp: locked })).code, 400, 'attempt limit survives restart');

    const concurrent = await issue();
    const results = await Promise.all([1, 2].map(() => call('verify-otp', { email: signup.email, otp: concurrent })));
    assert.deepEqual(results.map(result => result.code).sort(), [200, 400], 'code is consumed atomically');

    rejectEmail = true;
    assert.equal((await call('send-otp', { email: signup.email })).code, 502);
    assert.equal((await db.query('SELECT count(*)::int AS count FROM otp_codes')).rows[0].count, 0);
    rejectEmail = false;
    failOtpPersistence = true;
    assert.equal((await call('send-otp', { email: signup.email })).code, 503, 'never report sent if persistence fails');
    assert.equal((await call('verify-otp', { email: signup.email, otp: delivered.text.match(/\b\d{6}\b/)[0] })).code, 400);
    failOtpPersistence = false;
    const retried = await issue();
    assert.equal((await call('verify-otp', { email: signup.email, otp: retried })).code, 200);

    // A failed related insert must not leave a partially created account.
    failAddressInsert = true;
    assert.equal((await call('signup', { ...signup, email: 'rollback@example.test', mobile: '9876543211' })).code, 503);
    failAddressInsert = false;
    assert.equal((await db.query('SELECT count(*)::int AS count FROM users')).rows[0].count, 1);
    await db.query("UPDATE users SET status='rejected' WHERE id=$1", [saved.id]);
    assert.equal((await call('login', credentials)).code, 403);
    assert.equal((await call('session', {}, login.body.token)).code, 403);
  } finally { await db.close(); }
});
