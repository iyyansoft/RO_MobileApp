// Pure checkout rules shared by the Edge Functions and Node tests.
// The caller must supply products loaded from PostgreSQL; client-sent prices
// and totals are deliberately ignored.
export function validGstin(input) {
  const gst = String(input ?? '').trim().toUpperCase();
  if (!/^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(gst)) return false;
  const alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  let sum = 0;
  let factor = 2;
  for (let i = 13; i >= 0; i -= 1) {
    const product = alphabet.indexOf(gst[i]) * factor;
    sum += Math.floor(product / 36) + (product % 36);
    factor = factor === 2 ? 1 : 2;
  }
  return gst[14] === alphabet[(36 - (sum % 36)) % 36];
}

const money = value => Math.round((value + Number.EPSILON) * 100) / 100;
const requiredText = (value, label) => {
  const result = String(value ?? '').trim();
  if (!result) throw new Error(`${label} is required.`);
  return result;
};
function validAddress(input, label) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new Error(`${label} is required.`);
  }
  const address = {
    name: requiredText(input.name, `${label} name`),
    mobile: requiredText(input.mobile, `${label} mobile`),
    address: requiredText(input.address, `${label} street`),
    city: requiredText(input.city, `${label} city`),
    state: requiredText(input.state, `${label} state`),
    pincode: requiredText(input.pincode, `${label} pincode`),
  };
  if (!/^\d{6}$/.test(address.pincode)) throw new Error(`${label} pincode must contain six digits.`);
  return address;
}

export function quoteCheckout(input, products, dealer) {
  if (!dealer || dealer.status !== 'approved' || dealer.is_approved !== true || dealer.email_verified !== true) {
    throw new Error('This dealer account is not approved for checkout.');
  }
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid checkout request.');
  const paymentMethod = input.paymentMethod;
  if (!['Cash on Delivery', 'Razorpay'].includes(paymentMethod)) throw new Error('Select Cash on Delivery or Razorpay.');
  if (!Array.isArray(input.items) || input.items.length === 0) throw new Error('Add products before checkout.');
  const deliveryAddress = validAddress(input.deliveryAddress, 'Delivery address');
  const sameAsDelivery = input.sameAsDelivery !== false;
  const billingAddress = sameAsDelivery ? deliveryAddress : validAddress(input.billingAddress, 'Billing address');
  const withGst = input.withGst !== false;
  const gstin = withGst ? String(input.gstin ?? '').trim().toUpperCase() : '';
  if (withGst && !validGstin(gstin)) throw new Error('With GST requires a valid GST number.');

  const quantities = new Map();
  for (const item of input.items) {
    const id = String(item?.id ?? '').trim();
    const quantity = item?.quantity;
    if (!id || !Number.isSafeInteger(quantity) || quantity < 1) throw new Error('Product quantity must be a positive integer.');
    quantities.set(id, (quantities.get(id) ?? 0) + quantity);
  }
  const byId = new Map(products.map(product => [String(product.id), product]));
  const items = [...quantities].map(([id, quantity]) => {
    const product = byId.get(id);
    const price = Number(product?.price);
    if (!product || product.status === 'inactive' || !Number.isFinite(price) || price <= 0) {
      throw new Error('A product is no longer available. Refresh your cart.');
    }
    if (product.stock_quantity != null && quantity > Number(product.stock_quantity)) {
      throw new Error(`Not enough stock for ${product.name}.`);
    }
    return {
      id,
      quantity,
      name: String(product.name),
      brand: String(product.brand ?? ''),
      numericPrice: price,
      imgSrc: String(product.img ?? ''),
    };
  });
  const subtotal = money(items.reduce((sum, item) => sum + item.numericPrice * item.quantity, 0));
  const discount = money(subtotal * 0.1);
  const gst = withGst ? money((subtotal - discount) * 0.18) : 0;
  const deliveryFee = subtotal > 5000 ? 0 : 250;
  const grandTotal = money(subtotal - discount + gst + deliveryFee);
  return {
    dealerId: dealer.id,
    paymentMethod,
    items,
    withGst,
    gstin,
    companyName: String(input.companyName ?? dealer.business_name ?? '').trim(),
    panNumber: String(input.panNumber ?? '').trim().toUpperCase(),
    deliveryNote: String(input.deliveryNote ?? '').trim(),
    sameAsDelivery,
    deliveryAddress,
    billingAddress,
    subtotal,
    discount,
    gst,
    deliveryFee,
    grandTotal,
  };
}

export function checkoutFingerprint(quote) {
  // Stable business input only. Do not include client-calculated totals.
  return JSON.stringify({
    paymentMethod: quote.paymentMethod,
    items: quote.items.map(item => [item.id, item.quantity]),
    withGst: quote.withGst,
    gstin: quote.gstin,
    companyName: quote.companyName,
    panNumber: quote.panNumber,
    deliveryNote: quote.deliveryNote,
    sameAsDelivery: quote.sameAsDelivery,
    deliveryAddress: quote.deliveryAddress,
    billingAddress: quote.billingAddress,
  });
}

// Validate the provider response independently of the client callback. This
// helper is shared by the deployed Edge Function and Node's automated tests.
export function validateRazorpayPayment(payment, expected) {
  if (!payment || typeof payment !== 'object' ||
      payment.id !== expected.paymentId || payment.order_id !== expected.gatewayOrderId ||
      Number(payment.amount) !== Number(expected.amountPaise) ||
      payment.currency !== 'INR') {
    throw new Error('Payment does not match this checkout.');
  }
  if (!['authorized', 'captured'].includes(String(payment.status))) {
    throw new Error('Payment has not been captured. Retry verification before starting another payment.');
  }
  return payment.status;
}

export function completedCheckoutReplay(session, paymentId) {
  if (session?.status !== 'completed' || !session.order_id) return null;
  if (session.payment_id !== paymentId) {
    throw new Error('A different payment already completed this checkout. Contact support about the second payment.');
  }
  return { orderId: session.order_id, paymentStatus: 'paid' };
}
