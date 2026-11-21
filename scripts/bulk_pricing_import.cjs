// Fill the Bulk Orders offers (migration 011 columns) from the supplier PDFs.
//
//   node scripts/bulk_pricing_import.cjs                       dry run (default): reads only, writes nothing
//   APPLY_BULK_PRICING=YES node scripts/bulk_pricing_import.cjs --apply
//   ROLLBACK_BULK_PRICING=YES node scripts/bulk_pricing_import.cjs --rollback
//     (clears the four bulk columns again on exactly the products this file offers)
//
// Data: assets/product_pdfs/extracted/bulk_pricing.json (scripts/extract_bulk_pricing.cjs);
// only rows with status 'bulk' are offered, the rest stay held for review.
//
// Touches ONLY products.bulk_price / bulk_min_qty / bulk_step / bulk_pack_label.
// Dealer Price (price), MRP, Cabinet Price, stock, carts, orders and rewards are
// never written. Requires migration 011 and the PDF catalogue import (the
// PDF_ products must exist). --apply refuses unless the dry-run checks pass,
// and runs in ONE transaction that verifies nothing else changed.
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const DATA = path.join(ROOT, 'assets', 'product_pdfs', 'extracted', 'bulk_pricing.json');
const BULK_COLUMNS = ['bulk_price', 'bulk_min_qty', 'bulk_step', 'bulk_pack_label'];

function loadOffers(file = DATA) {
  const all = JSON.parse(fs.readFileSync(file, 'utf8')).products;
  return { offers: all.filter(p => p.status === 'bulk'), held: all.filter(p => p.status !== 'bulk') };
}

/** Same rules as the 011 CHECK constraint, checked before touching the database. */
function offerProblems(o) {
  const problems = [];
  if (!(Number(o.box_price) > 0)) problems.push('bulk price must be > 0');
  if (!Number.isInteger(o.min_qty) || o.min_qty < 1) problems.push('min qty must be a whole number >= 1');
  if (!Number.isInteger(o.step) || o.step < 1) problems.push('step must be a whole number >= 1');
  if (Number.isInteger(o.min_qty) && Number.isInteger(o.step) && o.step >= 1 && o.min_qty % o.step !== 0) problems.push('min qty must be a whole number of steps');
  if (!o.pack_label || String(o.pack_label).length > 32) problems.push('pack label missing or longer than 32');
  if (!/^PDF_/.test(o.product_id || '')) problems.push('not a PDF_ product id');
  return problems;
}

async function inspect(q, offers) {
  const errors = [], warnings = [];
  const cols = (await q(`SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='products' AND column_name = ANY($1)`, [BULK_COLUMNS])).map(r => r.column_name);
  if (cols.length !== BULK_COLUMNS.length) { errors.push('migration 011 is not applied (products bulk columns missing)'); return { errors, warnings, rows: [] }; }
  const ids = offers.map(o => o.product_id);
  const rows = await q(`SELECT id, sku, name, price, mrp, cabinet_price, bulk_price, bulk_min_qty, bulk_step, bulk_pack_label FROM products WHERE id = ANY($1)`, [ids]);
  const byId = new Map(rows.map(r => [r.id, r]));
  for (const o of offers) {
    for (const p of offerProblems(o)) errors.push(`${o.sku}: ${p}`);
    const row = byId.get(o.product_id);
    if (!row) { errors.push(`${o.sku}: product ${o.product_id} not found (run the PDF catalogue import first)`); continue; }
    if (row.sku !== o.sku) errors.push(`${o.sku}: product ${o.product_id} has SKU ${row.sku}`);
    if (BULK_COLUMNS.some(c => row[c] != null)) warnings.push(`${o.sku}: already has a bulk offer (will be left unchanged)`);
    if (Number(o.box_price) > Number(row.price)) warnings.push(`${o.sku}: bulk price ${o.box_price} is above Dealer Price ${row.price}`);
  }
  const already = (await q(`SELECT count(*)::int n FROM products WHERE bulk_price IS NOT NULL`))[0].n;
  return { errors, warnings, rows, productsWithBulkNow: already };
}

/** Untouched-columns fingerprint of every product (everything except the bulk columns). */
const otherColumnsDigest = async q => (await q(`SELECT count(*)::int n, md5(string_agg(
    (to_jsonb(p) - '${BULK_COLUMNS.join("' - '")}')::text, '|' ORDER BY p.id COLLATE "C")) h FROM products p`))[0];
