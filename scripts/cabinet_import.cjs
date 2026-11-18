// Add the "Cabinet" category and the 41 products from
// "CABINET MODELS FOR COIMBATORE qty.pdf".
//
//   node scripts/cabinet_import.cjs                 dry run (default): reads only, writes nothing
//   APPLY_CABINET_IMPORT=YES node scripts/cabinet_import.cjs --apply
//
// Data: assets/product_pdfs/extracted/cabinet_import.json (read from the PDF).
//   dealer price = PDF "Cabinet price"; MRP 0 = not available (hidden in the
//   apps); Min qty exactly as printed; no picture (placeholder); stock 0.
//
// --apply: full backup (scripts/backup_database.cjs) and a check of it, then
// ONE transaction that adds the category and the 41 products and verifies
// that every existing category and product is unchanged, else rolls back.
// Nothing is deleted or modified.
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const DATA = path.join(ROOT, 'assets', 'product_pdfs', 'extracted', 'cabinet_import.json');
const affected = r => (r.rowCount ?? r.affectedRows ?? 0);
const productId = sku => `PDF_${sku.replace(/[^A-Za-z0-9]+/g, '_').toUpperCase()}`;

function loadData(file = DATA) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/** Checks the data on its own. */
function checkData(data) {
  const errors = [];
  if (data.products.length !== 41) errors.push(`expected 41 products, found ${data.products.length}`);
  const skus = data.products.map(p => p.sku);
  if (new Set(skus).size !== skus.length) errors.push('duplicate codes');
  data.products.forEach((p, i) => {
    if (p.sku !== `CAB-${String(i + 1).padStart(2, '0')}`) errors.push(`code ${p.sku} out of order`);
    if (!(Number.isInteger(p.dealer_price) && p.dealer_price > 0)) errors.push(`${p.sku}: dealer price must be a positive number`);
    if (p.mrp !== 0) errors.push(`${p.sku}: MRP must be 0 (not available)`);
    if (!/^\d+\s*nos$/i.test(p.moq_text)) errors.push(`${p.sku}: Min qty "${p.moq_text}" is not as printed`);
  });
  return errors;
}

/** The exact rows that will be inserted. */
function productRows(data) {
  return data.products.map(p => ({
    id: productId(p.sku),
    category_id: data.category.id,
    category_key: data.category.key_name,
    sku: p.sku,
    name: p.name,
    brand: '',
    price: p.dealer_price,
    mrp: 0,
    moq: p.moq_text,
    img: '',
    status: 'active',
    stock_quantity: 0,
  }));
}

/** Read-only look at the database. */
async function inspect(q, data) {
  const errors = [];
  const cats = await q('SELECT id, key_name, title FROM categories ORDER BY display_order');
  if (cats.some(c => c.id === data.category.id || String(c.key_name).toLowerCase() === data.category.key_name)) {
    errors.push(`category ${data.category.id} / "${data.category.key_name}" already exists`);
  }
  if (cats.some(c => String(c.title).toLowerCase() === data.category.title.toLowerCase())) {
    errors.push(`a category titled "${data.category.title}" already exists`);
  }
  const products = await q('SELECT id, sku, name FROM products');
  const skus = new Set(products.map(p => String(p.sku).toLowerCase()));
  const ids = new Set(products.map(p => p.id));
  for (const r of productRows(data)) {
    if (skus.has(r.sku.toLowerCase())) errors.push(`code ${r.sku} already used`);
    if (ids.has(r.id)) errors.push(`product id ${r.id} already exists`);
  }
  return { errors, categories: cats, productCount: products.length };
}

