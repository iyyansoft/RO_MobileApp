// Product Description / Specifications / Key Features from the product-information spreadsheet.
//
//   node scripts/product_info_import.cjs --export current.json            read only: current info of every product
//   python scripts/product_info_template.py generate current.json OUT.xlsx
//   python scripts/product_info_template.py read FILLED.xlsx entries.json
//   node scripts/product_info_import.cjs entries.json                     dry run (default): reads only
//   APPLY_PRODUCT_INFO=YES node scripts/product_info_import.cjs entries.json --apply [--replace-existing]
//   ROLLBACK_PRODUCT_INFO=YES node scripts/product_info_import.cjs --rollback backups/product_info_before_<stamp>.json
//
// Writes ONLY products.description, products.specs_json and products.features_json,
// only for the cells filled in the spreadsheet's "New ..." columns (blank = keep what
// is saved; nothing is ever cleared, invented or deleted). Each row is matched by
// Product ID AND SKU. Filling an empty field is allowed; replacing text that is
// already saved is refused unless --replace-existing is passed (the dry run lists
// every such replacement with the old text). --apply runs in ONE transaction, saves
// the previous values of every product it changes (for --rollback), refuses if a
// product's information changed since the dry run, verifies the saved values, and
// verifies no other column of any product changed.
const fs = require('node:fs');
const path = require('node:path');
const { parseSpecifications, specificationLines, parseFeatures } = require('../product_info');

const ROOT = path.join(__dirname, '..');
const FIELDS = ['description', 'specs', 'features'];
const LIMITS = { description: 5000, specCount: 60, specKey: 80, specValue: 500, featureCount: 30, feature: 300 };

const jsonText = v => (v === undefined || v === null ? null : String(v));
const specsOf = text => { try { const v = JSON.parse(text); return v && typeof v === 'object' && !Array.isArray(v) ? v : {}; } catch (_) { return {}; } };
const featuresOf = text => { try { const v = JSON.parse(text); return Array.isArray(v) ? v.map(String) : []; } catch (_) { return []; } };
const isEmpty = (field, current) => (field === 'description' ? !String(current ?? '').trim()
  : field === 'specs' ? Object.keys(specsOf(current)).length === 0 : featuresOf(current).length === 0);

/** One spreadsheet cell -> the value to save, or an error. Never guesses. */
function parseField(field, raw) {
  const text = String(raw ?? '').trim();
  if (!text) return { error: 'is blank (blank cells are skipped, never saved)' };
  if (field === 'description') {
    if (text.length > LIMITS.description) return { error: `is ${text.length} characters (max ${LIMITS.description})` };
    return { value: text, stored: text };
  }
  if (field === 'specs') {
    const parsed = parseSpecifications(text);
    if (parsed.error) return { error: parsed.error };
    const entries = Object.entries(parsed.value);
    if (!entries.length) return { error: 'has no "Name: Value" lines' };
    if (entries.length > LIMITS.specCount) return { error: `has ${entries.length} lines (max ${LIMITS.specCount})` };
    const long = entries.find(([k, v]) => k.length > LIMITS.specKey || v.length > LIMITS.specValue);
    if (long) return { error: `"${long[0].slice(0, 40)}" is too long (name max ${LIMITS.specKey}, value max ${LIMITS.specValue} characters)` };
    return { value: parsed.value, stored: JSON.stringify(parsed.value) };
  }
  const features = parseFeatures(text);
  if (features.length > LIMITS.featureCount) return { error: `has ${features.length} features (max ${LIMITS.featureCount})` };
  const long = features.find(f => f.length > LIMITS.feature);
  if (long) return { error: `feature "${long.slice(0, 40)}..." is longer than ${LIMITS.feature} characters` };
  return { value: features, stored: JSON.stringify(features) };
}

const sameValue = (field, current, value) => (field === 'description' ? String(current ?? '').trim() === value
  : field === 'specs' ? JSON.stringify(specsOf(current)) === JSON.stringify(value) : JSON.stringify(featuresOf(current)) === JSON.stringify(value));

const shown = (field, stored) => (field === 'description' ? String(stored ?? '') : field === 'specs' ? specificationLines(specsOf(stored)) : featuresOf(stored).join('\n'));

