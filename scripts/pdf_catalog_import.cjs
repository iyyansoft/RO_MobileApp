// Replace the SAMPLE_ catalogue with the products from the two supplier PDFs.
//
//   node scripts/pdf_catalog_import.cjs                 dry run (default): reads only, writes nothing
//   APPLY_PDF_CATALOG_IMPORT=YES node scripts/pdf_catalog_import.cjs --apply
//   ROLLBACK_PDF_CATALOG_IMPORT=YES node scripts/pdf_catalog_import.cjs --rollback backups/<folder>
//     (undo: PDF_ products out, SAMPLE_ products, their cart lines and the
//      order-line SKUs back exactly as in that backup)
//
// Data: assets/product_pdfs/extracted/catalog_import.json + images/<SKU>.jpg
// (extracted from the PDFs; prices and quantities exactly as printed).
//
// --apply runs, stopping at the first failure:
//   1. the same checks as the dry run (must be error-free)
//   2. full database backup (scripts/backup_database.cjs), then verifies it
//   3. uploads the pictures to Supabase Storage (ro-product-images/pdf-catalog/)
//      and checks each public URL returns the same bytes
//   4. ONE database transaction (all-or-nothing):
//        copy each SAMPLE_ product's SKU onto its order lines whose SKU is empty,
//        delete the SAMPLE_ products (their cart lines go with them: ON DELETE CASCADE),
//        insert the PDF products (stock 0),
//        verify orders / order lines / supply records / genuine products are unchanged,
//      and rolls back if any check fails.
// Pictures are uploaded before the transaction because Storage cannot take part
// in it; if the transaction rolls back they stay unused in the bucket.
//
// Never prints the Supabase key.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const ROOT = path.join(__dirname, '..');
const DATA_DIR = path.join(ROOT, 'assets', 'product_pdfs', 'extracted');
const BUCKET = 'ro-product-images';
const PREFIX = 'pdf-catalog';
const SAMPLE_LIKE = 'SAMPLE\\_%';
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const CATEGORY_KEYS = ['systems', 'membranes', 'filters', 'pumps', 'pipes', 'spares'];

const productId = sku => `PDF_${sku.replace(/[^A-Za-z0-9]+/g, '_').toUpperCase()}`;
// Min qty exactly as printed in the PDF's "Mini qty" cell (e.g. "10 nos");
// blank when the PDF has no Min Qty for the product.
const moqText = p => (p.moq_text == null || p.moq_text === '' ? null : String(p.moq_text));
const affected = r => (r.rowCount ?? r.affectedRows ?? 0);

function loadPlanData(dataDir = DATA_DIR) {
  const data = JSON.parse(fs.readFileSync(path.join(dataDir, 'catalog_import.json'), 'utf8'));
  const products = data.products.map(p => ({ ...p, imagePath: path.join(dataDir, p.image) }));
  return {
    all: products,
    toImport: products.filter(p => p.status === 'import'),
    pending: products.filter(p => p.status !== 'import'),
  };
}

function publicImageUrl(supabaseUrl, sku) {
  return `${String(supabaseUrl).replace(/\/+$/, '')}/storage/v1/object/public/${BUCKET}/${PREFIX}/${sku}.jpg`;
}

/** The exact rows that will be inserted. */
function productRows(toImport, categoryIdByKey, supabaseUrl) {
  return toImport.map(p => ({
    id: productId(p.sku),
    category_id: categoryIdByKey[p.category_key],
    category_key: p.category_key,
    sku: p.sku,
    name: p.name,
    brand: '',
    price: p.dealer_price,
    mrp: p.mrp,
    moq: moqText(p),
    img: publicImageUrl(supabaseUrl, p.sku),
    status: 'active',
    stock_quantity: 0,
  }));
}

