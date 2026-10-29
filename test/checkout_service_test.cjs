const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { validGstin, quoteCheckout, createDealerToken, verifyDealerToken, verifyCapturedPayment } = require('../checkout_service');
const products = [{ id: 'ro', name: 'RO System', price: '900', stock_quantity: 8 }];
test('GST format and checksum are validated', () => {
  assert.equal(validGstin('27AAPFU0939F1ZV'), true);
  assert.equal(validGstin('27AAPFU0939F1ZA'), false);
  assert.throws(() => quoteCheckout({ items: [{ id: 'ro', quantity: 1 }], withGst: true, gstin: '' }, products), /GST/);
});
test('checkout ignores client prices and calculates GST only when requested', () => {
  const input = { items: [{ id: 'ro', quantity: 1, numericPrice: 1 }], grandTotal: 1, withGst: false };
  const without = quoteCheckout(input, products);
  assert.equal(without.subtotal, 900); assert.equal(without.gst, 0); assert.equal(without.grandTotal, 1060);
  const withGst = quoteCheckout({ ...input, withGst: true, gstin: '27AAPFU0939F1ZV' }, products);
  assert.equal(withGst.gst, 145.8); assert.equal(withGst.grandTotal, 1205.8);
  assert.throws(() => quoteCheckout({ ...input, items: [{ id: 'ro', quantity: 9 }] }, products), /stock/);
});
test('dealer tokens reject tampering', () => {
  const token = createDealerToken({ id: 'dealer', email: 'dealer@example.test' }, 'secret');
  assert.equal(verifyDealerToken(token, 'secret').id, 'dealer');
  assert.equal(verifyDealerToken(token + '0', 'secret'), null);
});
test('Razorpay requires a signature and real captured matching payment', async () => {
  process.env.RAZORPAY_KEY_SECRET = 'test-only-secret';
  const session = { id: 'order_test', amount: '120580' };
  const signature = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET).update('order_test|pay_test').digest('hex');
  let requested = false;
  await assert.rejects(verifyCapturedPayment(session, 'pay_test', 'forged', async () => { requested = true; }), /signature/);
  assert.equal(requested, false);
  const payment = { order_id: session.id, amount: 120580, currency: 'INR', status: 'captured' };
  assert.equal((await verifyCapturedPayment(session, 'pay_test', signature, async () => payment)).status, 'captured');
  await assert.rejects(verifyCapturedPayment(session, 'pay_test', signature, async () => ({ ...payment, status: 'failed' })), /not been captured/);
  await assert.rejects(verifyCapturedPayment(session, 'pay_test', signature, async () => ({ ...payment, amount: 1 })), /does not match/);
});
