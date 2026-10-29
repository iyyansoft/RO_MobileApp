const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { createDealerToken } = require('../checkout_service');

function setup({ existingUser } = {}) {
  const routes = {};
  const queries = [];
  let lookupCount = 0;
  let tokenIssued = false;
  const source = fs.readFileSync(require.resolve('../server'), 'utf8');
  const start = source.indexOf("app.post('/api/auth/google-signin'");
  const end = source.indexOf('// ADMIN AUTHENTICATION & SECURITY SYSTEM', start);
  assert.notEqual(start, -1);
  assert.notEqual(end, -1);
  const context = {
    app: { post: (route, handler) => { routes[route] = handler; } },
    console: { error() {} },
    crypto,
    SESSION_SECRET: 'local-test-only',
    verifyGoogleToken: async () => ({ email: 'dealer@example.test', name: 'Dealer' }),
    findUserByEmailOrMobile: async () => {
      lookupCount += 1;
      if (existingUser) return existingUser;
      if (lookupCount === 1) return null;
      return {
        id: 'dealer-new', email: 'dealer@example.test', name: 'Dealer',
        status: 'pending', isApproved: false, addresses: [],
      };
    },
    createDealerToken: (...args) => {
      tokenIssued = true;
      return createDealerToken(...args);
    },
    pool: {
      getConnection: async () => ({
        beginTransaction: async () => {},
        query: async (sql, values) => {
          queries.push([sql, values]);
          return [{ affectedRows: 1 }];
        },
        commit: async () => {},
        rollback: async () => {},
        release: () => {},
      }),
    },
  };
  vm.runInNewContext(source.slice(start, end), context);
  return {
    queries,
    tokenIssued: () => tokenIssued,
    call: async () => {
      const response = {
        code: 200,
        status(code) { this.code = code; return this; },
        json(body) { this.body = body; return this; },
      };
      await routes['/api/auth/google-signin']({ body: { credential: 'verified-test-credential' } }, response);
      return response;
    },
  };
}

test('new Google dealer is saved pending and does not receive an app token', async () => {
  const api = setup();
  const response = await api.call();
  const insert = api.queries.find(([sql]) => sql.includes('INSERT INTO users'));
  assert.ok(insert);
  assert.match(insert[0], /'pending', FALSE, 0/i);
  assert.equal(response.code, 403);
  assert.equal(response.body.status, 'pending');
  assert.equal(response.body.token, undefined);
  assert.equal(api.tokenIssued(), false);
});

test('existing pending Google dealer cannot receive an app token', async () => {
  const api = setup({ existingUser: {
    id: 'dealer-pending', email: 'dealer@example.test', name: 'Dealer',
    status: 'pending', isApproved: false,
  } });
  const response = await api.call();
  assert.equal(response.code, 403);
  assert.equal(response.body.status, 'pending');
  assert.equal(api.queries.length, 0);
  assert.equal(api.tokenIssued(), false);
});

test('approved Google dealer continues to receive a session', async () => {
  const api = setup({ existingUser: {
    id: 'dealer-approved', email: 'dealer@example.test', name: 'Dealer',
    status: 'approved', isApproved: true, addresses: [],
  } });
  const response = await api.call();
  assert.equal(response.code, 200);
  assert.equal(response.body.user.status, 'approved');
  assert.equal(response.body.user.isApproved, true);
  assert.equal(api.tokenIssued(), true);
});
