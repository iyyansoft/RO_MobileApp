const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { offerProblems, loadOffers } = require('../scripts/bulk_pricing_import.cjs');

const ok = { product_id: 'PDF_DOM_01', sku: 'DOM-01', box_price: 77, min_qty: 42, step: 42, pack_label: '42 PCS' };

test('bulk offer rules match the 011 CHECK constraint', () => {
  assert.deepEqual(offerProblems(ok), []);
  assert.deepEqual(offerProblems({ ...ok, step: 1, min_qty: 40 }), [], 'Mukhil: Mini qty then +1');
  assert.match(offerProblems({ ...ok, box_price: 0 }).join(), /price/);
  assert.match(offerProblems({ ...ok, min_qty: 50 }).join(), /whole number of steps/);
  assert.match(offerProblems({ ...ok, step: 0 }).join(), /step/);
  assert.match(offerProblems({ ...ok, pack_label: '' }).join(), /pack label/);
  assert.match(offerProblems({ ...ok, product_id: 'prod_1' }).join(), /PDF_/);
});

const DATA = path.join(__dirname, '..', 'assets', 'product_pdfs', 'extracted', 'bulk_pricing.json');
test('every offer in the extracted PDF data is valid (64 offered, rest held)', { skip: !fs.existsSync(DATA) && 'extracted PDF data is not in the repository' }, () => {
  const { offers, held } = loadOffers(DATA);
  assert.equal(offers.length, 64);
  assert.equal(held.length, 16);
  for (const o of offers) assert.deepEqual(offerProblems(o), [], o.sku);
});
