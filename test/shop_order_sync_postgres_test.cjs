// Customer checkout -> Shop App Current Orders, on a real (in-memory)
// PostgreSQL built from the project's own schema files. Never touches the
// configured database.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { PGlite } = require('@electric-sql/pglite');
const { citext } = require('@electric-sql/pglite/contrib/citext');
const { toPostgresPlaceholders, adaptResult, normalizeDatabaseError } = require('../db');
const { createDealerToken } = require('../checkout_service');
const { signEmployeeToken } = require('../shop_service');
const vm = require('node:vm');
const orderStatus = require('../order_status');

const root = path.join(__dirname, '..');
const SECRET = 'shop-order-sync-test-secret';
const EMPLOYEE_SECRET = 'shop-order-sync-employee-secret';

async function setup({ withAssignmentTable = true, withStockLedger = true } = {}) {
  const db = new PGlite({ extensions: { citext } });
  await db.exec(fs.readFileSync(path.join(root, 'supabase_migration.sql'), 'utf8'));
  await db.exec(fs.readFileSync(path.join(root, 'shop_app_migration.sql'), 'utf8'));
  if (!withAssignmentTable) await db.exec('DROP TABLE public.shop_order_assignments');
  if (withStockLedger) await db.exec(fs.readFileSync(path.join(root, 'supabase', 'staging', '007_stock_movements.sql'), 'utf8'));

  const query = async (sql, values = []) => {
    try {
      const result = await db.query(toPostgresPlaceholders(sql), Array.from(values));
      const command = sql.trim().split(/\s/)[0].toUpperCase();
      return adaptResult({ ...result, command: command === 'WITH' ? 'SELECT' : command, rowCount: result.affectedRows });
    } catch (error) { throw normalizeDatabaseError(error); }
  };
  const pool = {
    query,
    getConnection: async () => ({
      query,
      beginTransaction: () => db.exec('BEGIN'),
      commit: () => db.exec('COMMIT'),
      rollback: () => db.exec('ROLLBACK'),
      release() {},
    }),
  };
  const routes = new Map();
  const app = {
    get: (p, ...h) => routes.set(`GET ${p}`, h),
    post: (p, ...h) => routes.set(`POST ${p}`, h),
    put: (p, ...h) => routes.set(`PUT ${p}`, h),
    delete: (p, ...h) => routes.set(`DELETE ${p}`, h),
    patch: (p, ...h) => routes.set(`PATCH ${p}`, h),
  };
  // Same shape as server.js findUserByEmailOrMobile (business_name -> business).
  const findUser = async email => {
    const row = (await query('SELECT * FROM users WHERE email = ?', [email]))[0][0];
    return row && { ...row, business: row.business_name };
  };
  const requireAdminAuth = (req, res, next) => next();
  const quiet = console.error;
  console.error = () => {};
  require('../order_checkout')(app, pool, SECRET, findUser);
  require('../shop_routes')(app, pool, EMPLOYEE_SECRET, requireAdminAuth);
  const server = fs.readFileSync(path.join(root, 'server.js'), 'utf8');
  const adminRoutes = server.slice(
    server.indexOf('async function orderSupplyTotals('),
    server.indexOf("app.get('/api/admin/dashboard-stats'"),
  );
  vm.runInNewContext(adminRoutes, { app, pool, requireAdminAuth, console: { error() {} }, ...orderStatus, ...require('../stock_service') });
  // Dealer invoices / credit and support tickets (real routes from server.js).
  vm.runInNewContext(
    server.slice(server.indexOf("app.get('/api/user/gst-invoices'"), server.indexOf('// PRODUCT CATALOG ENDPOINTS')),
    { app, pool, console: { error() {} }, process, Intl, Date, Number, Math },
  );
  console.error = quiet;

  const call = async (key, { body = {}, query: q = {}, params = {}, headers = {} } = {}) => {
    const handlers = routes.get(key);
    assert.ok(handlers, `route ${key}`);
    const res = { statusCode: 200, body: null, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; }, set() { return this; } };
    const req = { body, query: q, params, headers, ip: '127.0.0.1', socket: {} };
    let i = 0;
    const next = async () => { const h = handlers[i++]; if (h) await h(req, res, next); };
    const original = console.error;
    console.error = () => {};
    try { await next(); } finally { console.error = original; }
    return res;
  };

  // Catalogue and a registered dealer.
  await query(`INSERT INTO categories (id, key_name, title, display_order) VALUES ('CAT_MEM', 'membranes', 'Membranes', 1)`);
  for (const [id, name, price] of [['P1', 'RO Membrane 75 GPD', 650], ['P2', 'RO Filter Housing 10 Inch', 290]]) {
    await query(`INSERT INTO products (id, category_id, category_key, sku, name, brand, price, mrp, status, stock_quantity)
      VALUES (?, 'CAT_MEM', 'membranes', ?, ?, 'RO Wholesale', ?, ?, 'active', 100)`, [id, `SKU-${id}`, name, price, price * 1.4]);
  }
  const dealer = { id: 'DEALER_1', email: 'priya@example.test' };
  await query(`INSERT INTO users (id, email, name, business_name, password_hash, email_verified, status, is_approved)
    VALUES (?, ?, 'Priya', 'SRP', 'x', TRUE, 'approved', TRUE)`, [dealer.id, dealer.email]);
  const dealerToken = createDealerToken(dealer, SECRET);

  const employees = {};
  async function addShop(loginId, shopName) {
    const id = crypto.randomUUID();
    await query(`INSERT INTO shop_employees (id, employee_id, shop_name, full_name, password_hash, active)
      VALUES (?, ?, ?, ?, 'x', TRUE)`, [id, loginId, shopName, `${shopName} staff`]);
    employees[shopName] = signEmployeeToken({ id, employee_id: loginId, shop_name: shopName, full_name: `${shopName} staff` }, EMPLOYEE_SECRET);
  }

  async function placeOrder(items, extra = {}) {
    return call('POST /api/user/orders/create', {
      headers: { authorization: `Bearer ${dealerToken}` },
      body: {
        email: dealer.email,
        paymentMethod: 'Cash on Delivery',
        deliveryAddress: { line1: '12 Main Road', city: 'Chennai', pincode: '600001' },
        items,
        ...extra,
      },
    });
  }
  async function shopOrders(shopName, q = {}) {
    return call('GET /api/shop/orders', { headers: { authorization: `Bearer ${employees[shopName]}` }, query: q });
  }
  const admin = {
    setStatus: (orderId, status) => call('PUT /api/admin/orders/:id/status', { params: { id: orderId }, body: { status } }),
    setPayment: (orderId, paymentStatus) => call('PUT /api/admin/orders/:id/payment-status', { params: { id: orderId }, body: { paymentStatus } }),
  };
  async function supply(shopName, orderId, lines, cashCollected = false) {
    return call('POST /api/shop/orders/:orderId/delivery', {
      headers: { authorization: `Bearer ${employees[shopName]}` },
      params: { orderId },
      body: {
        mode: 'confirm',
        cashCollected,
        items: lines.map(([orderItemId, quantity]) => ({
          orderItemId: Number(orderItemId), deliveredQuantity: quantity,
          deliveryConfirmed: quantity > 0, deliveryStatus: quantity > 0 ? 'delivered' : 'not_delivered', delivered: quantity > 0,
        })),
      },
    });
  }
  return { db, query, call, addShop, placeOrder, shopOrders, employees, admin, supply };
}

