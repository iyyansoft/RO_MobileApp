// Admin "Add Product": Brand, Purchase Price, Dealer Price and MRP are optional.
// Runs the real server.js on the isolated in-memory database
// (scripts/local_sandbox.cjs) with the real products table.
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
  assert.ok(token, 'admin login');
});
test.after(async () => { await sandbox?.close(); });

const admin = async (method, url, body) => {
  const res = await fetch(base + url, { method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const adminProduct = async sku => (await admin('GET', '/api/admin/products')).body.products.find(p => p.sku === sku);
// Exactly what the HTML Admin Panel sends when the four boxes are empty.
const emptyForm = { brand: '', purchase_price: '', purchasePrice: '', price: '', mrp: '' };

test('saves a product with Brand, Purchase Price, Dealer Price and MRP all empty', async () => {
  const res = await admin('POST', '/api/admin/products', { name: 'Optional Fields Valve', sku: 'opt-empty-1', category: 'spares', ...emptyForm, moq: '', stock_quantity: 5, min_stock: 1, status: 'active' });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  const saved = await adminProduct('OPT-EMPTY-1');
  assert.ok(saved, 'product is in the database');
  assert.equal(saved.name, 'Optional Fields Valve');
  assert.equal(saved.brand, '', 'no made-up brand');
  assert.equal(Number(saved.purchase_price), 0);
  assert.equal(Number(saved.price), 0, 'dealer price not set');
  assert.equal(Number(saved.mrp), 0, 'MRP not available, never estimated');
});

test('also when the four fields are left out of the request entirely', async () => {
  const res = await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'Optional Fields Missing', sku: 'OPT-MISSING-1', category: 'spares' });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  const saved = await adminProduct('OPT-MISSING-1');
  assert.deepEqual([saved.brand, Number(saved.price), Number(saved.mrp), Number(saved.purchase_price)], ['', 0, 0, 0]);
});

test('values that are given are still validated and saved exactly', async () => {
  const cases = [
    [{ price: '-5' }, /Dealer price must be greater than zero/],
    [{ price: '0' }, /Dealer price must be greater than zero/],
    [{ price: 'abc' }, /Dealer price must be greater than zero/],
    [{ purchase_price: '-1' }, /Purchase price must be zero or more/],
    [{ mrp: '0' }, /MRP must be a valid amount/],
    [{ price: '500', mrp: '400' }, /MRP cannot be lower than the dealer price/],
  ];
  for (const [fields, error] of cases) {
    const res = await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'Bad', sku: `OPT-BAD-${Math.random().toString(36).slice(2, 8)}`, category: 'spares', ...emptyForm, ...fields });
    assert.equal(res.status, 400, JSON.stringify(fields));
    assert.match(res.body.error, error, JSON.stringify(fields));
  }
  // MRP alone (no dealer price) is fine.
  assert.equal((await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'MRP only', sku: 'OPT-MRP-ONLY', category: 'spares', ...emptyForm, mrp: '900' })).status, 201);
  const full = await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'All Set', sku: 'OPT-FULL-1', category: 'spares', brand: 'Aqua Mars', purchase_price: '400', price: '650', mrp: '900' });
  assert.equal(full.status, 201);
  const saved = await adminProduct('OPT-FULL-1');
  assert.deepEqual([saved.brand, Number(saved.purchase_price), Number(saved.price), Number(saved.mrp)], ['Aqua Mars', 400, 650, 900]);
  // Other required fields are unchanged.
  assert.match((await admin('POST', '/api/admin/products', { stock_quantity: 5, sku: 'OPT-NONAME', category: 'spares', ...emptyForm })).body.error, /name is required/);
  assert.match((await admin('POST', '/api/admin/products', { stock_quantity: 5, name: 'No SKU', category: 'spares', ...emptyForm })).body.error, /SKU is required/);
});

test('editing: empty optional fields keep the saved values; new values replace them', async () => {
  const saved = await adminProduct('OPT-FULL-1');
  const edit = await admin('PUT', `/api/admin/products/${saved.id}`, { name: 'All Set (edited)', sku: 'OPT-FULL-1', category: 'spares', ...emptyForm });
  assert.equal(edit.status, 200, JSON.stringify(edit.body));
  let after = await adminProduct('OPT-FULL-1');
  assert.deepEqual([after.name, after.brand, Number(after.purchase_price), Number(after.price), Number(after.mrp)], ['All Set (edited)', 'Aqua Mars', 400, 650, 900]);
  assert.equal((await admin('PUT', `/api/admin/products/${saved.id}`, { name: 'All Set', sku: 'OPT-FULL-1', category: 'spares', brand: 'Kent', purchase_price: '450', price: '700', mrp: '950' })).status, 200);
  after = await adminProduct('OPT-FULL-1');
  assert.deepEqual([after.brand, Number(after.purchase_price), Number(after.price), Number(after.mrp)], ['Kent', 450, 700, 950]);
  // A product saved without a dealer price can be edited and given one later.
  const empty = await adminProduct('OPT-EMPTY-1');
  assert.equal((await admin('PUT', `/api/admin/products/${empty.id}`, { name: empty.name, sku: empty.sku, category: 'spares', ...emptyForm, price: '320' })).status, 200);
  assert.equal(Number((await adminProduct('OPT-EMPTY-1')).price), 320);
  assert.equal((await admin('PUT', `/api/admin/products/${empty.id}`, { name: empty.name, sku: empty.sku, category: 'spares', ...emptyForm, price: '-3' })).status, 400);
});