async function plan(q, entries, { replaceExisting = false } = {}) {
  const errors = [];
  const seen = new Set();
  const rows = await q(`SELECT id, sku, name, description, specs_json::text AS specs, features_json::text AS features FROM products WHERE id = ANY($1)`,
    [entries.map(e => String(e.product_id ?? ''))]);
  const byId = new Map(rows.map(r => [r.id, r]));
  const changes = [];
  for (const e of entries) {
    const where = `row ${e.row ?? '?'} (${e.sku})`;
    if (seen.has(e.product_id)) { errors.push(`${where}: product ${e.product_id} is listed twice`); continue; }
    seen.add(e.product_id);
    const row = byId.get(e.product_id);
    if (!row) { errors.push(`${where}: product ${e.product_id} not found`); continue; }
    if (String(row.sku).trim() !== String(e.sku ?? '').trim()) { errors.push(`${where}: product ${e.product_id} has SKU ${row.sku}`); continue; }
    const change = { product_id: row.id, sku: row.sku, name: row.name, row: e.row ?? null, current: { description: row.description, specs: row.specs, features: row.features }, set: {}, fields: [] };
    for (const field of FIELDS) {
      if (e[field] === undefined || e[field] === null || String(e[field]).trim() === '') continue;   // blank = keep
      const parsed = parseField(field, e[field]);
      if (parsed.error) { errors.push(`${where}: New ${field === 'specs' ? 'Specifications' : field === 'features' ? 'Key Features' : 'Description'} ${parsed.error}`); continue; }
      const current = row[field];
      if (sameValue(field, current, parsed.value)) { change.fields.push({ field, action: 'unchanged' }); continue; }
      const action = isEmpty(field, current) ? 'fill' : 'replace';
      if (action === 'replace' && !replaceExisting) errors.push(`${where}: would replace the saved ${field} (pass --replace-existing after checking the old text below)`);
      change.set[field] = parsed.stored;
      change.fields.push({ field, action, before: shown(field, current), after: shown(field, parsed.stored) });
    }
    if (change.fields.length) changes.push(change);
  }
  return { errors, changes, toWrite: changes.filter(c => Object.keys(c.set).length) };
}

const COLUMN = { description: 'description', specs: 'specs_json', features: 'features_json' };
const otherColumnsDigest = async q => (await q(`SELECT count(*)::int n, md5(string_agg((to_jsonb(p) - 'description' - 'specs_json' - 'features_json')::text, '|' ORDER BY p.id COLLATE "C")) h FROM products p`))[0];