/** Checks the data files on their own (no database). */
function checkData(plan) {
  const errors = []; const warnings = [];
  const skus = plan.all.map(p => p.sku.toLowerCase());
  const names = plan.toImport.map(p => p.name.toLowerCase());
  for (const s of new Set(skus)) if (skus.filter(x => x === s).length > 1) errors.push(`duplicate SKU in data: ${s}`);
  for (const n of new Set(names)) if (names.filter(x => x === n).length > 1) errors.push(`duplicate product name in import: ${n}`);
  for (const p of plan.toImport) {
    if (!(Number.isFinite(p.dealer_price) && p.dealer_price > 0)) errors.push(`${p.sku}: dealer price is not a single positive number (${p.dealer_price})`);
    if (!(Number.isFinite(p.mrp) && p.mrp > 0)) errors.push(`${p.sku}: MRP is not a single positive number (${p.mrp})`);
    if (p.mrp < p.dealer_price) warnings.push(`${p.sku}: MRP ${p.mrp} is below dealer price ${p.dealer_price}`);
    if (p.moq != null && !(Number.isInteger(p.moq) && p.moq >= 1)) errors.push(`${p.sku}: Min qty must be blank or a whole number`);
    if ((p.moq == null) !== (p.moq_text == null)) errors.push(`${p.sku}: Min qty number and printed text disagree`);
    if (p.moq_text != null && Number((String(p.moq_text).match(/^\d+/) || [])[0]) !== p.moq) errors.push(`${p.sku}: Min qty text "${p.moq_text}" does not start with ${p.moq}`);
    if (!CATEGORY_KEYS.includes(p.category_key)) errors.push(`${p.sku}: unknown category ${p.category_key}`);
    if (!fs.existsSync(p.imagePath)) { errors.push(`${p.sku}: image missing ${p.image}`); continue; }
    const bytes = fs.readFileSync(p.imagePath);
    if (bytes.length > MAX_IMAGE_BYTES) errors.push(`${p.sku}: image larger than 5 MB`);
    if (!(bytes[0] === 0xff && bytes[1] === 0xd8)) errors.push(`${p.sku}: image is not a JPEG`);
    if (crypto.createHash('sha256').update(bytes).digest('hex') !== p.image_sha256) errors.push(`${p.sku}: image changed since extraction`);
  }
  return { errors, warnings };
}

/** Read-only look at the database. `q(sql, params)` returns rows. */
async function inspectDatabase(q, plan) {
  const errors = []; const warnings = [];
  const categories = await q('SELECT id, key_name, title FROM categories');
  const categoryIdByKey = {};
  for (const key of CATEGORY_KEYS) {
    const c = categories.find(x => x.key_name === key);
    if (!c) errors.push(`category "${key}" does not exist`); else categoryIdByKey[key] = c.id;
  }
  const samples = await q(`SELECT id, sku, name FROM products WHERE id LIKE '${SAMPLE_LIKE}' ORDER BY id`);
  const genuine = await q(`SELECT * FROM products WHERE id NOT LIKE '${SAMPLE_LIKE}' ORDER BY id`);
  const lines = await q(`SELECT oi.id, oi.order_id, oi.product_id, oi.sku FROM order_items oi WHERE oi.product_id LIKE '${SAMPLE_LIKE}'`);
  const carts = await q(`SELECT product_id FROM cart_items WHERE product_id LIKE '${SAMPLE_LIKE}'`);
  const fks = await q(`SELECT tc.table_name, rc.delete_rule FROM information_schema.table_constraints tc
      JOIN information_schema.referential_constraints rc ON rc.constraint_name = tc.constraint_name AND rc.constraint_schema = tc.table_schema
      JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name AND ccu.constraint_schema = tc.table_schema
      WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public' AND ccu.table_name = 'products'`);
  for (const fk of fks) {
    if (!(fk.table_name === 'cart_items' && fk.delete_rule === 'CASCADE')) errors.push(`unexpected link to products from ${fk.table_name} (${fk.delete_rule}); review before deleting`);
  }
  const newSkus = new Set(plan.toImport.map(p => p.sku.toLowerCase()));
  const newIds = new Set(plan.toImport.map(p => productId(p.sku)));
  for (const g of genuine) {
    if (newSkus.has(String(g.sku).toLowerCase())) errors.push(`SKU ${g.sku} already used by "${g.name}"`);
    if (newIds.has(g.id)) errors.push(`product id ${g.id} already exists`);
    if (plan.toImport.some(p => p.name.toLowerCase() === String(g.name).toLowerCase())) warnings.push(`name "${g.name}" already used by a kept product`);
  }
  const emptySkuLines = lines.filter(l => !String(l.sku || '').trim());
  const deliveries = lines.length
    ? await q(`SELECT count(*)::int AS n FROM shop_delivery_items d JOIN order_items oi ON oi.id = d.order_item_id WHERE oi.product_id LIKE '${SAMPLE_LIKE}'`)
    : [{ n: 0 }];
  return {
    errors, warnings, categoryIdByKey,
    samples, genuine,
    orderLines: lines.length, orders: new Set(lines.map(l => l.order_id)).size,
    emptySkuLines: emptySkuLines.length, deliveryRecordsOnSampleLines: deliveries[0].n,
    cartLines: carts.length,
  };
}

