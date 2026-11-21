// Bulk Orders pricing from the two supplier PDFs (reads only; writes one JSON).
//
//   node scripts/extract_bulk_pricing.cjs   -> assets/product_pdfs/extracted/bulk_pricing.json
//
// Needs `pdftotext` (poppler) and the PDFs in assets/product_pdfs/ (not in git).
//
// What the PDFs print, and how it is used (confirmed with the owner):
//   Domestic PDF  "UNIT  BOX (pack)  MRP"   e.g. 80  77 (42 PCS)  590
//     BOX = price per piece when buying whole packs.
//     Bulk: min = one pack, step = one pack (42, 84, 126 ...).
//   Mukhil PDF    "UNIT  BOX  Mini qty  MRP"  e.g. 1000  980  10 nos  2800
//     No pack printed with BOX. Bulk: min = Mini qty, step = 1 (10, 11, 12 ...).
//   UNIT stays the normal Dealer Price; nothing here changes it.
//
// Held for review (not offered in Bulk Orders), never guessed:
//   price ranges (165-265), packs that are not a piece count (1 KG, 1 BOX,
//   100 MTRS, 1 PKTS), BOX higher than UNIT, missing BOX/pack/Mini qty.
// Only the Bulk Orders categories are offered: membranes, filters, pipes, spares.
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const PDF_DIR = path.join(ROOT, 'assets', 'product_pdfs');
const OUT = path.join(PDF_DIR, 'extracted', 'bulk_pricing.json');
const BULK_CATEGORIES = ['membranes', 'filters', 'pipes', 'spares'];
const DOMESTIC_PDF = 'Domest Items -SPARE FOR COIMBATORE NEW.pdf';
const productId = sku => `PDF_${sku.replace(/[^A-Za-z0-9]+/g, '_').toUpperCase()}`;

/** Domestic PDF rows: code, name, unit, box, pack, mrp (as printed). */
function parseDomestic(text) {
  const lines = text.split(/\r?\n/).map(l => l.trim())
    .filter(l => l && !/MUKIL WATER|9894255715|^Code|^price$|^Note\./.test(l));
  const rows = []; let cur = null;
  for (const line of lines) {
    const m = line.match(/^(\d{1,2})\s+(.*)$/);
    if (m && Number(m[1]) === (cur ? cur.code + 1 : 1)) { cur = { code: Number(m[1]), text: m[2] }; rows.push(cur); }
    else if (cur) cur.text += ` ${line}`;
  }
  return rows.map(r => {
    const t = r.text.replace(/\(\s*/g, '(').replace(/\s*\)/g, ')');
    const m = t.match(/^(.*?)\s+([\d-]+)\s+([\d-]+)\s*(?:\((\d+)\s*([A-Za-z]+)\))?\s*([\d-]+)?\s*$/);
    if (!m) return { code: r.code, unparsed: t };
    return { code: r.code, name: m[1].trim(), unit: m[2], box: m[3], packQty: m[4] ? Number(m[4]) : null, packUnit: m[5] ? m[5].toUpperCase() : null, mrp: m[6] || null };
  });
}

function build({ domesticText, catalog }) {
  const out = [];
  for (const row of parseDomestic(domesticText)) {
    const c = catalog.find(p => p.pdf === 'domestic' && Number(p.pdf_code) === row.code);
    const issues = [];
    if (!c) issues.push('not in the catalogue import');
    if (row.unparsed) issues.push('row could not be read');
    const range = /-/.test(`${row.unit}${row.box}${row.mrp}`);
    if (range) issues.push('price range');
    if (row.packQty == null) issues.push('no pack size');
    else if (!['NOS', 'PCS'].includes(row.packUnit)) issues.push(`pack "${row.packQty} ${row.packUnit}" is not a piece count`);
    if (!range && Number(row.box) > Number(row.unit)) issues.push(`BOX ${row.box} > UNIT ${row.unit}`);
    if (c && !range && (Number(row.unit) !== c.dealer_price || Number(row.box) !== c.box_price_not_saved)) issues.push('differs from the catalogue import');
    out.push({
      sku: c?.sku ?? null, product_id: c ? productId(c.sku) : null, pdf: 'domestic', pdf_code: String(row.code),
      name: row.name ?? c?.name, category_key: c?.category_key ?? null,
      unit_price: range ? null : Number(row.unit), box_price: range ? null : Number(row.box),
      pack_label: row.packQty != null ? `${row.packQty} ${row.packUnit}` : null,
      min_qty: row.packQty, step: row.packQty, basis: 'per piece, whole packs',
      issues,
    });
  }
  for (const c of catalog.filter(p => p.pdf === 'mukhil')) {
    const issues = [];
    const min = /^(\d+)\s*nos$/i.exec(String(c.pdf_qty_text || '').trim());
    if (c.status !== 'import') issues.push('held in the catalogue import');
    if (c.box_price_not_saved == null) issues.push('no BOX price');
    if (!min) issues.push('no Mini qty');
    if (c.box_price_not_saved != null && c.box_price_not_saved > c.dealer_price) issues.push(`BOX ${c.box_price_not_saved} > UNIT ${c.dealer_price}`);
    out.push({
      sku: c.sku, product_id: productId(c.sku), pdf: 'mukhil', pdf_code: String(c.pdf_code), name: c.name,
      category_key: c.category_key, unit_price: c.dealer_price, box_price: c.box_price_not_saved,
      pack_label: min ? `${min[1]} NOS` : null, min_qty: min ? Number(min[1]) : null, step: 1,
      basis: 'per piece, from Mini qty', issues,
    });
  }
  for (const r of out) {
    if (!BULK_CATEGORIES.includes(r.category_key)) r.issues.unshift('category not in Bulk Orders');
    r.status = r.issues.length ? 'review' : 'bulk';
  }
  return out;
}

if (require.main === module) {
  const domesticText = execFileSync('pdftotext', ['-raw', path.join(PDF_DIR, DOMESTIC_PDF), '-'], { encoding: 'utf8' });
  const catalog = JSON.parse(fs.readFileSync(path.join(PDF_DIR, 'extracted', 'catalog_import.json'), 'utf8')).products;
  const rows = build({ domesticText, catalog });
  fs.writeFileSync(OUT, `${JSON.stringify({ source_pdfs: [DOMESTIC_PDF, 'MUKIL SPARES FOR COIMBATORE NEW.pdf'], rules: [
    'Domestic: BOX price per piece; min = step = printed pack',
    'Mukhil: BOX price per piece; min = Mini qty; step 1',
    'UNIT (Dealer Price), MRP and Cabinet Price are never changed',
    'status review = not offered in Bulk Orders (see issues)',
  ], products: rows }, null, 1)}\n`);
  const bulk = rows.filter(r => r.status === 'bulk');
  const per = {}; for (const r of bulk) per[r.category_key] = (per[r.category_key] || 0) + 1;
  console.log(`Bulk Orders: ${bulk.length} products`, per);
  console.log(`Held for review: ${rows.filter(r => r.status === 'review' && !r.issues[0].startsWith('category')).length} (in Bulk categories); outside Bulk categories: ${rows.filter(r => r.issues[0]?.startsWith('category')).length}`);
  for (const r of rows.filter(r => r.status === 'review' && !r.issues[0].startsWith('category'))) console.log(`  ${r.sku} ${r.name}: ${r.issues.join('; ')}`);
  console.log(`Wrote ${path.relative(ROOT, OUT)}`);
}

module.exports = { build, parseDomestic, BULK_CATEGORIES, productId };
