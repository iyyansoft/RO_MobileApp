// scripts/product_info_import.cjs: fills only the cells given, refuses to replace saved
// information without --replace-existing, writes nothing on any error, guards against
// edits since the dry run, and rolls back exactly. Runs on the in-memory database.
const test = require('node:test');
const assert = require('node:assert/strict');
const { startSandbox } = require('../scripts/local_sandbox.cjs');
const { parseField, plan, applyInfo, rollbackInfo, exportCurrent } = require('../scripts/product_info_import.cjs');

let sandbox, tx, q;
test.before(async () => {
  sandbox = await startSandbox({ port: 0, quiet: true });
  const c = await sandbox.pool.raw.connect();
  tx = { query: async (s, p) => { const r = await c.query(s, p); return { ...r, rowCount: r.rowCount ?? r.affectedRows }; } };
  q = async (s, p) => (await tx.query(s, p)).rows;
  c.release();
  // Two products with no information yet (like CAB-11 in production).
  blankProducts = await q(`UPDATE products SET description = NULL, specs_json = NULL, features_json = NULL
    WHERE id IN (SELECT id FROM products WHERE sku <> 'RO-FLT-CTO' ORDER BY id LIMIT 2) RETURNING id, sku`);
  blankProducts.sort((a, b) => (a.id < b.id ? -1 : 1));
});
test.after(async () => { await sandbox?.close(); });

const hash = async (except = []) => (await q(`SELECT md5(string_agg((to_jsonb(p) ${except.map(c => `- '${c}'`).join(' ')})::text, '|' ORDER BY p.id COLLATE "C")) h FROM products p`))[0].h;
const row = async sku => (await q(`SELECT id, sku, description, specs_json::text AS specs, features_json::text AS features FROM products WHERE sku = $1`, [sku]))[0];
let blankProducts;
const empty = async () => blankProducts[0];

test('cells are checked with the Admin Dashboard rules', () => {
  assert.deepEqual(parseField('specs', 'Body: ABS\nVoltage: 24V').value, { Body: 'ABS', Voltage: '24V' });
  assert.match(parseField('specs', 'Body: ABS\njust text').error, /line 2 .*needs a name and a value/);
  assert.deepEqual(parseField('features', 'Easy fit\nSilent, low power').value, ['Easy fit', 'Silent, low power']);
  assert.match(parseField('description', '   ').error, /blank/);
  assert.match(parseField('description', 'x'.repeat(5001)).error, /max 5000/);
});

test('export lists every product with its saved information as editable lines', async () => {
  const products = await exportCurrent(q);
  assert.equal(products.length, Number((await q('SELECT count(*)::int n FROM products'))[0].n));
  const cto = products.find(p => p.sku === 'RO-FLT-CTO');
  assert.ok(cto.description && cto.specs && cto.features, 'sample product information is exported');
  assert.doesNotMatch(cto.specs, /^\{/, 'specifications are "Name: Value" lines, not JSON');
});

test('dry run: replacing saved information is refused unless allowed; a bad cell blocks everything', async () => {
  const blank = await empty();
  const entries = [
    { row: 2, product_id: blank.id, sku: blank.sku, description: 'Real text', specs: 'Body: ABS', features: 'Easy fit' },
    { row: 3, product_id: 'SAMPLE_RO_FLT_CTO', sku: 'RO-FLT-CTO', specs: 'Size: 10 inch' },
  ];
  let p = await plan(q, entries);
  assert.equal(p.errors.length, 1);
  assert.match(p.errors[0], /would replace the saved specs/);
  p = await plan(q, entries, { replaceExisting: true });
  assert.deepEqual(p.errors, []);
  assert.deepEqual(p.changes.find(c => c.sku === 'RO-FLT-CTO').fields.map(f => f.action), ['replace']);
  assert.deepEqual(p.changes.find(c => c.sku === blank.sku).fields.map(f => f.action), ['fill', 'fill', 'fill']);
  p = await plan(q, [...entries, { row: 4, product_id: 'SAMPLE_RO_FLT_CTO', sku: 'WRONG', description: 'x' }, { row: 5, product_id: 'NOPE', sku: 'NOPE', description: 'x' }], { replaceExisting: true });
  assert.equal(p.errors.length, 2, p.errors.join('\n'));
  p = await plan(q, [{ row: 6, product_id: blank.id, sku: blank.sku, specs: 'no colon' }]);
  assert.match(p.errors[0], /needs a name and a value/);
});

test('apply writes only the filled fields, keeps every other column, and rolls back exactly', async () => {
  const blank = await empty();
  const cto = await row('RO-FLT-CTO');
  const start = await hash();
  const others = await hash(['description', 'specs_json', 'features_json']);
  const p = await plan(q, [
    { product_id: blank.id, sku: blank.sku, description: 'Line one.\nLine two, with a comma.', specs: 'Body: ABS plastic\nStorage tank: 10 L', features: 'Wall mountable\nSilent, low-power pump' },
    { product_id: cto.id, sku: cto.sku, specs: 'Size: 10 inch' },   // description and features blank = keep
  ], { replaceExisting: true });
  const result = await applyInfo(tx, p.toWrite);
  assert.equal(result.updated, 2);
  const b = await row(blank.sku);
  assert.equal(b.description, 'Line one.\nLine two, with a comma.');
  assert.deepEqual(JSON.parse(b.specs), { Body: 'ABS plastic', 'Storage tank': '10 L' });
  assert.deepEqual(JSON.parse(b.features), ['Wall mountable', 'Silent, low-power pump']);
  const c = await row('RO-FLT-CTO');
  assert.deepEqual(JSON.parse(c.specs), { Size: '10 inch' });
  assert.equal(c.description, cto.description);
  assert.equal(c.features, cto.features);
  assert.equal(await hash(['description', 'specs_json', 'features_json']), others, 'no other column changed');
  // An admin edits the product after the import: rollback refuses and changes nothing.
  await q(`UPDATE products SET description = 'edited later' WHERE id = $1`, [blank.id]);
  const edited = await hash();
  await assert.rejects(rollbackInfo(tx, { changes: p.toWrite }), /changed since the import/);
  assert.equal(await hash(), edited);
  await q(`UPDATE products SET description = $2 WHERE id = $1`, [blank.id, 'Line one.\nLine two, with a comma.']);
  assert.deepEqual(await rollbackInfo(tx, { changes: p.toWrite }), { restored: 2 });
  assert.equal(await hash(), start, 'rollback restores every product exactly');
});

test('a product changed between dry run and apply: nothing is saved', async () => {
  const blank = await empty();
  const other = blankProducts[1];
  const p = await plan(q, [
    { product_id: other.id, sku: other.sku, description: 'First product text' },
    { product_id: blank.id, sku: blank.sku, description: 'Second product text' },
  ]);
  assert.deepEqual(p.errors, []);
  await q(`UPDATE products SET description = 'typed in Admin meanwhile' WHERE id = $1`, [blank.id]);
  const before = await hash();
  await assert.rejects(applyInfo(tx, p.toWrite), /changed since the dry run/);
  assert.equal(await hash(), before, 'the first product was not saved either (one transaction)');
});
