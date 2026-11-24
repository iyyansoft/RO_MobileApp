// Deployment readiness: the new backend must work BOTH on the live database
// as it is today (no shop_order_assignments / product_images /
// stock_movements) AND after the Phase 1 migration adds them.
//
// Every Shop App endpoint, the admin shop endpoints and the customer order
// flow are exercised in both states against a real (in-memory) PostgreSQL
// built from the project's own schema files.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const bcrypt = require('bcryptjs');
const { PGlite } = require('@electric-sql/pglite');
const { citext } = require('@electric-sql/pglite/contrib/citext');
const { toPostgresPlaceholders, adaptResult, normalizeDatabaseError } = require('../db');
const { createDealerToken } = require('../checkout_service');
const { signEmployeeToken } = require('../shop_service');
const orderStatus = require('../order_status');
const stockService = require('../stock_service');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const SECRET = 'deployment-readiness-secret';
const EMPLOYEE_SECRET = 'deployment-readiness-employee';
const PHASE1 = [
  'supabase/staging/008_shop_order_assignments.sql',
  'supabase/staging/006_product_images.sql',
  'supabase/staging/007_stock_movements.sql',
];

/**
 * @param migrated false = today's live database, true = after Phase 1.
 */
async function backend({ migrated }) {
  const db = new PGlite({ extensions: { citext } });
  await db.exec(read('supabase_migration.sql'));
  await db.exec(read('shop_app_migration.sql'));
  // Today's live state: the assignment table was never created.
  if (!migrated) await db.exec('DROP TABLE public.shop_order_assignments');
  if (migrated) for (const file of PHASE1) await db.exec(read(file));

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
  const app = {};
  for (const method of ['get', 'post', 'put', 'delete', 'patch']) {
    app[method] = (p, ...handlers) => routes.set(`${method.toUpperCase()} ${p}`, handlers);
  }
  const findUser = async email => {
    const row = (await query('SELECT * FROM users WHERE email = ?', [email]))[0][0];
    return row && { ...row, business: row.business_name };
  };
  const quiet = console.error;
  console.error = () => {};
  require('../order_checkout')(app, pool, SECRET, findUser);
  require('../shop_routes')(app, pool, EMPLOYEE_SECRET, (req, res, next) => next());
  const server = read('server.js');
  vm.runInNewContext(
    server.slice(server.indexOf('async function orderSupplyTotals('), server.indexOf("app.get('/api/admin/dashboard-stats'")),
    { app, pool, requireAdminAuth: (req, res, next) => next(), console: { error() {} }, ...orderStatus, ...stockService, ...require('../rewards') },
  );
  console.error = quiet;

  const call = async (key, { body = {}, query: q = {}, params = {}, headers = {} } = {}) => {
    const handlers = routes.get(key);
    assert.ok(handlers, `route ${key} is registered`);
    const res = {
      statusCode: 200, body: null, headers: {},
      status(c) { this.statusCode = c; return this; },
      json(b) { this.body = b; return this; },
      set() { return this; }, setHeader() { return this; },
    };
    const req = { body, query: q, params, headers, ip: '127.0.0.1', socket: {} };
    let i = 0;
    const next = async () => { const h = handlers[i++]; if (h) await h(req, res, next); };
    const original = console.error;
    console.error = () => {};
    try { await next(); } finally { console.error = original; }
    return res;
  };

  // Catalogue, dealer and one shop employee.
  await query(`INSERT INTO categories (id, key_name, title, display_order) VALUES ('CAT_MEM', 'membranes', 'Membranes', 1)`);
  for (const [id, name, price] of [['P1', 'RO Membrane 75 GPD', 650], ['P2', 'RO Filter Housing 10 Inch', 290]]) {
    await query(`INSERT INTO products (id, category_id, category_key, sku, name, brand, price, mrp, status, stock_quantity)
      VALUES (?, 'CAT_MEM', 'membranes', ?, ?, 'RO Wholesale', ?, ?, 'active', 50)`, [id, `SKU-${id}`, name, price, price * 1.4]);
  }
  await query(`INSERT INTO users (id, email, name, business_name, password_hash, email_verified, status, is_approved)
    VALUES ('DEALER_1', 'priya@example.test', 'Priya', 'SRP', 'x', TRUE, 'approved', TRUE)`);
  const dealerToken = createDealerToken({ id: 'DEALER_1', email: 'priya@example.test' }, SECRET);
  const employeeId = crypto.randomUUID();
  await query(`INSERT INTO shop_employees (id, employee_id, shop_name, full_name, password_hash, active)
    VALUES (?, 'IYYAN', 'ROSHOP', 'Iyyan', ?, TRUE)`, [employeeId, await bcrypt.hash('shop-password', 8)]);
  const employeeToken = signEmployeeToken({ id: employeeId, employee_id: 'IYYAN', shop_name: 'ROSHOP', full_name: 'Iyyan' }, EMPLOYEE_SECRET);
  const shop = (key, options = {}) => call(key, { ...options, headers: { authorization: `Bearer ${employeeToken}` } });

  return { db, query, call, shop, dealerToken, employeeToken, employeeId };
}

