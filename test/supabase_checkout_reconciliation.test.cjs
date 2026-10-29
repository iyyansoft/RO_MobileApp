const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const root = path.join(__dirname, '..');
const corePath = path.join(root, 'supabase', 'functions', '_shared', 'checkout_refund_core.mjs');
const sqlPath = path.join(root, 'supabase', 'drafts', 'unreconciled', '20261028_checkout_refund_reconciliation.sql');
const verifyPath = path.join(root, 'supabase', 'functions', 'verify-razorpay-payment', 'index.ts');

test('only definitive, allow-listed database rejections start captured-payment recovery', async () => {
  const { definitiveFinalizeFailure } = await import(pathToFileURL(corePath).href);
  assert.equal(definitiveFinalizeFailure('P0001', 'Not enough stock for RO Membrane'), true);
  assert.equal(definitiveFinalizeFailure('P0001', 'Configured default shop is not active'), true);
  assert.equal(definitiveFinalizeFailure('42501', 'Dealer account is not approved for checkout'), true);
  assert.equal(definitiveFinalizeFailure('08006', 'connection failure'), false);
  assert.equal(definitiveFinalizeFailure('P0001', 'statement timeout'), false);
  assert.equal(definitiveFinalizeFailure('23505', 'duplicate key'), false);
});

test('provider refund matching requires the expected amount, INR currency, and payment identity', async () => {
  const { findMatchingRefund, refundRecordState } = await import(pathToFileURL(corePath).href);
  const expected = { amountPaise: 290500, paymentId: 'pay_verified' };
  const good = { id: 'rf_1', payment_id: 'pay_verified', amount: 290500, currency: 'INR', status: 'processed' };
  assert.deepEqual(findMatchingRefund({ items: [good] }, expected), good);
  assert.equal(findMatchingRefund({ items: [{ ...good, payment_id: 'pay_other' }] }, expected), null);
  assert.equal(findMatchingRefund({ items: [{ ...good, amount: 290499 }] }, expected), null);
  assert.equal(findMatchingRefund({ items: [{ ...good, currency: 'USD' }] }, expected), null);
  assert.equal(refundRecordState('processed'), 'refunded');
  assert.equal(refundRecordState('pending'), 'submitted');
  assert.equal(refundRecordState('failed'), 'needs_review');
});

test('refund draft keeps payment records private and claims each payment for one POST', () => {
  const sql = fs.readFileSync(sqlPath, 'utf8');
  assert.match(sql, /payment_id varchar\(100\) NOT NULL UNIQUE/);
  assert.match(sql, /UNIQUE \(auth_user_id, request_id, payment_id\)/);
  assert.match(sql, /'pending','processing','submitted','refunded','needs_review'/);
  assert.match(sql, /REVOKE ALL ON TABLE public\.checkout_refund_reconciliations FROM PUBLIC, anon, authenticated/);
  assert.match(sql, /GRANT ALL ON TABLE public\.checkout_refund_reconciliations TO service_role/);
  assert.match(sql, /v_session\.status <> 'razorpay_pending'/);
  assert.match(sql, /v_session\.order_id IS NOT NULL/);
  assert.match(sql, /IF v_record\.state='pending' THEN[\s\S]*v_claimed := true/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.ro_open_checkout_refund_reconciliation[\s\S]*TO service_role/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.ro_claim_checkout_refund[\s\S]*TO service_role/);
});

test('verification checks Razorpay refund records before any retry and never blindly repeats a POST', () => {
  const source = fs.readFileSync(verifyPath, 'utf8');
  const lookup = source.indexOf("payments/${encodeURIComponent(paymentId)}/refunds");
  const claim = source.indexOf("ro_claim_checkout_refund");
  const post = source.indexOf("payments/${encodeURIComponent(paymentId)}/refund`, 'POST'");
  assert.ok(lookup >= 0 && lookup < claim && claim < post);
  assert.match(source, /claim\.claimed !== true/);
  assert.match(source, /Never blindly repeat a refund POST/);
  assert.match(source, /definitiveFinalizeFailure\(error\.code, safe\)/);
  assert.match(source, /p_auth_user_id: authUser\.id/);
  assert.match(source, /\.eq\('auth_user_id', authUser\.id\)[\s\S]*\.eq\('request_id', requestId\)[\s\S]*\.eq\('payment_id', paymentId\)/);
  assert.match(source, /priorRecovery\.state === 'refunded'[\s\S]*cannot be used to place an order/);
  assert.ok(source.indexOf("from('checkout_refund_reconciliations')") < source.indexOf("service.rpc('ro_finalize_checkout'"));
  assert.doesNotMatch(source, /RAZORPAY_KEY_SECRET|SUPABASE_SERVICE_ROLE_KEY/);
});
