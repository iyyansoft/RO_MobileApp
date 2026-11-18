// --live-snapshot mode of scripts/local_sandbox.cjs, with a stand-in snapshot
// (never touches the live database): existing password hashes keep working,
// ids and links are kept, new local rows do not collide, nothing reaches out.
const test = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');
const { startSandbox } = require('../scripts/local_sandbox.cjs');

const DEALER_PASSWORD = 'Existing#Pass2026';
const SHOP_PASSWORD = 'Shop#Pass2026';
let sandbox;
let base;

async function http(method, url, body, token) {
  const res = await fetch(base + url, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json().catch(() => null) };
}

test.before(async () => {
  const dealerHash = await bcrypt.hash(DEALER_PASSWORD, 10);
  const shopHash = await bcrypt.hash(SHOP_PASSWORD, 10);
  // Shape of what readLiveSnapshot() returns: table -> rows, dates as database text.
  const snapshot = {
    categories: [
      ['CAT_SYS', 'systems'], ['CAT_MEM', 'membranes'], ['CAT_FLT', 'filters'],
      ['CAT_PMP', 'pumps'], ['CAT_PIP', 'pipes'], ['CAT_SPR', 'spares'],
    ].map(([id, key], i) => ({ id, key_name: key, title: key, display_order: i })),
    products: [
      { id: 'SAMPLE_RO_MEM_75', category_id: 'CAT_MEM', category_key: 'membranes', sku: 'RO-MEM-75', name: 'RO Membrane 75 GPD', brand: 'X', price: '650.00', mrp: '950.00', stock_quantity: 100, status: 'active' },
      { id: 'prod_genuine_1', category_id: 'CAT_MEM', category_key: 'membranes', sku: 'ABC', name: 'ABC', brand: 'X', price: '17000.00', mrp: '20000.00', stock_quantity: 5, status: 'active' },
    ],
    users: [
      { id: 'user_1791538245915_77', email: 'real.dealer@example.test', mobile: '9000000011', name: 'Real Dealer', password_hash: dealerHash, email_verified: true, business_name: 'Real Water Co', status: 'approved', is_approved: true, reward_points: 120, created_at: '2026-10-09 09:30:45' },
      { id: 'user_pending_2', email: 'pending.dealer@example.test', mobile: '9000000012', name: 'Pending Dealer', password_hash: dealerHash, email_verified: true, status: 'pending', is_approved: false, reward_points: 0, created_at: '2026-10-10 10:00:00' },
    ],
    user_addresses: [{ id: 'ADDR_1', user_id: 'user_1791538245915_77', full_name: 'Real Dealer', street: '14 Gandhi Road', city: 'Chennai', state: 'Tamil Nadu', pincode: '600040', is_default: true }],
    orders: [{ order_id: 'RO-old-1', user_id: 'user_1791538245915_77', user_email: 'real.dealer@example.test', user_name: 'Real Dealer', delivery_address: '14 Gandhi Road', invoice_number: 'INV-1', subtotal: '1300.00', grand_total: '1300.00', status: 'Processing & Dispatched', payment_status: 'due_on_delivery', payment_method: 'Cash on Delivery', created_at: '2026-10-12 13:10:44' }],
    order_items: [{ id: '41', order_id: 'RO-old-1', product_id: 'SAMPLE_RO_MEM_75', product_name: 'RO Membrane 75 GPD', unit_price: '650.00', quantity: 2, sku: '' }],
    cart_items: [{ id: '7', user_id: 'user_1791538245915_77', product_id: 'prod_genuine_1', quantity: 1 }],
    shop_employees: [{ id: '1937bfd8-1ee1-4694-87bf-945c480ac761', employee_id: 'ROSHOP01', shop_name: 'ROSHOP', full_name: 'Shop Staff', password_hash: shopHash, active: true }],
  };
  process.env.ADMIN_EMAIL = 'owner@example.test';
  process.env.ADMIN_PASSWORD = 'Admin#Pass2026';
  sandbox = await startSandbox({ port: 0, quiet: true, liveSnapshot: true, snapshotLoader: async () => snapshot, pdfImport: true });
  base = `http://localhost:${sandbox.port}`;
});
test.after(async () => { await sandbox?.close(); });

test('existing dealer logs in with the password behind the copied hash; details kept', async () => {
  assert.equal((await http('POST', '/api/auth/login', { identifier: 'real.dealer@example.test', password: 'wrong-password' })).body.token, undefined);
  const login = await http('POST', '/api/auth/login', { identifier: 'real.dealer@example.test', password: DEALER_PASSWORD });
  assert.equal(login.status, 200, JSON.stringify(login.body));
  assert.equal(login.body.user.id, 'user_1791538245915_77', 'same dealer id');
  const token = login.body.token;
  const orders = await http('GET', '/api/user/orders?email=real.dealer%40example.test', null, token);
  assert.equal(orders.status, 200);
  assert.deepEqual(orders.body.orders.map(o => o.orderId), ['RO-old-1'], 'existing order kept');
  assert.equal(orders.body.orders[0].items[0].sku, 'RO-MEM-75', 'order line SKU filled by the local PDF import');
  const addresses = await http('GET', '/api/user/addresses?email=real.dealer%40example.test', null, token);
  assert.ok(JSON.stringify(addresses.body).includes('600040'), 'address kept');
  const pending = await http('POST', '/api/auth/login', { identifier: 'pending.dealer@example.test', password: DEALER_PASSWORD });
  assert.equal(pending.status, 200, 'approval status kept (verified pending dealers may sign in, as on live)');
  assert.equal(pending.body.user.status, 'pending');
});

