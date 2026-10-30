const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { toPostgresPlaceholders, adaptResult } = require('../db');

const server = fs.readFileSync(require.resolve('../server'), 'utf8');
const portal = fs.readFileSync(require.resolve('../web_preview/admin.html'), 'utf8');
const testToken = 'local-test-admin-token';

// Execute the real route and middleware with an in-memory database boundary.
// Do not start server.js, read credentials or connect to PostgreSQL.
function backend({ missing = false, failure = false } = {}) {
  let route;
  const calls = [], logs = [];
  const dealer = { id: 'dealer-1', status: 'pending', is_approved: false };
  const context = vm.createContext({
    activeAdminTokens: new Set([testToken]),
    console: { error: (...args) => logs.push(args) },
    app: { post(path, auth, handler) { route = { auth, handler }; } },
    pool: { async query(sql, values) {
      calls.push({ sql: toPostgresPlaceholders(sql), values: Array.from(values) });
      if (failure) throw Object.assign(new Error('private database detail'), { code: 'TEST_DB_FAILURE' });
      if (sql.startsWith('SELECT')) return [[...(missing ? [] : [{ id: dealer.id }])]];
      if (!missing) Object.assign(dealer, { status: values[0], is_approved: values[1] });
      return adaptResult({ command: 'UPDATE', rowCount: missing ? 0 : 1, rows: [] });
    } },
  });
  vm.runInContext(server.slice(server.indexOf('function requireAdminAuth('), server.indexOf('// Shop Employee routes')), context);
  vm.runInContext(server.slice(server.indexOf("app.post('/api/admin/set-status'"), server.indexOf('// Admin Endpoint: Delete User')), context);
  return { calls, logs, dealer, async call(body, headers = { authorization: `Bearer ${testToken}` }) {
    const res = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(data) { this.body = data; return this; } };
    const req = { body, headers };
    let authorized = false;
    route.auth(req, res, () => { authorized = true; });
    if (authorized) await route.handler(req, res);
    return { status: res.statusCode, ok: res.statusCode < 400, json: async () => res.body, body: res.body };
  } };
}

function frontend(fetch) {
  const toasts = [], refreshes = [], storage = new Map([['admin_token', testToken]]);
  const context = vm.createContext({
    fetch, sessionStorage: { getItem: key => storage.get(key), removeItem: key => storage.delete(key) },
    localStorage: { removeItem: key => storage.delete(key) },
    showAdminLoginScreen: () => refreshes.push('login'),
    showToast: (message, color) => toasts.push({ message, color }),
    loadUsers: async () => refreshes.push('users'), loadStats: async () => refreshes.push('stats'),
  });
  vm.runInContext(portal.slice(portal.indexOf('    function getAdminToken()'), portal.indexOf('    function showAdminLoginScreen()')), context);
  vm.runInContext(portal.slice(portal.indexOf('    async function setUserStatus('), portal.indexOf('    function promptDeleteUser(')), context);
  return { toasts, refreshes, storage, approve: () => context.setUserStatus('dealer-1', 'Approved') };
}

test('green tick sends the authenticated canonical payload and updates PostgreSQL approval flags', async () => {
  const api = backend();
  const ui = frontend(async (url, options) => {
    assert.equal(url, '/api/admin/set-status');
    assert.equal(options.method, 'POST');
    assert.equal(options.headers.Authorization, `Bearer ${testToken}`);
    assert.equal(options.headers['x-admin-token'], testToken);
    const body = JSON.parse(options.body);
    assert.deepEqual(body, { identifier: 'dealer-1', status: 'approved' });
    return api.call(body, { authorization: options.headers.Authorization });
  });
  await ui.approve();
  assert.deepEqual(api.dealer, { id: 'dealer-1', status: 'approved', is_approved: true });
  assert.equal(api.calls[0].sql, 'UPDATE users SET status = $1, is_approved = $2 WHERE email = $3 OR id = $4 OR mobile = $5');
  assert.deepEqual(api.calls[0].values, ['approved', true, 'dealer-1', 'dealer-1', 'dealer-1']);
  assert.deepEqual(ui.refreshes, ['users', 'stats']);
  assert.equal(ui.toasts[0].color, '#10B981');
});

