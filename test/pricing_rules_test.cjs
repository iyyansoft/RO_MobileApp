const { test } = require('node:test');
const assert = require('node:assert/strict');
const fixture = require('./fixtures/pricing_scenarios.json');
const { pricingRules, priceOrder, DEFAULTS } = require('../pricing_rules');
const { quoteCheckout } = require('../checkout_service');

const pick = t => ({
  subtotal: t.subtotal,
  discount: t.discount,
  gst: t.gst,
  deliveryFee: t.deliveryFee,
  grandTotal: t.grandTotal,
});

test('defaults match the shared fixture (and the Flutter fallback)', () => {
  assert.deepEqual({ ...DEFAULTS }, fixture.defaultRules);
  assert.deepEqual({ ...pricingRules({}) }, fixture.defaultRules);
});

for (const s of fixture.scenarios) {
  test(`priceOrder: ${s.name}`, () => {
    const rules = s.rules || fixture.defaultRules;
    assert.deepEqual(pick(priceOrder(s.lines, false, rules)), s.without, 'Without GST');
    assert.deepEqual(pick(priceOrder(s.lines, true, rules)), s.with, 'With GST');
    // Grand Total = Subtotal - Dealer Discount + GST + Delivery.
    for (const t of [s.without, s.with]) {
      assert.equal(
        Math.round((t.subtotal - t.discount + t.gst + t.deliveryFee) * 100),
        Math.round(t.grandTotal * 100),
      );
    }
  });
}

test('rules are read from the environment and validated', () => {
  const rules = pricingRules({
    DEALER_DISCOUNT_PERCENT: '12.5',
    DEALER_TIER_LABEL: 'Silver Dealer',
    GST_PERCENT: '12',
    DELIVERY_CHARGE: '99',
    FREE_DELIVERY_ABOVE: '1000',
  });
  assert.deepEqual({ ...rules }, fixture.scenarios.find(s => s.rules?.dealerTierLabel === 'Silver Dealer').rules);
  assert.throws(() => pricingRules({ GST_PERCENT: '-1' }), /GST_PERCENT/);
  assert.throws(() => pricingRules({ DEALER_DISCOUNT_PERCENT: '150' }), /DEALER_DISCOUNT_PERCENT/);
  assert.throws(() => pricingRules({ DELIVERY_CHARGE: 'abc' }), /DELIVERY_CHARGE/);
});

test('invalid prices and quantities are rejected', () => {
  assert.throws(() => priceOrder([{ unitPrice: 0, quantity: 1 }], false), /price/);
  assert.throws(() => priceOrder([{ unitPrice: -5, quantity: 1 }], false), /price/);
  assert.throws(() => priceOrder([{ unitPrice: 10, quantity: 0 }], false), /quantity/);
  assert.throws(() => priceOrder([{ unitPrice: 10, quantity: 1.5 }], false), /quantity/);
});

test('checkout re-prices from database prices, ignoring client amounts', () => {
  const products = [
    { id: 'housing', name: 'RO Filter Housing 10 Inch', price: '290', stock_quantity: 50 },
    { id: 'ro25', name: 'Commercial RO System 25 LPH', price: '16500', stock_quantity: 5 },
  ];
  const tampered = {
    items: [
      { id: 'housing', quantity: 3, numericPrice: 1 },
      { id: 'ro25', quantity: 2, numericPrice: 1 },
    ],
    subtotal: 1, discount: 999, gst: 0, deliveryFee: 0, grandTotal: 1,
    withGst: true, gstin: '27AAPFU0939F1ZV',
  };
  const quote = quoteCheckout(tampered, products);
  // 290*3 + 16500*2 = 33870; -10% = 30483; +18% GST = 5486.94; free delivery.
  assert.deepEqual(pick(quote), { subtotal: 33870, discount: 3387, gst: 5486.94, deliveryFee: 0, grandTotal: 35969.94 });
  assert.equal(quote.withGst, true);

  const without = quoteCheckout({ ...tampered, withGst: false }, products);
  assert.equal(without.gst, 0);
  assert.equal(without.grandTotal, 30483);

  // Configured rules are applied on the server too.
  const custom = quoteCheckout({ ...tampered, withGst: false }, products, pricingRules({ DEALER_DISCOUNT_PERCENT: '5' }));
  assert.equal(custom.discount, 1693.5);
  assert.equal(custom.grandTotal, 32176.5);
});
