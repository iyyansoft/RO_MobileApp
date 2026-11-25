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
    adminTokenFrom: require('../admin_auth').adminTokenFrom,
    verifyAdminToken: token => (token === testToken ? { sub: 'admin' } : null),
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

// The Admin Panel's real code, run against a fake page. Every save goes
// through adminWrite(): "Saving to Production..." -> the request -> a fresh
// read of the dealer list -> "Successfully saved to Production." only when the
// read-back shows the new status.
function frontend(fetch, api) {
  const toasts = [], refreshes = [], statuses = [], storage = new Map([['admin_token', testToken]]);
  const text = {};
  const box = { className: '', dataset: {} };
  Object.defineProperty(text, 'textContent', { get() { return this.value || ''; }, set(v) { this.value = v; statuses.push(v); } });
  const reads = async (url, options) => {
    if (url === '/api/admin/dealers') {
      return { ok: true, status: 200, json: async () => ({ success: true, dealers: [{ id: api.dealer.id, status: api.dealer.status }] }) };
    }
    return fetch(url, options);
  };
  const context = vm.createContext({
    fetch: reads, sessionStorage: { getItem: key => storage.get(key), removeItem: key => storage.delete(key) },
    localStorage: { removeItem: key => storage.delete(key) },
    document: { getElementById: id => (id === 'writeStatusText' ? text : box) },
    setTimeout: () => 0, clearTimeout: () => {},
    showAdminLoginScreen: () => refreshes.push('login'),
    showToast: (message, color) => toasts.push({ message, color }),
    loadUsers: async () => refreshes.push('users'), loadStats: async () => refreshes.push('stats'),
  });
  vm.runInContext(portal.slice(portal.indexOf('    function getAdminToken()'), portal.indexOf('    function showAdminLoginScreen()')), context);
  vm.runInContext(portal.slice(portal.indexOf('    async function setUserStatus('), portal.indexOf('    function promptDeleteUser(')), context);
  // As served by Render (Production Admin).
  vm.runInContext("Object.assign(ADMIN_ENV, { mode: 'production', realProduction: true, name: 'Production' })", context);
  return { toasts, refreshes, storage, statuses, state: () => box.dataset.state, approve: () => context.setUserStatus('dealer-1', 'Approved') };
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
  }, api);
  await ui.approve();
  assert.deepEqual(api.dealer, { id: 'dealer-1', status: 'approved', is_approved: true });
  // Email matches case-insensitively; id and mobile match exactly as sent
  // (ids are case-sensitive, so they are no longer lowercased).
  assert.equal(api.calls[0].sql, 'UPDATE users SET status = $1, is_approved = $2 WHERE lower(email) = $3 OR id = $4 OR mobile = $5');
  assert.deepEqual(api.calls[0].values, ['approved', true, 'dealer-1', 'dealer-1', 'dealer-1']);
  assert.deepEqual(ui.refreshes, ['users', 'stats']);
  assert.deepEqual(ui.statuses, ['Saving to Production...', 'Confirming the saved data in Production...', 'Successfully saved to Production.']);
  assert.equal(ui.state(), 'success');
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

test('database failures show "Production save failed" without logging details', async () => {
  const api = backend({ failure: true });
  const ui = frontend(async (url, options) => api.call(JSON.parse(options.body)), api);
  await ui.approve();
  assert.equal(ui.state(), 'failed');
  assert.match(ui.statuses.at(-1), /^Production save failed\. Changes were not saved\.\n.*status was not changed/);
  assert.ok(!ui.statuses.some(t => /^Successfully/.test(t)));
  // The list is reloaded so it shows what is really saved.
  assert.deepEqual(ui.refreshes, ['users', 'stats']);
  assert.equal(api.dealer.status, 'pending');
  assert.equal(JSON.stringify(api.logs), JSON.stringify([['[API ERROR] Admin set-status:', 'TEST_DB_FAILURE']]));
});

test('expired portal session still clears tokens and displays login', async () => {
  const api = backend();
  const ui = frontend(async (url, options) => api.call(JSON.parse(options.body), {}), api);
  await ui.approve();
  assert.equal(ui.storage.has('admin_token'), false);
  assert.equal(ui.refreshes[0], 'login');
  assert.equal(ui.state(), 'failed');
  assert.match(ui.statuses.at(-1), /Changes were not saved\.\nYour admin session has expired/);
  assert.equal(api.dealer.status, 'pending');
});

test('non-JSON errors and network failures are never shown as saved', async () => {
  // Network failure: the outcome is unknown, so the dealer list is read back;
  // the status did not change -> "save failed".
  let api = backend();
  let ui = frontend(async () => { throw new Error('offline'); }, api);
  await ui.approve();
  assert.equal(ui.state(), 'failed');
  assert.match(ui.statuses.at(-1), /^Production save failed\. Changes were not saved\.\nProduction did not answer, and the data is unchanged\.$/);
  // An HTML error page instead of JSON.
  api = backend();
  ui = frontend(async () => ({ ok: false, status: 500, json: async () => { throw new SyntaxError('html'); } }), api);
  await ui.approve();
  assert.equal(ui.state(), 'failed');
  assert.equal(ui.statuses.at(-1), 'Production save failed. Changes were not saved.\nThe server returned status 500.');
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