test('live-database state: no assignment table, one shop — new orders appear', async () => {
  const t = await setup({ withAssignmentTable: false });
  await t.addShop('IYYAN', 'ROSHOP');
  const placed = await t.placeOrder([{ id: 'P2', quantity: 1 }]);
  assert.equal(placed.statusCode, 200, JSON.stringify(placed.body));
  assert.equal(placed.body.assignedShopName, 'ROSHOP');
  const list = await t.shopOrders('ROSHOP');
  assert.equal(list.statusCode, 200, JSON.stringify(list.body));
  assert.deepEqual(list.body.orders.map(o => o.orderId), [placed.body.order.orderId]);
});

test('one shop with the assignment table: order is saved, assigned and shown with full details', async () => {
  const t = await setup();
  await t.addShop('IYYAN', 'ROSHOP');
  const placed = await t.placeOrder([{ id: 'P1', quantity: 3 }, { id: 'P2', quantity: 2 }]);
  assert.equal(placed.statusCode, 200, JSON.stringify(placed.body));
  const orderId = placed.body.order.orderId;
  assert.equal(placed.body.assignedShopName, 'ROSHOP');

  // Saved in the shared database, with its shop assignment.
  const [[order]] = await t.query('SELECT user_name, user_business, payment_method, payment_status, status FROM orders WHERE order_id = ?', [orderId]);
  assert.deepEqual({ ...order }, { user_name: 'Priya', user_business: 'SRP', payment_method: 'Cash on Delivery', payment_status: 'due_on_delivery', status: 'Processing & Dispatched' });
  const [[assignment]] = await t.query('SELECT shop_name FROM shop_order_assignments WHERE order_id = ?', [orderId]);
  assert.equal(assignment.shop_name, 'ROSHOP');

  // Shop App Current Orders (this used to return nothing once the
  // assignment table existed: the shop filter read the search value).
  const list = await t.shopOrders('ROSHOP');
  assert.equal(list.statusCode, 200, JSON.stringify(list.body));
  assert.equal(list.body.orders.length, 1);
  const shown = list.body.orders[0];
  assert.equal(shown.orderId, orderId);
  assert.equal(shown.vendorName, 'Priya');
  assert.equal(shown.companyName, 'SRP');
  assert.equal(shown.paymentMethod, 'Cash on Delivery');
  assert.equal(shown.paymentStatus, 'due_on_delivery');
  // Same status as the Admin Panel (nothing supplied yet).
  assert.equal(shown.status, 'Processing & Dispatched');
  assert.deepEqual(shown.items.map(i => [i.name, i.quantity, i.unitPrice]), [
    ['RO Membrane 75 GPD', 3, 650],
    ['RO Filter Housing 10 Inch', 2, 290],
  ]);
  // SKU and category come from the catalogue, so the Shop App can show
  // each product's own picture.
  assert.deepEqual(shown.items.map(i => [i.sku, i.categoryKey]), [['SKU-P1', 'membranes'], ['SKU-P2', 'membranes']]);

  // Search, status and date filters.
  assert.equal((await t.shopOrders('ROSHOP', { search: 'Housing' })).body.orders.length, 1);
  assert.equal((await t.shopOrders('ROSHOP', { search: 'no-such-thing' })).body.orders.length, 0);
  assert.equal((await t.shopOrders('ROSHOP', { status: 'pending' })).body.orders.length, 1);
  assert.equal((await t.shopOrders('ROSHOP', { status: 'delivered' })).body.orders.length, 0);
  const istToday = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(new Date());
  assert.equal((await t.shopOrders('ROSHOP', { from: istToday, to: istToday })).body.orders.length, 1);

  // Partially deliver one product -> Partially Delivered filter.
  // Same payload shape as ShopEmployeeRepository.buildDeliveryItemsPayload.
  const delivery = await t.call('POST /api/shop/orders/:orderId/delivery', {
    headers: { authorization: `Bearer ${t.employees.ROSHOP}` },
    params: { orderId },
    body: {
      mode: 'confirm',
      cashCollected: false,
      items: [
        { orderItemId: Number(shown.items[0].id), deliveredQuantity: 3, deliveryConfirmed: true, deliveryStatus: 'delivered', delivered: true },
        { orderItemId: Number(shown.items[1].id), deliveredQuantity: 0, deliveryConfirmed: false, deliveryStatus: 'not_delivered', delivered: false },
      ],
    },
  });
  assert.equal(delivery.statusCode, 200, JSON.stringify(delivery.body));
  assert.equal((await t.shopOrders('ROSHOP', { status: 'partially delivered' })).body.orders.length, 1);
  assert.equal((await t.shopOrders('ROSHOP', { status: 'pending' })).body.orders.length, 0);
});

