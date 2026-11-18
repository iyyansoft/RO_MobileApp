// Full-stack end-to-end test: the REAL backend (server.js, every route) on an
// isolated in-memory PostgreSQL (scripts/local_sandbox.cjs), driven over HTTP
// exactly as the Admin Panel, Customer Portal and Shop App call it.
// Never touches the live database; emails are captured, not sent.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { startSandbox } = require('../scripts/local_sandbox.cjs');

const root = path.join(__dirname, '..');
let sandbox;
let base;
const state = {};

async function http(method, url, { body, token, headers = {} } = {}) {
  const res = await fetch(base + url, {
    method,
    headers: {
      ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const type = res.headers.get('content-type') || '';
  const data = type.includes('json') ? await res.json() : Buffer.from(await res.arrayBuffer());
  return { status: res.status, body: data, type };
}
const admin = (method, url, body) => http(method, url, { body, token: state.adminToken });
const dealer = (method, url, body, who = 'dealer') => http(method, url, { body, token: state[`${who}Token`] });
const shop = (method, url, body) => http(method, url, { body, token: state.shopToken });
const stockOf = async id => (await http('GET', '/api/products')).body.products.find(p => p.id === id)?.stock_quantity;
const png = fs.readFileSync(path.join(root, 'assets', 'images', 'RO_System.png'));
const pngDataUrl = `data:image/png;base64,${png.toString('base64')}`;

test.before(async () => {
  sandbox = await startSandbox({ port: 0, quiet: true });
  base = `http://localhost:${sandbox.port}`;
});
test.after(async () => { await sandbox?.close(); });

test('1. Admin Panel: login, dashboard, products, categories, dealers, orders', async t => {
  await t.test('wrong password is refused; correct one gives a signed session', async () => {
    const { email, password } = sandbox.credentials.admin;
    assert.equal((await http('POST', '/api/admin/login', { body: { email, password: 'wrong' } })).status, 401);
    const ok = await http('POST', '/api/admin/login', { body: { email, password } });
    assert.equal(ok.status, 200);
    state.adminToken = ok.body.token;
    assert.equal((await admin('GET', '/api/admin/session')).status, 200);
    assert.equal((await http('GET', '/api/admin/orders')).status, 401, 'protected without a session');
  });

  await t.test('dashboard statistics and analytics load', async () => {
    const stats = await admin('GET', '/api/admin/dashboard-stats');
    assert.equal(stats.status, 200);
    assert.equal(stats.body.stats.totalProducts, 18);
    assert.equal(stats.body.stats.totalCategories, 6);
    const analytics = await admin('GET', '/api/admin/analytics?period=daily');
    assert.equal(analytics.status, 200);
    assert.ok(Array.isArray(analytics.body.chart.labels));
  });

  await t.test('categories: list, create with image, edit', async () => {
    assert.equal((await admin('GET', '/api/admin/categories')).body.categories.length, 6);
    const created = await admin('POST', '/api/admin/categories', { title: 'UV Lamps', key: 'uv', image: pngDataUrl, description: 'UV sterilisation' });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const category = (await admin('GET', '/api/admin/categories')).body.categories.find(c => c.key_name === 'uv');
    assert.match(category.image_url, /^\/api\/product-images\//, 'category image kept in the shared database');
    const edited = await admin('PUT', `/api/admin/categories/${category.id}`, { title: 'UV Lamps & Sterilisers', key: 'uv' });
    assert.equal(edited.status, 200, JSON.stringify(edited.body));
    state.categoryId = category.id;
  });

  await t.test('products: create with image, edit, bulk import, delete; customers see them', async () => {
    const created = await admin('POST', '/api/admin/products', {
      name: 'UV Lamp 11W', sku: 'UV-11W', category: 'uv', brand: 'Aqua Mars',
      purchase_price: 300, price: 450, mrp: 700, stock_quantity: 5, img: pngDataUrl, desc: 'Replacement UV lamp',
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    state.uvProductId = created.body.product.id;
    assert.match(created.body.product.img, /^\/api\/product-images\/img_\d+_[0-9a-f]+\.png$/);
    assert.equal((await admin('POST', '/api/admin/products', { name: 'Bad', sku: 'BAD-1', category: 'uv', price: 500, mrp: 400 })).status, 400, 'MRP below dealer price');
    assert.equal((await admin('POST', '/api/admin/products', { name: 'Dup', sku: 'UV-11W', category: 'uv', price: 1, mrp: 2 })).status, 400, 'duplicate SKU');
    const edited = await admin('PUT', `/api/admin/products/${state.uvProductId}`, { name: 'UV Lamp 11 W', sku: 'UV-11W', category: 'uv', price: 450, mrp: 700, stock_quantity: 5 });
    assert.equal(edited.status, 200, JSON.stringify(edited.body));
    const bulk = await admin('POST', '/api/admin/products/bulk', { products: [
      { name: 'UV Lamp 16W', sku: 'UV-16W', category: 'UV Lamps & Sterilisers', brand: 'Aqua Mars', purchase_price: 350, price: 520, mrp: 800 },
      { name: 'Broken row', sku: 'UV-BAD', category: 'uv', brand: 'X', price: 10, mrp: 5 },
    ] });
    assert.equal(bulk.status, 201, JSON.stringify(bulk.body));
    assert.equal(bulk.body.importedCount, 1);
    assert.equal(bulk.body.skippedCount, 1);
    const catalog = (await http('GET', '/api/products')).body.products;
    const uv = catalog.find(p => p.sku === 'UV-11W');
    assert.equal(uv.name, 'UV Lamp 11 W');
    assert.equal(uv.category_name, 'UV Lamps & Sterilisers');
    assert.equal('purchase_price' in uv, false, 'customers never see purchase price');
    assert.ok(catalog.some(p => p.sku === 'UV-16W'), 'bulk product visible to customers');
    const toDelete = catalog.find(p => p.sku === 'UV-16W').id;
    assert.equal((await admin('DELETE', `/api/admin/products/${toDelete}`)).status, 200);
    assert.equal((await http('GET', '/api/products')).body.products.some(p => p.sku === 'UV-16W'), false);
  });
});

test('5. Image uploads and display', async t => {
  await t.test('uploaded product image is served with the right type and bytes', async () => {
    const product = (await http('GET', '/api/products')).body.products.find(p => p.id === state.uvProductId);
    const image = await http('GET', product.img);
    assert.equal(image.status, 200);
    assert.equal(image.type, 'image/png');
    assert.deepEqual(image.body, png);
  });
  await t.test('share page and share image use the product picture; MRP only', async () => {
    const page = await http('GET', `/share/products/${state.uvProductId}`);
    assert.equal(page.status, 200);
    const html = page.body.toString('utf8');
    assert.match(html, /og:title" content="UV Lamp 11 W — MRP ₹700"/);
    assert.equal(html.includes('450'), false, 'dealer price never on the public page');
    assert.equal(html.includes('300'), false, 'purchase price never on the public page');
    const shareImage = await http('GET', `/share/products/${state.uvProductId}/image`);
    assert.equal(shareImage.status, 200);
    assert.deepEqual(shareImage.body, png);
  });
});

test('2. Customer Portal: signup, login, products, cart, checkout, order history', async t => {
  await t.test('signup creates a pending account; duplicate email refused', async () => {
    const account = { name: 'Priya', email: 'priya.sandbox@example.test', mobile: '9876543210', password: 'priya-sandbox-pass', confirmPassword: 'priya-sandbox-pass', companyName: 'SRP Traders', address: '12 Main Road, Chennai, Tamil Nadu 600001' };
    const signup = await http('POST', '/api/auth/signup', { body: account });
    assert.equal(signup.status, 200, JSON.stringify(signup.body));
    assert.equal(signup.body.status, 'pending');
    assert.equal((await http('POST', '/api/auth/signup', { body: account })).status, 409);
    const second = { ...account, name: 'Karthik', email: 'karthik.sandbox@example.test', mobile: '9123456780' };
    assert.equal((await http('POST', '/api/auth/signup', { body: second })).status, 200);
  });

  await t.test('admin approves the dealer', async () => {
    const dealers = (await admin('GET', '/api/admin/dealers')).body;
    const list = dealers.dealers || dealers.users;
    assert.ok(list.some(d => d.email === 'priya.sandbox@example.test'));
    const approve = await admin('POST', '/api/admin/set-status', { email: 'priya.sandbox@example.test', status: 'approved' });
    assert.equal(approve.status, 200, JSON.stringify(approve.body));
  });

  await t.test('password login and email-code login both work', async () => {
    // Existing API contract: wrong credentials -> 400 with an error message.
    const wrong = await http('POST', '/api/auth/login', { body: { identifier: 'priya.sandbox@example.test', password: 'wrong-password' } });
    assert.equal(wrong.status, 400);
    assert.equal(wrong.body.success, false);
    const login = await http('POST', '/api/auth/login', { body: { identifier: 'priya.sandbox@example.test', password: 'priya-sandbox-pass' } });
    assert.equal(login.status, 200, JSON.stringify(login.body));
    state.dealerToken = login.body.token || login.body.user.token;
    state.dealer = login.body.user;
    const other = await http('POST', '/api/auth/login', { body: { identifier: 'karthik.sandbox@example.test', password: 'priya-sandbox-pass' } });
    state.otherToken = other.body.token || other.body.user.token;
    // One-time code by email (captured in the sandbox outbox).
    const send = await http('POST', '/api/auth/send-otp', { body: { email: 'priya.sandbox@example.test' } });
    assert.equal(send.status, 200, JSON.stringify(send.body));
    const code = sandbox.outbox.at(-1).text.match(/\b(\d{6})\b/)[1];
    const verify = await http('POST', '/api/auth/verify-otp', { body: { email: 'priya.sandbox@example.test', otp: code } });
    assert.equal(verify.status, 200, JSON.stringify(verify.body));
  });

  await t.test('products and categories', async () => {
    const products = await http('GET', '/api/products');
    assert.equal(products.status, 200);
    assert.ok(products.body.products.length >= 19);
    assert.equal((await http('GET', '/api/categories')).body.categories.length, 7);
  });

  await t.test('cart: add, update, remove; private to the dealer', async () => {
    const userId = state.dealer.id;
    assert.equal((await dealer('POST', '/api/cart/add', { userId, productId: 'SAMPLE_RO_MEM_75', quantity: 2 })).status, 200);
    assert.equal((await dealer('POST', '/api/cart/add', { userId, productId: state.uvProductId, quantity: 1 })).status, 200);
    assert.equal((await dealer('PUT', '/api/cart/update', { userId, productId: 'SAMPLE_RO_MEM_75', quantity: 3 })).status, 200);
    let cart = await dealer('GET', `/api/cart?userId=${encodeURIComponent(userId)}`);
    assert.equal(cart.status, 200);
    assert.deepEqual(cart.body.items.map(i => [i.product_id, i.quantity]).sort(), [['SAMPLE_RO_MEM_75', 3], [state.uvProductId, 1]].sort());
    assert.equal((await dealer('DELETE', '/api/cart/remove', { userId, productId: state.uvProductId })).status, 200);
    cart = await dealer('GET', `/api/cart?userId=${encodeURIComponent(userId)}`);
    assert.equal(cart.body.items.length, 1);
    // Another dealer, or nobody, cannot read or change it.
    assert.equal((await http('GET', `/api/cart?userId=${encodeURIComponent(userId)}`)).status, 401);
    assert.equal((await dealer('GET', `/api/cart?userId=${encodeURIComponent(userId)}`, undefined, 'other')).status, 403);
    assert.equal((await http('GET', `/api/cart`, { headers: { 'x-user-id': userId } })).status, 401, 'id header alone is not enough');
  });

  await t.test('checkout (Cash on Delivery) saves the order, reduces stock, empties the cart', async () => {
    const before = await stockOf('SAMPLE_RO_MEM_75');
    const order = await dealer('POST', '/api/user/orders/create', {
      email: 'priya.sandbox@example.test', userId: state.dealer.id, paymentMethod: 'Cash on Delivery',
      deliveryAddress: { line1: '12 Main Road', city: 'Chennai', pincode: '600001' },
      items: [{ id: 'SAMPLE_RO_MEM_75', quantity: 3 }, { id: state.uvProductId, quantity: 2 }],
    });
    assert.equal(order.status, 200, JSON.stringify(order.body));
    state.orderId = order.body.order.orderId;
    assert.equal(order.body.order.paymentStatus, 'due_on_delivery');
    assert.equal(order.body.assignedShopName, 'ROSHOP');
    assert.equal(await stockOf('SAMPLE_RO_MEM_75'), before - 3);
    assert.equal(await stockOf(state.uvProductId), 3);
    await dealer('DELETE', '/api/cart/clear', { userId: state.dealer.id });
    assert.equal((await dealer('GET', `/api/cart?userId=${encodeURIComponent(state.dealer.id)}`)).body.items.length, 0);
    // Someone else cannot order as this dealer.
    assert.equal((await dealer('POST', '/api/user/orders/create', { email: 'priya.sandbox@example.test', paymentMethod: 'Cash on Delivery', deliveryAddress: 'x', items: [{ id: 'SAMPLE_RO_MEM_75', quantity: 1 }] }, 'other')).status, 403);
  });

  await t.test('order history, invoices, rewards are private and correct', async () => {
    const history = await dealer('GET', '/api/user/orders?email=priya.sandbox%40example.test');
    assert.equal(history.status, 200);
    const order = history.body.orders.find(o => o.orderId === state.orderId);
    assert.ok(order, 'the new order is in the history');
    assert.equal(order.items.length, 2);
    assert.equal((await http('GET', '/api/user/orders?email=priya.sandbox%40example.test')).status, 401);
    assert.equal((await dealer('GET', '/api/user/orders?email=priya.sandbox%40example.test', undefined, 'other')).status, 403);
    const invoices = await dealer('GET', '/api/user/gst-invoices?email=priya.sandbox%40example.test');
    assert.equal(invoices.status, 200);
    assert.equal(invoices.body.creditLimit, null, 'credit limit not set');
    assert.ok(invoices.body.outstandingAmount > 0, 'unpaid order counts as outstanding');
    assert.equal((await dealer('GET', '/api/user/rewards?email=priya.sandbox%40example.test')).status, 200);
    assert.equal((await dealer('POST', '/api/user/update-profile', { email: 'priya.sandbox@example.test', name: 'Hacked' }, 'other')).status, 403, 'cannot edit another dealer');
  });
});

test('3. Shop App: login, current orders, product details, supply, status sync', async t => {
  await t.test('employee login and the order appears with product details', async () => {
    const { loginId, password } = sandbox.credentials.shop;
    assert.equal((await http('POST', '/api/shop/auth/login', { body: { loginId, password: 'wrong' } })).status, 401);
    const login = await http('POST', '/api/shop/auth/login', { body: { loginId, password } });
    assert.equal(login.status, 200);
    state.shopToken = login.body.token;
    const orders = await shop('GET', '/api/shop/orders');
    const order = orders.body.orders.find(o => o.orderId === state.orderId);
    assert.ok(order, 'customer order is in the Shop App');
    state.shopItems = order.items;
    assert.deepEqual(order.items.map(i => [i.name, i.sku, i.quantity, i.unitPrice]), [
      ['RO Membrane 75 GPD', 'RO-MEM-75', 3, 650],
      ['UV Lamp 11 W', 'UV-11W', 2, 450],
    ]);
    const products = await shop('GET', '/api/shop/products?search=UV');
    assert.equal(products.body.products[0].name, 'UV Lamp 11 W');
  });

  const supply = (lines, cashCollected = false) => shop('POST', `/api/shop/orders/${state.orderId}/delivery`, {
    mode: 'confirm', cashCollected,
    items: lines.map(([index, quantity]) => ({
      orderItemId: Number(state.shopItems[index].id), deliveredQuantity: quantity, deliveryConfirmed: quantity > 0,
      deliveryStatus: quantity > 0 ? 'delivered' : 'not_delivered', delivered: quantity > 0,
    })),
  });

  await t.test('partial supply -> Partially Delivered everywhere; payment unchanged', async () => {
    const res = await supply([[0, 3], [1, 0]]);
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.status, 'Partially Delivered');
    const adminOrder = (await admin('GET', '/api/admin/orders')).body.orders.find(o => o.orderId === state.orderId);
    assert.equal(adminOrder.orderStatus, 'Partially Delivered');
    assert.equal(adminOrder.paymentStatus, 'due_on_delivery');
    assert.equal(adminOrder.deliveredQuantity, 3);
    const customerOrder = (await dealer('GET', '/api/user/orders?email=priya.sandbox%40example.test')).body.orders.find(o => o.orderId === state.orderId);
    assert.equal(customerOrder.status, 'Partially Delivered');
  });

  await t.test('admin status change is visible in the Shop App; rules enforced', async () => {
    assert.equal((await admin('PUT', `/api/admin/orders/${state.orderId}/status`, { status: 'Delivered' })).status, 409);
    assert.equal((await admin('PUT', `/api/admin/orders/${state.orderId}/payment-status`, { paymentStatus: 'PARTIALLY_PAID' })).status, 200);
    const shopOrder = (await shop('GET', '/api/shop/orders')).body.orders.find(o => o.orderId === state.orderId);
    assert.equal(shopOrder.paymentStatus, 'partially_paid');
  });

  await t.test('full supply -> Delivered; COD not auto-paid', async () => {
    const res = await supply([[0, 3], [1, 2]]);
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.status, 'Delivered');
    const adminOrder = (await admin('GET', '/api/admin/orders')).body.orders.find(o => o.orderId === state.orderId);
    assert.equal(adminOrder.orderStatus, 'Delivered');
    assert.equal(adminOrder.paymentStatus, 'partially_paid', 'still the recorded payment');
    assert.equal((await admin('PUT', `/api/admin/orders/${state.orderId}/payment-status`, { paymentStatus: 'paid' })).status, 200);
    const customerOrder = (await dealer('GET', '/api/user/orders?email=priya.sandbox%40example.test')).body.orders.find(o => o.orderId === state.orderId);
    assert.equal(customerOrder.status, 'Delivered');
    assert.equal(customerOrder.paymentStatus, 'paid');
  });

  await t.test('overview and reports include the order', async () => {
    const dash = await shop('GET', '/api/shop/dashboard');
    assert.equal(dash.status, 200);
    assert.ok(dash.body.metrics.todayOrders >= 1);
    const report = await shop('GET', '/api/shop/reports?period=product');
    assert.ok(report.body.rows.some(r => r.product_name === 'UV Lamp 11 W' && r.quantitySold === 2));
  });
});

test('4. Stock: placement, never negative, cancellation and restoration', async t => {
  await t.test('stock 0: cannot be added to the cart, grown in the cart, or ordered', async () => {
    const cartOf = async () => (await dealer('GET', `/api/cart?userId=${encodeURIComponent(state.dealer.id)}`)).body.items;
    await dealer('DELETE', '/api/cart/clear', { userId: state.dealer.id });
    await sandbox.db.query("UPDATE products SET stock_quantity = 0 WHERE id = 'SAMPLE_RO_PIPE_KIT'");
    const add = await dealer('POST', '/api/cart/add', { userId: state.dealer.id, productId: 'SAMPLE_RO_PIPE_KIT', quantity: 1 });
    assert.equal(add.status, 409, JSON.stringify(add.body));
    assert.equal(add.body.code, 'OUT_OF_STOCK');
    assert.match(add.body.error, /RO Inlet Pipe Kit is out of stock/);
    assert.equal((await cartOf()).length, 0, 'nothing was added');

    // More than in stock is refused too; within stock is fine.
    await sandbox.db.query("UPDATE products SET stock_quantity = 3 WHERE id = 'SAMPLE_RO_PIPE_14'");
    assert.equal((await dealer('POST', '/api/cart/add', { userId: state.dealer.id, productId: 'SAMPLE_RO_PIPE_14', quantity: 4 })).body.code, 'INSUFFICIENT_STOCK');
    assert.equal((await dealer('POST', '/api/cart/add', { userId: state.dealer.id, productId: 'SAMPLE_RO_PIPE_14', quantity: 2 })).status, 200);
    assert.equal((await dealer('POST', '/api/cart/add', { userId: state.dealer.id, productId: 'SAMPLE_RO_PIPE_14', quantity: 2 })).body.code, 'INSUFFICIENT_STOCK', 'cart total counts');
    const line = (await cartOf()).find(i => i.id === 'SAMPLE_RO_PIPE_14');
    assert.equal(line.quantity, 2);
    assert.equal(line.stock_quantity, 3, 'the cart reports stock so the app can warn');

    // It runs out after it was added: the line can be lowered or removed, not grown, not ordered.
    await sandbox.db.query("UPDATE products SET stock_quantity = 0 WHERE id = 'SAMPLE_RO_PIPE_14'");
    assert.equal((await dealer('PUT', '/api/cart/update', { userId: state.dealer.id, productId: 'SAMPLE_RO_PIPE_14', quantity: 3 })).status, 409);
    assert.equal((await dealer('PUT', '/api/cart/update', { userId: state.dealer.id, productId: 'SAMPLE_RO_PIPE_14', quantity: 1 })).status, 200);
    const order = await dealer('POST', '/api/user/orders/create', {
      email: 'priya.sandbox@example.test', paymentMethod: 'Cash on Delivery', deliveryAddress: 'Chennai',
      items: [{ id: 'SAMPLE_RO_PIPE_14', quantity: 1 }],
    });
    assert.ok([400, 409].includes(order.status), JSON.stringify(order.body));
    assert.match(order.body.error, /stock/i);
    assert.equal(await stockOf('SAMPLE_RO_PIPE_14'), 0, 'stock never goes negative');
    assert.equal((await dealer('DELETE', '/api/cart/remove', { userId: state.dealer.id, productId: 'SAMPLE_RO_PIPE_14' })).status, 200);
    await sandbox.db.query("UPDATE products SET stock_quantity = 100 WHERE id IN ('SAMPLE_RO_PIPE_KIT', 'SAMPLE_RO_PIPE_14')");
  });

  await t.test('PDF quantity is the maximum per order line (cart, update, checkout)', async () => {
    const cartOf = async () => (await dealer('GET', `/api/cart?userId=${encodeURIComponent(state.dealer.id)}`)).body.items;
    await dealer('DELETE', '/api/cart/clear', { userId: state.dealer.id });
    // A product from the supplier-PDF catalogue: PDF quantity "10 nos", real stock 40.
    await sandbox.db.query(`INSERT INTO products (id, category_id, category_key, sku, name, brand, price, mrp, moq, img, stock_quantity, status)
      VALUES ('PDF_TEST_01', 'CAT_PMP', 'pumps', 'MUK-T1', 'Test Pump', '', 1050, 2700, '10 nos', '', 40, 'active')`);
    const listed = (await http('GET', '/api/products')).body.products.find(p => p.id === 'PDF_TEST_01');
    assert.equal(listed.max_order_quantity, 10);
    assert.equal(listed.min_order_quantity, 1);
    assert.equal(listed.stock_quantity, 40, 'stock is the real inventory, not the PDF quantity');
    const add = quantity => dealer('POST', '/api/cart/add', { userId: state.dealer.id, productId: 'PDF_TEST_01', quantity });
    assert.equal((await add(1)).status, 200, 'one unit');
    assert.equal((await add(9)).status, 200, 'up to the maximum');
    const over = await add(1);
    assert.equal(over.status, 400);
    assert.equal(over.body.code, 'MAX_ORDER_QTY');
    assert.equal(over.body.max, 10);
    assert.equal(over.body.error, 'You can order a maximum of 10 units for this product.');
    assert.equal((await cartOf()).find(i => i.id === 'PDF_TEST_01').quantity, 10);
    assert.equal((await cartOf()).find(i => i.id === 'PDF_TEST_01').max_order_quantity, 10, 'the cart knows the limit');
    assert.equal((await dealer('PUT', '/api/cart/update', { userId: state.dealer.id, productId: 'PDF_TEST_01', quantity: 11 })).body.code, 'MAX_ORDER_QTY');
    assert.equal((await dealer('PUT', '/api/cart/update', { userId: state.dealer.id, productId: 'PDF_TEST_01', quantity: 1 })).status, 200, 'down to 1');
    const order = quantity => dealer('POST', '/api/user/orders/create', {
      email: 'priya.sandbox@example.test', paymentMethod: 'Cash on Delivery', deliveryAddress: 'Chennai', items: [{ id: 'PDF_TEST_01', quantity }],
    });
    assert.match((await order(11)).body.error, /You can order a maximum of 10 units for this product/);
    assert.equal(await stockOf('PDF_TEST_01'), 40, 'nothing taken');
    const ok = await order(10);
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    assert.equal(await stockOf('PDF_TEST_01'), 30, 'production rule: real stock is reduced by the order');
    await dealer('DELETE', '/api/cart/clear', { userId: state.dealer.id });
  });

  await t.test('an order larger than stock is refused and changes nothing', async () => {
    const before = await stockOf(state.uvProductId);
    const res = await dealer('POST', '/api/user/orders/create', {
      email: 'priya.sandbox@example.test', paymentMethod: 'Cash on Delivery', deliveryAddress: 'Chennai',
      items: [{ id: state.uvProductId, quantity: before + 1 }],
    });
    assert.ok([400, 409].includes(res.status), JSON.stringify(res.body));
    assert.equal(await stockOf(state.uvProductId), before);
  });

  await t.test('partial supply then cancel returns only unsupplied units, once', async () => {
    const before = await stockOf('SAMPLE_RO_FLT_SED');
    const order = await dealer('POST', '/api/user/orders/create', {
      email: 'priya.sandbox@example.test', paymentMethod: 'Cash on Delivery', deliveryAddress: 'Chennai',
      items: [{ id: 'SAMPLE_RO_FLT_SED', quantity: 10 }],
    });
    assert.equal(order.status, 200, JSON.stringify(order.body));
    const orderId = order.body.order.orderId;
    assert.equal(await stockOf('SAMPLE_RO_FLT_SED'), before - 10);
    const item = (await shop('GET', '/api/shop/orders')).body.orders.find(o => o.orderId === orderId).items[0];
    const partial = await shop('POST', `/api/shop/orders/${orderId}/delivery`, { mode: 'confirm', items: [{ orderItemId: Number(item.id), deliveredQuantity: 4, deliveryConfirmed: true, deliveryStatus: 'delivered', delivered: true }] });
    assert.equal(partial.status, 200, JSON.stringify(partial.body));
    const cancel = await admin('PUT', `/api/admin/orders/${orderId}/status`, { status: 'Cancelled' });
    assert.equal(cancel.status, 200, JSON.stringify(cancel.body));
    assert.equal(cancel.body.stockReturned, 6);
    assert.equal(await stockOf('SAMPLE_RO_FLT_SED'), before - 4, 'only the 4 supplied units stay out');
    assert.equal((await admin('PUT', `/api/admin/orders/${orderId}/status`, { status: 'Cancelled' })).body.stockReturned, 0);
    // The Shop App cannot supply a cancelled order.
    const blocked = await shop('POST', `/api/shop/orders/${orderId}/delivery`, { mode: 'confirm', items: [{ orderItemId: Number(item.id), deliveredQuantity: 10, deliveryConfirmed: true, deliveryStatus: 'delivered', delivered: true }] });
    assert.equal(blocked.status, 409);
  });
});

test('6. Synchronisation: one order id, one record, three apps', async t => {
  await t.test('admin, customer and Shop App see the same order and values', async () => {
    const adminOrder = (await admin('GET', '/api/admin/orders')).body.orders.find(o => o.orderId === state.orderId);
    const customerOrder = (await dealer('GET', '/api/user/orders?email=priya.sandbox%40example.test')).body.orders.find(o => o.orderId === state.orderId);
    const shopOrder = (await shop('GET', '/api/shop/orders')).body.orders.find(o => o.orderId === state.orderId);
    assert.equal(adminOrder.orderStatus, 'Delivered');
    assert.equal(customerOrder.status, 'Delivered');
    assert.equal(shopOrder.status, 'Delivered');
    assert.equal(adminOrder.paymentStatus, customerOrder.paymentStatus);
    assert.equal(shopOrder.paymentStatus, customerOrder.paymentStatus);
    assert.equal(adminOrder.grandTotal, customerOrder.grandTotal);
    assert.equal(adminOrder.shopName, 'ROSHOP');
    const [[{ n }]] = await sandbox.pool.query('SELECT COUNT(*)::int AS n FROM orders WHERE order_id = ?', [state.orderId]);
    assert.equal(n, 1, 'one database record');
  });

  await t.test('product edits by admin reach customers and the Shop App', async () => {
    await admin('PUT', `/api/admin/products/${state.uvProductId}`, { name: 'UV Lamp 11 W (Philips)', sku: 'UV-11W', category: 'uv', price: 460, mrp: 700, stock_quantity: 3 });
    assert.equal((await http('GET', '/api/products')).body.products.find(p => p.id === state.uvProductId).name, 'UV Lamp 11 W (Philips)');
    assert.equal((await shop('GET', '/api/shop/products?search=Philips')).body.products.length, 1);
  });

  await t.test('admin logout ends the session', async () => {
    await admin('POST', '/api/admin/logout');
    assert.equal((await admin('GET', '/api/admin/session')).status, 401);
  });
});
