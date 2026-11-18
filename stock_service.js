// Stock reservation and release for orders, recorded in public.stock_movements.
//
// - Placing an order takes its quantities out of stock (never below zero).
// - Cancelling an order returns only what was taken for it and not supplied.
// - Re-opening a cancelled order takes those units again.
// - Supplying an order does not change stock (it was taken at order time).
// Orders placed before the ledger existed have no movements, so nothing is
// returned for them. Until the ledger table exists, stock is left untouched
// (the previous behaviour), so every stock change stays reversible.

const { stockEnforced } = require('./order_rules');

async function ledgerAvailable(conn) {
  // Local preview with stock checks off (never with a real database): stock
  // is left exactly as it is.
  if (!stockEnforced()) return false;
  const [rows] = await conn.query("SELECT to_regclass('public.stock_movements') IS NOT NULL AS available");
  return rows[0]?.available === true;
}

function stockError(message) {
  const error = new Error(message);
  error.status = 409;
  error.code = 'INSUFFICIENT_STOCK';
  return error;
}

async function confirmedSupplyByItem(conn, orderId) {
  const [meta] = await conn.query(`SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'shop_delivery_items' AND column_name = 'delivery_confirmed'
  ) AS available`);
  const confirmed = meta[0]?.available === true ? 'COALESCE(d.delivery_confirmed, FALSE)' : 'COALESCE(d.delivered, FALSE)';
  const [rows] = await conn.query(`SELECT oi.id, CASE WHEN ${confirmed} THEN COALESCE(d.delivered_quantity, 0) ELSE 0 END AS supplied
    FROM order_items oi LEFT JOIN shop_delivery_items d ON d.order_item_id = oi.id WHERE oi.order_id = ?`, [orderId]);
  return new Map(rows.map(row => [String(row.id), Number(row.supplied || 0)]));
}

/** Take `units` of a product, or fail without changing anything. */
async function takeStock(conn, productId, productName, units) {
  const [rows] = await conn.query(
    'UPDATE products SET stock_quantity = stock_quantity - ? WHERE id = ? AND stock_quantity >= ? RETURNING stock_quantity',
    [units, productId, units],
  );
  const updated = Array.isArray(rows) ? rows : rows?.rows;
  if (!updated || !updated.length) {
    const [current] = await conn.query('SELECT stock_quantity FROM products WHERE id = ?', [productId]);
    const left = current[0] ? Number(current[0].stock_quantity) : 0;
    throw stockError(`Not enough stock for ${productName}: ${left} left, ${units} needed.`);
  }
  return Number(updated[0].stock_quantity);
}

async function giveStock(conn, productId, units) {
  const [rows] = await conn.query(
    'UPDATE products SET stock_quantity = stock_quantity + ? WHERE id = ? RETURNING stock_quantity',
    [units, productId],
  );
  const updated = Array.isArray(rows) ? rows : rows?.rows;
  return updated && updated[0] ? Number(updated[0].stock_quantity) : null;
}

async function recordMovement(conn, { productId, orderId, orderItemId, change, reason, stockAfter }) {
  await conn.query(
    'INSERT INTO stock_movements (product_id, order_id, order_item_id, quantity_change, reason, stock_after) VALUES (?, ?, ?, ?, ?, ?)',
    [productId, orderId, orderItemId, change, reason, stockAfter],
  );
}

async function orderLines(conn, orderId) {
  const [lines] = await conn.query(
    'SELECT id, product_id, product_name, quantity FROM order_items WHERE order_id = ? ORDER BY product_id, id',
    [orderId],
  );
  return lines;
}

/** Units currently held for each order line (from the ledger). */
async function heldByItem(conn, orderId) {
  const [rows] = await conn.query(
    'SELECT order_item_id, -SUM(quantity_change)::int AS held FROM stock_movements WHERE order_id = ? GROUP BY order_item_id',
    [orderId],
  );
  return new Map(rows.map(row => [String(row.order_item_id), Number(row.held || 0)]));
}

/** Call inside the order-creation transaction, after order_items are inserted. */
async function reserveOrderStock(conn, orderId) {
  if (!(await ledgerAvailable(conn))) return { tracked: false };
  // Products are locked in id order, so concurrent orders cannot deadlock.
  for (const line of await orderLines(conn, orderId)) {
    const units = Number(line.quantity || 0);
    if (units <= 0) continue;
    const stockAfter = await takeStock(conn, line.product_id, line.product_name, units);
    await recordMovement(conn, { productId: line.product_id, orderId, orderItemId: line.id, change: -units, reason: 'order_placed', stockAfter });
  }
  return { tracked: true };
}

/**
 * Return the units held for an order and not supplied (cancellation or short
 * supply). Safe to call more than once: what was already returned is not held.
 */
async function releaseOrderStock(conn, orderId) {
  if (!(await ledgerAvailable(conn))) return { tracked: false, released: [] };
  const held = await heldByItem(conn, orderId);
  const supplied = await confirmedSupplyByItem(conn, orderId);
  const released = [];
  for (const line of await orderLines(conn, orderId)) {
    const key = String(line.id);
    const units = Math.max(0, (held.get(key) || 0) - (supplied.get(key) || 0));
    if (!units) continue;
    const stockAfter = await giveStock(conn, line.product_id, units);
    await recordMovement(conn, { productId: line.product_id, orderId, orderItemId: line.id, change: units, reason: 'order_cancelled', stockAfter });
    released.push({ productId: line.product_id, units });
  }
  return { tracked: true, released };
}

/**
 * Re-opening a cancelled order: take its unsupplied units again (only for
 * orders that were tracked by the ledger). Fails if stock is insufficient.
 */
async function reReserveOrderStock(conn, orderId) {
  if (!(await ledgerAvailable(conn))) return { tracked: false };
  const [placed] = await conn.query("SELECT 1 FROM stock_movements WHERE order_id = ? AND reason = 'order_placed' LIMIT 1", [orderId]);
  if (!placed.length) return { tracked: false };
  // Units already supplied stay counted as taken, so the line needs its full
  // ordered quantity held again.
  const held = await heldByItem(conn, orderId);
  for (const line of await orderLines(conn, orderId)) {
    const key = String(line.id);
    const needed = Number(line.quantity || 0) - (held.get(key) || 0);
    if (needed <= 0) continue;
    const stockAfter = await takeStock(conn, line.product_id, line.product_name, needed);
    await recordMovement(conn, { productId: line.product_id, orderId, orderItemId: line.id, change: -needed, reason: 'order_reopened', stockAfter });
  }
  return { tracked: true };
}

module.exports = { ledgerAvailable, reserveOrderStock, releaseOrderStock, reReserveOrderStock };