test('two shops: each sees only its own orders; retries never duplicate', async () => {
  const t = await setup();
  await t.addShop('IYYAN', 'ROSHOP');
  await t.addShop('ANNA', 'AQUA SHOP');
  process.env.SHOP_DEFAULT_NAME = 'ROSHOP';
  let first, second;
  try {
    const requestId = crypto.randomUUID();
    first = await t.placeOrder([{ id: 'P1', quantity: 1 }], { checkoutRequestId: requestId });
    const retry = await t.placeOrder([{ id: 'P1', quantity: 1 }], { checkoutRequestId: requestId });
    assert.equal(first.statusCode, 200, JSON.stringify(first.body));
    assert.equal(retry.body.idempotent, true);
    assert.equal(retry.body.order.orderId, first.body.order.orderId);
    second = await t.placeOrder([{ id: 'P2', quantity: 4 }]);
    assert.equal(second.body.assignedShopName, 'ROSHOP');
  } finally {
    delete process.env.SHOP_DEFAULT_NAME;
  }
  const [[{ count }]] = await t.query('SELECT COUNT(*)::int AS count FROM orders');
  assert.equal(count, 2, 'no duplicate order from the retry');

  // Admin moves the second order to the other shop.
  const moved = await t.call('PUT /api/admin/shop/orders/:orderId/assignment', {
    params: { orderId: second.body.order.orderId },
    body: { shopName: 'AQUA SHOP' },
  });
  assert.equal(moved.statusCode, 200, JSON.stringify(moved.body));

  const ro = await t.shopOrders('ROSHOP');
  const aqua = await t.shopOrders('AQUA SHOP');
  assert.deepEqual(ro.body.orders.map(o => o.orderId), [first.body.order.orderId]);
  assert.deepEqual(aqua.body.orders.map(o => o.orderId), [second.body.order.orderId]);

  // Overview and reports are scoped the same way.
  const roDash = await t.call('GET /api/shop/dashboard', { headers: { authorization: `Bearer ${t.employees.ROSHOP}` } });
  const aquaDash = await t.call('GET /api/shop/dashboard', { headers: { authorization: `Bearer ${t.employees['AQUA SHOP']}` } });
  assert.equal(roDash.body.metrics.todayOrders, 1);
  assert.equal(aquaDash.body.metrics.todayOrders, 1);
  const aquaReport = await t.call('GET /api/shop/reports', { headers: { authorization: `Bearer ${t.employees['AQUA SHOP']}` }, query: { period: 'product' } });
  assert.equal(aquaReport.statusCode, 200, JSON.stringify(aquaReport.body));
  assert.deepEqual(aquaReport.body.rows.map(r => r.product_name), ['RO Filter Housing 10 Inch']);

  // A shop cannot record delivery for another shop's order.
  const [[foreignItem]] = await t.query('SELECT id FROM order_items WHERE order_id = ?', [second.body.order.orderId]);
  const blocked = await t.call('POST /api/shop/orders/:orderId/delivery', {
    headers: { authorization: `Bearer ${t.employees.ROSHOP}` },
    params: { orderId: second.body.order.orderId },
    body: { mode: 'confirm', items: [{ orderItemId: Number(foreignItem.id), deliveredQuantity: 1, deliveryConfirmed: true, deliveryStatus: 'delivered', delivered: true }] },
  });
  assert.equal(blocked.statusCode, 404);
});