/** Writes `values[field]` for each change, only where the saved values are still `expect`. */
async function writeAll(tx, changes, valuesOf, expectOf, what) {
  const q = async (s, p) => (await tx.query(s, p)).rows;
  await tx.query('BEGIN');
  try {
    const before = await otherColumnsDigest(q);
    let updated = 0;
    for (const c of changes) {
      const values = valuesOf(c);
      const fields = Object.keys(values);
      if (!fields.length) continue;
      const expect = expectOf(c);
      const params = [c.product_id, c.sku];
      const sets = fields.map(f => { params.push(values[f]); return f === 'description' ? `description = $${params.length}` : `${COLUMN[f]} = $${params.length}::json`; });
      const guards = FIELDS.map(f => { params.push(jsonText(expect[f])); return f === 'description' ? `description IS NOT DISTINCT FROM $${params.length}` : `${COLUMN[f]}::text IS NOT DISTINCT FROM $${params.length}`; });
      const r = await tx.query(`UPDATE products SET ${sets.join(', ')} WHERE id = $1 AND sku = $2 AND ${guards.join(' AND ')}`, params);
      if (r.rowCount !== 1) throw new Error(`${c.sku}: product information changed since ${what}; nothing was saved`);
      // Read back what was saved.
      const saved = (await q(`SELECT description, specs_json::text AS specs, features_json::text AS features FROM products WHERE id = $1`, [c.product_id]))[0];
      for (const f of fields) if (jsonText(saved[f]) !== jsonText(values[f])) throw new Error(`${c.sku}: ${f} did not save as expected; rolled back`);
      updated += 1;
    }
    if (JSON.stringify(before) !== JSON.stringify(await otherColumnsDigest(q))) throw new Error('a column other than description/specifications/features changed; rolled back');
    await tx.query('COMMIT');
    return { updated };
  } catch (error) {
    await tx.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

const applyInfo = (tx, toWrite) => writeAll(tx, toWrite, c => c.set, c => c.current, 'the dry run');

/** Puts back the previous values, only where the product still has what the import saved. */
const rollbackInfo = (tx, saved) => writeAll(tx, saved.changes,
  c => Object.fromEntries(Object.keys(c.set).map(f => [f, c.current[f]])),
  c => ({ ...c.current, ...c.set }), 'the import (edited afterwards? restore it by hand)')
  .then(r => ({ restored: r.updated }));

async function exportCurrent(q) {
  const rows = await q(`SELECT p.id, p.sku, p.name, COALESCE(c.title, p.category_key, '') AS category, c.display_order,
      p.description, p.specs_json::text AS specs, p.features_json::text AS features
    FROM products p LEFT JOIN categories c ON c.id = p.category_id
    ORDER BY c.display_order NULLS LAST, p.sku COLLATE "C"`);
  return rows.map(r => ({ product_id: r.id, sku: r.sku, name: r.name, category: r.category,
    description: r.description ?? '', specs: shown('specs', r.specs), features: shown('features', r.features) }));
}

module.exports = { parseField, plan, applyInfo, rollbackInfo, exportCurrent };

async function readOnly(pool, fn) {
  const c = await pool.raw.connect();
  try {
    await c.query('BEGIN READ ONLY');
    try { return await fn(async (s, p) => (await c.query(s, p)).rows); } finally { await c.query('ROLLBACK'); }
  } finally { c.release(); }
}

async function main() {
  process.chdir(ROOT);
  require('dotenv').config({ path: path.join(ROOT, '.env') });
  const { pool } = require('../db');
  const args = process.argv.slice(2);
  const at = flag => args.indexOf(flag);
  if (at('--export') !== -1) {
    const out = args[at('--export') + 1];
    if (!out) { console.error('Usage: node scripts/product_info_import.cjs --export current.json'); process.exitCode = 2; return; }
    const products = await readOnly(pool, exportCurrent);
    fs.writeFileSync(path.resolve(ROOT, out), JSON.stringify({ exported_at: new Date().toISOString(), products }, null, 1));
    console.log(`Exported ${products.length} products (read only) to ${out}`);
    return;
  }
  if (at('--rollback') !== -1) {
    if (process.env.ROLLBACK_PRODUCT_INFO !== 'YES') { console.error('Refusing: set ROLLBACK_PRODUCT_INFO=YES and pass --rollback <file>.'); process.exitCode = 2; return; }
    const saved = JSON.parse(fs.readFileSync(path.resolve(ROOT, args[at('--rollback') + 1]), 'utf8'));
    const tx = await pool.raw.connect();
    try { console.log('Rolled back:', JSON.stringify(await rollbackInfo(tx, saved))); } finally { tx.release(); }
    return;
  }
  const apply = args.includes('--apply');
  const replaceExisting = args.includes('--replace-existing');
  if (apply && process.env.APPLY_PRODUCT_INFO !== 'YES') { console.error('Refusing: set APPLY_PRODUCT_INFO=YES and pass --apply.'); process.exitCode = 2; return; }
  const file = args.find(a => !a.startsWith('--'));
  if (!file) { console.error('Usage: node scripts/product_info_import.cjs entries.json [--apply] [--replace-existing]'); process.exitCode = 2; return; }
  const { entries } = JSON.parse(fs.readFileSync(path.resolve(ROOT, file), 'utf8'));
  const result = await readOnly(pool, q => plan(q, entries, { replaceExisting }));
  console.log(`Product information: ${apply ? 'APPLY' : 'DRY RUN'}, ${entries.length} rows with something filled in`);
  for (const c of result.changes) {
    for (const f of c.fields) {
      console.log(`  ${c.sku.padEnd(12)} ${f.field.padEnd(11)} ${f.action.toUpperCase()}  ${c.name}`);
      if (f.action === 'replace') console.log(`      OLD: ${f.before.replace(/\n/g, ' | ')}`);
      if (f.action !== 'unchanged') console.log(`      NEW: ${f.after.replace(/\n/g, ' | ')}`);
    }
  }
  for (const e of result.errors) console.log('  ERROR', e);
  const counts = result.changes.flatMap(c => c.fields).reduce((m, f) => ({ ...m, [f.action]: (m[f.action] || 0) + 1 }), {});
  console.log(`  Summary: ${result.toWrite.length} products to update; fields ${JSON.stringify(counts)}; ${result.errors.length} errors`);
  if (result.errors.length) { console.log('Nothing was written.'); process.exitCode = 1; return; }
  if (!apply) { console.log('Dry run only: nothing was written.'); return; }
  if (!result.toWrite.length) { console.log('Nothing to change.'); return; }
  const savedFile = path.join(ROOT, 'backups', `product_info_before_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.mkdirSync(path.dirname(savedFile), { recursive: true });
  fs.writeFileSync(savedFile, JSON.stringify({ source: file, changes: result.toWrite }, null, 1));
  const tx = await pool.raw.connect();
  try { console.log('Committed:', JSON.stringify(await applyInfo(tx, result.toWrite)), `| previous values saved to ${path.relative(ROOT, savedFile)}`); } finally { tx.release(); }
}

if (require.main === module) {
  main().catch(error => { console.error('FAILED:', error.message); process.exitCode = 1; })
    .finally(() => { try { require('../db').pool.end(); } catch (_) { /* ignore */ } });
}
