const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const root = path.join(__dirname, '..');
const corePath = path.join(root, 'supabase', 'functions', '_shared', 'checkout_core.mjs');
const migrationPath = path.join(root, 'supabase', 'drafts', 'unreconciled', '20261027_secure_checkout.sql');

const products = [
  { id: 'membrane', name: 'RO Membrane', brand: 'Neero', price: '1000.00', img: '/membrane.png', stock_quantity: 5, status: 'active' },
  { id: 'filter', name: 'Sediment Filter', brand: 'Neero', price: '500.00', img: '/filter.png', stock_quantity: 2, status: 'active' },
];
const dealer = { id: 'dealer-1', status: 'approved', is_approved: true, email_verified: true, business_name: 'Dealer Co' };
const address = { name: 'Priya', mobile: '9876543210', address: '12 Market Road', city: 'Pune', state: 'Maharashtra', pincode: '411001' };

test('Supabase checkout quote ignores client prices/totals and uses DB dealer prices', async () => {
  const { quoteCheckout } = await import(pathToFileURL(corePath).href);
  const quote = quoteCheckout({
    paymentMethod: 'Cash on Delivery', withGst: true, gstin: '27AAPFU0939F1ZV',
    items: [
      { id: 'membrane', quantity: 1, numericPrice: 0.01, name: 'forged name' },
      { id: 'membrane', quantity: 1, numericPrice: 0.01 },
      { id: 'filter', quantity: 1, numericPrice: 0.01 },
    ],
    subtotal: 0.03, grandTotal: 0.03, deliveryAddress: address,
  }, products, dealer);
  assert.deepEqual(quote.items.map(item => [item.id, item.quantity, item.numericPrice]), [
    ['membrane', 2, 1000], ['filter', 1, 500],
  ]);
  assert.equal(quote.subtotal, 2500);
  assert.equal(quote.discount, 250);
  assert.equal(quote.gst, 405);
  assert.equal(quote.deliveryFee, 250);
  assert.equal(quote.grandTotal, 2905);
  assert.equal(quote.companyName, 'Dealer Co');
});

test('Supabase checkout validates approval, GST, payment method, addresses and stock', async () => {
  const { quoteCheckout } = await import(pathToFileURL(corePath).href);
  const request = { paymentMethod: 'Cash on Delivery', withGst: false, items: [{ id: 'filter', quantity: 1 }], deliveryAddress: address };
  assert.throws(() => quoteCheckout(request, products, { ...dealer, is_approved: false }), /not approved/);
  assert.throws(() => quoteCheckout(request, products, { ...dealer, email_verified: false }), /not approved/);
  assert.throws(() => quoteCheckout({ ...request, paymentMethod: 'UPI' }, products, dealer), /Cash on Delivery or Razorpay/);
  assert.throws(() => quoteCheckout({ ...request, withGst: true, gstin: 'invalid' }, products, dealer), /valid GST/);
  assert.throws(() => quoteCheckout({ ...request, items: [{ id: 'filter', quantity: 3 }] }, products, dealer), /Not enough stock/);
  assert.throws(() => quoteCheckout({ ...request, items: [{ id: 'filter', quantity: 0 }] }, products, dealer), /positive integer/);
  assert.throws(() => quoteCheckout({ ...request, deliveryAddress: { ...address, pincode: '4110' } }, products, dealer), /six digits/);
  assert.throws(() => quoteCheckout({ ...request, items: [{ id: 'missing', quantity: 1 }] }, products, dealer), /no longer available/);
});

test('checkout retry fingerprint excludes forged client totals and unit prices', async () => {
  const { quoteCheckout, checkoutFingerprint } = await import(pathToFileURL(corePath).href);
  const first = quoteCheckout({ paymentMethod: 'Cash on Delivery', withGst: false, items: [{ id: 'filter', quantity: 1, numericPrice: 1 }], subtotal: 1, deliveryAddress: address }, products, dealer);
  const second = quoteCheckout({ paymentMethod: 'Cash on Delivery', withGst: false, items: [{ id: 'filter', quantity: 1, numericPrice: 9999 }], subtotal: 9999, deliveryAddress: address }, products, dealer);
  assert.equal(checkoutFingerprint(first), checkoutFingerprint(second));
});

