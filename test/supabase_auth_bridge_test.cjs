const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const AbortSignal = globalThis.AbortSignal;

function setup({ env = {}, fetchResult, profile } = {}) {
  let route;
  const dbCalls = [];
  const context = {
    app: { post(path, handler) { if (path === '/api/auth/supabase/exchange') route = handler; } },
    process: { env },
    fetch: async (...args) => {
      context.fetchArgs = args;
      return fetchResult || { ok: true, json: async () => ({ id: 'auth-1', email: 'dealer@example.test', email_confirmed_at: '2026-10-01T00:00:00Z' }) };
    },
    AbortSignal,
    pool: { query: async (...args) => { dbCalls.push(args); return [profile ? [profile] : []]; } },
    createDealerToken: user => `ro-token:${user.id}`,
    isDatabaseTrue: value => value === true || value === 1 || value === '1',
    SESSION_SECRET: 'test-secret',
    console: { error() {} },
  };
  const source = fs.readFileSync(require.resolve('../server'), 'utf8');
  const start = source.indexOf("app.post('/api/auth/supabase/exchange'");
  const end = source.indexOf("app.post('/api/auth/send-otp'", start);
  assert.ok(start >= 0 && end > start, 'Supabase exchange route exists');
  vm.runInNewContext(source.slice(start, end), context);
  return { dbCalls, context, call: async (headers = {}, body = {}) => {
    const res = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(data) { this.body = data; return this; } };
    await route({ headers, body }, res);
    return res;
  } };
}

const validProfile = {
  id: 'dealer-1', email: 'dealer@example.test', mobile: '9876543210', name: 'Dealer',
  address: '', business_name: 'Dealer Co', gst_number: '', status: 'approved', is_approved: true,
};

test('Supabase exchange validates the bearer with Auth and uses its identity, not a body-supplied email', async () => {
  const api = setup({
    env: { SUPABASE_URL: 'https://project.example.test', SUPABASE_ANON_KEY: 'public-test-key' },
    profile: validProfile,
  });
  const response = await api.call({ authorization: 'Bearer actual-jwt' }, { email: 'attacker@example.test' });
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.user.email, 'dealer@example.test');
  assert.equal(response.body.token, 'ro-token:dealer-1');
  assert.equal(api.context.fetchArgs[0], 'https://project.example.test/auth/v1/user');
  assert.equal(api.context.fetchArgs[1].headers.Authorization, 'Bearer actual-jwt');
  assert.match(api.dbCalls[0][0], /auth_user_id = \?/);
  assert.equal(api.dbCalls[0][1][0], 'auth-1');
});

test('Supabase exchange refuses invalid or unverified sessions before dealer lookup', async () => {
  const invalid = setup({
    env: { SUPABASE_URL: 'https://project.example.test', SUPABASE_ANON_KEY: 'public-test-key' },
    fetchResult: { ok: false, json: async () => ({}) },
  });
  assert.equal((await invalid.call({ authorization: 'Bearer invalid' })).statusCode, 401);
  assert.equal(invalid.dbCalls.length, 0);

  const unverified = setup({
    env: { SUPABASE_URL: 'https://project.example.test', SUPABASE_ANON_KEY: 'public-test-key' },
    fetchResult: { ok: true, json: async () => ({ id: 'auth-1', email: 'dealer@example.test' }) },
  });
  assert.equal((await unverified.call({ authorization: 'Bearer valid-but-unverified' })).statusCode, 403);
  assert.equal(unverified.dbCalls.length, 0);
});

test('Supabase exchange refuses an unlinked dealer profile and missing bridge configuration', async () => {
  const unlinked = setup({
    env: { SUPABASE_URL: 'https://project.example.test', SUPABASE_ANON_KEY: 'public-test-key' },
  });
  assert.equal((await unlinked.call({ authorization: 'Bearer actual-jwt' })).statusCode, 409);

  const unconfigured = setup();
  assert.equal((await unconfigured.call({ authorization: 'Bearer actual-jwt' })).statusCode, 503);
  assert.equal(unconfigured.context.fetchArgs, undefined);
});
