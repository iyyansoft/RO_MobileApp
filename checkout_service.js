const { pricingRules, priceOrder } = require('./pricing_rules');
const { orderQuantityProblem } = require('./order_rules');
const crypto = require('crypto');

function validGstin(input) {
  const gst = String(input || '').trim().toUpperCase();
  if (!/^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(gst)) return false;
  const alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  let sum = 0, factor = 2;
  for (let i = 13; i >= 0; i--) {
    const product = alphabet.indexOf(gst[i]) * factor;
    sum += Math.floor(product / 36) + product % 36;
    factor = factor === 2 ? 1 : 2;
  }
  return gst[14] === alphabet[(36 - sum % 36) % 36];
}
function fail(message, status = 400) { const error = new Error(message); error.status = status; throw error; }
function quoteCheckout(input, products, rules = pricingRules()) {
  if (!Array.isArray(input.items) || !input.items.length) fail('Add products before checkout.');
  const withGst = input.withGst === true || input.withGst === 'true';
  const gstin = withGst ? String(input.gstin || '').trim().toUpperCase() : '';
  if (withGst && !validGstin(gstin)) fail('With GST requires a valid GST number.');
  const quantities = new Map();
  for (const item of input.items) {
    if (!Number.isSafeInteger(item.quantity) || item.quantity < 1) fail('Product quantity must be a positive integer.');
    quantities.set(String(item.id), (quantities.get(String(item.id)) || 0) + item.quantity);
  }
  const items = Array.from(quantities, ([id, quantity]) => {
    const product = products.find(p => String(p.id) === id && p.status !== 'inactive');
    if (!product || !Number.isFinite(Number(product.price)) || Number(product.price) <= 0) fail('A product is no longer available. Refresh your cart.');
    // Same rule as the cart (order_rules.js): MOQ <= quantity <= stock.
    const problem = orderQuantityProblem(product, quantity);
    // "Not enough stock" keeps its existing wording and status (400).
    if (problem) fail(problem.code === 'INSUFFICIENT_STOCK' ? `Not enough stock for ${product.name}.` : problem.error, problem.code === 'INSUFFICIENT_STOCK' ? 400 : problem.status);
    return { id, quantity, name: product.name, brand: product.brand, numericPrice: Number(product.price), imgSrc: product.img || '' };
  });
  // Amounts sent by the client are ignored: everything is recomputed here
  // from database prices and the configured pricing rules.
  const totals = priceOrder(items.map(item => ({ unitPrice: item.numericPrice, quantity: item.quantity })), withGst, rules);
  return { ...input, items, withGst, gstin, ...totals };
}

function createDealerToken(user, secret) {
  const payload = Buffer.from(JSON.stringify({ email: user.email, id: user.id, exp: Date.now() + 30 * 86400000 })).toString('base64url');
  return `${payload}.${crypto.createHmac('sha256', secret).update(payload).digest('hex')}`;
}
function verifyDealerToken(token, secret) {
  try {
    const [payload, signature] = token.split('.');
    const expected = crypto.createHmac('sha256', secret).update(payload).digest('hex');
    if (!signature || signature.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;
    const user = JSON.parse(Buffer.from(payload, 'base64url').toString());
    return user.exp > Date.now() ? user : null;
  } catch (_) { return null; }
}

async function razorpayRequest(route, method = 'GET', body, fetcher = fetch) {
  const key = process.env.RAZORPAY_KEY_ID, secret = process.env.RAZORPAY_KEY_SECRET;
  if (!key || !secret) fail('Razorpay is not configured. Contact the store administrator or select Cash on Delivery.', 503);
  const response = await fetcher(`https://api.razorpay.com/v1/${route}`, {
    method, headers: { Authorization: `Basic ${Buffer.from(`${key}:${secret}`).toString('base64')}`, 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(20000),
  });
  const data = await response.json();
  if (!response.ok) fail(data.error?.description || 'Razorpay could not process the request.', 502);
  return data;
}
async function verifyCapturedPayment(session, paymentId, signature, request = razorpayRequest) {
  const expected = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || '').update(`${session.id}|${paymentId}`).digest('hex');
  if (typeof signature !== 'string' || signature.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) fail('Payment signature verification failed.');
  let payment = await request(`payments/${encodeURIComponent(paymentId)}`);
  if (payment.order_id !== session.id || Number(payment.amount) !== Number(session.amount) || payment.currency !== 'INR') fail('Payment does not match this checkout.');
  if (payment.status === 'authorized') payment = await request(`payments/${encodeURIComponent(paymentId)}/capture`, 'POST', { amount: session.amount, currency: 'INR' });
  if (payment.status !== 'captured') fail('Payment has not been captured. Please retry payment verification.', 409);
  if (payment.order_id !== session.id || Number(payment.amount) !== Number(session.amount) || payment.currency !== 'INR') fail('Captured payment does not match this checkout.');
  return payment;
}
module.exports = { validGstin, quoteCheckout, createDealerToken, verifyDealerToken, razorpayRequest, verifyCapturedPayment };
