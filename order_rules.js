// One ordering rule for the cart and checkout (the Flutter app, the Customer
// Portal and the old HTML site all go through these routes):
//
//   quantity   at least 1 for every product
//   maximum    for the supplier-PDF catalogue (ids PDF_...): the PDF "Min Qty"
//              saved for that product ("10 nos" -> at most 10). Products with no
//              PDF quantity, and all other products, have no product maximum.
//   stock      products.stock_quantity, the real inventory (never derived from
//              the PDF quantity): stock 0 = Out of Stock, and no more than stock.
//
// Stock checks can be switched off ONLY for a local preview: the sandbox sets
// RO_PREVIEW_IGNORE_STOCK=1, and it is ignored whenever a real database is
// configured, so a production server always enforces stock.

/** The first number in a saved quantity ("10 nos" -> 10), or null. */
function moqNumber(moq) {
  const match = String(moq ?? '').match(/\d+/);
  const n = match ? parseInt(match[0], 10) : NaN;
  return Number.isInteger(n) && n >= 1 ? n : null;
}

/** Products imported from the supplier PDFs. */
function isPdfCatalogue(product) {
  return /^PDF_/.test(String(product?.id || product?.product_id || ''));
}

/** Smallest quantity that may be ordered: always 1. */
function minOrderQuantity() {
  return 1;
}

/** Largest quantity per order line: the PDF quantity for PDF products, else null. */
function maxOrderQuantity(product) {
  return isPdfCatalogue(product) ? moqNumber(product?.moq) : null;
}

/** False only in a local preview with no real database (see top of file). */
function stockEnforced() {
  if (process.env.RO_PREVIEW_IGNORE_STOCK !== '1') return true;
  const realDatabase = ['SUPABASE_DB_URL', 'DATABASE_URL', 'DB_HOST', 'PGHOST', 'SUPABASE_DB_HOST'].some(k => String(process.env[k] || '').trim());
  return realDatabase;
}

/** Stock as a number, or null when it is not tracked (or not enforced here). */
function stockOf(product) {
  if (!stockEnforced()) return null;
  if (product?.stock_quantity == null || product.stock_quantity === '') return null;
  const n = Number(product.stock_quantity);
  return Number.isFinite(n) ? n : null;
}

/** 'out_of_stock' | 'in_stock' */
function availability(product) {
  const stock = stockOf(product);
  return stock !== null && stock <= 0 ? 'out_of_stock' : 'in_stock';
}

/**
 * Why `quantity` (the whole cart line) cannot be ordered, or null when it can.
 * Returns { status, code, error, max? }. checkMax=false lets a line be lowered.
 */
function orderQuantityProblem(product, quantity, { checkMax = true } = {}) {
  const name = product?.name || 'This product';
  if (!(Number.isInteger(quantity) && quantity >= 1)) {
    return { status: 400, code: 'INVALID_QUANTITY', error: 'Quantity must be at least 1.' };
  }
  if (!checkMax) return null;
  const max = maxOrderQuantity(product);
  if (max !== null && quantity > max) {
    return { status: 400, code: 'MAX_ORDER_QTY', max, error: `You can order a maximum of ${max} units for this product.` };
  }
  const stock = stockOf(product);
  if (stock !== null && stock <= 0) return { status: 409, code: 'OUT_OF_STOCK', error: `${name} is out of stock.` };
  if (stock !== null && quantity > stock) return { status: 409, code: 'INSUFFICIENT_STOCK', error: `Only ${stock} of ${name} in stock.` };
  return null;
}

module.exports = { moqNumber, isPdfCatalogue, minOrderQuantity, maxOrderQuantity, stockEnforced, stockOf, availability, orderQuantityProblem };
