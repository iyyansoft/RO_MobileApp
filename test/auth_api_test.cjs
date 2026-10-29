const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { validGstin, createDealerToken } = require('../checkout_service');
function setup(options = {}) {
  const routes = {}, users = {}, queries = [], memoryOtps = new Map();
  let sent;
  const context = { app: { post: (path, fn) => routes[path] = fn }, console: { log() {}, error() {} }, crypto, Buffer, validGstin, createDealerToken,
    SESSION_SECRET: 'test-secret', memoryOtps, process: { env: { SMTP_USER: 'sender@example.test' } },
    isValidEmailAddress: email => /^[^@]+@[^@]+\.[^@]+$/.test(email),
    logEmailFailure: () => {},
    findUserByEmailOrMobile: async email => options.registered && email === 'dealer@example.test' ? { id: 'dealer', email, name: 'Registered Name', status: options.status || 'approved', gstNumber: '27AAPFU0939F1ZV', passwordHash: options.passwordHash, emailVerified: true, isApproved: options.isApproved ?? (options.status !== 'pending') } : null,
    findAuthUserByEmailOrMobile: async email => options.registered && email === 'dealer@example.test' ? { id: 'dealer', email, name: 'Registered Name', status: options.status || 'approved', gstNumber: '27AAPFU0939F1ZV', passwordHash: options.passwordHash, emailVerified: true, isApproved: options.isApproved ?? (options.status !== 'pending'), addresses: [] } : null,
    sendTransactionalEmail: async message => { if (options.mailError) throw Object.assign(Error('test provider unavailable'), { code: 'EMAIL_PROVIDER_ERROR', provider: 'test' }); sent = message; return { accepted: [message.to], provider: 'test' }; },
    hashOtp: (email, code) => crypto.createHmac('sha256', 'test-secret').update(email + ':' + code).digest('hex'),
    bcrypt: require('bcryptjs'), parseAddressString: () => ({city:'',state:'',pincode:''}),
    loadJsonUsers: () => users, saveJsonUsers: () => {},
    pool: { query: async (sql, values) => { queries.push([sql, values]);
      if (sql.startsWith('SELECT id, email, status FROM users')) return [options.registered ? [{ id: 'dealer', email: 'dealer@example.test', status: options.status || 'approved' }] : []];
      return sql.startsWith('SELECT') ? [[]] : [{ affectedRows: 1 }]; },
      getConnection: async () => { if (options.dbError) throw Error('PostgreSQL unavailable'); return { beginTransaction: async () => {}, query: async (sql, values) => { queries.push([sql, values]); return sql.startsWith('SELECT') ? [[]] : [{ affectedRows: 1 }]; }, commit: async () => {}, rollback: async () => {}, release: async () => {} }; } },
  };
  const source = fs.readFileSync(require.resolve('../server'), 'utf8');
  vm.runInNewContext(source.slice(source.indexOf("app.post('/api/auth/send-otp'"), source.indexOf('// 5.')), context);
  const call = async (path, body) => { const response = { code: 200, status(code) { this.code = code; return this; }, json(body) { this.body = body; return this; } }; await routes['/api/auth/' + path]({body}, response); return response; };
  return { call, memoryOtps, users, queries, sent: () => sent };
}
test('OTP is emailed only to registered accounts and provider failure never reports success', async () => {
  const missing = setup(); assert.equal((await missing.call('send-otp', {email:'dealer@example.test'})).code, 404); assert.equal(missing.sent(), undefined);
  const failed = setup({registered:true,mailError:true}); assert.equal((await failed.call('send-otp', {email:'dealer@example.test'})).code, 502); assert.equal(failed.memoryOtps.size, 0);
});
test('password reset keeps the OTP invalid when the email provider rejects the request', async () => {
  const failed = setup({registered:true,mailError:true});
  assert.equal((await failed.call('forgot-password', {email:'dealer@example.test'})).code, 502);
  assert.equal(failed.memoryOtps.size, 0);
  assert.equal(failed.queries.some(([sql]) => sql.startsWith('INSERT INTO otp_codes')), false);
});
test('password reset records its hashed OTP only after the email provider accepts it', async () => {
  const api = setup({registered:true});
  const response = await api.call('forgot-password', {email:'dealer@example.test'});
  assert.equal(response.code, 200);
  assert.equal(api.sent().subject, 'Reset your RO Wholesale password');
  const code = api.sent().text.match(/\b\d{6}\b/)[0];
  assert.notEqual(api.memoryOtps.get('dealer@example.test').otp, code);
  assert.ok(api.queries.some(([sql]) => sql.startsWith('INSERT INTO otp_codes')));
});
test('real email code is hashed, verified once, and preserves registered name/GST', async () => {
  const api = setup({registered:true}); assert.equal((await api.call('send-otp', {email:'dealer@example.test'})).code, 200);
  const code = api.sent().text.match(/\b\d{6}\b/)[0]; assert.notEqual(api.memoryOtps.get('dealer@example.test').otp, code);
  assert.equal((await api.call('verify-otp', {email:'dealer@example.test',otp:'000000'})).code, 400);
  const login = await api.call('verify-otp', {email:'dealer@example.test',otp:code}); assert.equal(login.body.user.name, 'Registered Name'); assert.equal(login.body.user.gstNumber, '27AAPFU0939F1ZV');
  assert.equal((await api.call('verify-otp', {email:'dealer@example.test',otp:code})).code, 400);
});
test('signup requires confirmation, leaves new dealers pending, and writes PostgreSQL first', async () => {
  const body = {name:'Dealer',email:'new@example.test',mobile:'9876543210',address:'Saved address',password:'Password1',confirmPassword:'Password1'};
  const api = setup(); assert.equal((await api.call('signup', {...body,confirmPassword:'wrong'})).code, 400);
  assert.equal((await api.call('signup', body)).code, 200);
  const userInsert = api.queries.find(([sql]) => sql.startsWith('INSERT INTO users'));
  assert.match(userInsert[0], /'pending', FALSE, 0\)/i);
  assert.equal((await api.call('signup', body)).body.isApproved, false);
  assert.ok(userInsert); assert.equal(userInsert[1][5], ''); assert.equal(userInsert[1][7], body.address);
  assert.equal(await require('bcryptjs').compare(body.password, userInsert[1][4]), true);
  const failed = setup({dbError:true}); assert.equal((await failed.call('signup', body)).code, 503); assert.equal(Object.keys(failed.users).length, 0);
});
test('password login requires the actual saved password and returns name/GST', async () => {
  const api = setup({registered:true, passwordHash: await require('bcryptjs').hash('ActualPassword1', 4)});
  assert.equal((await api.call('login', {email:'dealer@example.test',password:'wrong'})).code, 400);
  const response = await api.call('login', {email:'dealer@example.test',password:'ActualPassword1'});
  assert.equal(response.body.success, true); assert.equal(response.body.user.name, 'Registered Name'); assert.equal(response.body.user.gstNumber, '27AAPFU0939F1ZV'); assert.ok(response.body.token.includes('.'));
});

test('pending dealers cannot password-login before an admin approves them', async () => {
  const api = setup({registered:true, status:'pending', isApproved:false, passwordHash: await require('bcryptjs').hash('ActualPassword1', 4)});
  const response = await api.call('login', {email:'dealer@example.test',password:'ActualPassword1'});
  assert.equal(response.code, 403);
  assert.equal(response.body.status, 'pending');
  assert.equal(response.body.isApproved, false);
  assert.equal(response.body.token, undefined);
});

test('pending dealers can verify an email code but do not receive an app session', async () => {
  const api = setup({registered:true, status:'pending', isApproved:false});
  assert.equal((await api.call('send-otp', {email:'dealer@example.test'})).code, 200);
  const code = api.sent().text.match(/\b\d{6}\b/)[0];
  const response = await api.call('verify-otp', {email:'dealer@example.test',otp:code});
  assert.equal(response.code, 403);
  assert.equal(response.body.status, 'pending');
  assert.equal(response.body.token, undefined);
});
