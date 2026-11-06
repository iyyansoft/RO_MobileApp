const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

function sessionRouteFor(user) {
  let route;
  const source = fs.readFileSync(require.resolve('../server'), 'utf8');
  const start = source.indexOf("app.get('/api/auth/session'");
  const end = source.indexOf("app.post('/api/auth/supabase/exchange'", start);
  assert.ok(start >= 0 && end > start);
  vm.runInNewContext(source.slice(start, end), {
    app: { get(path, handler) { if (path === '/api/auth/session') route = handler; } },
    SESSION_SECRET: 'local-test-only',
    verifyDealerToken: () => ({ id: user.id, email: user.email }),
    findAuthUserByEmailOrMobile: async () => user,
    console: { error() {} },
  });
  return async () => {
    const response = {
      code: 200,
      status(code) { this.code = code; return this; },
      json(body) { this.body = body; return this; },
    };
    await route({ headers: { authorization: 'Bearer local-test-token' } }, response);
    return response;
  };
}

test('verified pending dealer token restores an application session without approval', async () => {
  const response = await sessionRouteFor({
    id: 'dealer-pending', email: 'dealer@example.test', status: 'pending',
    isApproved: false, emailVerified: true,
  })();
  assert.equal(response.code, 200);
  assert.equal(response.body.user.status, 'pending');
  assert.equal(response.body.user.isApproved, false);
});

test('approved dealer can still restore an application session', async () => {
  const response = await sessionRouteFor({
    id: 'dealer-approved', email: 'dealer@example.test', status: 'approved',
    isApproved: true, emailVerified: true, name: 'Dealer', mobile: '', address: '', business: '',
    gstNumber: '',
  })();
  assert.equal(response.code, 200);
  assert.equal(response.body.user.status, 'approved');
});

test('unverified and rejected dealer sessions remain blocked', async () => {
  for (const user of [
    { id: 'dealer', status: 'pending', emailVerified: false },
    { id: 'dealer', status: 'rejected', emailVerified: true },
  ]) {
    const response = await sessionRouteFor(user)();
    assert.equal(response.code, 403);
    assert.equal(response.body.user, undefined);
  }
});
