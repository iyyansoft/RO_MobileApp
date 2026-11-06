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
        status: 'pending', isApproved: false, emailVerified: true, addresses: [],
      };
    },
    createDealerToken: (...args) => {
      tokenIssued = true;
      return createDealerToken(...args);
    },
    pool: {
      query: async (sql, values) => { queries.push([sql, values]); return [{ affectedRows: 1 }]; },
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

test('new verified Google dealer receives a dealer session without admin approval', async () => {
  const api = setup();
  const response = await api.call();
  const insert = api.queries.find(([sql]) => sql.includes('INSERT INTO users'));
  assert.ok(insert);
  assert.match(insert[0], /'pending', FALSE, 0, TRUE/i);
  assert.equal(response.code, 200);
  assert.equal(response.body.user.status, 'pending');
  assert.equal(api.tokenIssued(), true);
});

test('existing pending Google dealer can receive a dealer token', async () => {
  const api = setup({ existingUser: {
    id: 'dealer-pending', email: 'dealer@example.test', name: 'Dealer',
    status: 'pending', isApproved: false,
  } });
  const response = await api.call();
  assert.equal(response.code, 200);
  assert.equal(response.body.user.status, 'pending');
  assert.match(api.queries[0][0], /email_verified = TRUE/);
  assert.equal(api.tokenIssued(), true);
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

test('Google sign-in cannot reinstate a rejected dealer', async () => {
  const api = setup({ existingUser: { id: 'rejected', status: 'rejected' } });
  assert.equal((await api.call()).code, 403);
  assert.equal(api.tokenIssued(), false);
  assert.equal(api.queries.length, 0);
});

test('Google identity verification fails closed on invalid signatures, missing audience or unverified email', async () => {
  const source = fs.readFileSync(require.resolve('../server'), 'utf8');
  const functionSource = source.slice(source.indexOf('async function verifyGoogleToken('), source.indexOf("app.post('/api/auth/google-signin'"));
  for (const scenario of ['valid', 'badSignature', 'unverified', 'unconfigured']) {
    let checked = false;
    const context = vm.createContext({
      process: { env: { GOOGLE_CLIENT_ID: scenario === 'unconfigured' ? '' : 'test-client-id' } },
      googleClient: { async verifyIdToken(options) {
        checked = true;
        assert.equal(options.audience, 'test-client-id');
        if (scenario === 'badSignature') throw new Error('invalid signature');
        return { getPayload: () => ({ sub: 'google-identity', email: 'dealer@example.test', email_verified: scenario !== 'unverified' }) };
      } },
    });
    vm.runInContext(functionSource, context);
    if (scenario === 'valid') assert.equal((await context.verifyGoogleToken('test-id-token')).email, 'dealer@example.test');
    else await assert.rejects(context.verifyGoogleToken('header.forged-payload.signature'));
    assert.equal(checked, scenario !== 'unconfigured');
  }
});
