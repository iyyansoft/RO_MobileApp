// scripts/cabinet_import.cjs on an in-memory Postgres with the app schema.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PGlite } = require('@electric-sql/pglite');
const { citext } = require('@electric-sql/pglite/contrib/citext');
const cab = require('../scripts/cabinet_import.cjs');

const root = path.join(__dirname, '..');
const read = f => fs.readFileSync(path.join(root, f), 'utf8');
const data = cab.loadData();

async function db() {
  const d = new PGlite({ extensions: { citext } });
  await d.exec(read('supabase_migration.sql'));
  await d.exec(read('shop_app_migration.sql'));
  const cats = [['CAT_SYS', 'systems', 'RO Systems'], ['CAT_MEM', 'membranes', 'Membranes'], ['CAT_FLT', 'filters', 'Filters & Cartridges'],
    ['CAT_PMP', 'pumps', 'Booster Pumps'], ['CAT_PIP', 'pipes', 'Pipes & Tubing'], ['CAT_SPR', 'spares', 'Spare Parts & Valves']];
  for (const [i, [id, key, title]] of cats.entries()) {
    await d.query('INSERT INTO categories (id, key_name, title, image_url, display_order) VALUES ($1, $2, $3, $4, $5)', [id, key, title, `${key}.jpg`, i + 1]);
  }
  await d.query(`INSERT INTO products (id, category_id, category_key, sku, name, brand, price, mrp, moq, img)
    VALUES ('prod_genuine_1', 'CAT_SYS', 'systems', 'ABC', 'ABC', 'X', 17000, 20000, 'MOQ: 1 Unit', 'purifier.jpg')`);
  return d;
}
const q = d => async (sql, params) => (await d.query(sql, params)).rows;

test('the data matches the PDF rules', () => {
  assert.deepEqual(cab.checkData(data), []);
  const first = data.products[0];
  assert.deepEqual([first.sku, first.name, first.dealer_price, first.mrp, first.moq_text], ['CAB-01', 'Dolphin king/ABS', 1100, 0, '10 nos']);
  assert.equal(data.products.find(p => p.sku === 'CAB-39').moq_text, '1 nos');
  assert.equal(data.products.find(p => p.sku === 'CAB-36').name, '20”jambo housing-eco jambo204');
});

test('adds the Cabinet category and 41 products; nothing else changes', async () => {
  const d = await db();
  const before = JSON.stringify(await q(d)('SELECT * FROM categories ORDER BY id')) + JSON.stringify(await q(d)('SELECT * FROM products ORDER BY id'));
  const result = await cab.applyCabinetImport(d, data);
  assert.deepEqual(result, { category: 'CAT_CAB', displayOrder: 7, inserted: 41, cabinetPrice: false });
  const cat = (await q(d)("SELECT * FROM categories WHERE id = 'CAT_CAB'"))[0];
  assert.deepEqual([cat.key_name, cat.title, cat.image_url, cat.display_order], ['cabinets', 'Cabinet', '', 7]);
  const rows = await q(d)("SELECT * FROM products WHERE category_id = 'CAT_CAB' ORDER BY sku");
  assert.equal(rows.length, 41);
  assert.ok(rows.every(r => Number(r.mrp) === 0 && r.img === '' && r.stock_quantity === 0 && r.category_key === 'cabinets'));
  assert.deepEqual([rows[0].sku, rows[0].name, Number(rows[0].price), rows[0].moq], ['CAB-01', 'Dolphin king/ABS', 1100, '10 nos']);
  assert.equal(Number(rows.find(r => r.sku === 'CAB-19').price), 900, 'Cabinet price, not the 6500 Unit-price');
  const after = JSON.stringify(await q(d)("SELECT * FROM categories WHERE id <> 'CAT_CAB' ORDER BY id")) + JSON.stringify(await q(d)("SELECT * FROM products WHERE category_id IS DISTINCT FROM 'CAT_CAB' ORDER BY id"));
  assert.equal(after, before, 'existing categories and products unchanged');
  await d.close();
});

test('with migration 009: Cabinet Price = PDF Cabinet price, Dealer Price unchanged', async () => {
  const d = await db();
  await d.exec(read('supabase/staging/009_product_cabinet_price.sql'));
  const result = await cab.applyCabinetImport(d, data);
  assert.equal(result.cabinetPrice, true);
  const rows = await q(d)("SELECT sku, price, cabinet_price FROM products WHERE category_id = 'CAT_CAB' ORDER BY sku");
  assert.ok(rows.every(r => Number(r.cabinet_price) === Number(r.price)));
  assert.equal(Number(rows.find(r => r.sku === 'CAB-19').cabinet_price), 900);
  assert.equal((await q(d)("SELECT cabinet_price FROM products WHERE id = 'prod_genuine_1'"))[0].cabinet_price, null, 'other products untouched');
  await d.close();
});

test('refuses to run twice and leaves everything as it was', async () => {
  const d = await db();
  await cab.applyCabinetImport(d, data);
  const snapshot = JSON.stringify(await q(d)('SELECT * FROM products ORDER BY id'));
  await assert.rejects(cab.applyCabinetImport(d, data), /already exists/);
  assert.equal(JSON.stringify(await q(d)('SELECT * FROM products ORDER BY id')), snapshot);
  await d.close();
});