test('Razorpay provider verification rejects failed, mismatched, and wrong-amount payments', async () => {
  const { validateRazorpayPayment, completedCheckoutReplay } = await import(pathToFileURL(corePath).href);
  const expected = { paymentId: 'pay_123', gatewayOrderId: 'order_123', amountPaise: 290500 };
  assert.equal(validateRazorpayPayment({ id: 'pay_123', order_id: 'order_123', amount: 290500, currency: 'INR', status: 'authorized' }, expected), 'authorized');
  assert.equal(validateRazorpayPayment({ id: 'pay_123', order_id: 'order_123', amount: 290500, currency: 'INR', status: 'captured' }, expected), 'captured');
  assert.throws(() => validateRazorpayPayment({ id: 'pay_123', order_id: 'other', amount: 290500, currency: 'INR', status: 'captured' }, expected), /does not match/);
  assert.throws(() => validateRazorpayPayment({ id: 'pay_123', order_id: 'order_123', amount: 290499, currency: 'INR', status: 'captured' }, expected), /does not match/);
  assert.throws(() => validateRazorpayPayment({ id: 'pay_123', order_id: 'order_123', amount: 290500, currency: 'INR', status: 'failed' }, expected), /not been captured/);
  assert.throws(() => validateRazorpayPayment({ id: 'wrong_payment', order_id: 'order_123', amount: 290500, currency: 'INR', status: 'captured' }, expected), /does not match/);
  assert.deepEqual(completedCheckoutReplay({ status: 'completed', order_id: 'RO-1', payment_id: 'pay_123' }, 'pay_123'), { orderId: 'RO-1', paymentStatus: 'paid' });
  assert.throws(() => completedCheckoutReplay({ status: 'completed', order_id: 'RO-1', payment_id: 'pay_123' }, 'pay_456'), /different payment/);
});

test('checkout migration keeps records server-only and makes order writes idempotent', () => {
  const sql = fs.readFileSync(migrationPath, 'utf8');
  assert.match(sql, /CREATE TABLE IF NOT EXISTS public\.checkout_sessions/);
  assert.match(sql, /PRIMARY KEY \(auth_user_id, request_id\)/);
  assert.match(sql, /REVOKE ALL ON TABLE public\.checkout_sessions FROM PUBLIC, anon, authenticated/);
  assert.match(sql, /GRANT ALL ON TABLE public\.checkout_sessions TO service_role/);
  assert.match(sql, /GRANT USAGE, SELECT ON SEQUENCE public\.checkout_inventory_movements_id_seq TO service_role/);
  assert.match(sql, /pg_advisory_xact_lock/);
  assert.match(sql, /payment_status.*CASE WHEN/s);
  assert.match(sql, /'due_on_delivery'/);
  assert.match(sql, /ALTER TABLE public\.checkout_sessions ENABLE ROW LEVEL SECURITY/);
  assert.match(sql, /shop_order_assignments/);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.ro_finalize_checkout/);
  assert.match(sql, /UNIQUE \(order_id, product_id, movement_type\)/);
  assert.match(sql, /movement_type IN \('order_deduction','cancellation_restock'\)/);
  assert.match(sql, /stock_quantity=stock_quantity-v_item_quantity/);
  assert.match(sql, /FOR UPDATE/);
  assert.match(sql, /CREATE OR REPLACE FUNCTION public\.ro_cancel_checkout_order/);
  assert.match(sql, /SELECT id INTO v_dealer_id FROM public\.users WHERE auth_user_id=p_auth_user_id/);
  assert.match(sql, /WHERE order_id=p_order_id AND user_id=v_dealer_id FOR UPDATE/);
  assert.match(sql, /movement_type='order_deduction'/);
  assert.match(sql, /movement_type='cancellation_restock'/);
  assert.match(sql, /ON CONFLICT \(order_id,product_id,movement_type\) DO NOTHING/);
  assert.match(sql, /Online-paid or collected orders require a verified refund before cancellation/);
  assert.match(sql, /shop_delivery_items WHERE order_id=p_order_id/);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.ro_cancel_checkout_order/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.ro_cancel_checkout_order\(uuid,text\) TO service_role/);
});

