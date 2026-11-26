// Admin Add/Edit Product: "Cabinet Price" is asked for, required and stored
// (products.cabinet_price, migration 009) only for the Cabinet category.
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
  await sandbox.db.query(`INSERT INTO categories (id, key_name, title, image_url, display_order)
    VALUES ('CAT_CAB', 'cabinets', 'Cabinet', '', 99)`);
  const { email, password } = sandbox.credentials.admin;
  token = (await (await fetch(`${base}/api/admin/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) })).json()).token;
});
test.after(async () => { await sandbox?.close(); });

const admin = async (method, url, body) => {
  const res = await fetch(base + url, { method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const row = async sku => (await sandbox.db.query('SELECT * FROM products WHERE sku = $1', [sku])).rows[0];
const listed = async sku => (await admin('GET', '/api/admin/products')).body.products.find(p => p.sku === sku);

test('migration 009 adds one nullable column and changes no product', async () => {
  const col = (await sandbox.db.query(`SELECT is_nullable FROM information_schema.columns WHERE table_name = 'products' AND column_name = 'cabinet_price'`)).rows[0];
  assert.equal(col.is_nullable, 'YES');
  const set = (await sandbox.db.query('SELECT COUNT(*)::int AS n FROM products WHERE cabinet_price IS NOT NULL')).rows[0].n;
  assert.equal(set, 0, 'every existing product starts without a Cabinet Price');
});

test('Cabinet product: Cabinet Price is required and saved in its own column', async () => {
  const missing = await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'Cab A', sku: 'CABT-1', category: 'cabinets', price: '1100' });
  assert.equal(missing.status, 400);
  assert.match(missing.body.error, /Cabinet Price is required/);
  for (const bad of ['0', '-5', 'abc']) {
    assert.equal((await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'Cab A', sku: 'CABT-1', category: 'cabinets', cabinet_price: bad })).status, 400, bad);
  }
  const ok = await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'Cab A', sku: 'CABT-1', category: 'cabinets', brand: '', purchase_price: '700', price: '1100', mrp: '1500', cabinet_price: '950' });
  assert.equal(ok.status, 201, JSON.stringify(ok.body));
  const r = await row('CABT-1');
  assert.deepEqual([Number(r.cabinet_price), Number(r.price), Number(r.purchase_price), Number(r.mrp)], [950, 1100, 700, 1500], 'other prices untouched');
  assert.equal((await listed('CABT-1')).cabinet_price, 950, 'admin list returns it');
  // Works with the other prices empty, too.
  assert.equal((await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'Cab B', sku: 'CABT-2', category: 'Cabinet', cabinet_price: 1200 })).status, 201);
  assert.equal(Number((await row('CABT-2')).cabinet_price), 1200);
  assert.equal(Number((await row('CABT-2')).price), 0);
});

test('other categories: no Cabinet Price required, and none stored even if sent', async () => {
  assert.equal((await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'Valve', sku: 'NONCAB-1', category: 'spares', price: '80' })).status, 201);
  assert.equal((await row('NONCAB-1')).cabinet_price, null);
  assert.equal((await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'Valve 2', sku: 'NONCAB-2', category: 'spares', price: '80', cabinet_price: '999' })).status, 201);
  assert.equal((await row('NONCAB-2')).cabinet_price, null);
  assert.equal((await listed('NONCAB-1')).cabinet_price, null);
});

test('editing: saved Cabinet Price is kept/changed; leaving Cabinet keeps it (hidden), never deleted', async () => {
  const id = (await row('CABT-1')).id;
  const base = { name: 'Cab A', sku: 'CABT-1', price: '', purchase_price: '', mrp: '', brand: '' };
  assert.equal((await admin('PUT', `/api/admin/products/${id}`, { ...base, category: 'cabinets', cabinet_price: '' })).status, 200);
  let r = await row('CABT-1');
  assert.deepEqual([Number(r.cabinet_price), Number(r.price)], [950, 1100], 'blank keeps the saved values');
  assert.equal((await admin('PUT', `/api/admin/products/${id}`, { ...base, category: 'cabinets', cabinet_price: '-1' })).status, 400);
  assert.equal((await admin('PUT', `/api/admin/products/${id}`, { ...base, category: 'cabinets', cabinet_price: '980' })).status, 200);
  r = await row('CABT-1');
  assert.deepEqual([Number(r.cabinet_price), Number(r.price), Number(r.purchase_price), Number(r.mrp)], [980, 1100, 700, 1500]);
  // Moved to another category: the saved Cabinet Price is preserved exactly
  // (a value sent for it is ignored), other prices unchanged, and dealers do
  // not see it outside the Cabinet category.
  assert.equal((await admin('PUT', `/api/admin/products/${id}`, { ...base, category: 'filters', cabinet_price: '' })).status, 200);
  r = await row('CABT-1');
  assert.equal(r.category_key, 'filters');
  assert.equal(Number(r.cabinet_price), 980, 'kept when the Admin form sends it blank');
  assert.equal((await admin('PUT', `/api/admin/products/${id}`, { ...base, category: 'filters', cabinet_price: '1' })).status, 200);
  r = await row('CABT-1');
  assert.equal(Number(r.cabinet_price), 980, 'not overwritten outside Cabinet');
  assert.deepEqual([Number(r.price), Number(r.purchase_price), Number(r.mrp)], [1100, 700, 1500]);
  assert.equal((await listed('CABT-1')).cabinet_price, 980, 'Admin still shows the saved value');
  const pub = (await (await fetch(`http://localhost:${sandbox.port}/api/products`)).json()).products.find(p => p.sku === 'CABT-1');
  assert.equal(pub.cabinet_price, null, 'not shown to dealers outside Cabinet');
  // Back to Cabinet: the preserved Cabinet Price applies again (blank keeps it).
  assert.equal((await admin('PUT', `/api/admin/products/${id}`, { ...base, category: 'cabinets' })).status, 200);
  assert.equal(Number((await row('CABT-1')).cabinet_price), 980);
});

test('dealer catalog (/api/products) returns Cabinet Price for Cabinet products only, and admin changes show on the next read', async () => {
  const pub = async sku => (await (await fetch(`${base}/api/products`)).json()).products.find(p => p.sku === sku);
  assert.equal((await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'Cab C', sku: 'CABT-3', category: 'cabinets', price: '400', mrp: '500', cabinet_price: '375' })).status, 201);
  let p = await pub('CABT-3');
  assert.equal(p.cabinet_price, 375);
  assert.deepEqual([p.price, p.dealer_price, p.mrp], [400, 400, 500], 'Dealer Price and MRP unchanged');
  assert.equal(Object.hasOwn(p, 'purchase_price'), false, 'purchase price still never public');
  const id = (await row('CABT-3')).id;
  assert.equal((await admin('PUT', `/api/admin/products/${id}`, { name: 'Cab C', sku: 'CABT-3', category: 'cabinets', price: '', mrp: '', cabinet_price: '390' })).status, 200);
  p = await pub('CABT-3');
  assert.equal(p.cabinet_price, 390);
  assert.equal(p.price, 400);
  // Non-Cabinet products: null, even if a stray value sits in the column.
  assert.equal((await pub('NONCAB-1')).cabinet_price, null);
  await sandbox.db.query(`UPDATE products SET cabinet_price = 50 WHERE sku = 'NONCAB-2'`);
  assert.equal((await pub('NONCAB-2')).cabinet_price, null);
});