const tableCounts = async q => Object.fromEntries((await q(`SELECT 'cart_items' t, count(*)::int n FROM cart_items UNION ALL SELECT 'orders', count(*) FROM orders
    UNION ALL SELECT 'order_items', count(*) FROM order_items UNION ALL SELECT 'users', count(*) FROM users UNION ALL SELECT 'rewards_history', count(*) FROM rewards_history`)).map(r => [r.t, r.n]));

async function applyOffers(tx, offers) {
  const q = async (sql, params) => (await tx.query(sql, params)).rows;
  await tx.query('BEGIN');
  try {
    const before = { other: await otherColumnsDigest(q), counts: await tableCounts(q) };
    let updated = 0;
    for (const o of offers) {
      // Only products without an offer; never overwrites an existing one.
      const r = await tx.query(`UPDATE products SET bulk_price = $2, bulk_min_qty = $3, bulk_step = $4, bulk_pack_label = $5
        WHERE id = $1 AND sku = $6 AND bulk_price IS NULL AND bulk_min_qty IS NULL AND bulk_step IS NULL AND bulk_pack_label IS NULL`,
        [o.product_id, o.box_price, o.min_qty, o.step, o.pack_label, o.sku]);
      updated += r.rowCount;
    }
    const after = { other: await otherColumnsDigest(q), counts: await tableCounts(q) };
    if (JSON.stringify(before) !== JSON.stringify(after)) throw new Error('a column other than the bulk offer changed; rolled back');
    await tx.query('COMMIT');
    return { updated, untouchedColumnsVerified: true, counts: after.counts };
  } catch (error) {
    await tx.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

async function rollbackOffers(tx, offers) {
  await tx.query('BEGIN');
  try {
    const q = async (sql, params) => (await tx.query(sql, params)).rows;
    const before = await otherColumnsDigest(q);
    const r = await tx.query(`UPDATE products SET bulk_price = NULL, bulk_min_qty = NULL, bulk_step = NULL, bulk_pack_label = NULL WHERE id = ANY($1)`, [offers.map(o => o.product_id)]);
    const blockers = await q(`SELECT count(*)::int n FROM cart_items WHERE purchase_mode = 'bulk' AND product_id = ANY($1)`, [offers.map(o => o.product_id)]);
    if (blockers[0].n) throw new Error(`${blockers[0].n} cart lines are bulk lines on these products; clear them first`);
    if (JSON.stringify(before) !== JSON.stringify(await otherColumnsDigest(q))) throw new Error('a column other than the bulk offer changed; rolled back');
    await tx.query('COMMIT');
    return { cleared: r.rowCount };
  } catch (error) {
    await tx.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

module.exports = { loadOffers, offerProblems, inspect, applyOffers, rollbackOffers, otherColumnsDigest };

async function main() {
  process.chdir(ROOT);
  require('dotenv').config({ path: path.join(ROOT, '.env') });
  const { pool } = require('../db');
  const apply = process.argv.includes('--apply');
  const rollback = process.argv.includes('--rollback');
  const { offers, held } = loadOffers();
  if (rollback) {
    if (process.env.ROLLBACK_BULK_PRICING !== 'YES') { console.error('Refusing to roll back: set ROLLBACK_BULK_PRICING=YES and pass --rollback.'); process.exitCode = 2; return; }
    const tx = await pool.raw.connect();
    try { console.log('Rolled back:', JSON.stringify(await rollbackOffers(tx, offers))); } finally { tx.release(); }
    return;
  }
  if (apply && process.env.APPLY_BULK_PRICING !== 'YES') { console.error('Refusing to apply: set APPLY_BULK_PRICING=YES and pass --apply.'); process.exitCode = 2; return; }
  const client = await pool.raw.connect();
  let report;
  try {
    await client.query('BEGIN READ ONLY');
    report = await inspect(async (sql, params) => (await client.query(sql, params)).rows, offers);
    await client.query('ROLLBACK');
  } finally { client.release(); }
  console.log(`Bulk pricing import: ${apply ? 'APPLY' : 'DRY RUN'}`);
  console.log(`  ${offers.length} offers to set; ${held.length} held for review (not offered); products with an offer now: ${report.productsWithBulkNow ?? '-'}`);
  for (const w of report.warnings) console.log('  WARNING', w);
  for (const e of report.errors) console.log('  ERROR', e);
  if (report.errors.length) { process.exitCode = 1; return; }
  if (!apply) { console.log('Dry run only: nothing was written.'); return; }
  const tx = await pool.raw.connect();
  try { console.log('Committed:', JSON.stringify(await applyOffers(tx, offers))); } finally { tx.release(); }
}

if (require.main === module) {
  main().catch(error => { console.error('FAILED:', error.message); process.exitCode = 1; })
    .finally(() => { try { require('../db').pool.end(); } catch (_) { /* ignore */ } });
}
