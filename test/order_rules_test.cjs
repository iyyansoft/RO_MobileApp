// The one ordering rule shared by cart and checkout (order_rules.js).
// Quantity starts at 1; for the supplier-PDF catalogue the PDF quantity is the
// MAXIMUM per order line; stock is the real inventory.
const test = require('node:test');
const assert = require('node:assert/strict');
const rules = require('../order_rules');
const { quoteCheckout } = require('../checkout_service');

const pdfPump = (stock, moq = '10 nos') => ({ id: 'PDF_MUK_01', name: 'BLUEBERRY 100 GPD Pump', price: '1050', moq, stock_quantity: stock, status: 'active' });
const genuine = (stock) => ({ id: 'prod_genuine_1', name: 'ABC', price: '17000', moq: 'MOQ: 1 Unit', stock_quantity: stock, status: 'active' });

function withEnv(values, fn) {
  const saved = {};
  for (const k of Object.keys(values)) { saved[k] = process.env[k]; if (values[k] === undefined) delete process.env[k]; else process.env[k] = values[k]; }
  try { return fn(); } finally { for (const k of Object.keys(saved)) { if (saved[k] === undefined) delete process.env[k]; else process.env[k] = saved[k]; } }
}
const PRODUCTION = { RO_PREVIEW_IGNORE_STOCK: undefined };
const PREVIEW = { RO_PREVIEW_IGNORE_STOCK: '1', SUPABASE_DB_URL: '', DATABASE_URL: '', DB_HOST: '', PGHOST: '', SUPABASE_DB_HOST: '' };

test('minimum is 1; PDF quantity is the maximum (read per product)', () => withEnv(PRODUCTION, () => {
  assert.equal(rules.minOrderQuantity(pdfPump(50)), 1);
  assert.equal(rules.maxOrderQuantity(pdfPump(50, '10 nos')), 10);
  assert.equal(rules.maxOrderQuantity(pdfPump(50, '25 nos')), 25);
  assert.equal(rules.maxOrderQuantity(pdfPump(50, '6 nos')), 6);
  assert.equal(rules.maxOrderQuantity(pdfPump(50, null)), null, 'no PDF quantity: no limit is invented');
  assert.equal(rules.maxOrderQuantity(genuine(50)), null, 'only the PDF catalogue is limited');
}));

test('PDF quantity 10: 1 to 10 allowed, 11 refused with the popup message', () => withEnv(PRODUCTION, () => {
  for (const q of [1, 5, 10]) assert.equal(rules.orderQuantityProblem(pdfPump(50), q), null, `qty ${q}`);
  const over = rules.orderQuantityProblem(pdfPump(50), 11);
  assert.equal(over.code, 'MAX_ORDER_QTY');
  assert.equal(over.max, 10);
  assert.equal(over.error, 'You can order a maximum of 10 units for this product.');
  assert.equal(rules.orderQuantityProblem(pdfPump(50), 0).code, 'INVALID_QUANTITY');
}));

test('production: real stock still limits orders; the PDF quantity is never stock', () => withEnv(PRODUCTION, () => {
  assert.equal(rules.stockEnforced(), true);
  assert.equal(rules.orderQuantityProblem(pdfPump(0), 1).code, 'OUT_OF_STOCK');
  assert.equal(rules.orderQuantityProblem(pdfPump(4), 5).code, 'INSUFFICIENT_STOCK');
  assert.equal(rules.availability(pdfPump(0)), 'out_of_stock');
}));

test('local preview: stock checks off; the maximum still applies', () => withEnv(PREVIEW, () => {
  assert.equal(rules.stockEnforced(), false);
  assert.equal(rules.orderQuantityProblem(pdfPump(0), 10), null, 'stock 0 does not block the preview');
  assert.equal(rules.orderQuantityProblem(pdfPump(0), 11).code, 'MAX_ORDER_QTY');
}));

test('the preview switch is ignored whenever a real database is configured', () => {
  for (const key of ['SUPABASE_DB_URL', 'DATABASE_URL', 'DB_HOST', 'PGHOST', 'SUPABASE_DB_HOST']) {
    withEnv({ ...PREVIEW, [key]: 'postgres://real-database' }, () => {
      assert.equal(rules.stockEnforced(), true, key);
      assert.equal(rules.orderQuantityProblem(pdfPump(0), 1).code, 'OUT_OF_STOCK', key);
    });
  }
});

test('checkout applies the same rule', () => withEnv(PRODUCTION, () => {
  const order = items => ({ items, paymentMethod: 'Cash on Delivery', deliveryAddress: 'Chennai' });
  assert.equal(quoteCheckout(order([{ id: 'PDF_MUK_01', quantity: 10 }]), [pdfPump(50)]).items[0].quantity, 10);
  assert.throws(() => quoteCheckout(order([{ id: 'PDF_MUK_01', quantity: 11 }]), [pdfPump(50)]), /You can order a maximum of 10 units for this product/);
  assert.throws(() => quoteCheckout(order([{ id: 'PDF_MUK_01', quantity: 5 }]), [pdfPump(4)]), /Not enough stock/);
  assert.equal(quoteCheckout(order([{ id: 'prod_genuine_1', quantity: 3 }]), [genuine(5)]).items[0].quantity, 3, 'no maximum for other products');
}));
