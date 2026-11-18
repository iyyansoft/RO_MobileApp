// Order status and payment status rules shared by the Admin Panel routes
// (server.js) and the Shop App routes (shop_routes.js).
//
// orders.status         -> order / delivery progress (ORDER_STATUSES)
// orders.payment_status -> money (PAYMENT_STATUSES), changed only by an
//                          explicit payment action, never by delivery.

const ORDER_STATUSES = ['Pending', 'Processing & Dispatched', 'Partially Delivered', 'Delivered', 'Cancelled'];

// Stored lowercase; the Admin Panel shows them upper-case.
const PAYMENT_STATUSES = ['due_on_delivery', 'partially_paid', 'paid'];

const isCashOnDelivery = method => ['cod', 'cash on delivery'].includes(String(method || '').trim().toLowerCase());

/** Canonical spelling of an order status, or null if it is not one. */
function normalizeOrderStatus(value) {
  const key = String(value || '').trim().toLowerCase();
  return ORDER_STATUSES.find(status => status.toLowerCase() === key) || null;
}

/** Canonical payment status (accepts DUE_ON_DELIVERY, "Partially Paid", ...). */
function normalizePaymentStatus(value) {
  const key = String(value || '').trim().toLowerCase().replace(/[\s-]+/g, '_');
  return PAYMENT_STATUSES.includes(key) ? key : null;
}

/**
 * Status an order should show, from the stored status and the quantities the
 * Shop App has confirmed as supplied. Cancelled always wins; once anything is
 * supplied the quantities decide; before that the stored status is kept.
 */
function effectiveOrderStatus(storedStatus, deliveredQuantity, orderedQuantity) {
  const stored = normalizeOrderStatus(storedStatus) || 'Processing & Dispatched';
  if (stored === 'Cancelled') return 'Cancelled';
  const delivered = Number(deliveredQuantity || 0);
  const ordered = Number(orderedQuantity || 0);
  if (delivered > 0) return ordered > 0 && delivered >= ordered ? 'Delivered' : 'Partially Delivered';
  return stored === 'Delivered' || stored === 'Partially Delivered' ? 'Processing & Dispatched' : stored;
}

/**
 * Why an admin cannot set `status` for an order with these supplied
 * quantities, or null if the change is allowed.
 */
function orderStatusChangeError(status, deliveredQuantity, orderedQuantity) {
  const delivered = Number(deliveredQuantity || 0);
  const ordered = Number(orderedQuantity || 0);
  const fullySupplied = ordered > 0 && delivered >= ordered;
  switch (status) {
    case 'Delivered':
      return fullySupplied ? null
        : 'An order can be marked Delivered only after every ordered unit is supplied in the Shop App.';
    case 'Partially Delivered':
      return delivered > 0 && !fullySupplied ? null
        : delivered === 0
          ? 'Nothing has been supplied for this order yet, so it cannot be Partially Delivered.'
          : 'Every unit has been supplied; this order is Delivered.';
    case 'Pending':
    case 'Processing & Dispatched':
      return delivered === 0 ? null
        : `${delivered} unit(s) have already been supplied; the status follows the supplied quantities.`;
    case 'Cancelled':
      return fullySupplied ? 'A fully delivered order cannot be cancelled.' : null;
    default:
      return `Choose one of: ${ORDER_STATUSES.join(', ')}.`;
  }
}

/** Why a payment status change is not allowed, or null. */
function paymentStatusChangeError(paymentMethod, currentPaymentStatus, nextPaymentStatus) {
  if (!nextPaymentStatus) return 'Choose DUE_ON_DELIVERY, PARTIALLY_PAID or PAID.';
  if (!isCashOnDelivery(paymentMethod)) {
    return String(currentPaymentStatus || '').toLowerCase() === nextPaymentStatus
      ? null
      : 'Online payments are confirmed by the payment gateway and cannot be changed here.';
  }
  return null;
}

module.exports = {
  ORDER_STATUSES,
  PAYMENT_STATUSES,
  isCashOnDelivery,
  normalizeOrderStatus,
  normalizePaymentStatus,
  effectiveOrderStatus,
  orderStatusChangeError,
  paymentStatusChangeError,
};