const COUNT_TABLES = ['orders', 'order_items', 'shop_delivery_items', 'payment_sessions', 'users', 'categories'];

async function tableCounts(q) {
  const counts = {};
  for (const t of COUNT_TABLES) {
    const exists = await q(`SELECT to_regclass('public.${t}') AS t`);
    if (exists[0].t) counts[t] = (await q(`SELECT count(*)::int AS n FROM public.${t}`))[0].n;
  }
  return counts;
}

/**
 * The database part of --apply, inside ONE transaction on `client`
 * (pg client or PGlite: query(text, params) with $1.. placeholders).
 * Throws (after ROLLBACK) if anything does not match the plan.
 */
async function applyDatabaseChanges(client, { rows, expectedSampleIds, expectedGenuineIds }) {
  const q = async (sql, params = []) => (await client.query(sql, params)).rows;
  await client.query('BEGIN');
  try {
    const samples = (await q(`SELECT id FROM products WHERE id LIKE '${SAMPLE_LIKE}' ORDER BY id FOR UPDATE`)).map(r => r.id);
    if (JSON.stringify(samples) !== JSON.stringify([...expectedSampleIds].sort())) {
      throw new Error(`SAMPLE_ products changed since the check (${samples.length} now, ${expectedSampleIds.length} planned)`);
    }
    const genuineBefore = await q(`SELECT * FROM products WHERE id NOT LIKE '${SAMPLE_LIKE}' ORDER BY id`);
    if (JSON.stringify(genuineBefore.map(r => r.id)) !== JSON.stringify([...expectedGenuineIds].sort())) {
      throw new Error('the list of genuine products changed since the check');
    }
    const before = await tableCounts(q);
    const orderLinesBefore = await q('SELECT id, order_id, product_id, product_name, brand, unit_price, quantity, moq, img_src, sku FROM order_items ORDER BY id');

    // 1. SKU onto historical order lines (only where it is empty).
    const toFill = (await q(`SELECT count(*)::int AS n FROM order_items oi JOIN products p ON p.id = oi.product_id
        WHERE p.id LIKE '${SAMPLE_LIKE}' AND COALESCE(TRIM(oi.sku), '') = ''`))[0].n;
    const filled = affected(await client.query(`UPDATE order_items oi SET sku = p.sku FROM products p
        WHERE p.id = oi.product_id AND p.id LIKE '${SAMPLE_LIKE}' AND COALESCE(TRIM(oi.sku), '') = ''`));
    if (filled !== toFill) throw new Error(`SKU copy touched ${filled} order lines, expected ${toFill}`);

    // 2. Delete the SAMPLE_ products (cart lines cascade).
    const cartLines = (await q(`SELECT count(*)::int AS n FROM cart_items WHERE product_id LIKE '${SAMPLE_LIKE}'`))[0].n;
    const deleted = affected(await client.query(`DELETE FROM products WHERE id LIKE '${SAMPLE_LIKE}'`));
    if (deleted !== expectedSampleIds.length) throw new Error(`deleted ${deleted} products, expected ${expectedSampleIds.length}`);

    // 3. Insert the PDF products.
    for (const r of rows) {
      await client.query(
        `INSERT INTO products (id, category_id, category_key, sku, name, brand, price, mrp, moq, img, status, stock_quantity)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
        [r.id, r.category_id, r.category_key, r.sku, r.name, r.brand, r.price, r.mrp, r.moq, r.img, r.status, r.stock_quantity]);
    }

    // 4. Verify before committing.
    const after = await tableCounts(q);
    for (const t of Object.keys(before)) if (before[t] !== after[t]) throw new Error(`${t} row count changed (${before[t]} -> ${after[t]})`);
    const orderLinesAfter = await q('SELECT id, order_id, product_id, product_name, brand, unit_price, quantity, moq, img_src, sku FROM order_items ORDER BY id');
    for (let i = 0; i < orderLinesBefore.length; i++) {
      const b = orderLinesBefore[i]; const a = orderLinesAfter[i];
      const { sku: bs, ...bRest } = b; const { sku: as, ...aRest } = a;
      if (JSON.stringify(bRest) !== JSON.stringify(aRest)) throw new Error(`order line ${b.id} changed beyond its SKU`);
      if (String(bs || '').trim() && bs !== as) throw new Error(`order line ${b.id}: an existing SKU was changed`);
    }
    const genuineAfter = await q(`SELECT * FROM products WHERE id NOT LIKE '${SAMPLE_LIKE}' AND id NOT LIKE 'PDF\\_%' ORDER BY id`);
    if (JSON.stringify(genuineAfter) !== JSON.stringify(genuineBefore)) throw new Error('a genuine product changed');
    if ((await q(`SELECT count(*)::int AS n FROM products WHERE id LIKE '${SAMPLE_LIKE}'`))[0].n) throw new Error('SAMPLE_ products remain');
    const inserted = await q(`SELECT id, sku, name, category_id, category_key, price, mrp, moq, img, stock_quantity, status FROM products WHERE id LIKE 'PDF\\_%' ORDER BY id`);
    if (inserted.length !== rows.length) throw new Error(`${inserted.length} PDF products in the table, expected ${rows.length}`);
    const byId = Object.fromEntries(inserted.map(r => [r.id, r]));
    for (const r of rows) {
      const got = byId[r.id];
      const same = got && got.sku === r.sku && got.name === r.name && got.category_id === r.category_id && got.category_key === r.category_key
        && Number(got.price) === r.price && Number(got.mrp) === r.mrp && (got.moq ?? null) === r.moq && got.img === r.img
        && Number(got.stock_quantity) === 0 && got.status === 'active';
      if (!same) throw new Error(`product ${r.sku} was not saved exactly as planned`);
    }
    const leftCarts = (await q(`SELECT count(*)::int AS n FROM cart_items WHERE product_id LIKE '${SAMPLE_LIKE}'`))[0].n;
    if (leftCarts) throw new Error('cart lines for SAMPLE_ products remain');

    await client.query('COMMIT');
    return { skuFilled: filled, deleted, cartLinesRemoved: cartLines, inserted: rows.length, counts: after };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

/** Rows of one table from a backup folder (bytea restored from { $base64 }). */
function backupRows(dir, table) {
  const file = path.join(dir, `${table}.json`);
  if (!fs.existsSync(file)) return [];
  return JSON.parse(fs.readFileSync(file, 'utf8'), (key, value) =>
    (value && typeof value === 'object' && typeof value.$base64 === 'string' ? Buffer.from(value.$base64, 'base64') : value));
}

async function insertRow(client, table, row) {
  const cols = Object.keys(row);
  const values = cols.map(c => (row[c] !== null && typeof row[c] === 'object' && !Buffer.isBuffer(row[c]) ? JSON.stringify(row[c]) : row[c]));
  await client.query(
    `INSERT INTO public.${table} (${cols.map(c => `"${c}"`).join(', ')}) OVERRIDING SYSTEM VALUE VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')}) ON CONFLICT DO NOTHING`,
    values);
}

/**
 * Undo the import from the backup taken just before it, in ONE transaction:
 * removes the PDF_ products, puts the SAMPLE_ products and their cart lines
 * back exactly as backed up, and returns the copied order-line SKUs to their
 * backed-up (empty) value. Nothing else is touched.
 */
async function rollbackFromBackup(client, backupDir) {
  const products = backupRows(backupDir, 'products').filter(p => String(p.id).startsWith('SAMPLE_'));
  const carts = backupRows(backupDir, 'cart_items').filter(c => String(c.product_id).startsWith('SAMPLE_'));
  const lines = backupRows(backupDir, 'order_items').filter(l => String(l.product_id).startsWith('SAMPLE_'));
  await client.query('BEGIN');
  try {
    const removed = affected(await client.query("DELETE FROM products WHERE id LIKE 'PDF\\_%'"));
    for (const p of products) await insertRow(client, 'products', p);
    for (const c of carts) await insertRow(client, 'cart_items', c);
    let skuReset = 0;
    for (const l of lines) {
      skuReset += affected(await client.query('UPDATE order_items SET sku = $1 WHERE id = $2 AND sku IS DISTINCT FROM $1', [l.sku, l.id]));
    }
    const back = (await client.query(`SELECT count(*)::int AS n FROM products WHERE id LIKE '${SAMPLE_LIKE}'`)).rows[0].n;
    if (back !== products.length) throw new Error(`restored ${back} SAMPLE_ products, backup has ${products.length}`);
    await client.query('COMMIT');
    return { pdfProductsRemoved: removed, sampleProductsRestored: products.length, cartLinesRestored: carts.length, orderLineSkusReset: skuReset };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

/** Re-reads a backup folder and checks it is complete and readable. */
function verifyBackup(dir, { expectedSampleIds, expectedGenuineIds }) {
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
  const problems = [];
  // Rollback re-inserts rows from this backup, so dates/times must be the
  // database's own text (scripts/backup_database.cjs does this).
  if (manifest.dateTimes !== 'database-text') problems.push('dates/times not saved as database text (old backup format)');
  for (const [table, count] of Object.entries(manifest.tables)) {
    const rows = JSON.parse(fs.readFileSync(path.join(dir, `${table}.json`), 'utf8'));
    if (rows.length !== count) problems.push(`${table}: ${rows.length} rows in file, manifest says ${count}`);
  }
  for (const t of ['products', 'orders', 'order_items', 'cart_items', 'categories', 'users', 'shop_delivery_items']) {
    if (!(t in manifest.tables)) problems.push(`${t} missing from the backup`);
  }
  const products = JSON.parse(fs.readFileSync(path.join(dir, 'products.json'), 'utf8')).map(p => p.id);
  for (const id of [...expectedSampleIds, ...expectedGenuineIds]) if (!products.includes(id)) problems.push(`product ${id} missing from the backup`);
  if (problems.length) throw new Error(`backup check failed: ${problems.join('; ')}`);
  return manifest;
}

// ---------------------------------------------------------------- Storage --
function storageClient(supabaseUrl, key) {
  const base = String(supabaseUrl).replace(/\/+$/, '');
  const headers = { apikey: key, Authorization: `Bearer ${key}` };
  const call = async (method, p, extra = {}, body) => {
    const res = await fetch(base + p, { method, headers: { ...headers, ...extra }, body, signal: AbortSignal.timeout(60000) });
    return { status: res.status, buf: Buffer.from(await res.arrayBuffer()) };
  };
  return {
    bucket: () => call('GET', `/storage/v1/bucket/${BUCKET}`),
    list: async () => {
      const r = await call('POST', `/storage/v1/object/list/${BUCKET}`, { 'Content-Type': 'application/json' }, JSON.stringify({ prefix: `${PREFIX}/`, limit: 1000 }));
      if (r.status !== 200) throw new Error(`could not list ${BUCKET}/${PREFIX} (HTTP ${r.status})`);
      return JSON.parse(r.buf.toString('utf8')).map(o => o.name);
    },
    upload: (sku, bytes) => call('POST', `/storage/v1/object/${BUCKET}/${PREFIX}/${sku}.jpg`, { 'Content-Type': 'image/jpeg', 'x-upsert': 'false', 'Cache-Control': '3600' }, bytes),
    fetchPublic: async sku => {
      const res = await fetch(publicImageUrl(base, sku), { signal: AbortSignal.timeout(60000) });
      return { status: res.status, buf: Buffer.from(await res.arrayBuffer()) };
    },
  };
}

async function uploadImages(storage, toImport) {
  const existing = new Set(await storage.list());
  const result = { uploaded: 0, alreadyThere: 0 };
  for (const p of toImport) {
    const bytes = fs.readFileSync(p.imagePath);
    if (existing.has(`${p.sku}.jpg`)) {
      result.alreadyThere++;
    } else {
      const up = await storage.upload(p.sku, bytes);
      if (up.status !== 200) throw new Error(`upload of ${p.sku}.jpg failed (HTTP ${up.status})`);
      result.uploaded++;
    }
    const pub = await storage.fetchPublic(p.sku);
    if (pub.status !== 200 || !pub.buf.equals(bytes)) throw new Error(`public picture for ${p.sku} does not match the extracted file (HTTP ${pub.status})`);
  }
  return result;
}

// -------------------------------------------------------------------- CLI --
async function main() {
  process.chdir(ROOT);
  require('dotenv').config({ path: path.join(ROOT, '.env') });
  const { pool } = require('../db');
  const apply = process.argv.includes('--apply');
  const rollbackAt = process.argv.indexOf('--rollback');
  if (rollbackAt !== -1) {
    const dir = path.resolve(ROOT, process.argv[rollbackAt + 1] || '');
    if (process.env.ROLLBACK_PDF_CATALOG_IMPORT !== 'YES') {
      console.error('Refusing to roll back: set ROLLBACK_PDF_CATALOG_IMPORT=YES and pass --rollback <backup folder>.');
      process.exitCode = 2; return;
    }
    if (!fs.existsSync(path.join(dir, 'manifest.json'))) throw new Error(`no backup at ${dir}`);
    const tx = await pool.raw.connect();
    try { console.log('Rolled back:', JSON.stringify(await rollbackFromBackup(tx, dir))); } finally { tx.release(); }
    return;
  }
  if (apply && process.env.APPLY_PDF_CATALOG_IMPORT !== 'YES') {
    console.error('Refusing to apply: set APPLY_PDF_CATALOG_IMPORT=YES and pass --apply.');
    process.exitCode = 2; return;
  }
  const supabaseUrl = process.env.SUPABASE_URL || '';
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
  const plan = loadPlanData();
  const report = { mode: apply ? 'APPLY' : 'DRY RUN', errors: [], warnings: [] };

  const data = checkData(plan);
  report.errors.push(...data.errors); report.warnings.push(...data.warnings);
  if (!supabaseUrl || !key) report.errors.push('SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not set');

  // Read-only database inspection.
  const client = await pool.raw.connect();
  let db;
  try {
    await client.query('BEGIN READ ONLY');
    db = await inspectDatabase(async (sql, params) => (await client.query(sql, params)).rows, plan);
    report.tableCounts = await tableCounts(async (sql, params) => (await client.query(sql, params)).rows);
    await client.query('ROLLBACK');
  } finally { client.release(); }
  report.errors.push(...db.errors); report.warnings.push(...db.warnings);

  // Storage (read-only in a dry run).
  const storage = storageClient(supabaseUrl, key);
  if (key) {
    const b = await storage.bucket();
    if (b.status !== 200) report.errors.push(`Storage bucket ${BUCKET} not reachable with the key (HTTP ${b.status})`);
    else {
      const info = JSON.parse(b.buf.toString('utf8'));
      if (info.public !== true) report.errors.push(`bucket ${BUCKET} is not public`);
      const existing = await storage.list();
      report.storageObjectsAlreadyInFolder = existing.length;
      for (const p of plan.toImport) if (existing.includes(`${p.sku}.jpg`)) report.warnings.push(`${PREFIX}/${p.sku}.jpg already in Storage (will be checked, not replaced)`);
    }
  }

  const rows = productRows(plan.toImport, db.categoryIdByKey, supabaseUrl);
  Object.assign(report, {
    sampleProductsToDelete: db.samples.map(s => `${s.id} | ${s.sku} | ${s.name}`),
    genuineProductsKept: db.genuine.map(g => `${g.id} | ${g.sku} | ${g.name}`),
    orderLinesOnSampleProducts: db.orderLines, ordersAffected: db.orders,
    orderLinesGettingSku: db.emptySkuLines, supplyRecordsOnThoseLines: db.deliveryRecordsOnSampleLines,
    cartLinesRemovedWithProducts: db.cartLines,
    productsToImport: rows.length,
    importByCategory: Object.fromEntries(CATEGORY_KEYS.map(k => [k, rows.filter(r => r.category_key === k).length])),
    moqBlank: rows.filter(r => r.moq == null).length,
    pendingReview: plan.pending.map(p => `${p.sku} | ${p.name} | dealer ${p.dealer_price} | MRP ${p.mrp}`),
    productCountAfter: db.genuine.length + rows.length,
  });
  fs.mkdirSync(path.join(ROOT, 'backups'), { recursive: true });
  const reportFile = path.join(ROOT, 'backups', `pdf_catalog_import_${apply ? 'apply' : 'dryrun'}_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(reportFile, JSON.stringify({ ...report, rows }, null, 1));

  console.log(`PDF catalogue import: ${report.mode}`);
  console.log(`  delete ${db.samples.length} SAMPLE_ products; keep ${db.genuine.length} genuine products`);
  console.log(`  ${db.emptySkuLines} of ${db.orderLines} order lines (${db.orders} orders) get their SKU copied; ${db.cartLines} cart lines removed with the products`);
  console.log(`  import ${rows.length} products (stock 0, ${report.moqBlank} with Min qty not set); ${plan.pending.length} pending review`);
  console.log(`  products after: ${report.productCountAfter}`);
  for (const w of report.warnings) console.log('  WARNING', w);
  for (const e of report.errors) console.log('  ERROR', e);
  console.log(`  report: ${path.relative(ROOT, reportFile)}`);
  if (report.errors.length) { process.exitCode = 1; return; }
  if (!apply) { console.log('Dry run only: nothing was written.'); return; }

  // ---- APPLY ----
  const expected = { expectedSampleIds: db.samples.map(s => s.id), expectedGenuineIds: db.genuine.map(g => g.id) };
  const { backupDatabase } = require('./backup_database.cjs');
  const backup = await backupDatabase();
  verifyBackup(backup.dir, expected);
  console.log(`Backup verified: ${path.relative(ROOT, backup.dir)}`);
  const up = await uploadImages(storage, plan.toImport);
  console.log(`Pictures: ${up.uploaded} uploaded, ${up.alreadyThere} already there; all ${plan.toImport.length} public URLs verified`);
  const tx = await pool.raw.connect();
  try {
    const result = await applyDatabaseChanges(tx, { rows, ...expected });
    console.log('Committed:', JSON.stringify(result));
  } finally { tx.release(); }
}

module.exports = { loadPlanData, checkData, inspectDatabase, productRows, applyDatabaseChanges, rollbackFromBackup, backupRows, insertRow, verifyBackup, productId, publicImageUrl };

if (require.main === module) {
  main().catch(error => { console.error('FAILED:', error.message); process.exitCode = 1; })
    .finally(() => { try { require('../db').pool.end(); } catch (_) { /* ignore */ } });
}