test('admin login is the one from .env; shop employee logs in with the copied hash', async () => {
  const admin = await http('POST', '/api/admin/login', { email: 'owner@example.test', password: 'Admin#Pass2026' });
  assert.equal(admin.status, 200);
  const dealers = await http('GET', '/api/admin/dealers', null, admin.body.token);
  assert.equal((dealers.body.dealers || dealers.body.users).length, 2);
  const shop = await http('POST', '/api/shop/auth/login', { loginId: 'ROSHOP01', password: SHOP_PASSWORD });
  assert.equal(shop.status, 200, JSON.stringify(shop.body));
  const shopOrders = await http('GET', '/api/shop/orders', null, shop.body.token);
  assert.ok(shopOrders.body.orders.some(o => (o.orderId || o.order_id) === 'RO-old-1'), 'existing order visible in the Shop App');
});

test('new local rows continue after the copied ids', async () => {
  const login = await http('POST', '/api/auth/login', { identifier: 'real.dealer@example.test', password: DEALER_PASSWORD });
  const add = await http('POST', '/api/cart/add', { userId: login.body.user.id, productId: 'prod_genuine_1', quantity: 1 }, login.body.token);
  assert.equal(add.status, 200, JSON.stringify(add.body));
  const order = await http('POST', '/api/user/orders/create', {
    email: 'real.dealer@example.test', paymentMethod: 'Cash on Delivery', deliveryAddress: '14 Gandhi Road', items: [{ id: 'prod_genuine_1', quantity: 1 }],
  }, login.body.token);
  assert.equal(order.status, 200, JSON.stringify(order.body));
  const ids = (await sandbox.db.query('SELECT id FROM order_items ORDER BY id')).rows.map(r => Number(r.id));
  assert.ok(ids.at(-1) > 41, `new order line id ${ids.at(-1)} follows the copied 41`);
});

test('PDF import applied to the local copy only; pictures served locally', async () => {
  assert.equal(sandbox.pdf.inserted, 78);
  const products = (await http('GET', '/api/products')).body.products;
  assert.equal(products.length, 79 + 41, '1 kept + 78 PDF products + 41 Cabinet products');
  assert.equal(products.filter(p => p.category === 'cabinets').length, 41);
  assert.equal(sandbox.pdf.cabinet.inserted, 41);
  assert.ok(!products.some(p => p.id.startsWith('SAMPLE_')));
  const img = products.find(p => p.sku === 'DOM-27').img;
  assert.equal(img, '/__pdf_images/DOM-27.jpg', 'site-relative: works from web and Android');
  const pic = await fetch(base + img);
  assert.equal(pic.status, 200);
  assert.match(pic.headers.get('content-type'), /image\/jpeg/);
});

test('isolated: localhost only, no credentials page, no live database, no .env secrets', async () => {
  assert.equal(sandbox.server.address().address, '127.0.0.1');
  // No credentials route: the address falls through to the normal web page.
  const page = await fetch(base + '/__sandbox/credentials');
  const text = await page.text();
  assert.ok(!/application\/json/.test(page.headers.get('content-type') || ''), 'no JSON answer');
  assert.ok(!text.includes('Admin#Pass2026') && !text.includes('owner@example.test'), 'no login data');
  const pg = require('pg');
  await assert.rejects(new pg.Client({ connectionString: 'postgres://u:p@127.0.0.1:5/db' }).connect(), /disabled in the local sandbox/);
  for (const key of ['SUPABASE_DB_URL', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_PUBLISHABLE_KEY', 'SMTP_PASS', 'DB_PASSWORD']) {
    assert.ok(!process.env[key], `${key} is blank`);
  }
  assert.equal(sandbox.credentials, null);
});

test('PDF preview: stock-0 products can be ordered 1..max; stock is not changed; max enforced', async () => {
  const login = await http('POST', '/api/auth/login', { identifier: 'real.dealer@example.test', password: DEALER_PASSWORD });
  const { token } = login.body;
  const userId = login.body.user.id;
  const product = (await http('GET', '/api/products')).body.products.find(p => p.sku === 'MUK-01');
  assert.equal(product.stock_quantity, 0, 'real stock stays 0 (never set from the PDF quantity)');
  assert.equal(product.stock_enforced, false, 'preview only');
  assert.equal(product.max_order_quantity, 10, 'PDF "10 nos" is the maximum');
  assert.equal(product.availability, 'in_stock');
  await http('DELETE', '/api/cart/clear', { userId }, token);
  assert.equal((await http('POST', '/api/cart/add', { userId, productId: product.id, quantity: 10 }, token)).status, 200);
  const over = await http('POST', '/api/cart/add', { userId, productId: product.id, quantity: 1 }, token);
  assert.equal(over.body.code, 'MAX_ORDER_QTY');
  assert.equal(over.body.max, 10);
  const order = await http('POST', '/api/user/orders/create', {
    email: 'real.dealer@example.test', paymentMethod: 'Cash on Delivery', deliveryAddress: '14 Gandhi Road', items: [{ id: product.id, quantity: 10 }],
  }, token);
  assert.equal(order.status, 200, JSON.stringify(order.body));
  const stock = (await sandbox.db.query('SELECT stock_quantity FROM products WHERE id = $1', [product.id])).rows[0].stock_quantity;
  assert.equal(stock, 0, 'stock unchanged in the preview');
  const tooMany = await http('POST', '/api/user/orders/create', {
    email: 'real.dealer@example.test', paymentMethod: 'Cash on Delivery', deliveryAddress: '14 Gandhi Road', items: [{ id: product.id, quantity: 11 }],
  }, token);
  assert.match(tooMany.body.error, /You can order a maximum of 10 units for this product/);
});
