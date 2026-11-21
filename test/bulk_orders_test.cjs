// Bulk Orders (bulk_orders.js, migration 011): a second purchase mode on the
// same products. Real server on an isolated in-memory PostgreSQL; never
// touches the live database.
const test = require('node:test');
const assert = require('node:assert/strict');
const { startSandbox } = require('../scripts/local_sandbox.cjs');
const { purchaseMode, bulkOffer, bulkQuantityProblem, validBulkQuantity } = require('../bulk_orders');
const { quoteCheckout } = require('../checkout_service');
const { parseDomestic } = require('../scripts/extract_bulk_pricing.cjs');

const pack42 = { id: 'P1', name: 'Cruze gold inline', price: 80, mrp: 590, bulk_price: 77, bulk_min_qty: 42, bulk_step: 42, bulk_pack_label: '42 PCS', stock_quantity: 1000 };
const mini10 = { id: 'P2', name: 'Ro pipe 3/8', price: 1000, mrp: 2800, bulk_price: 980, bulk_min_qty: 10, bulk_step: 1, bulk_pack_label: '10 NOS', stock_quantity: 1000 };

test('rules: Domestic pack (min = step) and Mukhil Mini qty (step 1)', () => {
  assert.equal(purchaseMode(undefined), 'normal');
  assert.equal(purchaseMode('BULK'), 'bulk');
  assert.equal(purchaseMode('wholesale'), null);
  assert.deepEqual(bulkOffer(pack42), { price: 77, min: 42, step: 42, label: '42 PCS' });
  assert.equal(bulkOffer({ ...pack42, bulk_price: null }), null, 'no bulk price = not in Bulk Orders');
  for (const q of [42, 84, 126, 168]) assert.equal(bulkQuantityProblem(pack42, q), null, `${q}`);
  for (const q of [1, 41, 43, 50, 83, 85]) assert.ok(bulkQuantityProblem(pack42, q), `${q} refused`);
  assert.equal(bulkQuantityProblem(pack42, 41).code, 'BULK_MIN_QTY');
  assert.equal(bulkQuantityProblem(pack42, 50).code, 'BULK_STEP');
  for (const q of [10, 11, 12, 37]) assert.equal(bulkQuantityProblem(mini10, q), null, `${q}`);
  assert.equal(bulkQuantityProblem(mini10, 9).code, 'BULK_MIN_QTY');
  assert.equal(bulkQuantityProblem({ ...mini10, stock_quantity: 10 }, 11).code, 'INSUFFICIENT_STOCK');
  assert.ok(validBulkQuantity({ min: 50, step: 50 }, 150));
});

test('checkout quote: bulk lines at the bulk price, normal lines at Dealer Price', () => {
  const q = quoteCheckout({
    items: [
      { id: 'P1', quantity: 42, purchaseMode: 'bulk', numericPrice: 1 }, // client price ignored
      { id: 'P2', quantity: 3 }, // normal
    ],
  }, [pack42, mini10]);
  const bulk = q.items.find(i => i.id === 'P1');
  const normal = q.items.find(i => i.id === 'P2');
  assert.deepEqual([bulk.purchaseMode, bulk.numericPrice, bulk.bulkPackLabel], ['bulk', 77, '42 PCS']);
  assert.deepEqual([normal.purchaseMode, normal.numericPrice], ['normal', 1000]);
  assert.equal(q.subtotal, 42 * 77 + 3 * 1000);
  // Dealer discount (10% by default) on the normal line only; bulk lines are excluded.
  assert.equal(q.discount, Math.round(3 * 1000 * q.dealerDiscountPercent) / 100);
  assert.equal(quoteCheckout({ items: [{ id: 'P1', quantity: 42, purchaseMode: 'bulk' }] }, [pack42]).discount, 0);
  assert.throws(() => quoteCheckout({ items: [{ id: 'P1', quantity: 43, purchaseMode: 'bulk' }] }, [pack42]), /packs of 42/);
  assert.throws(() => quoteCheckout({ items: [{ id: 'P1', quantity: 42, purchaseMode: 'bulk' }, { id: 'P1', quantity: 1 }] }, [pack42]), /both normally and in bulk/);
  assert.throws(() => quoteCheckout({ items: [{ id: 'P2', quantity: 10, purchaseMode: 'bulk' }] }, [{ ...mini10, bulk_price: null }]), /not available in Bulk Orders/);
});