test('an order placed just after midnight IST counts as that IST day', async () => {
  const t = await setup();
  await t.addShop('IYYAN', 'ROSHOP');
  const placed = await t.placeOrder([{ id: 'P2', quantity: 1 }]);
  // 00:30 IST on 12 Nov 2026 = 19:00 UTC on 11 Nov (stored as UTC).
  await t.query(`UPDATE orders SET created_at = '2026-11-11 19:00:00' WHERE order_id = ?`, [placed.body.order.orderId]);
  assert.equal((await t.shopOrders('ROSHOP', { from: '2026-11-12', to: '2026-11-12' })).body.orders.length, 1);
  assert.equal((await t.shopOrders('ROSHOP', { from: '2026-11-11', to: '2026-11-11' })).body.orders.length, 0);
});

test('order status and payment status workflow: admin, Shop App and customer stay in step', async () => {
  const t = await setup();
  await t.addShop('IYYAN', 'ROSHOP');
  const placed = await t.placeOrder([{ id: 'P1', quantity: 3 }, { id: 'P2', quantity: 2 }]);
  const orderId = placed.body.order.orderId;
  const row = async () => (await t.query('SELECT status, payment_status FROM orders WHERE order_id = ?', [orderId]))[0][0];
  const shopView = async () => (await t.shopOrders('ROSHOP')).body.orders.find(o => o.orderId === orderId);
  assert.deepEqual({ ...await row() }, { status: 'Processing & Dispatched', payment_status: 'due_on_delivery' });
  const items = (await shopView()).items;

  // Admin: statuses must match what has been supplied (nothing yet).
  assert.equal((await t.admin.setStatus(orderId, 'Shipped')).statusCode, 400);
  assert.equal((await t.admin.setStatus(orderId, 'Delivered')).statusCode, 409);
  assert.equal((await t.admin.setStatus(orderId, 'Partially Delivered')).statusCode, 409);
  assert.equal((await t.admin.setStatus(orderId, 'pending')).statusCode, 200);
  assert.equal((await row()).status, 'Pending');
  assert.equal((await shopView()).status, 'Pending', 'admin change shows in the Shop App');
  assert.equal((await t.admin.setStatus(orderId, 'Processing & Dispatched')).statusCode, 200);
  assert.equal((await shopView()).status, 'Processing & Dispatched');

  // Shop: partial supply. Cash cannot be confirmed for a partial delivery.
  const partialWithCash = await t.supply('ROSHOP', orderId, [[items[0].id, 3], [items[1].id, 0]], true);
  assert.equal(partialWithCash.statusCode, 400);
  const partial = await t.supply('ROSHOP', orderId, [[items[0].id, 3], [items[1].id, 0]]);
  assert.equal(partial.statusCode, 200, JSON.stringify(partial.body));
  assert.equal(partial.body.status, 'Partially Delivered');
  assert.deepEqual({ ...await row() }, { status: 'Partially Delivered', payment_status: 'due_on_delivery' });
  assert.equal((await shopView()).status, 'Partially Delivered');
  assert.equal((await t.shopOrders('ROSHOP', { status: 'partially delivered' })).body.orders.length, 1);
  // Admin can no longer move it back or skip ahead.
  assert.equal((await t.admin.setStatus(orderId, 'Pending')).statusCode, 409);
  assert.equal((await t.admin.setStatus(orderId, 'Delivered')).statusCode, 409);

  // Payment is separate: a partial payment is recorded by the admin.
  assert.equal((await t.admin.setPayment(orderId, 'PARTIALLY_PAID')).statusCode, 200);
  assert.deepEqual({ ...await row() }, { status: 'Partially Delivered', payment_status: 'partially_paid' });

  // Shop: remaining units supplied -> Delivered; payment is NOT auto-paid.
  const full = await t.supply('ROSHOP', orderId, [[items[0].id, 3], [items[1].id, 2]]);
  assert.equal(full.statusCode, 200, JSON.stringify(full.body));
  assert.equal(full.body.status, 'Delivered');
  assert.deepEqual({ ...await row() }, { status: 'Delivered', payment_status: 'partially_paid' });
  assert.equal((await shopView()).status, 'Delivered');
  assert.equal((await t.admin.setStatus(orderId, 'Cancelled')).statusCode, 409, 'a delivered order cannot be cancelled');

  // Payment collected -> PAID.
  assert.equal((await t.admin.setPayment(orderId, 'paid')).statusCode, 200);
  assert.deepEqual({ ...await row() }, { status: 'Delivered', payment_status: 'paid' });
  assert.equal((await t.admin.setPayment(orderId, 'refunded')).statusCode, 400);

  // A cancelled order shows as Cancelled in the Shop App and cannot be supplied.
  const other = await t.placeOrder([{ id: 'P2', quantity: 1 }]);
  const otherId = other.body.order.orderId;
  assert.equal((await t.admin.setStatus(otherId, 'Cancelled')).statusCode, 200);
  const cancelledView = (await t.shopOrders('ROSHOP')).body.orders.find(o => o.orderId === otherId);
  assert.equal(cancelledView.status, 'Cancelled');
  assert.equal((await t.shopOrders('ROSHOP', { status: 'pending' })).body.orders.some(o => o.orderId === otherId), false);
  const blocked = await t.supply('ROSHOP', otherId, [[cancelledView.items[0].id, 1]]);
  assert.equal(blocked.statusCode, 409);
  assert.equal((await t.query('SELECT payment_status FROM orders WHERE order_id = ?', [otherId]))[0][0].payment_status, 'due_on_delivery');

  // Online (non-COD) payments are not editable here.
  await t.query("UPDATE orders SET payment_method = 'Razorpay', payment_status = 'paid' WHERE order_id = ?", [otherId]);
  assert.equal((await t.admin.setPayment(otherId, 'due_on_delivery')).statusCode, 409);
});