test('Edge Functions validate Auth identity and never expose server keys to Flutter', () => {
  const functionRoot = path.join(root, 'supabase', 'functions');
  for (const name of ['place-cod-order', 'create-razorpay-order', 'verify-razorpay-payment']) {
    const source = fs.readFileSync(path.join(functionRoot, name, 'index.ts'), 'utf8');
    assert.match(source, /authenticatedUser\(request\)/);
    assert.match(source, /serviceClient\(\)/);
  }
  const verify = fs.readFileSync(path.join(functionRoot, 'verify-razorpay-payment', 'index.ts'), 'utf8');
  assert.match(verify, /verifySignature\(/);
  assert.match(verify, /payments\/.*\/capture/);
  assert.match(verify, /validateRazorpayPayment\(payment,[\s\S]*\) !== 'captured'/);
  const config = fs.readFileSync(path.join(functionRoot, '..', 'config.toml'), 'utf8');
  assert.match(config, /verify_jwt = false/);
  assert.match(config, /function-level authentication checks/);
  const flutterRepository = fs.readFileSync(path.join(root, 'lib', 'core', 'supabase', 'supabase_checkout_repository.dart'), 'utf8');
  assert.doesNotMatch(flutterRepository, /SERVICE_ROLE|RAZORPAY_KEY_SECRET/);
  assert.match(flutterRepository, /checkoutSessionActive/);
  const flutterConfig = fs.readFileSync(path.join(root, 'lib', 'core', 'supabase', 'supabase_config.dart'), 'utf8');
  assert.match(flutterConfig, /USE_SUPABASE_CHECKOUT'[\s\S]*defaultValue: false/);
  const authSource = fs.readFileSync(path.join(functionRoot, '_shared', 'checkout_http.ts'), 'utf8');
  assert.match(authSource, /auth\.getUser\(accessToken\)/);
  const cod = fs.readFileSync(path.join(functionRoot, 'place-cod-order', 'index.ts'), 'utf8');
  assert.match(cod, /paymentMethod !== 'Cash on Delivery'/);
  assert.doesNotMatch(cod, /cash collected|payment_status.*paid/i);
  const verifyUsesSharedPaymentValidator = fs.readFileSync(path.join(functionRoot, 'verify-razorpay-payment', 'index.ts'), 'utf8');
  assert.match(verifyUsesSharedPaymentValidator, /validateRazorpayPayment\(/);
  assert.match(verifyUsesSharedPaymentValidator, /paymentStatus === 'authorized'/);
});

test('cancel-order authenticates owner identity and only reaches service-role cancellation RPC', () => {
  const functionRoot = path.join(root, 'supabase', 'functions');
  const cancel = fs.readFileSync(path.join(functionRoot, 'cancel-order', 'index.ts'), 'utf8');
  assert.ok(cancel.indexOf('authenticatedUser(request)') < cancel.indexOf('serviceClient().rpc'));
  assert.match(cancel, /ro_cancel_checkout_order/);
  assert.match(cancel, /p_auth_user_id: authUser\.id/);
  assert.match(cancel, /p_order_id: orderId/);
  assert.match(fs.readFileSync(path.join(functionRoot, '..', 'config.toml'), 'utf8'), /\[functions\.cancel-order\][\s\S]*verify_jwt = false/);
  const flutterRepository = fs.readFileSync(path.join(root, 'lib', 'core', 'supabase', 'supabase_checkout_repository.dart'), 'utf8');
  assert.match(flutterRepository, /cancelUnfulfilledOrder/);
  assert.match(flutterRepository, /_invoke\('cancel-order'/);
});

test('checkout retries serialize on the user/request pair and canceled retries cannot recreate orders', () => {
  const sql = fs.readFileSync(migrationPath, 'utf8');
  assert.match(sql, /PRIMARY KEY \(auth_user_id, request_id\)/);
  assert.match(sql, /pg_advisory_xact_lock\(hashtextextended\(p_auth_user_id::text\|\|p_request_id::text,0\)\)/);
  assert.match(sql, /IF lower\(coalesce\(v_saved_order_status,''\)\)='cancelled' THEN RAISE EXCEPTION 'This checkout order was cancelled'/);
});
