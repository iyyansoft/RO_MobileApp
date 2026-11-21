'use strict';

/**
 * Single source of truth for order pricing (cart, checkout, orders).
 *
 * Rules are configured per deployment through environment variables. The
 * defaults are the business rules the app has always used, so behaviour is
 * unchanged until a value is configured:
 *
 *   DEALER_DISCOUNT_PERCENT  dealer discount on the product subtotal (10)
 *   DEALER_TIER_LABEL        label shown for that discount ("Gold Dealer")
 *   GST_PERCENT              GST on (subtotal - discount), With GST only (18)
 *   DELIVERY_CHARGE          delivery / freight per order, in rupees (250)
 *   FREE_DELIVERY_ABOVE      subtotal above which delivery is free (5000)
 *
 * All money is computed in integer paise and rounded once per component, so
 * totals never drift from floating-point error. The Flutter app fetches these
 * rules from GET /api/pricing-rules and applies the identical algorithm
 * (lib/features/cart/domain/order_pricing.dart).
 */

const DEFAULTS = Object.freeze({
  dealerDiscountPercent: 10,
  dealerTierLabel: 'Gold Dealer',
  gstPercent: 18,
  deliveryCharge: 250,
  freeDeliveryAbove: 5000,
});

function numberFromEnv(env, name, fallback, { max = Infinity } = {}) {
  const raw = env[name];
  if (raw === undefined || String(raw).trim() === '') return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0 || value > max) {
    throw new Error(`${name} must be a number between 0 and ${max}.`);
  }
  return value;
}

/** Current pricing rules (validated). */
function pricingRules(env = process.env) {
  return Object.freeze({
    dealerDiscountPercent: numberFromEnv(env, 'DEALER_DISCOUNT_PERCENT', DEFAULTS.dealerDiscountPercent, { max: 100 }),
    dealerTierLabel: String(env.DEALER_TIER_LABEL || DEFAULTS.dealerTierLabel).trim().slice(0, 40),
    gstPercent: numberFromEnv(env, 'GST_PERCENT', DEFAULTS.gstPercent, { max: 100 }),
    deliveryCharge: numberFromEnv(env, 'DELIVERY_CHARGE', DEFAULTS.deliveryCharge),
    freeDeliveryAbove: numberFromEnv(env, 'FREE_DELIVERY_ABOVE', DEFAULTS.freeDeliveryAbove),
  });
}

const toPaise = rupees => Math.round(Number(rupees) * 100);
const toRupees = paise => paise / 100;

/**
 * Prices an order.
 * @param {{unitPrice: number, quantity: number}[]} lines
 * @param {boolean} withGst
 * @param {ReturnType<typeof pricingRules>} rules
 */
function priceOrder(lines, withGst, rules = pricingRules()) {
  let subtotal = 0;
  // Lines marked discountable: false (Bulk Orders lines, already at the bulk
  // price) are not part of the dealer discount.
  let discountable = 0;
  for (const line of lines) {
    const unit = toPaise(line.unitPrice);
    if (!Number.isSafeInteger(unit) || unit <= 0) throw new Error('Invalid product price.');
    if (!Number.isSafeInteger(line.quantity) || line.quantity < 1) throw new Error('Invalid quantity.');
    subtotal += unit * line.quantity;
    if (line.discountable !== false) discountable += unit * line.quantity;
  }
  const discount = Math.round(discountable * rules.dealerDiscountPercent / 100);
  const taxable = subtotal - discount;
  const gst = withGst ? Math.round(taxable * rules.gstPercent / 100) : 0;
  const delivery = subtotal === 0 || subtotal > toPaise(rules.freeDeliveryAbove)
    ? 0
    : toPaise(rules.deliveryCharge);
  return {
    subtotal: toRupees(subtotal),
    discount: toRupees(discount),
    gst: toRupees(gst),
    deliveryFee: toRupees(delivery),
    grandTotal: toRupees(taxable + gst + delivery),
    dealerDiscountPercent: rules.dealerDiscountPercent,
    gstPercent: withGst ? rules.gstPercent : 0,
  };
}

module.exports = { DEFAULTS, pricingRules, priceOrder };