test('stock: orders take stock, never below zero; cancel returns only unsupplied units, once', async () => {
  const t = await setup();
  await t.addShop('IYYAN', 'ROSHOP');
  const stock = async id => (await t.query('SELECT stock_quantity FROM products WHERE id = ?', [id]))[0][0].stock_quantity;
  assert.equal(await stock('P1'), 100);

  const placed = await t.placeOrder([{ id: 'P1', quantity: 3 }, { id: 'P2', quantity: 2 }]);
  assert.equal(placed.statusCode, 200, JSON.stringify(placed.body));
  const orderId = placed.body.order.orderId;
  assert.equal(await stock('P1'), 97);
  assert.equal(await stock('P2'), 98);
  const [moves] = await t.query("SELECT product_id, quantity_change, reason FROM stock_movements WHERE order_id = ? ORDER BY product_id", [orderId]);
  assert.deepEqual(moves.map(m => [m.product_id, m.quantity_change, m.reason]), [['P1', -3, 'order_placed'], ['P2', -2, 'order_placed']]);

  // Not enough stock: refused, nothing saved, stock unchanged.
  const tooMany = await t.placeOrder([{ id: 'P1', quantity: 98 }]);
  assert.equal(tooMany.statusCode, 400, 'checkout quote refuses it first');
  await t.query('UPDATE products SET stock_quantity = 5 WHERE id = ?', ['P2']);
  // Bypass the quote check to prove the database update itself never goes negative.
  const { reserveOrderStock } = require('../stock_service');
  const conn = { query: t.query };
  await t.query("INSERT INTO orders (order_id, user_id, user_email, user_name, subtotal, discount, gst, delivery_fee, grand_total, payment_method, status, payment_status, delivery_address, invoice_number) VALUES ('RACE01', 'DEALER_1', 'priya@example.test', 'Priya', 0, 0, 0, 0, 0, 'Cash on Delivery', 'Pending', 'due_on_delivery', 'Chennai', 'INV-TEST-' || md5(random()::text))");
  await t.query("INSERT INTO order_items (order_id, product_id, product_name, brand, unit_price, quantity) VALUES ('RACE01', 'P2', 'RO Filter Housing 10 Inch', 'RO Wholesale', 290, 6)");
  await assert.rejects(() => reserveOrderStock(conn, 'RACE01'), /Not enough stock for RO Filter Housing 10 Inch: 5 left, 6 needed/);
  assert.equal(await stock('P2'), 5);
  await t.query('UPDATE products SET stock_quantity = 98 WHERE id = ?', ['P2']);

  // Partial supply (2 of 3 membranes, 0 of 2 housings), then cancel the rest.
  const items = (await t.shopOrders('ROSHOP')).body.orders.find(o => o.orderId === orderId).items;
  assert.equal((await t.supply('ROSHOP', orderId, [[items[0].id, 2], [items[1].id, 0]])).statusCode, 200);
  assert.equal(await stock('P1'), 97, 'supplying does not change stock again');
  const cancel = await t.admin.setStatus(orderId, 'Cancelled');
  assert.equal(cancel.statusCode, 200, JSON.stringify(cancel.body));
  assert.equal(cancel.body.stockReturned, 3, '1 membrane + 2 housings not supplied');
  assert.equal(await stock('P1'), 98);
  assert.equal(await stock('P2'), 100);
  // Cancelling again returns nothing more.
  assert.equal((await t.admin.setStatus(orderId, 'Cancelled')).body.stockReturned, 0);
  assert.equal(await stock('P1'), 98);

  // Re-opening takes the unsupplied units again.
  const reopen = await t.admin.setStatus(orderId, 'Partially Delivered');
  assert.equal(reopen.statusCode, 200, JSON.stringify(reopen.body));
  assert.equal(await stock('P1'), 97);
  assert.equal(await stock('P2'), 98);

  // An order placed before the ledger existed: cancelling it never adds stock.
  await t.query("INSERT INTO orders (order_id, user_id, user_email, user_name, subtotal, discount, gst, delivery_fee, grand_total, payment_method, status, payment_status, delivery_address, invoice_number) VALUES ('OLD001', 'DEALER_1', 'priya@example.test', 'Priya', 650, 0, 0, 0, 650, 'Cash on Delivery', 'Processing & Dispatched', 'due_on_delivery', 'Chennai', 'INV-TEST-' || md5(random()::text))");
  await t.query("INSERT INTO order_items (order_id, product_id, product_name, brand, unit_price, quantity) VALUES ('OLD001', 'P1', 'RO Membrane 75 GPD', 'RO Wholesale', 650, 4)");
  assert.equal((await t.admin.setStatus('OLD001', 'Cancelled')).body.stockReturned, 0);
  assert.equal(await stock('P1'), 97);
});