test('older portal userId and existing email callers remain compatible', async () => {
  for (const key of ['identifier', 'userId', 'email']) {
    const api = backend();
    assert.equal((await api.call({ [key]: 'dealer-1', status: 'Approved' })).status, 200);
  }
});

test('pending and rejected clear is_approved; repeated approval remains successful', async () => {
  const api = backend();
  for (const status of ['approved', 'approved', 'pending', 'rejected']) {
    assert.equal((await api.call({ identifier: 'dealer-1', status })).status, 200);
    assert.equal(api.dealer.is_approved, status === 'approved');
    assert.equal(api.dealer.status, status);
  }
});

test('missing, expired and dealer tokens cannot write; alternate admin header still works', async () => {
  const api = backend();
  for (const headers of [{}, { authorization: 'Bearer expired' }, { authorization: 'Bearer dealer-token' }]) {
    assert.equal((await api.call({ identifier: 'dealer-1', status: 'approved' }, headers)).status, 401);
  }
  assert.equal(api.calls.length, 0);
  assert.equal((await api.call({ identifier: 'dealer-1', status: 'approved' }, { 'x-admin-token': testToken })).status, 200);
});

test('invalid payloads never reach the database', async () => {
  const api = backend();
  for (const body of [undefined, {}, { identifier: {}, status: 'approved' }, { identifier: 'dealer-1', status: {} }, { identifier: 'dealer-1', status: 'admin' }]) {
    assert.equal((await api.call(body)).status, 400);
  }
  assert.equal(api.calls.length, 0);
});

test('missing dealers return 404 rather than false success', async () => {
  const api = backend({ missing: true });
  assert.equal((await api.call({ identifier: 'dealer-1', status: 'approved' })).status, 404);
});

test('database failures show the existing error toast without refreshing or logging details', async () => {
  const api = backend({ failure: true });
  const ui = frontend(async (url, options) => api.call(JSON.parse(options.body)));
  await ui.approve();
  assert.match(ui.toasts[0].message, /status was not changed/);
  assert.equal(ui.toasts[0].color, '#EF4444');
  assert.deepEqual(ui.refreshes, []);
  assert.equal(JSON.stringify(api.logs), JSON.stringify([['[API ERROR] Admin set-status:', 'TEST_DB_FAILURE']]));
});

test('expired portal session still clears tokens and displays login', async () => {
  const api = backend();
  const ui = frontend(async (url, options) => api.call(JSON.parse(options.body), {}));
  await ui.approve();
  assert.equal(ui.storage.has('admin_token'), false);
  assert.deepEqual(ui.refreshes, ['login']);
  assert.match(ui.toasts[0].message, /Unauthorized/);
});

test('non-JSON errors and network failures display the error toast', async () => {
  for (const fetch of [async () => { throw new Error('offline'); }, async () => ({ json: async () => { throw new SyntaxError('html'); } })]) {
    const ui = frontend(fetch);
    await ui.approve();
    assert.equal(ui.toasts[0].message, 'Error updating status');
    assert.deepEqual(ui.refreshes, []);
  }
});

test('Approved filter displays lowercase statuses returned by Express', () => {
  const elements = Object.fromEntries(['userSearchInput', 'userTableBody', 'userPaginationInfo', 'userPaginationControls'].map(id => [id, { value: '' }]));
  const context = vm.createContext({
    document: { getElementById: id => elements[id] },
    allUsers: [{ id: 'dealer-1', status: 'approved', name: 'Test Dealer' }, { id: 'dealer-2', status: 'pending' }],
    userFilterStatus: 'Approved', userCurrentPage: 1, USERS_PER_PAGE: 10,
  });
  vm.runInContext(portal.slice(portal.indexOf('    function filterUserList()'), portal.indexOf('    async function setUserStatus(')), context);
  context.filterUserList();
  assert.match(elements.userTableBody.innerHTML, /Test Dealer/);
  assert.match(elements.userTableBody.innerHTML, /setUserStatus\('dealer-1', 'Approved'\)/);
  assert.doesNotMatch(elements.userTableBody.innerHTML, /dealer-2/);
});
