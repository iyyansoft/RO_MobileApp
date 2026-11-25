// Local Admin for Production (scripts/admin_production.cjs), tested against a
// FAKE Production: the real server.js on the isolated in-memory database.
// Nothing here talks to the real Render API.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { startSandbox } = require('../scripts/local_sandbox.cjs');
const { startAdminProduction, adminEnvironment, PRODUCTION_ORIGIN } = require('../scripts/admin_production.cjs');

let fake;
let proxy;
let base;
let token;
test.before(async () => {
  fake = await startSandbox({ port: 0, quiet: true });
  proxy = await startAdminProduction({ port: 0, target: `http://127.0.0.1:${fake.port}`, quiet: true });
  base = `http://127.0.0.1:${proxy.port}`;
  const { email, password } = fake.credentials.admin;
  const login = await fetch(`${base}/api/admin/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
  token = (await login.json()).token;
  assert.ok(token, 'admin login through the proxy');
});
test.after(async () => { await proxy?.close(); await fake?.close(); });

const call = async (method, url, body, headers = {}) => {
  const res = await fetch(base + url, {
    method,
    headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), Authorization: `Bearer ${token}`, ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const row = async id => (await fake.db.query('SELECT * FROM products WHERE id = $1', [id])).rows[0];

test('only the real Render API is labelled PRODUCTION', () => {
  assert.deepEqual(adminEnvironment(PRODUCTION_ORIGIN), { mode: 'production', realProduction: true, target: 'https://ro-mobileapp.onrender.com' });
  assert.equal(adminEnvironment('http://127.0.0.1:9000').realProduction, false);
});

test('serves the local Admin Panel with the target label; listens on 127.0.0.1 only', async () => {
  assert.equal(proxy.server.address().address, '127.0.0.1');
  const res = await fetch(`${base}/admin`);
  const html = await res.text();
  assert.equal(res.status, 200);
  assert.match(html, /window\.__ADMIN_ENV = \{"mode":"production","realProduction":false,"target":"http:\/\/127\.0\.0\.1:\d+"\}/);
  assert.match(html, /function adminWrite/);
  assert.equal(res.headers.get('cache-control'), 'no-store');
});

test('holds no secrets: never reads .env and has no database or Supabase key', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'scripts', 'admin_production.cjs'), 'utf8');
  assert.doesNotMatch(source, /require\(['"](dotenv|pg|\.\.\/db)/);
  assert.doesNotMatch(source, /\.env['"]|SERVICE_ROLE|DATABASE_URL|SUPABASE_DB/);
});

test('an edit goes to the target API with the admin login, and is saved there', async () => {
  const products = (await call('GET', '/api/admin/products')).body.products;
  const p = products.find(x => x.status === 'active');
  const res = await call('PUT', `/api/admin/products/${encodeURIComponent(p.id)}`, {
    name: p.name, sku: p.sku, category: p.category, price: String(p.price), mrp: String(p.mrp), moq: p.moq || '',
    stock_quantity: p.stock_quantity ?? 0, min_stock: p.min_stock ?? 10, img: p.img || '', desc: 'Saved through the Local Admin proxy',
    specs: p.specs, features: p.features, badge: p.badge || '', status: p.status,
  });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal((await row(p.id)).description, 'Saved through the Local Admin proxy');
});

test('without the admin login the target refuses the write (authentication is not bypassed)', async () => {
  const p = (await call('GET', '/api/admin/products')).body.products[0];
  const res = await fetch(`${base}/api/admin/products/${encodeURIComponent(p.id)}`, { method: 'DELETE' });
  assert.equal(res.status, 401);
  assert.ok(await row(p.id), 'not deleted');
});

test('If-Match is forwarded, so a stale edit gets 409 from the target', async () => {
  const p = (await call('GET', '/api/admin/products')).body.products[0];
  const res = await call('DELETE', `/api/admin/products/${encodeURIComponent(p.id)}`, undefined, { 'If-Match': '"0123456789abcdef0123456789abcdef"' });
  assert.equal(res.status, 409);
  assert.equal(res.body.conflict, true);
  assert.ok(await row(p.id), 'not deleted');
});

test('writes outside /api are refused', async () => {
  const res = await fetch(`${base}/upload`, { method: 'POST', body: 'x' });
  assert.equal(res.status, 405);
});

test('target unreachable: a write reports an UNKNOWN outcome (never success)', async () => {
  const closed = http.createServer();
  await new Promise(r => closed.listen(0, '127.0.0.1', r));
  const port = closed.address().port;
  await new Promise(r => closed.close(r));
  const dead = await startAdminProduction({ port: 0, target: `http://127.0.0.1:${port}`, quiet: true });
  try {
    const write = await fetch(`http://127.0.0.1:${dead.port}/api/admin/products/X`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    const body = await write.json();
    assert.equal(write.status, 502);
    assert.deepEqual([body.success, body.outcomeUnknown], [false, true]);
    const read = await (await fetch(`http://127.0.0.1:${dead.port}/api/admin/products`)).json();
    assert.equal(read.outcomeUnknown, false);
  } finally { await dead.close(); }
});

test('no answer in time: 504, outcome unknown, and the write is sent once (never retried)', async () => {
  let hits = 0;
  const slow = http.createServer(() => { hits++; /* never answers */ });
  await new Promise(r => slow.listen(0, '127.0.0.1', r));
  const p = await startAdminProduction({ port: 0, target: `http://127.0.0.1:${slow.address().port}`, quiet: true, timeoutMs: 300 });
  try {
    const res = await fetch(`http://127.0.0.1:${p.port}/api/admin/products/X`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    const body = await res.json();
    assert.equal(res.status, 504);
    assert.equal(body.outcomeUnknown, true);
    assert.equal(hits, 1);
  } finally {
    await p.close();
    slow.closeAllConnections();
    await new Promise(r => slow.close(r));
  }
});