/** ONE transaction: add the category and products, verify, commit. */
async function applyCabinetImport(client, data) {
  const q = async (sql, params = []) => (await client.query(sql, params)).rows;
  const rows = productRows(data);
  await client.query('BEGIN');
  try {
    const { errors } = await inspect(q, data);
    if (errors.length) throw new Error(errors.join('; '));
    const catsBefore = await q('SELECT * FROM categories ORDER BY id');
    const productsBefore = await q('SELECT * FROM products ORDER BY id');
    const order = (await q('SELECT COALESCE(MAX(display_order), 0)::int + 1 AS n FROM categories'))[0].n;
    const c = data.category;
    await client.query(
      `INSERT INTO categories (id, key_name, title, description, badge_text, icon_color, image_url, display_order)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [c.id, c.key_name, c.title, '', c.badge_text, c.icon_color, c.image_url, order]);
    // Cabinet Price (migration 009): the PDF "Cabinet price", in its own column
    // when the database has it. The Dealer Price stays the same value.
    const withCabinetPrice = (await q(`SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'cabinet_price'`)).length > 0;
    for (const r of rows) {
      await client.query(
        `INSERT INTO products (id, category_id, category_key, sku, name, brand, price, mrp, moq, img, status, stock_quantity${withCabinetPrice ? ', cabinet_price' : ''})
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12${withCabinetPrice ? ', $13' : ''})`,
        [r.id, r.category_id, r.category_key, r.sku, r.name, r.brand, r.price, r.mrp, r.moq, r.img, r.status, r.stock_quantity, ...(withCabinetPrice ? [r.price] : [])]);
    }
    // Verify before committing.
    const catsAfter = await q('SELECT * FROM categories WHERE id <> $1 ORDER BY id', [c.id]);
    if (JSON.stringify(catsAfter) !== JSON.stringify(catsBefore)) throw new Error('an existing category changed');
    const productsAfter = await q('SELECT * FROM products WHERE category_id IS DISTINCT FROM $1 ORDER BY id', [c.id]);
    if (JSON.stringify(productsAfter) !== JSON.stringify(productsBefore)) throw new Error('an existing product changed');
    const added = await q('SELECT id, sku, name, category_id, price, mrp, moq, img, stock_quantity FROM products WHERE category_id = $1 ORDER BY sku', [c.id]);
    if (added.length !== rows.length) throw new Error(`${added.length} cabinet products saved, expected ${rows.length}`);
    for (const r of rows) {
      const got = added.find(a => a.id === r.id);
      if (!got || got.name !== r.name || Number(got.price) !== r.price || Number(got.mrp) !== 0 || got.moq !== r.moq || got.img !== '' || Number(got.stock_quantity) !== 0) {
        throw new Error(`product ${r.sku} was not saved exactly as planned`);
      }
    }
    await client.query('COMMIT');
    return { category: c.id, displayOrder: order, inserted: rows.length, cabinetPrice: withCabinetPrice };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

async function main() {
  process.chdir(ROOT);
  require('dotenv').config({ path: path.join(ROOT, '.env') });
  const { pool } = require('../db');
  const apply = process.argv.includes('--apply');
  if (apply && process.env.APPLY_CABINET_IMPORT !== 'YES') {
    console.error('Refusing to apply: set APPLY_CABINET_IMPORT=YES and pass --apply.');
    process.exitCode = 2; return;
  }
  const data = loadData();
  const errors = checkData(data);
  const client = await pool.raw.connect();
  let db;
  try {
    await client.query('BEGIN READ ONLY');
    db = await inspect(async (sql, params) => (await client.query(sql, params)).rows, data);
    await client.query('ROLLBACK');
  } finally { client.release(); }
  errors.push(...db.errors);
  const rows = productRows(data);
  console.log(`Cabinet import: ${apply ? 'APPLY' : 'DRY RUN'}`);
  console.log(`  new category "${data.category.title}" (${data.category.id}) after ${db.categories.length} existing: ${db.categories.map(c => c.title).join(', ')}`);
  console.log(`  ${rows.length} products ${rows[0].sku}..${rows.at(-1).sku}; dealer price = Cabinet price; MRP 0 (not available); no picture; stock 0`);
  console.log(`  products after: ${db.productCount + rows.length} (now ${db.productCount})`);
  for (const e of errors) console.log('  ERROR', e);
  if (errors.length) { process.exitCode = 1; return; }
  if (!apply) { console.log('Dry run only: nothing was written.'); return; }
  const { backupDatabase } = require('./backup_database.cjs');
  const backup = await backupDatabase();
  const manifest = JSON.parse(fs.readFileSync(path.join(backup.dir, 'manifest.json'), 'utf8'));
  if (manifest.dateTimes !== 'database-text' || !manifest.tables.products || !manifest.tables.categories) throw new Error('backup check failed');
  console.log(`Backup verified: ${path.relative(ROOT, backup.dir)}`);
  const tx = await pool.raw.connect();
  try { console.log('Committed:', JSON.stringify(await applyCabinetImport(tx, data))); } finally { tx.release(); }
}

module.exports = { loadData, checkData, productRows, inspect, applyCabinetImport, productId };

if (require.main === module) {
  main().catch(error => { console.error('FAILED:', error.message); process.exitCode = 1; })
    .finally(() => { try { require('../db').pool.end(); } catch (_) { /* ignore */ } });
}
