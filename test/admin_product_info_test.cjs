// Product Description, Specifications and Key Features entered in the Admin
// Dashboard are saved per product, returned by the APIs and never lost.
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
});
test.after(async () => { await sandbox?.close(); });
const admin = async (method, url, body) => {
  const res = await fetch(base + url, { method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const dbRow = async sku => { const r = await sandbox.db.query('SELECT * FROM products WHERE UPPER(sku) = $1', [sku]); return (r.rows ?? r[0])[0]; };
const apiProduct = async sku => (await (await fetch(`${base}/api/products`)).json()).products.find(p => p.sku === sku);
const json = v => (typeof v === 'string' ? JSON.parse(v) : v);
const form = (p, extra) => ({ name: p.name, sku: p.sku, category: p.category_key, price: String(p.price), mrp: String(p.mrp), stock_quantity: p.stock_quantity, moq: p.moq || '', ...extra });

test('Add Product: "Name: Value" lines become one specification each; features one per line', async () => {
  const res = await admin('POST', '/api/admin/products', {
    name: 'Info Cabinet', sku: 'INFO-1', category: 'spares', price: '100', mrp: '150', stock_quantity: 4,
    desc: 'Line one.\nLine two, with a comma.',
    specs: 'Body: ABS plastic\nColour: Cherry red\nStorage tank: 10 L',
    features: 'Wall mountable\nSilent, low-power pump',
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  const row = await dbRow('INFO-1');
  assert.equal(row.description, 'Line one.\nLine two, with a comma.');
  assert.deepEqual(json(row.specs_json), { Body: 'ABS plastic', Colour: 'Cherry red', 'Storage tank': '10 L' });
  assert.deepEqual(json(row.features_json), ['Wall mountable', 'Silent, low-power pump'], 'a comma does not split a feature');
  const api = await apiProduct('INFO-1');
  assert.equal(api.desc, 'Line one.\nLine two, with a comma.');
  assert.deepEqual(api.specs, { Body: 'ABS plastic', Colour: 'Cherry red', 'Storage tank': '10 L' });
  assert.deepEqual(api.features, ['Wall mountable', 'Silent, low-power pump']);
});

test('a specification line without a value is refused, nothing saved or changed', async () => {
  const bad = await admin('POST', '/api/admin/products', { name: 'Bad Specs', sku: 'INFO-BAD', category: 'spares', price: '100', stock_quantity: 1, specs: 'Body: ABS\njust some text' });
  assert.equal(bad.status, 400);
  assert.match(bad.body.error, /line 2 .*needs a name and a value/);
  assert.equal(await dbRow('INFO-BAD'), undefined);
  const before = await dbRow('INFO-1');
  const res = await admin('PUT', `/api/admin/products/${before.id}`, form(before, { specs: 'no colon here' }));
  assert.equal(res.status, 400);
  assert.deepEqual(json((await dbRow('INFO-1')).specs_json), json(before.specs_json), 'saved specifications kept');
});

test('Edit: new information replaces the old; a stock-only edit keeps it; description can be cleared', async () => {
  const p = await dbRow('INFO-1');
  let res = await admin('PUT', `/api/admin/products/${p.id}`, form(p, { desc: 'Updated text', specs: { Voltage: '24V' }, features: ['Easy fit'] }));
  assert.equal(res.status, 200, JSON.stringify(res.body));
  let row = await dbRow('INFO-1');
  assert.equal(row.description, 'Updated text');
  assert.deepEqual(json(row.specs_json), { Voltage: '24V' });
  assert.deepEqual(json(row.features_json), ['Easy fit']);
  // Stock-only edit through an API client that does not send the three fields.
  res = await admin('PUT', `/api/admin/products/${p.id}`, form(row, { stock_quantity: 9 }));
  assert.equal(res.status, 200);
  row = await dbRow('INFO-1');
  assert.equal(Number(row.stock_quantity), 9);
  assert.equal(row.description, 'Updated text');
  assert.deepEqual(json(row.specs_json), { Voltage: '24V' });
  assert.deepEqual(json(row.features_json), ['Easy fit']);
  // Clearing the description in the form.
  res = await admin('PUT', `/api/admin/products/${p.id}`, form(row, { desc: '' }));
  assert.equal(res.status, 200);
  assert.equal(((await dbRow('INFO-1')).description || ''), '', 'an admin can clear the description');
});

test('existing sample product information survives an unrelated edit', async () => {
  const before = await dbRow('RO-FLT-CTO');
  const res = await admin('PUT', `/api/admin/products/${before.id}`, form(before, { stock_quantity: Number(before.stock_quantity) + 1 }));
  assert.equal(res.status, 200, JSON.stringify(res.body));
  const after = await dbRow('RO-FLT-CTO');
  assert.equal(after.description, before.description);
  assert.deepEqual(json(after.specs_json), json(before.specs_json));
  assert.deepEqual(json(after.features_json), json(before.features_json));
});

test('Excel upload: specification lines and features are saved per row', async () => {
  const res = await admin('POST', '/api/admin/products/bulk', { products: [
    { row: 2, name: 'Info Bulk', sku: 'INFO-BULK', category: 'spares', price: '90', stock_quantity: '3', description: 'Bulk description', specs: 'Size: 10 inch\nMicron: 5', features: 'Food grade\nLong life' },
    { row: 3, name: 'Info Bulk Bad', sku: 'INFO-BULK-BAD', category: 'spares', price: '90', stock_quantity: '3', specs: 'oops' },
  ] });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  const row = await dbRow('INFO-BULK');
  assert.deepEqual(json(row.specs_json), { Size: '10 inch', Micron: '5' });
  assert.deepEqual(json(row.features_json), ['Food grade', 'Long life']);
  assert.equal(row.description, 'Bulk description');
  assert.match(res.body.rows.find(r => r.row === 3).errors.join(), /needs a name and a value/);
});

test('public share page shows the saved description', async () => {
  const p = await dbRow('RO-FLT-CTO');
  const html = await (await fetch(`${base}/share/products/${p.id}`)).text();
  assert.match(html, /og:description" content="[^"]*chlorine and odour reduction/);
});

test('Admin Panel edits specifications as "Name: Value" lines', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'web_preview', 'admin.html'), 'utf8');
  const a = html.indexOf('    function specsToLines'), b = html.indexOf('    async function handleSaveProduct');
  const [toLines, toSpecs] = new Function(`${html.slice(a, b)}; return [specsToLines, linesToSpecs];`)();
  assert.deepEqual(toSpecs('Body: ABS plastic\nColour: Cherry red').value, { Body: 'ABS plastic', Colour: 'Cherry red' });
  assert.match(toSpecs('just text').error, /needs a name and a value/);
  assert.equal(toLines({ Body: 'ABS', Voltage: '24V' }), 'Body: ABS\nVoltage: 24V');
  assert.doesNotMatch(html, /specsObj = \{ details:/, 'no longer merges everything into one "details" entry');
});
