// The database step of scripts/pdf_catalog_import.cjs, on an in-memory
// Postgres with the app's real schema: what it changes, what it must never
// change, and that a failure leaves everything as it was.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PGlite } = require('@electric-sql/pglite');
const { citext } = require('@electric-sql/pglite/contrib/citext');
const { applyDatabaseChanges, inspectDatabase, productRows, loadPlanData, checkData, productId } = require('../scripts/pdf_catalog_import.cjs');

const root = path.join(__dirname, '..');
const read = f => fs.readFileSync(path.join(root, f), 'utf8');

async function seededDb() {
  const db = new PGlite({ extensions: { citext } });
  await db.exec(read('supabase_migration.sql'));
  await db.exec(read('shop_app_migration.sql'));
  const cats = [['CAT_SYS', 'systems'], ['CAT_MEM', 'membranes'], ['CAT_FLT', 'filters'], ['CAT_PMP', 'pumps'], ['CAT_PIP', 'pipes'], ['CAT_SPR', 'spares']];
  for (const [id, key] of cats) await db.query('INSERT INTO categories (id, key_name, title) VALUES ($1, $2, $3)', [id, key, key]);
  const product = (id, sku, key, name) => db.query(
    `INSERT INTO products (id, category_id, category_key, sku, name, brand, price, mrp, moq, img, stock_quantity)
     VALUES ($1, $2, $3, $4, $5, 'Brand', 100, 150, 'MOQ: 1 Piece', 'purifier.jpg', 100)`,
    [id, cats.find(c => c[1] === key)[0], key, sku, name]);
  await product('SAMPLE_RO_FLT_CTO', 'RO-FLT-CTO', 'filters', 'Carbon CTO Filter 10 Inch');
  await product('SAMPLE_RO_MEM_75', 'RO-MEM-75', 'membranes', 'RO Membrane 75 GPD');
  await product('prod_genuine_1', 'ABC', 'membranes', 'ABC');
  await db.query(`INSERT INTO users (id, email, name, password_hash) VALUES ('u1', 'dealer@example.test', 'Dealer', '')`);
  await db.query(`INSERT INTO orders (order_id, user_id, user_email, user_name, delivery_address, invoice_number, grand_total, status)
    VALUES ('O1', 'u1', 'dealer@example.test', 'Dealer', '14 Gandhi Road', 'INV-1', 300, 'Processing')`);
  await db.query(`INSERT INTO order_items (order_id, product_id, product_name, brand, unit_price, quantity, moq, img_src, sku) VALUES
    ('O1', 'SAMPLE_RO_FLT_CTO', 'Carbon CTO Filter 10 Inch', 'Brand', 100, 2, 'MOQ: 1 Piece', 'purifier.jpg', ''),
    ('O1', 'SAMPLE_RO_MEM_75', 'RO Membrane 75 GPD', 'Brand', 100, 1, 'MOQ: 1 Piece', 'purifier.jpg', 'KEEP-THIS'),
    ('O1', 'prod_genuine_1', 'ABC', 'Brand', 100, 1, NULL, 'purifier.jpg', NULL)`);
  await db.query(`INSERT INTO cart_items (user_id, product_id, quantity) VALUES ('u1', 'SAMPLE_RO_MEM_75', 1), ('u1', 'prod_genuine_1', 2)`);
  return db;
}

const q = db => async (sql, params) => (await db.query(sql, params)).rows;
// Needs the git-ignored supplier data (assets/product_pdfs/extracted). Skipped where it is
// absent (e.g. GitHub Actions); runs fully on the owner's computer.
const LOCAL_DATA = 'assets/product_pdfs/extracted/catalog_import.json';
const SKIP = fs.existsSync(path.join(root, LOCAL_DATA)) ? false : `needs git-ignored local data: ${LOCAL_DATA}`;
const plan = SKIP ? null : loadPlanData();

test('the extracted data is complete and consistent', { skip: SKIP }, () => {
  assert.equal(plan.all.length, 80);
  assert.equal(plan.toImport.length, 78);
  assert.deepEqual(plan.pending.map(p => p.sku), ['DOM-53', 'DOM-54']);
  assert.deepEqual(checkData(plan).errors, []);
  // Rules: Domestic Min qty blank; FR 450 rows named by code; prices as printed.
  assert.ok(plan.toImport.filter(p => p.pdf === 'domestic').every(p => p.moq === null));
  assert.ok(plan.toImport.filter(p => p.pdf === 'mukhil').every(p => Number.isInteger(p.moq)));
  assert.deepEqual(plan.toImport.filter(p => p.name.startsWith('FR 450')).map(p => p.name), ['FR 450 (Code 34)', 'FR 450 (Code 35)']);
  const pump = plan.toImport.find(p => p.sku === 'MUK-01');
  assert.deepEqual([pump.dealer_price, pump.moq, pump.mrp], [1050, 10, 2700]);
});