test('stock: without the ledger table (today\'s live database) stock is left unchanged', async () => {
  const t = await setup({ withStockLedger: false });
  await t.addShop('IYYAN', 'ROSHOP');
  const placed = await t.placeOrder([{ id: 'P1', quantity: 3 }]);
  assert.equal(placed.statusCode, 200);
  assert.equal((await t.query('SELECT stock_quantity FROM products WHERE id = ?', ['P1']))[0][0].stock_quantity, 100);
  assert.equal((await t.admin.setStatus(placed.body.order.orderId, 'Cancelled')).statusCode, 200);
  assert.equal((await t.query('SELECT stock_quantity FROM products WHERE id = ?', ['P1']))[0][0].stock_quantity, 100);
});

test('invoices, credit and support tickets use real data (no hard-coded values)', async () => {
  const t = await setup();
  await t.addShop('IYYAN', 'ROSHOP');
  const gst = await t.placeOrder([{ id: 'P1', quantity: 2 }, { id: 'P2', quantity: 1 }], { withGst: true, gstin: '33AAAAA0000A1Z9' });
  assert.equal(gst.statusCode, 200, JSON.stringify(gst.body));
  const cod = await t.placeOrder([{ id: 'P2', quantity: 1 }]);
  const cancelled = await t.placeOrder([{ id: 'P1', quantity: 1 }]);
  await t.admin.setStatus(cancelled.body.order.orderId, 'Cancelled');

  const invoices = async () => (await t.call('GET /api/user/gst-invoices', { query: { email: 'priya@example.test' } })).body;
  delete process.env.DEALER_CREDIT_LIMIT;
  let body = await invoices();
  assert.equal(body.creditLimit, null, 'no invented credit limit');
  assert.equal(body.availableCredit, null);
  const [[{ total }]] = await t.query('SELECT SUM(grand_total) AS total FROM orders WHERE order_id IN (?, ?)', [gst.body.order.orderId, cod.body.order.orderId]);
  assert.equal(body.outstandingAmount, Number(total), 'unpaid, non-cancelled orders');
  assert.equal(body.invoices.length, 1);
  assert.equal(body.invoices[0].itemsSummary, 'RO Membrane 75 GPD × 2, RO Filter Housing 10 Inch × 1');
  assert.match(body.invoices[0].date, /^[A-Z][a-z]{2} \d{1,2}, \d{4}$/);
  assert.notEqual(body.invoices[0].date, 'Sep 18, 2026');

  process.env.DEALER_CREDIT_LIMIT = '100000';
  try {
    body = await invoices();
    assert.equal(body.creditLimit, 100000);
    assert.equal(body.availableCredit, 100000 - Number(total));
    // Paying an order frees its credit.
    await t.admin.setPayment(cod.body.order.orderId, 'paid');
    const [[{ g }]] = await t.query('SELECT grand_total AS g FROM orders WHERE order_id = ?', [gst.body.order.orderId]);
    assert.equal((await invoices()).availableCredit, 100000 - Number(g));
  } finally {
    delete process.env.DEALER_CREDIT_LIMIT;
  }

  const ticket = await t.call('POST /api/user/support-ticket', { body: { email: 'priya@example.test', message: 'Need a membrane', subject: 'Stock' } });
  assert.equal(ticket.statusCode, 200, JSON.stringify(ticket.body));
  const year = new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', year: 'numeric' }).format(new Date());
  assert.match(ticket.body.ticketId, new RegExp(`^TKT-${year}-\\d+$`));
});
