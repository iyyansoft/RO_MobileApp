const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const bcrypt = require('bcryptjs');
const { signEmployeeToken, verifyEmployeeToken, allocateDeliveryValues } = require('../shop_service');
const installShopRoutes = require('../shop_routes');

async function withServer(app, callback) {
  const server = await new Promise(resolve => {
    const instance = app.listen(0, '127.0.0.1', () => resolve(instance));
  });
  try { return await callback(`http://127.0.0.1:${server.address().port}`); }
  finally { await new Promise(resolve => server.close(resolve)); }
}

test('employee tokens are role-scoped, signed and expire', () => {
  const employee = { id: 'staff-id', employee_id: 'SHOP-001' };
  const token = signEmployeeToken(employee, 'test-secret', 1_000_000);
  assert.equal(verifyEmployeeToken(token, 'test-secret', 1_000_001).role, 'shop_employee');
  assert.equal(verifyEmployeeToken(`${token}x`, 'test-secret', 1_000_001), null);
  assert.equal(verifyEmployeeToken(token, 'other-secret', 1_000_001), null);
  assert.equal(verifyEmployeeToken(token, 'test-secret', 50_000_000), null);
});

test('delivery allocation reconciles discount and GST to order item values', () => {
  const result = allocateDeliveryValues([
    { unit_price: 400, quantity: 1, delivered: true },
    { unit_price: 300, quantity: 2, delivered: false },
  ], { subtotal: 1000, discount: 100, gst: 171 });
  assert.equal(result.deliveredValue, 400);
  assert.equal(result.refundAmount, 600);
  assert.equal(result.deliveredValue + result.refundAmount, 1000);
});

test('partial actual quantities allocate dealer price value and enforce quantity bounds', () => {
  const result = allocateDeliveryValues([
    { unit_price: 500, quantity: 2, deliveredQuantity: 1 },
    { unit_price: 125, quantity: 4, deliveredQuantity: 0 },
  ]);
  assert.equal(result.allocated[0].deliveredValue, 500);
  assert.equal(result.allocated[0].refundValue, 500);
  assert.equal(result.allocated[1].refundValue, 500);
  assert.equal(result.deliveredValue, 500);
  assert.equal(result.refundAmount, 1000);
  assert.equal(result.totalDeliveredQuantity, 1);
  assert.equal(result.totalQuantity, 6);
});

test('employee login uses stored bcrypt credentials and employee role token', async () => {
  const secret = 'route-test-secret';
  const hash = await bcrypt.hash('a-long-test-password', 4);
  const employee = { id: 'staff-id', employee_id: 'SHOP-001', shop_name: 'RO Test Shop', full_name: 'Shop Staff', password_hash: hash, active: true };
  const pool = { query: async sql => [[sql.includes('SELECT active') ? employee : employee]] };
  const app = express(); app.use(express.json()); installShopRoutes(app, pool, secret, (_req, res) => res.status(401).json({ success: false }));
  await withServer(app, async base => {
    const denied = await fetch(`${base}/api/shop/dashboard`);
    assert.equal(denied.status, 401);
    const response = await fetch(`${base}/api/shop/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ loginId: 'shop-001', password: 'a-long-test-password' }) });
    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.employee.role, 'shop_employee');
    assert.equal(payload.employee.shopName, 'RO Test Shop');
    assert.equal(verifyEmployeeToken(payload.token, secret).sub, 'staff-id');
    const adminOnly = await fetch(`${base}/api/admin/shop/employees`, { headers: { Authorization: `Bearer ${payload.token}` } });
    assert.equal(adminOnly.status, 401);
    const wrong = await fetch(`${base}/api/shop/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ employeeId: 'SHOP-001', password: 'incorrect' }) });
    assert.equal(wrong.status, 401);
  });
});