for (const migrated of [false, true]) {
  const label = migrated ? 'after the Phase 1 migration' : "on today's live database";

  test(`every Shop App endpoint works ${label}`, async () => {
    const t = await backend({ migrated });

    // Employee sign-in and session.
    const login = await t.call('POST /api/shop/auth/login', { body: { loginId: 'IYYAN', password: 'shop-password' } });
    assert.equal(login.statusCode, 200, JSON.stringify(login.body));
    assert.equal(login.body.employee.shopName, 'ROSHOP');
    const session = await t.call('GET /api/shop/auth/session', { headers: { authorization: `Bearer ${login.body.token}` } });
    assert.equal(session.statusCode, 200);
    assert.equal(session.body.employee.loginId, 'IYYAN');
    assert.equal((await t.call('GET /api/shop/orders')).statusCode, 401, 'still requires a session');

    // A customer places an order.
    const placed = await t.call('POST /api/user/orders/create', {
      headers: { authorization: `Bearer ${t.dealerToken}` },
      body: {
        email: 'priya@example.test', paymentMethod: 'Cash on Delivery',
        deliveryAddress: { line1: '12 Main Road', city: 'Chennai', pincode: '600001' },
        items: [{ id: 'P1', quantity: 2 }, { id: 'P2', quantity: 1 }],
      },
    });
    assert.equal(placed.statusCode, 200, JSON.stringify(placed.body));
    const orderId = placed.body.order.orderId;
    assert.equal(placed.body.assignedShopName, 'ROSHOP');

    // Current Orders, with search / status / date filters.
    const orders = await t.shop('GET /api/shop/orders');
    assert.equal(orders.statusCode, 200, JSON.stringify(orders.body));
    const shown = orders.body.orders.find(o => o.orderId === orderId);
    assert.ok(shown, 'the new order is listed');
    assert.equal(shown.vendorName, 'Priya');
    assert.deepEqual(shown.items.map(i => [i.name, i.quantity, i.unitPrice, i.sku, i.categoryKey]), [
      ['RO Membrane 75 GPD', 2, 650, 'SKU-P1', 'membranes'],
      ['RO Filter Housing 10 Inch', 1, 290, 'SKU-P2', 'membranes'],
    ]);
    const istToday = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(new Date());
    for (const [name, q, expected] of [
      ['search hit', { search: 'Membrane' }, 1],
      ['search miss', { search: 'no-such-product' }, 0],
      // In the Shop App "Pending" means nothing supplied yet, so a newly
      // dispatched order belongs there (its badge shows the order status).
      ['status pending', { status: 'pending' }, 1],
      ['status delivered', { status: 'delivered' }, 0],
      ['today', { from: istToday, to: istToday }, 1],
    ]) {
      const res = await t.shop('GET /api/shop/orders', { query: q });
      assert.equal(res.statusCode, 200, `${name}: ${JSON.stringify(res.body)}`);
      assert.equal(res.body.orders.length, expected, name);
    }
    assert.equal((await t.shop('GET /api/shop/orders', { query: { from: 'bad-date' } })).statusCode, 400);

    // Overview, products, categories, enquiries, reports.
    const dashboard = await t.shop('GET /api/shop/dashboard');
    assert.equal(dashboard.statusCode, 200, JSON.stringify(dashboard.body));
    assert.equal(dashboard.body.metrics.todayOrders, 1);
    assert.equal(dashboard.body.shop.name, 'ROSHOP');

    const products = await t.shop('GET /api/shop/products', { query: { search: 'Membrane' } });
    assert.equal(products.statusCode, 200, JSON.stringify(products.body));
    assert.equal(products.body.products.length, 1);
    assert.equal((await t.shop('GET /api/shop/categories')).body.categories.length, 1);

    const enquiry = await t.shop('POST /api/shop/enquiries', {
      body: { customerName: 'Karthik', companyName: 'KT Traders', contactNumber: '9876543210', category: 'Membranes', productName: 'RO Membrane 100 GPD', requiredQuantity: 5, remarks: 'urgent' },
    });
    assert.equal(enquiry.statusCode, 201, JSON.stringify(enquiry.body));
    assert.equal((await t.call('GET /api/admin/shop/enquiries')).body.enquiries.length, 1);

    const report = await t.shop('GET /api/shop/reports', { query: { period: 'daily' } });
    assert.equal(report.statusCode, 200, JSON.stringify(report.body));

    // Supply: partial, then full. Quantities, status and payment rules.
    const items = shown.items.map(i => Number(i.id));
    const supply = (lines, cashCollected = false) => t.shop('POST /api/shop/orders/:orderId/delivery', {
      params: { orderId },
      body: {
        mode: 'confirm', cashCollected,
        items: lines.map(([id, quantity]) => ({
          orderItemId: id, deliveredQuantity: quantity, deliveryConfirmed: quantity > 0,
          deliveryStatus: quantity > 0 ? 'delivered' : 'not_delivered', delivered: quantity > 0,
        })),
      },
    });
    const partial = await supply([[items[0], 2], [items[1], 0]]);
    assert.equal(partial.statusCode, 200, JSON.stringify(partial.body));
    assert.equal(partial.body.status, 'Partially Delivered');
    assert.equal(partial.body.paymentStatus, 'due_on_delivery', 'COD is never auto-paid');
    assert.equal((await t.shop('GET /api/shop/orders', { query: { status: 'partially delivered' } })).body.orders.length, 1);
    const notifications = await t.call('GET /api/admin/shop/notifications');
    assert.equal(notifications.statusCode, 200);
    assert.equal(notifications.body.notifications.length, 1, 'short supply notifies the admin');

    const full = await supply([[items[0], 2], [items[1], 1]], true);
    assert.equal(full.statusCode, 200, JSON.stringify(full.body));
    assert.equal(full.body.status, 'Delivered');
    assert.equal(full.body.cashCollected, true, 'explicit cash confirmation');
    const [[order]] = await t.query('SELECT status, payment_status FROM orders WHERE order_id = ?', [orderId]);
    assert.deepEqual({ ...order }, { status: 'Delivered', payment_status: 'paid' });

    // Admin shop endpoints.
    assert.equal((await t.call('GET /api/admin/shop/employees')).body.employees.length, 1);
    const created = await t.call('POST /api/admin/shop/employees', {
      body: { shopName: 'AQUA SHOP', loginId: 'ANNA', password: 'another-strong-password', fullName: 'Anna' },
    });
    assert.equal(created.statusCode, 201, JSON.stringify(created.body));
    assert.equal((await t.call('PUT /api/admin/shop/employees/:id/active', { params: { id: created.body.employee.id }, body: { active: false } })).statusCode, 200);
  });

  test(`admin order status and payment endpoints work ${label}`, async () => {
    const t = await backend({ migrated });
    const placed = await t.call('POST /api/user/orders/create', {
      headers: { authorization: `Bearer ${t.dealerToken}` },
      body: {
        email: 'priya@example.test', paymentMethod: 'Cash on Delivery',
        deliveryAddress: { line1: '12 Main Road', city: 'Chennai' },
        items: [{ id: 'P1', quantity: 2 }],
      },
    });
    const orderId = placed.body.order.orderId;
    const setStatus = status => t.call('PUT /api/admin/orders/:id/status', { params: { id: orderId }, body: { status } });

    assert.equal((await setStatus('Delivered')).statusCode, 409, 'nothing supplied yet');
    assert.equal((await setStatus('Pending')).statusCode, 200);
    assert.equal((await t.call('PUT /api/admin/orders/:id/payment-status', { params: { id: orderId }, body: { paymentStatus: 'partially_paid' } })).statusCode, 200);

    // Cancelling returns stock only where the ledger exists.
    const stock = async () => Number((await t.query('SELECT stock_quantity FROM products WHERE id = ?', ['P1']))[0][0].stock_quantity);
    assert.equal(await stock(), migrated ? 48 : 50, migrated ? 'ordered units are held' : 'stock untouched without the ledger');
    const cancelled = await setStatus('Cancelled');
    assert.equal(cancelled.statusCode, 200, JSON.stringify(cancelled.body));
    assert.equal(cancelled.body.stockReturned, migrated ? 2 : 0);
    assert.equal(await stock(), 50);
    const [[order]] = await t.query('SELECT status, payment_status FROM orders WHERE order_id = ?', [orderId]);
    assert.deepEqual({ ...order }, { status: 'Cancelled', payment_status: 'partially_paid' }, 'payment untouched by cancellation');
  });
}

