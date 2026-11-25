// Phase 2: optimistic concurrency for Admin product edits and deletes
// (If-Match = the product's version; 409 when it changed). No schema change.
// Runs the real server.js on the isolated in-memory database.
const test = require('node:test');
const assert = require('node:assert/strict');
const { startSandbox } = require('../scripts/local_sandbox.cjs');

let sandbox;
let base;
let token;
test.before(async () => {
  sandbox = await startSandbox({ port: 0, quiet: true });
  base = `http://localhost:${sandbox.port}`;
  const { email, password } = sandbox.credentials.admin;
  token = (await (await fetch(`${base}/api/admin/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) })).json()).token;
  assert.ok(token);
  await sandbox.db.query(`INSERT INTO products (id, category_id, category_key, sku, name, brand, price, mrp, moq, img, status, stock_quantity, description)
    VALUES ('PDF_CNF_01', (SELECT id FROM categories WHERE key_name = 'membranes'), 'membranes', 'CNF-01', 'Conflict Membrane', '', 1200, 2800, '40 nos', '', 'active', 5, 'Original'),
           ('PDF_CNF_02', (SELECT id FROM categories WHERE key_name = 'membranes'), 'membranes', 'CNF-02', 'Conflict Membrane 2', '', 1200, 2800, '40 nos', '', 'active', 5, 'Original')`);
});
test.after(async () => { await sandbox?.close(); });

const admin = async (method, url, body, headers = {}) => {
  const res = await fetch(base + url, { method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, ...headers }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const listed = async id => (await admin('GET', '/api/admin/products')).body.products.find(p => p.id === id);
const row = async id => (await sandbox.db.query('SELECT * FROM products WHERE id = $1', [id])).rows[0];
const form = (p, extra = {}) => ({
  name: p.name, sku: p.sku, category: p.category, price: String(p.price), mrp: String(p.mrp), moq: p.moq || '',
  stock_quantity: p.stock_quantity, min_stock: p.min_stock ?? 10, img: p.img || '', desc: p.desc || '',
  specs: p.specs, features: p.features, badge: p.badge || '', status: p.status, ...extra,
});

test('the Admin product list gives every product a version', async () => {
  const p = await listed('PDF_CNF_01');
  assert.match(p.version, /^[0-9a-f]{32}$/);
  assert.equal((await listed('PDF_CNF_01')).version, p.version, 'stable while unchanged');
});

test('an edit with the current version is saved and gets a new version', async () => {
  const p = await listed('PDF_CNF_01');
  const res = await admin('PUT', '/api/admin/products/PDF_CNF_01', form(p, { desc: 'First admin' }), { 'If-Match': `"${p.version}"` });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal((await row('PDF_CNF_01')).description, 'First admin');
  assert.notEqual((await listed('PDF_CNF_01')).version, p.version);
});

test('an edit based on an old version is refused with 409 and saves nothing', async () => {
  const opened = await listed('PDF_CNF_01');                       // admin B opens the form
  const first = await admin('PUT', '/api/admin/products/PDF_CNF_01', form(opened, { desc: 'Admin A' }), { 'If-Match': `"${opened.version}"` });
  assert.equal(first.status, 200);                                  // admin A saves first
  const before = await row('PDF_CNF_01');
  const stale = await admin('PUT', '/api/admin/products/PDF_CNF_01', form(opened, { desc: 'Admin B', stock_quantity: 99 }), { 'If-Match': `"${opened.version}"` });
  assert.equal(stale.status, 409);
  assert.equal(stale.body.conflict, true);
  assert.match(stale.body.error, /changed by someone else/);
  assert.deepEqual(await row('PDF_CNF_01'), before, 'Admin A\'s save is not overwritten');
});

test('a change made directly in the database also counts as a conflict', async () => {
  const opened = await listed('PDF_CNF_01');
  await sandbox.db.query(`UPDATE products SET stock_quantity = 7 WHERE id = 'PDF_CNF_01'`);
  const res = await admin('PUT', '/api/admin/products/PDF_CNF_01', form(opened, { desc: 'Late' }), { 'If-Match': `"${opened.version}"` });
  assert.equal(res.status, 409);
  assert.equal(Number((await row('PDF_CNF_01')).stock_quantity), 7);
});

test('without If-Match an edit works as before (older Admin Panels, imports)', async () => {
  const p = await listed('PDF_CNF_01');
  const res = await admin('PUT', '/api/admin/products/PDF_CNF_01', form(p, { desc: 'No version sent' }));
  assert.equal(res.status, 200);
  assert.equal((await row('PDF_CNF_01')).description, 'No version sent');
});

test('delete: an old version is refused (409, kept); the current version deletes', async () => {
  const opened = await listed('PDF_CNF_02');
  await sandbox.db.query(`UPDATE products SET description = 'Changed meanwhile' WHERE id = 'PDF_CNF_02'`);
  const stale = await admin('DELETE', '/api/admin/products/PDF_CNF_02', undefined, { 'If-Match': `"${opened.version}"` });
  assert.equal(stale.status, 409);
  assert.ok(await row('PDF_CNF_02'), 'still there');
  const current = await listed('PDF_CNF_02');
  const ok = await admin('DELETE', '/api/admin/products/PDF_CNF_02', undefined, { 'If-Match': `"${current.version}"` });
  assert.equal(ok.status, 200);
  assert.equal(await row('PDF_CNF_02'), undefined);
});

test('the sandbox Admin Panel is labelled LOCAL TEST COPY', async () => {
  const html = await (await fetch(`${base}/admin`)).text();
  assert.match(html, /window\.__ADMIN_ENV = \{ mode: "local-test" \}/);
});
