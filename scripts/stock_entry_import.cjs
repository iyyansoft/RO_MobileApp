// Apply counted stock from the filled stock-entry spreadsheet.
//
//   python scripts/stock_entry_template.py read FILLED.xlsx entries.json
//   node scripts/stock_entry_import.cjs entries.json                        dry run (default): reads only
//   APPLY_STOCK_ENTRY=YES node scripts/stock_entry_import.cjs entries.json --apply
//   ROLLBACK_STOCK_ENTRY=YES node scripts/stock_entry_import.cjs --rollback backups/stock_entry_before_<stamp>.json
//
// Writes ONLY products.stock_quantity, only for rows that have a quantity in
// the spreadsheet (blank rows are skipped, never assumed). Each row is matched
// by Product ID AND SKU. --apply runs in ONE transaction, saves the previous
// stock of every row it changes (for --rollback), refuses if a product's stock
// changed since the dry run, and verifies no other column of any product changed.
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');

function validateEntries(entries) {
  const errors = [];
  const seen = new Set();
  for (const e of entries) {
    if (!/^PDF_[A-Z0-9_]+$/.test(e.product_id || '')) errors.push(`${e.sku}: invalid product id ${e.product_id}`);
    if (!Number.isInteger(e.new_stock) || e.new_stock < 0 || e.new_stock > 1000000) errors.push(`${e.sku}: stock must be a whole number 0..1000000`);
    if (seen.has(e.product_id)) errors.push(`${e.sku}: listed twice`);
    seen.add(e.product_id);
  }
  return errors;
}

async function plan(q, entries) {
  const errors = validateEntries(entries);
  const rows = await q(`SELECT id, sku, name, stock_quantity FROM products WHERE id = ANY($1)`, [entries.map(e => e.product_id)]);
  const byId = new Map(rows.map(r => [r.id, r]));
  const changes = [];
  for (const e of entries) {
    const row = byId.get(e.product_id);
    if (!row) { errors.push(`${e.sku}: product ${e.product_id} not found (catalogue import not applied?)`); continue; }
    if (row.sku !== e.sku) { errors.push(`${e.sku}: product ${e.product_id} has SKU ${row.sku}`); continue; }
    changes.push({ product_id: row.id, sku: row.sku, name: row.name, current: row.stock_quantity, new_stock: e.new_stock, unchanged: Number(row.stock_quantity) === e.new_stock });
  }
  return { errors, changes };
}

const otherColumnsDigest = async q => (await q(`SELECT count(*)::int n, md5(string_agg((to_jsonb(p) - 'stock_quantity')::text, '|' ORDER BY p.id COLLATE "C")) h FROM products p`))[0];

async function applyStock(tx, changes) {
  const q = async (s, p) => (await tx.query(s, p)).rows;
  await tx.query('BEGIN');
  try {
    const before = await otherColumnsDigest(q);
    let updated = 0;
    for (const c of changes.filter(x => !x.unchanged)) {
      // Only if nobody changed this product's stock since the dry run.
      const r = await tx.query(`UPDATE products SET stock_quantity = $3 WHERE id = $1 AND sku = $2 AND stock_quantity IS NOT DISTINCT FROM $4`,
        [c.product_id, c.sku, c.new_stock, c.current]);
      if (r.rowCount !== 1) throw new Error(`${c.sku}: stock changed since the dry run (was ${c.current}); nothing was saved`);
      updated += 1;
    }
    if (JSON.stringify(before) !== JSON.stringify(await otherColumnsDigest(q))) throw new Error('a column other than stock changed; rolled back');
    await tx.query('COMMIT');
    return { updated, unchanged: changes.filter(x => x.unchanged).length };
  } catch (error) {
    await tx.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

async function rollbackStock(tx, saved) {
  await tx.query('BEGIN');
  try {
    let restored = 0;
    for (const c of saved.changes.filter(x => !x.unchanged)) {
      const r = await tx.query(`UPDATE products SET stock_quantity = $3 WHERE id = $1 AND sku = $2 AND stock_quantity = $4`, [c.product_id, c.sku, c.current, c.new_stock]);
      if (r.rowCount !== 1) throw new Error(`${c.sku}: stock is no longer ${c.new_stock} (orders or edits since); restore it by hand`);
      restored += 1;
    }
    await tx.query('COMMIT');
    return { restored };
  } catch (error) {
    await tx.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

module.exports = { validateEntries, plan, applyStock, rollbackStock };

async function main() {
  process.chdir(ROOT);
  require('dotenv').config({ path: path.join(ROOT, '.env') });
  const { pool } = require('../db');
  const args = process.argv.slice(2);
  const rb = args.indexOf('--rollback');
  if (rb !== -1) {
    if (process.env.ROLLBACK_STOCK_ENTRY !== 'YES') { console.error('Refusing: set ROLLBACK_STOCK_ENTRY=YES and pass --rollback <file>.'); process.exitCode = 2; return; }
    const saved = JSON.parse(fs.readFileSync(path.resolve(ROOT, args[rb + 1]), 'utf8'));
    const tx = await pool.raw.connect();
    try { console.log('Rolled back:', JSON.stringify(await rollbackStock(tx, saved))); } finally { tx.release(); }
    return;
  }
  const apply = args.includes('--apply');
  if (apply && process.env.APPLY_STOCK_ENTRY !== 'YES') { console.error('Refusing: set APPLY_STOCK_ENTRY=YES and pass --apply.'); process.exitCode = 2; return; }
  const file = args.find(a => !a.startsWith('--'));
  if (!file) { console.error('Usage: node scripts/stock_entry_import.cjs entries.json [--apply]'); process.exitCode = 2; return; }
  const { entries } = JSON.parse(fs.readFileSync(path.resolve(ROOT, file), 'utf8'));
  const c = await pool.raw.connect();
  let result;
  try {
    await c.query('BEGIN READ ONLY');
    result = await plan(async (s, p) => (await c.query(s, p)).rows, entries);
    await c.query('ROLLBACK');
  } finally { c.release(); }
  console.log(`Stock entry: ${apply ? 'APPLY' : 'DRY RUN'} — ${entries.length} rows with a quantity`);
  for (const ch of result.changes) console.log(`  ${ch.sku.padEnd(8)} ${String(ch.current).padStart(6)} -> ${String(ch.new_stock).padStart(6)}${ch.unchanged ? '  (unchanged)' : ''}  ${ch.name}`);
  for (const e of result.errors) console.log('  ERROR', e);
  if (result.errors.length) { process.exitCode = 1; return; }
  if (!apply) { console.log('Dry run only: nothing was written.'); return; }
  const savedFile = path.join(ROOT, 'backups', `stock_entry_before_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.mkdirSync(path.dirname(savedFile), { recursive: true });
  fs.writeFileSync(savedFile, JSON.stringify({ source: file, changes: result.changes }, null, 1));
  const tx = await pool.raw.connect();
  try { console.log('Committed:', JSON.stringify(await applyStock(tx, result.changes)), `| previous stock saved to ${path.relative(ROOT, savedFile)}`); } finally { tx.release(); }
}

if (require.main === module) {
  main().catch(error => { console.error('FAILED:', error.message); process.exitCode = 1; })
    .finally(() => { try { require('../db').pool.end(); } catch (_) { /* ignore */ } });
}
