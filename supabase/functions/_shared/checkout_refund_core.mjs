// Pure helpers for the captured-payment recovery path. The Edge Function must
// still authenticate the caller and use the private reconciliation RPCs.
const DEFINITIVE_FINALIZE_MESSAGES = [
  'Not enough stock for ',
  'A product is no longer available',
  'Dealer account is not approved for checkout',
  'Configured default shop is not active',
  'Order cannot be routed:',
];

export function definitiveFinalizeFailure(code, message) {
  if (!['P0001', '42501'].includes(String(code ?? ''))) return false;
  const text = String(message ?? '');
  return DEFINITIVE_FINALIZE_MESSAGES.some(prefix => text.startsWith(prefix));
}

export function findMatchingRefund(refunds, expected) {
  const items = Array.isArray(refunds) ? refunds : refunds?.items;
  if (!Array.isArray(items)) return null;
  return items.find(refund =>
    refund &&
    Number(refund.amount) === Number(expected.amountPaise) &&
    refund.currency === 'INR' &&
    (!expected.paymentId || refund.payment_id === expected.paymentId) &&
    ['created', 'pending', 'processed'].includes(String(refund.status)),
  ) ?? null;
}

export function refundRecordState(providerStatus) {
  if (providerStatus === 'processed') return 'refunded';
  if (providerStatus === 'created' || providerStatus === 'pending') return 'submitted';
  return 'needs_review';
}
