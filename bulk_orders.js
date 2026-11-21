// Bulk Orders: a second purchase mode on the same product records.
//
//   normal  Dealer Price (products.price); existing MOQ / maximum / stock rules.
//   bulk    products.bulk_price per piece; quantity = bulk_min_qty, then whole
//           steps of bulk_step (Domestic PDF: min = step = the printed pack,
//           e.g. 42, 84, 126; Mukhil PDF: min = Mini qty, step 1, e.g. 10, 11,
//           12). No product maximum (that is a normal-purchase rule); stock
//           still applies.
//
// Prices and quantities are always checked here, on the server; amounts sent
// by the app are ignored. Until migration 011 (supabase/staging/
// 011_bulk_orders.sql) is applied, nothing changes: every line is 'normal'
// and bulk requests are refused.
const { stockOf } = require('./order_rules');

const PURCHASE_MODES = ['normal', 'bulk'];

/** 'normal' | 'bulk' | null (invalid). Missing = 'normal'. */
function purchaseMode(value) {
  if (value === undefined || value === null || value === '') return 'normal';
  const mode = String(value).trim().toLowerCase();
  return PURCHASE_MODES.includes(mode) ? mode : null;
}

/** The product's bulk offer, or null when it is not sold in Bulk Orders. */
function bulkOffer(product) {
  const price = Number(product?.bulk_price);
  const min = Number(product?.bulk_min_qty);
  const step = Number(product?.bulk_step);
  const label = String(product?.bulk_pack_label ?? '').trim();
  if (!(price > 0) || !Number.isInteger(min) || min < 1 || !Number.isInteger(step) || step < 1 || min % step !== 0 || !label) return null;
  return { price, min, step, label };
}

/** True when `quantity` is a valid bulk quantity for the offer. */
function validBulkQuantity(offer, quantity) {
  return Number.isInteger(quantity) && quantity >= offer.min && (quantity - offer.min) % offer.step === 0;
}

/**
 * Why `quantity` (the whole cart line) cannot be bought in bulk, or null.
 * Same shape as order_rules.orderQuantityProblem: { status, code, error }.
 */
function bulkQuantityProblem(product, quantity, { checkStock = true } = {}) {
  const name = product?.name || 'This product';
  const offer = bulkOffer(product);
  if (!offer) return { status: 409, code: 'BULK_UNAVAILABLE', error: `${name} is not available in Bulk Orders.` };
  if (!Number.isInteger(quantity) || quantity < offer.min) {
    return { status: 400, code: 'BULK_MIN_QTY', min: offer.min, error: `Bulk orders of ${name} start at ${offer.min} (${offer.label}).` };
  }
  if (!validBulkQuantity(offer, quantity)) {
    return { status: 400, code: 'BULK_STEP', min: offer.min, step: offer.step, error: `Bulk quantity for ${name} must be in packs of ${offer.step} (${offer.min}, ${offer.min + offer.step}, ${offer.min + 2 * offer.step} ...).` };
  }
  if (checkStock) {
    const stock = stockOf(product);
    if (stock !== null && stock <= 0) return { status: 409, code: 'OUT_OF_STOCK', error: `${name} is out of stock.` };
    if (stock !== null && quantity > stock) return { status: 409, code: 'INSUFFICIENT_STOCK', error: `Only ${stock} of ${name} in stock.` };
  }
  return null;
}

/** Refusal when a product is already in the cart in the other mode. */
function modeConflict(product, existingMode, wantedMode) {
  if (!existingMode || existingMode === wantedMode) return null;
  const name = product?.name || 'This product';
  return {
    status: 409,
    code: 'PURCHASE_MODE_CONFLICT',
    error: existingMode === 'bulk'
      ? `${name} is already in your cart as a Bulk Order. Remove it from the cart to buy it normally.`
      : `${name} is already in your cart as a normal purchase. Remove it from the cart to buy it in bulk.`,
  };
}

// Migration 011 present? Positive answers are remembered per database pool;
// a missing column is re-checked each time, so applying the migration takes
// effect without a restart.
const readyPools = new WeakSet();
async function bulkOrdersReady(db) {
  if (db && typeof db === 'object' && readyPools.has(db)) return true;
  const [rows] = await db.query(
    `SELECT COUNT(*)::int AS n FROM information_schema.columns
      WHERE table_schema = 'public'
        AND ((table_name = 'products' AND column_name IN ('bulk_price', 'bulk_min_qty', 'bulk_step', 'bulk_pack_label'))
          OR (table_name = 'cart_items' AND column_name = 'purchase_mode')
          OR (table_name = 'order_items' AND column_name IN ('purchase_mode', 'bulk_pack_label')))`
  );
  const ready = Number(rows[0]?.n) === 7;
  if (ready && db && typeof db === 'object') readyPools.add(db);
  return ready;
}

/** Catalogue fields for a product row (null when not in Bulk Orders). */
function bulkFields(row) {
  const offer = bulkOffer(row);
  return offer
    ? { bulk_price: offer.price, bulk_min_qty: offer.min, bulk_step: offer.step, bulk_pack_label: offer.label }
    : { bulk_price: null, bulk_min_qty: null, bulk_step: null, bulk_pack_label: null };
}

module.exports = {
  PURCHASE_MODES,
  purchaseMode,
  bulkOffer,
  validBulkQuantity,
  bulkQuantityProblem,
  modeConflict,
  bulkOrdersReady,
  bulkFields,
};
