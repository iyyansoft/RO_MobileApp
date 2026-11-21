// Admin "Edit Product" used to update stock: only the stock may change.
// Runs the real server.js on the isolated in-memory database.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { startSandbox } = require('../scripts/local_sandbox.cjs');

let sandbox;
let base;
let token;
test.before(async () => {
  sandbox = await startSandbox({ port: 0, quiet: true });
  base = `http://localhost:${sandbox.port}`;
  const { email, password } = sandbox.credentials.admin;
  token = (await (await fetch(`${base}/api/admin/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) })).json()).token;
  assert.ok(token, 'admin login');
});
test.after(async () => { await sandbox?.close(); });

const admin = async (method, url, body) => {
  const res = await fetch(base + url, { method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const row = async id => (await sandbox.db.query('SELECT * FROM products WHERE id = $1', [id])).rows?.[0]
  ?? (await sandbox.db.query('SELECT * FROM products WHERE id = $1', [id]))[0];

// Exactly the fields the HTML Admin Panel sends when only the stock box was changed.
const formFor = p => ({
  name: p.name, sku: p.sku, category: p.category_key, brand: p.brand || '', purchase_price: '', purchasePrice: '',
  price: String(p.price), mrp: String(p.mrp), cabinet_price: '', moq: p.moq || '', stock_quantity: 120, min_stock: p.min_stock ?? 10,
  img: p.img || '', desc: p.description || '', specs: {}, features: [], badge: p.badge || '', status: p.status,
});

test('editing only the stock keeps the rating (none stays none) and the MOQ text', async () => {
  await sandbox.db.query(`INSERT INTO products (id, category_id, category_key, sku, name, brand, price, mrp, moq, img, status, stock_quantity, rating)
    VALUES ('PDF_TST_01', (SELECT id FROM categories WHERE key_name = 'membranes'), 'membranes', 'TST-01', 'Test Membrane', '', 1200, 2800, '40 nos', '', 'active', 0, NULL)`);
  const before = await row('PDF_TST_01');
  const res = await admin('PUT', '/api/admin/products/PDF_TST_01', formFor(before));
  assert.equal(res.status, 200, JSON.stringify(res.body));
  const after = await row('PDF_TST_01');
  assert.equal(Number(after.stock_quantity), 120);
  // Every other column is exactly as before (NULLs stay NULL, nothing filled in).
  const { stock_quantity: _b, ...restBefore } = before;
  const { stock_quantity: _a, ...restAfter } = after;
  assert.deepEqual(restAfter, restBefore, 'only the stock changed');
  assert.equal(after.rating, null, 'no made-up 5-star rating');
  assert.equal(after.moq, '40 nos', 'MOQ text unchanged (no "MOQ: " added)');
  assert.equal(Number(after.price), 1200);
  assert.equal(Number(after.mrp), 2800);
});

test('a rating or a changed MOQ that the admin does send is still saved', async () => {
  const before = await row('PDF_TST_01');
  const res = await admin('PUT', '/api/admin/products/PDF_TST_01', { ...formFor(before), rating: '4.2', moq: '50 nos' });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  const after = await row('PDF_TST_01');
  assert.equal(after.rating, '4.2');
  assert.equal(after.moq, 'MOQ: 50 nos');
});

test('Admin Panel refuses a blank stock instead of saving 50', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'web_preview', 'admin.html'), 'utf8');
  assert.doesNotMatch(html, /prodStockQuantity'\)\.value \|\| 50/, 'no silent default of 50');
  assert.match(html, /Enter the actual stock quantity/);
});
