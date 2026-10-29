const crypto = require('crypto');

function signEmployeeToken(employee, secret, now = Date.now()) {
  const payload = Buffer.from(JSON.stringify({
    sub: employee.id,
    employeeId: employee.employee_id,
    shopName: employee.shop_name || '',
    name: employee.full_name || '',
    role: 'shop_employee',
    exp: Math.floor(now / 1000) + 60 * 60 * 12
  })).toString('base64url');
  const signature = crypto.createHmac('sha256', secret).update(payload).digest('base64url');
  return `${payload}.${signature}`;
}

function verifyEmployeeToken(token, secret, now = Date.now()) {
  const [payload, signature, extra] = String(token || '').split('.');
  if (!payload || !signature || extra) return null;
  const expected = crypto.createHmac('sha256', secret).update(payload).digest();
  let actual;
  try { actual = Buffer.from(signature, 'base64url'); } catch (_) { return null; }
  if (actual.length !== expected.length || !crypto.timingSafeEqual(actual, expected)) return null;
  try {
    const identity = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (identity.role !== 'shop_employee' || !identity.sub || identity.exp <= Math.floor(now / 1000)) return null;
    return identity;
  } catch (_) { return null; }
}

function allocateDeliveryValues(items, order = {}) {
  const grossTotal = items.reduce((sum, item) => sum + Number(item.unit_price) * Number(item.quantity), 0);
  // Delivery/refund values use the order-line dealer-price snapshot. Checkout
  // totals and historic order prices remain untouched by shop delivery updates.
  let remainingCents = Math.round(grossTotal * 100);
  const allocated = items.map((item, index) => {
    const gross = Number(item.unit_price) * Number(item.quantity);
    const cents = index === items.length - 1
      ? remainingCents
      : Math.round(gross * 100);
    remainingCents -= cents;
    const quantity = Math.max(0, Number(item.quantity) || 0);
    const requestedQuantity = item.deliveredQuantity ?? item.delivered_quantity;
    const deliveredQuantity = requestedQuantity == null
      ? ((item.delivered === true || item.delivered === 'true') ? quantity : 0)
      : Math.min(quantity, Math.max(0, Math.trunc(Number(requestedQuantity) || 0)));
    const deliveredCents = quantity === 0 ? 0
      : deliveredQuantity === quantity ? cents
        : Math.round(cents * deliveredQuantity / quantity);
    return {
      ...item,
      allocatedValue: cents / 100,
      deliveredQuantity,
      undeliveredQuantity: quantity - deliveredQuantity,
      deliveredValue: deliveredCents / 100,
      refundValue: (cents - deliveredCents) / 100,
      fullyDelivered: quantity > 0 && deliveredQuantity === quantity,
    };
  });
  let deliveredValue = 0;
  let refundAmount = 0;
  let deliveredLines = 0;
  let totalDeliveredQuantity = 0;
  let totalQuantity = 0;
  for (const item of allocated) {
    deliveredValue += item.deliveredValue;
    refundAmount += item.refundValue;
    totalDeliveredQuantity += item.deliveredQuantity;
    totalQuantity += Math.max(0, Number(item.quantity) || 0);
    if (item.fullyDelivered) {
      deliveredLines++;
    }
  }
  return {
    deliveredValue: roundMoney(deliveredValue),
    refundAmount: roundMoney(refundAmount),
    deliveredLines,
    totalDeliveredQuantity,
    totalQuantity,
    allocated,
  };
}

function roundMoney(value) { return Math.round((value + Number.EPSILON) * 100) / 100; }

module.exports = { signEmployeeToken, verifyEmployeeToken, allocateDeliveryValues };