test('admin-created shop credentials authenticate and return the associated shop; duplicates are rejected', async () => {
  let inserted;
  let employee;
  const pool = {
    async query(sql, values = []) {
      if (sql.includes('INSERT INTO shop_employees')) {
        if (employee && employee.employee_id === values[1]) {
          const duplicate = new Error('duplicate'); duplicate.code = 'ER_DUP_ENTRY'; throw duplicate;
        }
        inserted = values;
        employee = { id: values[0], employee_id: values[1], shop_name: values[2], full_name: values[3], password_hash: values[4], active: true };
        return [{ affectedRows: 1 }];
      }
      if (sql.startsWith('SELECT id, employee_id, shop_name, full_name, password_hash')) return [[employee]];
      if (sql.startsWith('SELECT active, shop_name')) return [[employee]];
      if (sql.includes('COALESCE(SUM(CASE WHEN o.created_at::date')) return [[{ today_sales: 0, monthly_sales: 0, today_orders: 0, new_enquiries: 0 }]];
      if (sql.includes('UPDATE shop_employees')) return [{ affectedRows: 1 }];
      throw new Error('Unexpected query in mock.');
    },
  };
  const app = express(); app.use(express.json());
  installShopRoutes(app, pool, 'test-secret', (req, res, next) => req.headers.authorization === 'Bearer admin-token' ? next() : res.status(401).json({ success: false }));
  await withServer(app, async base => {
    const staffToken = signEmployeeToken({ id: 'employee-id', employee_id: 'SHOP-STAFF' }, 'test-secret');
    const denied = await fetch(`${base}/api/admin/shop/employees`, { headers: { Authorization: `Bearer ${staffToken}` } });
    assert.equal(denied.status, 401);
    const body = { shopName: 'Blue RO Store', loginId: 'blue_store', password: 'strong-test-password-42' };
    const created = await fetch(`${base}/api/admin/shop/employees`, { method: 'POST', headers: { Authorization: 'Bearer admin-token', 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    assert.equal(created.status, 201);
    const payload = await created.json();
    assert.equal(payload.employee.loginId, 'BLUE_STORE');
    assert.equal(payload.employee.shopName, body.shopName);
    assert.equal(Object.hasOwn(payload, 'generatedPassword'), false);
    assert.equal(await bcrypt.compare(body.password, inserted[4]), true);
    assert.notEqual(inserted[4], body.password);
    const login = await fetch(`${base}/api/shop/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ loginId: body.loginId, password: body.password }) });
    assert.equal(login.status, 200);
    const session = await login.json();
    assert.equal(session.employee.shopName, body.shopName);
    const dashboard = await fetch(`${base}/api/shop/dashboard`, { headers: { Authorization: `Bearer ${session.token}` } });
    assert.equal((await dashboard.json()).shop.name, body.shopName);
    const duplicate = await fetch(`${base}/api/admin/shop/employees`, { method: 'POST', headers: { Authorization: 'Bearer admin-token', 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    assert.equal(duplicate.status, 409);
  });
});

test('shop enquiry is validated and persisted for the admin workspace', async () => {
  let insertValues;
  const pool = {
    async query(sql, values = []) {
      if (sql.startsWith('SELECT active, shop_name')) return [[{ active: true, shop_name: 'Example Shop', full_name: 'Employee', employee_id: 'SHOP-STAFF' }]];
      if (sql.includes('INSERT INTO shop_product_enquiries')) { insertValues = values; return [{ affectedRows: 1 }]; }
      throw new Error('Unexpected query in mock.');
    },
  };
  const app = express(); app.use(express.json()); installShopRoutes(app, pool, 'test-secret', (_req, res) => res.status(401).json({ success: false }));
  const token = signEmployeeToken({ id: 'employee-id', employee_id: 'SHOP-STAFF' }, 'test-secret');
  await withServer(app, async base => {
    const response = await fetch(`${base}/api/shop/enquiries`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ customerName: 'Vendor Example', companyName: 'Example Supplies', contactNumber: '9876543210', category: 'Membranes', productName: '4040 membrane', requiredQuantity: 12, remarks: 'Next week' }) });
    assert.equal(response.status, 201);
    const payload = await response.json();
    assert.equal(payload.success, true);
    assert.equal(insertValues[6], '4040 membrane');
    assert.equal(insertValues[7], 12);
    const invalid = await fetch(`${base}/api/shop/enquiries`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ customerName: '', requiredQuantity: -1 }) });
    assert.equal(invalid.status, 400);
  });
});

test('current orders returns assigned real order lines and server-side date/search filters', async () => {
  const token = signEmployeeToken({ id: 'staff-id', employee_id: 'SHOP-001', shop_name: 'Priya Shop' }, 'test-secret');
  const order = { order_id: 'RO-500', user_name: 'Priya Enterprises', user_business: 'Priya Supplies', user_email: 'vendor@example.invalid', created_at: '2026-10-15T10:00:00Z', payment_status: 'paid', payment_method: 'COD', grand_total: 1300, subtotal: 1300, discount: 0, gst: 0, status: 'Processing' };
  let assignmentAvailable = true;
  let confirmationColumnAvailable = true;
  let orderListSql = '';
  const pool = {
    async query(sql, values = []) {
      if (sql.includes("to_regclass('public.shop_order_assignments')")) return [[{ available: assignmentAvailable }]];
      if (sql.includes('information_schema.columns')) return [[{ available: confirmationColumnAvailable }]];
      if (sql.includes('COUNT(DISTINCT lower(shop_name))')) return [[{ shop_count: 1, matching_shop_count: 1 }]];
      if (sql.includes('SELECT active, shop_name')) return [[{ active: true, shop_name: 'Priya Shop', full_name: 'Staff', employee_id: 'SHOP-001' }]];
      if (sql.includes('FROM orders o JOIN order_items oi')) {
        orderListSql = sql;
        if (values[0] === '%Priya%') {
          assert.equal(values[2], '2026-10-15');
          assert.equal(values[3], '2026-10-15');
        } else {
          assert.equal(values[0], '%%');
        }
        if (values.length >= 5) assert.equal(values[4], 'Priya Shop');
        if (values.length === 6) assert.equal(values[5], 'Priya Shop');
        return [[order]];
      }
      if (sql.includes('SELECT oi.id::text AS id')) return [[
        { id: '51', product_id: 7, product_name: 'RO Membrane', sku: 'MEM-1', unit_price: 500, quantity: 2, delivered: false, delivery_confirmed: true, delivered_quantity: 1, undelivered_quantity: 1, img_src: '', delivered_at: null },
        { id: '52', product_id: 8, product_name: 'Filter', sku: 'FIL-1', unit_price: 300, quantity: 1, delivered: false, delivered_quantity: 0, undelivered_quantity: 1, img_src: '', delivered_at: null },
        { id: '53', product_id: 9, product_name: 'Pipes', sku: 'PIPE-1', unit_price: 80, quantity: 3, delivered: false, delivered_quantity: 0, undelivered_quantity: 3, img_src: '', delivered_at: null },
      ]];
      throw new Error(`Unexpected order-list query: ${sql}`);
    },
  };
  const app = express(); app.use(express.json());
  installShopRoutes(app, pool, 'test-secret', (_req, res) => res.status(401).json({ success: false }));
  await withServer(app, async base => {
    const response = await fetch(`${base}/api/shop/orders?search=Priya&from=2026-10-15&to=2026-10-15`, { headers: { Authorization: `Bearer ${token}` } });
    assert.equal(response.status, 200);
    const data = await response.json();
    assert.equal(data.orders.length, 1);
    const found = data.orders[0];
    assert.equal(found.vendorName, 'Priya Enterprises');
    assert.equal(found.companyName, 'Priya Supplies');
    assert.equal(found.status, 'Partially Delivered');
    assert.equal(found.items.length, 3);
    assert.deepEqual(found.items.map(item => item.name), ['RO Membrane', 'Filter', 'Pipes']);
    assert.deepEqual(found.items.map(item => item.quantity), [2, 1, 3]);
    assert.deepEqual(found.items.map(item => item.unitPrice), [500, 300, 80]);
    assert.equal(found.items[0].unitPrice, 500);
    assert.equal(found.items[0].quantity, 2);
    assert.equal(found.items[0].deliveredQuantity, 1);
    assert.equal(found.items[0].lineValue, 1000);
    assert.equal(found.items[0].deliveredAmount, 500);
    assert.match(orderListSql, /NOT EXISTS \(SELECT 1 FROM shop_order_assignments/);
    const badDate = await fetch(`${base}/api/shop/orders?from=tomorrow`, { headers: { Authorization: `Bearer ${token}` } });
    assert.equal(badDate.status, 400);
    assignmentAvailable = false;
    confirmationColumnAvailable = false;
    const singleShopFallback = await fetch(`${base}/api/shop/orders`, { headers: { Authorization: `Bearer ${token}` } });
    assert.equal(singleShopFallback.status, 200);
    assert.equal((await singleShopFallback.json()).orders.length, 1);
    assert.match(orderListSql, /COALESCE\(sd\.delivered, FALSE\)/);
    assert.doesNotMatch(orderListSql, /sd\.delivery_confirmed/);
  });
});

test('admin can assign only existing orders to an active shop and clear assignments', async () => {
  const writes = [];
  const pool = {
    async query(sql, values = []) {
      if (sql.includes('SELECT order_id FROM orders')) return [[{ order_id: 'RO-500' }]];
      if (sql.includes("to_regclass('public.shop_order_assignments')")) return [[{ available: true }]];
      if (sql.includes('SELECT id FROM shop_employees')) return values[0] === 'Enabled Shop' ? [[{ id: 'staff-id' }]] : [[]];
      if (sql.includes('INSERT INTO shop_order_assignments')) { writes.push({ sql, values }); return [{ affectedRows: 1 }]; }
      if (sql.includes('DELETE FROM shop_order_assignments')) { writes.push({ sql, values }); return [{ affectedRows: 1 }]; }
      throw new Error(`Unexpected assignment query: ${sql}`);
    },
  };
  const app = express(); app.use(express.json());
  installShopRoutes(app, pool, 'test-secret', (req, res, next) => req.headers.authorization === 'Bearer admin' ? next() : res.status(401).json({ success: false }));
  await withServer(app, async base => {
    const assign = body => fetch(`${base}/api/admin/shop/orders/RO-500/assignment`, { method: 'PUT', headers: { Authorization: 'Bearer admin', 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    assert.equal((await assign({ shopName: 'Disabled Shop' })).status, 400);
    assert.equal((await assign({ shopName: 'Enabled Shop' })).status, 200);
    assert.equal(writes.length, 1);
    assert.equal(writes[0].values[1], 'Enabled Shop');
    assert.equal((await assign({ shopName: '' })).status, 200);
    assert.equal(writes.length, 2);
  });
});

test('partial delivery saves quantities, reconciles dealer prices and notifies admin once', async () => {
  const employeeId = 'staff-id';
  const secret = 'route-test-secret';
  const token = signEmployeeToken({ id: employeeId, employee_id: 'SHOP-001', shop_name: 'RO Shop' }, secret);
  const items = [
    { id: 11, unit_price: 500, quantity: 2 },
    { id: 12, unit_price: 125, quantity: 4 },
  ];
  const saved = new Map();
  let notificationCount = 0;
  let paymentStatus = 'due_on_delivery';
  let assignmentAvailable = true;
  const events = [];
  let orderAssigned = true;
  const connection = {
    async beginTransaction() { events.push('begin'); },
    async commit() { events.push('commit'); },
    async rollback() { events.push('rollback'); },
    release() { events.push('release'); },
    async query(sql, values = []) {
      if (sql.includes("to_regclass('public.shop_order_assignments')")) return [[{ available: assignmentAvailable }]];
      if (sql.includes('information_schema.columns')) return [[{ available: true }]];
      if (sql.includes('COUNT(DISTINCT lower(shop_name))')) return [[{ shop_count: 1, matching_shop_count: 1 }]];
      if (sql.includes('FROM orders o JOIN shop_order_assignments')) return orderAssigned && values[1] === 'RO Shop' ? [[{ order_id: 'RO-1', subtotal: 1500, discount: 0, gst: 0, payment_method: 'Cash on Delivery', payment_status: paymentStatus }]] : [[]];
      if (sql.includes('FROM orders o WHERE o.order_id')) return orderAssigned && (values[1] === 'RO Shop' || values[2] === 'RO Shop') ? [[{ order_id: 'RO-1', subtotal: 1500, discount: 0, gst: 0, payment_method: 'Cash on Delivery', payment_status: paymentStatus }]] : [[]];
      if (sql.includes('SELECT id, unit_price, quantity FROM order_items')) return [items];
      if (sql.includes('SELECT order_item_id, delivered_quantity')) {
        return [[...saved.entries()].map(([order_item_id, row]) => ({ order_item_id, ...row }))];
      }
      if (sql.includes('INSERT INTO shop_delivery_items')) {
        const previous = saved.get(Number(values[0]));
        const refund_status = previous?.refund_status === 'refunded' && values[6] > 0 ? 'refunded' : values[7];
        saved.set(Number(values[0]), { delivered: values[2], delivered_quantity: values[3], undelivered_quantity: values[4], delivered_amount: values[5], refund_amount: values[6], refund_status, delivery_confirmed: values[10] });
        events.push({ delivery: values });
        return [{ affectedRows: 1 }];
      }
      if (sql.includes('SELECT oi.id, oi.unit_price')) {
        return [[...items.map(item => ({ ...item, delivered_quantity: saved.get(item.id)?.delivered_quantity || 0, delivery_confirmed: saved.get(item.id)?.delivery_confirmed || false }))]];
      }
      if (sql.includes('INSERT INTO shop_admin_notifications')) {
        if (!notificationCount) notificationCount++;
        events.push({ notice: values });
        return [{ affectedRows: 1 }];
      }
      if (sql.includes('UPDATE orders SET payment_status')) { paymentStatus = 'paid'; events.push('cash-collected'); return [{ affectedRows: 1 }]; }
      if (sql.includes('DELETE FROM shop_admin_notifications')) { events.push('notification-cleared'); return [{ affectedRows: 1 }]; }
      throw new Error(`Unexpected query in delivery mock: ${sql}`);
    },
  };
  const pool = {
    query: async sql => sql.includes("to_regclass('public.shop_order_assignments')") ? [[{ available: true }]] : sql.includes('SELECT active, shop_name') ? [[{ active: true, shop_name: 'RO Shop', full_name: 'Employee', employee_id: 'SHOP-001' }]] : [[]],
    getConnection: async () => connection,
  };
  const app = express(); app.use(express.json());
  installShopRoutes(app, pool, secret, (_req, res) => res.status(401).json({ success: false }));
  await withServer(app, async base => {
    const submit = (authToken, body) => fetch(`${base}/api/shop/orders/RO-1/delivery`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${authToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const payload = { mode: 'confirm', items: [
      { orderItemId: 11, deliveredQuantity: 1, deliveryConfirmed: true, deliveryStatus: 'delivered', delivered: true },
      { orderItemId: 12, deliveredQuantity: 2, deliveryConfirmed: false, deliveryStatus: 'not_delivered', delivered: false },
    ] };
    const draft = await submit(token, { mode: 'submit', items: payload.items.map(item => ({ ...item, deliveryConfirmed: false, deliveryStatus: 'not_delivered', delivered: false })) });
    assert.equal(draft.status, 200);
    assert.equal((await draft.json()).status, 'Pending');
    assert.equal(saved.get(11).delivered_quantity, 1);
    assert.equal(saved.get(11).delivery_confirmed, false);
    assert.equal(notificationCount, 0);

    const response = await submit(token, payload);
    assert.equal(response.status, 200);
    const result = await response.json();
    assert.equal(result.status, 'Partially Delivered');
    assert.equal(result.deliveredValue, 500);
    assert.equal(result.refundAmount, 1000);
    assert.equal(result.deliveredQuantity, 1);
    assert.equal(result.undeliveredQuantity, 5);
    assert.equal(saved.get(11).delivered_quantity, 1);
    assert.equal(saved.get(11).delivery_confirmed, true);
    assert.equal(saved.get(11).delivered, false);
    assert.equal(saved.get(12).refund_amount, 500);
    assert.equal(saved.get(12).delivered_quantity, 2, 'available quantity remains saved for review');
    assert.equal(saved.get(12).delivered_amount, 0, 'unconfirmed quantity is not included in confirmed totals');
    assert.equal(notificationCount, 1);

    const missingStatus = await submit(token, { mode: 'confirm', items: [
      { orderItemId: 11, deliveredQuantity: 1 },
      { orderItemId: 12, deliveredQuantity: 2 },
    ] });
    assert.equal(missingStatus.status, 400);
    assert.equal((await missingStatus.json()).error, 'Select delivery status for each order item.');

    const conflictingStatus = await submit(token, { mode: 'confirm', items: [
      { orderItemId: 11, deliveredQuantity: 1, deliveryConfirmed: false, deliveryStatus: 'delivered' },
      { orderItemId: 12, deliveredQuantity: 2, deliveryConfirmed: false, deliveryStatus: 'not_delivered' },
    ] });
    assert.equal(conflictingStatus.status, 400);
    assert.equal((await conflictingStatus.json()).error, 'Select delivery status for each order item.');

    const overflow = await submit(token, { items: [{ orderItemId: 11, deliveredQuantity: 3 }, { orderItemId: 12, deliveredQuantity: 0 }] });
    assert.equal(overflow.status, 400);

    orderAssigned = false;
    const forbidden = await submit(token, payload);
    assert.equal(forbidden.status, 404);

    orderAssigned = true;
    saved.get(12).refund_status = 'refunded';
    const repeat = await submit(token, payload);
    assert.equal(repeat.status, 200);
    assert.equal(notificationCount, 1);
    const changeAfterRefund = await submit(token, { items: [
      { orderItemId: 11, deliveredQuantity: 2, deliveryConfirmed: true, deliveryStatus: 'delivered' },
      { orderItemId: 12, deliveredQuantity: 0, deliveryConfirmed: false, deliveryStatus: 'not_delivered' },
    ] });
    assert.equal(changeAfterRefund.status, 409);
    saved.get(12).refund_status = 'pending_admin_review';
    const fullDelivery = await submit(token, { mode: 'confirm', cashCollected: true, items: [
      { orderItemId: 11, deliveredQuantity: 2, deliveryConfirmed: true, deliveryStatus: 'delivered' },
      { orderItemId: 12, deliveredQuantity: 4, deliveryConfirmed: true, deliveryStatus: 'delivered' },
    ] });
    assert.equal(fullDelivery.status, 200);
    const cashResult = await fullDelivery.json();
    assert.equal(cashResult.status, 'Delivered');
    assert.equal(cashResult.cashCollected, true);
    assert.equal(cashResult.paymentStatus, 'paid');
    assert.equal(paymentStatus, 'paid');
    assert.ok(events.includes('cash-collected'));
    assert.ok(events.includes('commit'));
  });
});

test('single-shop delivery remains authorized when the optional assignment table is absent', async () => {
  const secret = 'single-shop-fallback-secret';
  const token = signEmployeeToken({ id: 'staff-id', employee_id: 'SHOP-001', shop_name: 'RO Shop' }, secret);
  let savedPaymentStatus = 'due_on_delivery';
  let deliveryRow = null;
  const connection = {
    async beginTransaction() {}, async commit() {}, async rollback() {}, release() {},
    async query(sql) {
      if (sql.includes("to_regclass('public.shop_order_assignments')")) return [[{ available: false }]];
      if (sql.includes('information_schema.columns')) return [[{ available: false }]];
      if (sql.includes('FROM orders o WHERE o.order_id')) return [[{ order_id: 'RO-SINGLE', subtotal: 500, discount: 0, gst: 0, payment_method: 'Cash on Delivery', payment_status: savedPaymentStatus }]];
      if (sql.includes('SELECT id, unit_price, quantity FROM order_items')) return [[{ id: 71, unit_price: 500, quantity: 1 }]];
      if (sql.includes('SELECT order_item_id, delivered_quantity')) return [[...(deliveryRow ? [deliveryRow] : [])]];
      if (sql.includes('INSERT INTO shop_delivery_items')) {
        deliveryRow = { order_item_id: 71, delivered_quantity: 1, delivery_confirmed: true, refund_status: 'not_required' };
        return [{ affectedRows: 1 }];
      }
      if (sql.includes('SELECT oi.id, oi.unit_price')) return [[{ id: 71, unit_price: 500, quantity: 1, delivered_quantity: 1, delivery_confirmed: true }]];
      if (sql.includes('UPDATE orders SET payment_status')) { savedPaymentStatus = 'paid'; return [{ affectedRows: 1 }]; }
      if (sql.includes('DELETE FROM shop_admin_notifications')) return [{ affectedRows: 0 }];
      throw new Error(`Unexpected single-shop fallback query: ${sql}`);
    },
  };
  const pool = {
    async query(sql) {
      if (sql.includes('SELECT active, shop_name')) return [[{ active: true, shop_name: 'RO Shop', full_name: 'Employee', employee_id: 'SHOP-001' }]];
      throw new Error(`Unexpected single-shop pool query: ${sql}`);
    },
    async getConnection() { return connection; },
  };
  const app = express(); app.use(express.json());
  installShopRoutes(app, pool, secret, (_req, res) => res.status(401).json({ success: false }));
  await withServer(app, async base => {
    const response = await fetch(`${base}/api/shop/orders/RO-SINGLE/delivery`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ mode: 'confirm', cashCollected: true, items: [{ orderItemId: 71, deliveredQuantity: 1, deliveryConfirmed: true, deliveryStatus: 'delivered' }] }),
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.status, 'Delivered');
    assert.equal(body.cashCollected, true);
    assert.equal(savedPaymentStatus, 'paid');
    assert.equal(deliveryRow.delivered_quantity, 1);
  });
});