test('deletes SAMPLE_ products, fills empty order-line SKUs, imports PDF products, keeps history', { skip: SKIP }, async () => {
  const db = await seededDb();
  const info = await inspectDatabase(q(db), plan);
  assert.deepEqual(info.errors, []);
  assert.equal(info.samples.length, 2);
  assert.equal(info.emptySkuLines, 1);
  const rows = productRows(plan.toImport, info.categoryIdByKey, 'https://example.supabase.co');
  const result = await applyDatabaseChanges(db, { rows, expectedSampleIds: info.samples.map(s => s.id), expectedGenuineIds: info.genuine.map(g => g.id) });
  assert.equal(result.skuFilled, 1);
  assert.equal(result.deleted, 2);
  assert.equal(result.cartLinesRemoved, 1);
  assert.equal(result.inserted, 78);

  const lines = await q(db)('SELECT product_id, product_name, unit_price, quantity, sku FROM order_items ORDER BY id');
  assert.deepEqual(lines.map(l => l.sku), ['RO-FLT-CTO', 'KEEP-THIS', null], 'only the empty SKU is filled');
  assert.deepEqual(lines.map(l => [l.product_name, Number(l.unit_price), l.quantity]),
    [['Carbon CTO Filter 10 Inch', 100, 2], ['RO Membrane 75 GPD', 100, 1], ['ABC', 100, 1]]);
  assert.equal((await q(db)('SELECT count(*)::int n FROM orders'))[0].n, 1);
  assert.deepEqual((await q(db)('SELECT product_id FROM cart_items')).map(r => r.product_id), ['prod_genuine_1']);

  const products = await q(db)('SELECT * FROM products ORDER BY id');
  assert.equal(products.length, 79);
  assert.ok(products.some(p => p.id === 'prod_genuine_1' && p.name === 'ABC'));
  const membrane = products.find(p => p.id === productId('DOM-27'));
  assert.equal(membrane.name, 'Vero membrane 80 gpd');
  assert.equal(membrane.category_id, 'CAT_MEM');
  assert.equal(Number(membrane.price), 300);
  assert.equal(Number(membrane.mrp), 2490);
  assert.equal(membrane.moq, null, 'Domestic Min qty stays blank');
  assert.equal(membrane.stock_quantity, 0);
  assert.equal(membrane.img, 'https://example.supabase.co/storage/v1/object/public/ro-product-images/pdf-catalog/DOM-27.jpg');
  const pump = products.find(p => p.sku === 'MUK-01');
  assert.equal(pump.moq, '10 nos', 'Min qty exactly as printed in the PDF');
  assert.ok(!products.some(p => ['DOM-53', 'DOM-54'].includes(p.sku)), 'price ranges are not imported');
  await db.close();
});

test('a failure part-way rolls everything back', { skip: SKIP }, async () => {
  const db = await seededDb();
  const info = await inspectDatabase(q(db), plan);
  const rows = productRows(plan.toImport, info.categoryIdByKey, 'https://example.supabase.co');
  rows[50] = { ...rows[50], sku: rows[0].sku }; // duplicate SKU -> insert fails
  const before = JSON.stringify(await q(db)('SELECT * FROM products ORDER BY id')) + JSON.stringify(await q(db)('SELECT * FROM order_items ORDER BY id'));
  await assert.rejects(applyDatabaseChanges(db, { rows, expectedSampleIds: info.samples.map(s => s.id), expectedGenuineIds: info.genuine.map(g => g.id) }));
  const after = JSON.stringify(await q(db)('SELECT * FROM products ORDER BY id')) + JSON.stringify(await q(db)('SELECT * FROM order_items ORDER BY id'));
  assert.equal(after, before);
  assert.equal((await q(db)('SELECT count(*)::int n FROM cart_items'))[0].n, 2);
  await db.close();
});

test('refuses when the SAMPLE_ products differ from the reviewed list', { skip: SKIP }, async () => {
  const db = await seededDb();
  const info = await inspectDatabase(q(db), plan);
  const rows = productRows(plan.toImport, info.categoryIdByKey, 'https://example.supabase.co');
  await assert.rejects(applyDatabaseChanges(db, { rows, expectedSampleIds: ['SAMPLE_RO_FLT_CTO'], expectedGenuineIds: info.genuine.map(g => g.id) }), /SAMPLE_ products changed/);
  assert.equal((await q(db)("SELECT count(*)::int n FROM products WHERE id LIKE 'SAMPLE\\_%'"))[0].n, 2);
  await db.close();
});

test('rollback from the pre-import backup returns products, carts and order lines exactly', { skip: SKIP }, async () => {
  const os = require('node:os');
  const { rollbackFromBackup } = require('../scripts/pdf_catalog_import.cjs');
  const db = await seededDb();
  // Dates/times as database text, exactly like scripts/backup_database.cjs saves them.
  const raw = { parsers: Object.fromEntries([1082, 1114, 1184, 1083, 1266].map(oid => [oid, v => v])) };
  const read = async sql => (await db.query(sql, [], raw)).rows;
  const snap = async () => ({
    products: await read('SELECT * FROM products ORDER BY id'),
    cart: await read('SELECT * FROM cart_items ORDER BY id'),
    lines: await read('SELECT * FROM order_items ORDER BY id'),
  });
  const before = await snap();
  // A backup folder as scripts/backup_database.cjs writes it.
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ro-pdf-rollback-'));
  try {
    fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ tables: { products: before.products.length, cart_items: before.cart.length, order_items: before.lines.length } }));
    fs.writeFileSync(path.join(dir, 'products.json'), JSON.stringify(before.products));
    fs.writeFileSync(path.join(dir, 'cart_items.json'), JSON.stringify(before.cart));
    fs.writeFileSync(path.join(dir, 'order_items.json'), JSON.stringify(before.lines));
    const info = await inspectDatabase(q(db), plan);
    const rows = productRows(plan.toImport, info.categoryIdByKey, 'https://example.supabase.co');
    await applyDatabaseChanges(db, { rows, expectedSampleIds: info.samples.map(s => s.id), expectedGenuineIds: info.genuine.map(g => g.id) });
    const result = await rollbackFromBackup(db, dir);
    assert.deepEqual(result, { pdfProductsRemoved: 78, sampleProductsRestored: 2, cartLinesRestored: 1, orderLineSkusReset: 1 });
    const after = await snap();
    assert.equal(JSON.stringify(after.products), JSON.stringify(before.products));
    assert.equal(JSON.stringify(after.cart), JSON.stringify(before.cart));
    assert.equal(JSON.stringify(after.lines), JSON.stringify(before.lines));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
    await db.close();
  }
});
