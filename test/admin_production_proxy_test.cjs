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
  // The target serves the same admin.html, so the UI check matches and saving is allowed.
  assert.match(html, /window\.__ADMIN_ENV = \{"mode":"production","realProduction":false,"target":"http:\/\/127\.0\.0\.1:\d+","uiCheck":"match","writesBlocked":null\}/);
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

// The deployed /admin page (same as the local file), so the UI check passes and
// the write itself reaches the target.
const sameAdminPage = (req, res) => {
  if (!req.url.startsWith('/admin')) return false;
  res.writeHead(200, { 'content-type': 'text/html' });
  res.end(fs.readFileSync(path.join(__dirname, '..', 'web_preview', 'admin.html')));
  return true;
};

test('target unreachable: a write reports an UNKNOWN outcome (never success)', async () => {
  // /admin answers; every API request has its connection dropped.
  const dropping = http.createServer((req, res) => { if (!sameAdminPage(req, res)) req.socket.destroy(); });
  await new Promise(r => dropping.listen(0, '127.0.0.1', r));
  const dead = await startAdminProduction({ port: 0, target: `http://127.0.0.1:${dropping.address().port}`, quiet: true });
  try {
    const write = await fetch(`http://127.0.0.1:${dead.port}/api/admin/products/X`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    const body = await write.json();
    assert.equal(write.status, 502);
    assert.deepEqual([body.success, body.outcomeUnknown], [false, true]);
    const read = await (await fetch(`http://127.0.0.1:${dead.port}/api/admin/products`)).json();
    assert.equal(read.outcomeUnknown, false);
  } finally {
    await dead.close();
    dropping.closeAllConnections();
    await new Promise(r => dropping.close(r));
  }
});

test('no answer in time: 504, outcome unknown, and the write is sent once (never retried)', async () => {
  let hits = 0;
  const slow = http.createServer((req, res) => { if (!sameAdminPage(req, res)) hits++; /* API: never answers */ });
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

// --- Unreleased local Admin UI must never save to Production ----------------
// A target that answers the API like the fake Production, but serves a
// DIFFERENT /admin page (= what is deployed differs from the local file).
async function targetWithAdminPage(adminAnswer) {
  const server = http.createServer(async (req, res) => {
    if (req.url.startsWith('/admin')) {
      const { status, body } = adminAnswer;
      res.writeHead(status, { 'content-type': 'text/html' });
      return res.end(body);
    }
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const up = await fetch(`http://127.0.0.1:${fake.port}${req.url}`, {
      method: req.method,
      headers: Object.fromEntries(Object.entries(req.headers).filter(([k]) => ['content-type', 'authorization', 'if-match'].includes(k))),
      body: chunks.length ? Buffer.concat(chunks) : undefined,
    });
    res.writeHead(up.status, { 'content-type': up.headers.get('content-type') || 'application/json' });
    res.end(Buffer.from(await up.arrayBuffer()));
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const proxied = await startAdminProduction({ port: 0, target: `http://127.0.0.1:${server.address().port}`, quiet: true, uiCheckTimeoutMs: 2000 });
  return { base: `http://127.0.0.1:${proxied.port}`, close: async () => { await proxied.close(); server.closeAllConnections(); await new Promise(r => server.close(r)); } };
}

for (const [name, answer, state, reason] of [
  ['the deployed Admin page differs from the local one', { status: 200, body: '<html><head></head><body>deployed version</body></html>' }, 'differs', /differs from the deployed Production Admin/],
  ['the deployed Admin page cannot be checked', { status: 503, body: 'unavailable' }, 'unknown', /Could not confirm/],
]) {
  test(`${name}: page warns, saves are refused by the proxy (423), reading and sign-in still work`, async () => {
    const t = await targetWithAdminPage(answer);
    try {
      const html = await (await fetch(`${t.base}/admin`)).text();
      assert.match(html, new RegExp(`"uiCheck":"${state}","writesBlocked":"[^"]+"`));
      const { email, password } = fake.credentials.admin;
      const login = await fetch(`${t.base}/api/admin/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
      assert.equal(login.status, 200, 'sign-in is allowed');
      const t2 = (await login.json()).token;
      const products = (await (await fetch(`${t.base}/api/admin/products`, { headers: { Authorization: `Bearer ${t2}` } })).json()).products;
      assert.ok(products.length > 0, 'reading is allowed');
      const p = products[0];
      const before = await row(p.id);
      for (const [method, url] of [['PUT', `/api/admin/products/${encodeURIComponent(p.id)}`], ['DELETE', `/api/admin/products/${encodeURIComponent(p.id)}`], ['POST', '/api/admin/products'], ['POST', '/api/admin/set-status']]) {
        const res = await fetch(t.base + url, { method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${t2}` }, body: method === 'DELETE' ? undefined : JSON.stringify({ name: 'Blocked', desc: 'must not be saved' }) });
        const body = await res.json();
        assert.equal(res.status, 423, `${method} ${url}`);
        assert.equal(body.writesBlocked, true);
        assert.match(body.error, reason);
        assert.match(body.error, /Nothing was sent to Production/);
      }
      assert.deepEqual(await row(p.id), before, 'nothing changed');
    } finally { await t.close(); }
  });
}

test('the UI comparison ignores line endings and the injected label only', async () => {
  const local = fs.readFileSync(path.join(__dirname, '..', 'web_preview', 'admin.html'), 'utf8');
  const crlfWithLabel = local.replace(/\r?\n/g, '\r\n').replace('<head>', '<head>\n<script>window.__ADMIN_ENV = { mode: "local-test" };</script>');
  let t = await targetWithAdminPage({ status: 200, body: crlfWithLabel });
  try { assert.match(await (await fetch(`${t.base}/admin`)).text(), /"uiCheck":"match","writesBlocked":null/); } finally { await t.close(); }
  t = await targetWithAdminPage({ status: 200, body: local.replace('</body>', '<!-- one extra comment --></body>') });
  try { assert.match(await (await fetch(`${t.base}/admin`)).text(), /"uiCheck":"differs"/); } finally { await t.close(); }
});