test('with two shops: assignment is required, and only works after the migration', async () => {
  for (const migrated of [false, true]) {
    const t = await backend({ migrated });
    await t.query(`INSERT INTO shop_employees (id, employee_id, shop_name, full_name, password_hash, active)
      VALUES (?, 'ANNA', 'AQUA SHOP', 'Anna', 'x', TRUE)`, [crypto.randomUUID()]);
    const order = () => t.call('POST /api/user/orders/create', {
      headers: { authorization: `Bearer ${t.dealerToken}` },
      body: {
        email: 'priya@example.test', paymentMethod: 'Cash on Delivery',
        deliveryAddress: { line1: '12 Main Road' }, items: [{ id: 'P1', quantity: 1 }],
      },
    });
    if (!migrated) {
      // Today's database: a second shop cannot be served at all.
      assert.equal((await order()).statusCode, 503, 'checkout refuses rather than mis-routing');
      assert.equal((await t.shop('GET /api/shop/orders')).statusCode, 503);
      continue;
    }
    process.env.SHOP_DEFAULT_NAME = 'ROSHOP';
    try {
      const placed = await order();
      assert.equal(placed.statusCode, 200, JSON.stringify(placed.body));
      assert.equal(placed.body.assignedShopName, 'ROSHOP');
      assert.equal((await t.shop('GET /api/shop/orders')).body.orders.length, 1, 'ROSHOP sees it');
      const moved = await t.call('PUT /api/admin/shop/orders/:orderId/assignment', {
        params: { orderId: placed.body.order.orderId }, body: { shopName: 'AQUA SHOP' },
      });
      assert.equal(moved.statusCode, 200, JSON.stringify(moved.body));
      assert.equal((await t.shop('GET /api/shop/orders')).body.orders.length, 0, 'no longer ROSHOP\'s');
    } finally {
      delete process.env.SHOP_DEFAULT_NAME;
    }
  }
});

test('product images: database store is used once the table exists, disk before that', async () => {
  for (const migrated of [false, true]) {
    const t = await backend({ migrated });
    const server = read('server.js');
    const context = {
      pool: { query: t.query }, process, Date, Buffer, crypto, console: { error() {} },
      saveUploadedFile: () => '/uploads/disk_image.png',
      productImageProblem: require('../storage_images').productImageProblem,
      path: require('node:path'), fs: require('node:fs'), __dirname: root,
    };
    vm.runInNewContext(
      server.slice(server.indexOf('let productImageTableCheck'), server.indexOf('// Helper: Secure OTP Hash')),
      context,
    );
    const stored = await context.storeProductImage(`data:image/png;base64,${Buffer.from([137, 80, 78, 71]).toString('base64')}`);
    if (migrated) {
      assert.match(stored, /^\/api\/product-images\/img_\d+_[0-9a-f]+\.png$/, 'kept in the shared database');
      const [[row]] = await t.query('SELECT content_type FROM product_images');
      assert.equal(row.content_type, 'image/png');
    } else {
      assert.equal(stored, '/uploads/disk_image.png', 'unchanged behaviour before the migration');
    }
  }
});
