// Admin "Add Product" and Excel bulk upload: nothing is invented (stock, rating,
// MOQ, brand, MRP, applications), every row is validated with its row number,
// a dry run saves nothing, and existing products are never changed.
// Runs the real server.js on the isolated in-memory database.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { startSandbox } = require('../scripts/local_sandbox.cjs');

let sandbox, base, token;
test.before(async () => {
  sandbox = await startSandbox({ port: 0, quiet: true });
  base = `http://localhost:${sandbox.port}`;
  const { email, password } = sandbox.credentials.admin;
  token = (await (await fetch(`${base}/api/admin/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) })).json()).token;
  assert.ok(token, 'admin login');
  // Production has a Cabinet category (Cabinet Price rule); the sample catalogue does not.
  await sandbox.db.query(`INSERT INTO categories (id, key_name, title, display_order) VALUES ('CAT_CAB', 'cabinets', 'Cabinet', 7)`);
});
test.after(async () => { await sandbox?.close(); });

const admin = async (method, url, body) => {
  const res = await fetch(base + url, { method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const rows = async (sql, params = []) => { const r = await sandbox.db.query(sql, params); return r.rows ?? r[0]; };
const productBySku = async sku => (await rows('SELECT * FROM products WHERE UPPER(sku) = $1', [sku]))[0];
const allProductsDigest = async () => JSON.stringify(await rows('SELECT * FROM products ORDER BY id'));

test('Add Product: a missing stock is refused, never set to 50', async () => {
  const res = await admin('POST', '/api/admin/products', { name: 'No Stock Valve', sku: 'UPL-NOSTOCK', category: 'spares', price: '100', mrp: '150' });
  assert.equal(res.status, 400);
  assert.match(res.body.error, /Stock quantity is required/);
  assert.equal(await productBySku('UPL-NOSTOCK'), undefined, 'nothing saved');
});

test('Add Product: rating, MOQ and applications stay empty when not given', async () => {
  const res = await admin('POST', '/api/admin/products', { name: 'Plain Valve', sku: 'UPL-PLAIN', category: 'spares', price: '100', mrp: '150', stock_quantity: 7, moq: '', rating: '' });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  const p = await productBySku('UPL-PLAIN');
  assert.equal(Number(p.stock_quantity), 7);
  assert.equal(p.rating, null, 'no made-up 5-star rating');
  assert.equal(p.moq, null, 'no made-up "MOQ: 1 Unit"');
  assert.equal(p.applications, null, 'no made-up applications text');
  assert.equal(p.brand, '');
  // Given values are kept.
  await admin('POST', '/api/admin/products', { name: 'Rated Valve', sku: 'UPL-RATED', category: 'spares', price: '100', stock_quantity: 3, moq: '10 nos', rating: '4.5' });
  const r = await productBySku('UPL-RATED');
  assert.equal(r.moq, 'MOQ: 10 nos');
  assert.equal(r.rating, '4.5');
});

const upload = [
  { row: 2, name: 'Good Filter', sku: 'UPL-OK-1', category: 'filters', price: '120', mrp: '200', stock_quantity: '15', moq: '10 nos', brand: 'Acme' },
  { row: 3, name: 'No MRP Filter', sku: 'UPL-OK-2', category: 'filters', price: '90', stock_quantity: '0' },
  { row: 4, name: 'No Stock Filter', sku: 'UPL-BAD-1', category: 'filters', price: '90' },
  { row: 5, name: 'Bad Stock Filter', sku: 'UPL-BAD-2', category: 'filters', price: '90', stock_quantity: '2.5' },
  { row: 6, name: 'No Price Filter', sku: 'UPL-BAD-3', category: 'filters', stock_quantity: '4' },
  { row: 7, name: 'Cheap MRP Filter', sku: 'UPL-BAD-4', category: 'filters', price: '90', mrp: '50', stock_quantity: '4' },
  { row: 8, name: 'Unknown Category', sku: 'UPL-BAD-5', category: 'rockets', price: '90', stock_quantity: '4' },
  { row: 9, name: 'Repeat SKU', sku: 'UPL-OK-1', category: 'filters', price: '90', stock_quantity: '4' },
  { row: 10, name: 'Existing product', sku: 'UPL-PLAIN', category: 'spares', price: '999', stock_quantity: '999' },
  { row: 11, name: 'Cabinet without Cabinet Price', sku: 'UPL-CAB-1', category: 'cabinets', price: '3000', mrp: '9000', stock_quantity: '5' },
  { row: 12, name: 'Cabinet with Cabinet Price', sku: 'UPL-CAB-2', category: 'cabinets', price: '3000', mrp: '9000', stock_quantity: '5', cabinet_price: '1200' },
];

test('Excel upload dry run: row-by-row results, nothing saved', async () => {
  const before = await allProductsDigest();
  const res = await admin('POST', '/api/admin/products/bulk', { products: upload, dryRun: true });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.dryRun, true);
  const byRow = Object.fromEntries(res.body.rows.map(r => [r.row, r]));
  assert.deepEqual(res.body.summary, { total: 11, ready: 3, errors: 7, duplicates: 1 });
  assert.equal(byRow[2].status, 'ready');
  assert.equal(byRow[3].status, 'ready');
  assert.equal(byRow[12].status, 'ready');
  assert.match(byRow[4].errors.join(), /Stock quantity is required/);
  assert.match(byRow[5].errors.join(), /whole number/);
  assert.match(byRow[6].errors.join(), /Dealer price is required/);
  assert.match(byRow[7].errors.join(), /MRP cannot be lower/);
  assert.match(byRow[8].errors.join(), /Category "rockets" does not exist/);
  assert.match(byRow[9].errors.join(), /more than once/);
  assert.equal(byRow[10].status, 'duplicate');
  assert.match(byRow[10].errors.join(), /existing product is not changed/);
  assert.match(byRow[11].errors.join(), /Cabinet Price/);
  assert.equal(byRow[3].values.mrp, 0, 'missing MRP is reported as not set, never estimated');
  assert.equal(await allProductsDigest(), before, 'a dry run changes nothing');
});

test('Excel upload import: only ready rows saved, exactly as given; existing product untouched', async () => {
  const existingBefore = JSON.stringify(await productBySku('UPL-PLAIN'));
  const res = await admin('POST', '/api/admin/products/bulk', { products: upload });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  assert.equal(res.body.importedCount, 3);
  assert.equal(res.body.rows.filter(r => r.status === 'imported').length, 3);
  const ok1 = await productBySku('UPL-OK-1');
  assert.equal(Number(ok1.stock_quantity), 15);
  assert.equal(ok1.moq, 'MOQ: 10 nos');
  assert.equal(ok1.brand, 'Acme');
  assert.equal(ok1.rating, null);
  assert.equal(ok1.applications, null);
  const ok2 = await productBySku('UPL-OK-2');
  assert.equal(Number(ok2.stock_quantity), 0, 'stock 0 is a real entered value');
  assert.equal(Number(ok2.mrp), 0, 'no MRP = not set (never price x 1.25)');
  assert.equal(ok2.brand, '', 'no made-up brand');
  assert.equal(ok2.moq, null);
  const cab = await productBySku('UPL-CAB-2');
  assert.equal(Number(cab.cabinet_price), 1200);
  for (const sku of ['UPL-BAD-1', 'UPL-BAD-2', 'UPL-BAD-3', 'UPL-BAD-4', 'UPL-BAD-5', 'UPL-CAB-1']) assert.equal(await productBySku(sku), undefined, `${sku} not saved`);
  assert.equal(JSON.stringify(await productBySku('UPL-PLAIN')), existingBefore, 'existing product never overwritten');
  assert.equal((await rows(`SELECT count(*)::int n FROM products WHERE UPPER(sku) = 'UPL-OK-1'`))[0].n, 1, 'repeated SKU saved once');
});

test('Admin Panel: no invented defaults; import runs a dry run first', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'web_preview', 'admin.html'), 'utf8');
  assert.doesNotMatch(html, /stock_quantity: 50|MOQ: 1 Unit|\* 1\.25|'Aqua Mars'\)|prodStockQuantity'\)\.value = 50/);
  assert.match(html, /dryRun: true/);
  assert.match(html, /bulk-stock/);
  assert.match(html, /"Stock Quantity", "MOQ", "Cabinet Price"/);
  const flutterAdmin = fs.readFileSync(path.join(__dirname, '..', 'lib', 'admin_web_main.dart'), 'utf8');
  assert.doesNotMatch(flutterAdmin, /\?\? 50|\* 1\.25|'RO Wholesale'|moq \?\? 1/);
});