test('PDF parser reads the Domestic rows as printed', () => {
  const rows = parseDomestic([
    'MUKIL WATER', 'Code Product Picture UNIT BOX MRP price',
    '1 Cruze gold inline', '80 77 (42 PCS) 590',
    '2 10" Copper', 'Cartridge', '180 170', '(50NOS)', '1750',
    '3 Taflon 30 20', '(1', 'BOX)', '60',
  ].join('\n'));
  assert.deepEqual(rows[0], { code: 1, name: 'Cruze gold inline', unit: '80', box: '77', packQty: 42, packUnit: 'PCS', mrp: '590' });
  assert.equal(rows[1].packQty, 50);
  assert.equal(rows[1].name, '10" Copper Cartridge');
  assert.deepEqual([rows[2].packQty, rows[2].packUnit], [1, 'BOX']);
});

test('Bulk Orders over HTTP', async t => {
  const sb = await startSandbox({ port: 0, quiet: true });
  t.after(() => sb.close());
  const base = `http://localhost:${sb.port}`;
  const http = async (method, url, body, token) => {
    const r = await fetch(base + url, { method, headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: body ? JSON.stringify(body) : undefined });
    return { status: r.status, body: await r.json() };
  };
  // Bulk offers on two sample products (as the PDF import would set them).
  await sb.db.query(`UPDATE products SET bulk_price = 600, bulk_min_qty = 42, bulk_step = 42, bulk_pack_label = '42 PCS', stock_quantity = 5000 WHERE id = 'SAMPLE_RO_MEM_75'`);
  await sb.db.query(`UPDATE products SET bulk_price = 270, bulk_min_qty = 10, bulk_step = 1, bulk_pack_label = '10 NOS', stock_quantity = 5000 WHERE id = 'SAMPLE_RO_FLT_SED'`);
  const before = (await sb.db.query(`SELECT id, price::float, mrp::float FROM products ORDER BY id`)).rows;
  const admin = (await http('POST', '/api/admin/login', sb.credentials.admin)).body.token;
  const email = 'bulk.dealer@example.test';
  await http('POST', '/api/auth/signup', { name: 'Bulk Dealer', email, mobile: '9000000003', password: 'bulk-pass-123', confirmPassword: 'bulk-pass-123', companyName: 'Bulk Traders', address: '3 Test Road, Chennai 600001' });
  await http('POST', '/api/admin/set-status', { email, status: 'approved' }, admin);
  const login = await http('POST', '/api/auth/login', { identifier: email, password: 'bulk-pass-123' });
  const token = login.body.token || login.body.user.token;
  const userId = login.body.user.id;
  const cart = (method, url, body) => http(method, url, { userId, ...body }, token);

  await t.test('catalogue carries the bulk offer next to the normal prices', async () => {
    const products = (await http('GET', '/api/products')).body.products;
    const mem = products.find(p => p.id === 'SAMPLE_RO_MEM_75');
    assert.deepEqual([mem.bulk_price, mem.bulk_min_qty, mem.bulk_step, mem.bulk_pack_label], [600, 42, 42, '42 PCS']);
    assert.equal(mem.price, before.find(p => p.id === 'SAMPLE_RO_MEM_75').price, 'Dealer Price unchanged');
    assert.equal(products.find(p => p.id === 'SAMPLE_RO_SYS_25')?.bulk_price ?? null, null);
  });

  await t.test('bulk cart: minimum, whole packs, no mixing with normal', async () => {
    assert.equal((await cart('POST', '/api/cart/add', { productId: 'SAMPLE_RO_MEM_75', quantity: 41, purchaseMode: 'bulk' })).body.code, 'BULK_MIN_QTY');
    assert.equal((await cart('POST', '/api/cart/add', { productId: 'SAMPLE_RO_MEM_75', quantity: 50, purchaseMode: 'bulk' })).body.code, 'BULK_STEP');
    const ok = await cart('POST', '/api/cart/add', { productId: 'SAMPLE_RO_MEM_75', quantity: 42, purchaseMode: 'bulk' });
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    let line = ok.body.items.find(i => i.product_id === 'SAMPLE_RO_MEM_75');
    assert.deepEqual([line.purchase_mode, line.quantity, line.bulk_price], ['bulk', 42, 600]);
    assert.equal((await cart('POST', '/api/cart/add', { productId: 'SAMPLE_RO_MEM_75', quantity: 42, purchaseMode: 'bulk' })).body.items.find(i => i.product_id === 'SAMPLE_RO_MEM_75').quantity, 84);
    assert.equal((await cart('PUT', '/api/cart/update', { productId: 'SAMPLE_RO_MEM_75', quantity: 100 })).body.code, 'BULK_STEP');
    assert.equal((await cart('PUT', '/api/cart/update', { productId: 'SAMPLE_RO_MEM_75', quantity: 41 })).body.code, 'BULK_MIN_QTY');
    assert.equal((await cart('PUT', '/api/cart/update', { productId: 'SAMPLE_RO_MEM_75', quantity: 42 })).status, 200, 'back down one pack');
    const mixed = await cart('POST', '/api/cart/add', { productId: 'SAMPLE_RO_MEM_75', quantity: 1 });
    assert.equal(mixed.status, 409);
    assert.match(mixed.body.error, /already in your cart as a Bulk Order/);
    assert.equal((await cart('POST', '/api/cart/add', { productId: 'SAMPLE_RO_SYS_25', quantity: 1, purchaseMode: 'bulk' })).body.code, 'BULK_UNAVAILABLE');
    // Mini qty product: 10, then +1 steps.
    assert.equal((await cart('POST', '/api/cart/add', { productId: 'SAMPLE_RO_FLT_SED', quantity: 9, purchaseMode: 'bulk' })).body.code, 'BULK_MIN_QTY');
    assert.equal((await cart('POST', '/api/cart/add', { productId: 'SAMPLE_RO_FLT_SED', quantity: 10, purchaseMode: 'bulk' })).status, 200);
    assert.equal((await cart('PUT', '/api/cart/update', { productId: 'SAMPLE_RO_FLT_SED', quantity: 11 })).status, 200);
    // Normal purchase of another product keeps working (single piece).
    const normal = await cart('POST', '/api/cart/add', { productId: 'SAMPLE_RO_SYS_25', quantity: 1 });
    assert.equal(normal.status, 200, JSON.stringify(normal.body));
    line = normal.body.items.find(i => i.product_id === 'SAMPLE_RO_SYS_25');
    assert.equal(line.purchase_mode, 'normal');
  });

  await t.test('checkout prices each line by its mode; order lines record it', async () => {
    const lines = (await http('GET', `/api/cart?userId=${encodeURIComponent(userId)}`, undefined, token)).body.items;
    const order = await http('POST', '/api/user/orders/create', {
      email, paymentMethod: 'Cash on Delivery',
      deliveryAddress: { line1: '3 Test Road', city: 'Chennai', pincode: '600001' },
      items: lines.map(l => ({ id: l.product_id, quantity: l.quantity, purchaseMode: l.purchase_mode, numericPrice: 1 })),
      subtotal: 1, grandTotal: 1,
    }, token);
    assert.equal(order.status, 200, JSON.stringify(order.body));
    const sys = before.find(p => p.id === 'SAMPLE_RO_SYS_25').price;
    assert.equal(order.body.order.subtotal, 42 * 600 + 11 * 270 + sys);
    assert.equal(order.body.order.discount, Math.round(sys * order.body.order.dealerDiscountPercent) / 100, 'no dealer discount on bulk lines');
    const rows = (await sb.db.query(`SELECT product_id, unit_price::float, quantity, purchase_mode, bulk_pack_label FROM order_items WHERE order_id = $1 ORDER BY product_id`, [order.body.order.orderId])).rows;
    assert.deepEqual(rows.map(r => [r.product_id, r.unit_price, r.quantity, r.purchase_mode, r.bulk_pack_label]), [
      ['SAMPLE_RO_FLT_SED', 270, 11, 'bulk', '10 NOS'],
      ['SAMPLE_RO_MEM_75', 600, 42, 'bulk', '42 PCS'],
      ['SAMPLE_RO_SYS_25', sys, 1, 'normal', null],
    ]);
    const history = (await http('GET', `/api/user/orders?email=${encodeURIComponent(email)}`, undefined, token)).body;
    const items = (history.orders || history)[0].items;
    assert.equal(items.find(i => i.id === 'SAMPLE_RO_MEM_75').purchaseMode, 'bulk');
    assert.equal(items.find(i => i.id === 'SAMPLE_RO_SYS_25').purchaseMode, 'normal');
    // Stored prices never changed.
    assert.deepEqual((await sb.db.query(`SELECT id, price::float, mrp::float FROM products ORDER BY id`)).rows, before);
  });
});
