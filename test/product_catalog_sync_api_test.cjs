// Runs the real server.js routes against an in-memory stand-in for the
// shared database: admin single add + bulk import, the customer catalog,
// product images (disk and database storage) and the public share page.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const categories = [
  { id: 'CAT_MEM', key_name: 'membranes', title: 'Membranes', display_order: 2 },
  { id: 'CAT_SPR', key_name: 'spares', title: 'Spare Parts & Valves', display_order: 6 },
];
const products = [
  { id: 'SAMPLE_1', category_id: 'CAT_MEM', category_key: 'membranes', sku: 'RO-MEM-75', name: 'RO Membrane 75 GPD', brand: 'RO Wholesale', purchase_price: 400, price: 650, mrp: 900, img: 'membrane.jpg', description: 'Existing', status: 'active', created_at: new Date('2026-10-09T08:16:36Z') },
  { id: 'NULL_STATUS', category_id: 'CAT_SPR', category_key: 'spares', sku: 'RO-NULL', name: 'Null Status Valve', brand: 'RO Wholesale', purchase_price: 10, price: 20, mrp: 30, img: '', description: '', status: null, created_at: new Date('2026-10-09T08:16:36Z') },
];
const images = new Map();
const sqlLog = [];

const PRODUCT_COLUMNS = ['id', 'category_id', 'category_key', 'sku', 'name', 'brand', 'purchase_price', 'price', 'mrp', 'moq', 'badge', 'rating', 'img', 'description', 'specs_json', 'features_json', 'applications', 'status', 'stock_quantity', 'min_stock'];

function categoryMatch(value) {
  const v = String(value).toLowerCase();
  return categories.filter(c => [c.id, c.key_name, c.title].some(x => x.toLowerCase() === v));
}

async function query(sql, params = []) {
  const s = sql.replace(/\s+/g, ' ').trim();
  sqlLog.push(s);
  if (s.startsWith('SELECT id FROM categories WHERE LOWER(id)')) return [categoryMatch(params[0]).map(c => ({ id: c.id }))];
  if (s.startsWith('SELECT id, key_name FROM categories')) return [categoryMatch(params[0])];
  if (s.startsWith('SELECT id, key_name, title FROM categories')) return [categories];
  if (s.startsWith('SELECT * FROM categories')) return [categories];
  if (s.startsWith('SELECT sku FROM products WHERE UPPER(sku)')) return [products.filter(p => p.sku.toUpperCase() === params[0])];
  if (s.startsWith('SELECT UPPER(sku) as sku FROM products')) return [products.map(p => ({ sku: p.sku.toUpperCase() }))];
  if (s.startsWith('INSERT INTO products')) {
    const row = Object.fromEntries(PRODUCT_COLUMNS.map((c, i) => [c, params[i]]));
    if (products.some(p => p.sku.toUpperCase() === row.sku.toUpperCase())) {
      const err = new Error('duplicate'); err.code = 'ER_DUP_ENTRY'; throw err;
    }
    products.push({ ...row, created_at: new Date() });
    return [{ affectedRows: 1 }];
  }
  if (s.startsWith('SELECT id, category_key, category_id, brand, name, price')) {
    assert.match(s, /COALESCE\(status, 'active'\) <> 'inactive'/);
    return [products.filter(p => (p.status || 'active') !== 'inactive')];
  }
  if (s.startsWith('SELECT * FROM products ORDER BY created_at DESC')) return [[...products].reverse()];
  if (s.includes('FROM products p LEFT JOIN categories c')) {
    const p = products.find(x => x.id === params[0]);
    if (!p) return [[]];
    const c = categories.find(x => x.id === p.category_id || x.key_name === p.category_key);
    // Only the columns the share query selects.
    return [[{ id: p.id, name: p.name, sku: p.sku, brand: p.brand, mrp: p.mrp, img: p.img, description: p.description, status: p.status, category_key: p.category_key, category_title: c ? c.title : p.category_key }]];
  }
  if (s.startsWith('INSERT INTO product_images')) {
    images.set(params[0], { content_type: params[1], bytes: params[2] });
    return [{ affectedRows: 1 }];
  }
  if (s.startsWith('SELECT content_type, bytes FROM product_images')) {
    const img = images.get(params[0]);
    return [img ? [img] : []];
  }
  return [[]];
}

let base;
let server;
let token;
const uploadsBefore = new Set();
let uploadsDir;

test.before(async () => {
  process.env.PORT = '0';
  process.env.ADMIN_EMAIL = 'admin@test.local';
  process.env.ADMIN_PASSWORD = 'test-password';
  delete process.env.PRODUCT_IMAGE_STORE;
  const dbPath = require.resolve(path.join(root, 'db'));
  require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: { pool: { query, end: async () => {} }, testConnection: async () => true } };
  const originalLog = console.log;
  console.log = () => {};
  ({ server } = require(path.join(root, 'server.js')));
  console.log = originalLog;
  if (!server.listening) await new Promise(r => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}`;
  const login = await fetch(`${base}/api/admin/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: 'admin@test.local', password: 'test-password' }) });
  token = (await login.json()).token;
  assert.ok(token, 'admin login');
  for (const dir of [path.join(root, 'web_preview', 'uploads'), path.join(root, 'uploads')]) {
    if (fs.existsSync(dir)) { uploadsDir = uploadsDir || dir; for (const f of fs.readdirSync(dir)) uploadsBefore.add(path.join(dir, f)); }
  }
});

test.after(async () => {
  // Remove only the image files this test wrote.
  for (const dir of [path.join(root, 'web_preview', 'uploads'), path.join(root, 'uploads')]) {
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      const full = path.join(dir, f);
      if (!uploadsBefore.has(full)) fs.rmSync(full, { force: true });
    }
  }
  server.closeAllConnections?.();
  await new Promise(r => server.close(r));
});

const png = fs.readFileSync(path.join(root, 'assets', 'images', 'RO_System.png'));
const dataUrl = `data:image/png;base64,${png.toString('base64')}`;
const admin = (url, body, method = 'POST') => fetch(base + url, {
  method,
  headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
  body: JSON.stringify(body),
});
const catalog = async () => (await (await fetch(`${base}/api/products`)).json()).products;

test('single product: validated, saved with its image, visible to customers', async () => {
  const bad = await admin('/api/admin/products', { stock_quantity: 5, name: 'Low MRP', sku: 'LOW-1', category: 'spares', brand: 'Aqua Mars', purchase_price: 7500, price: 8500, mrp: 8000 });
  assert.equal(bad.status, 400);
  assert.match((await bad.json()).error, /MRP cannot be lower/);

  const res = await admin('/api/admin/products', { stock_quantity: 5, name: 'Aqua Mars RO 100 GPD', sku: 'aqua-001', category: 'Spare Parts & Valves', brand: 'Aqua Mars', purchase_price: 7500, price: 8500, mrp: 12000, desc: 'Compact RO unit', img: dataUrl, status: 'active' });
  assert.equal(res.status, 201);
  const saved = (await res.json()).product;
  assert.match(saved.img, /^\/uploads\/prod_\d+_\d+\.png$/);
  assert.equal(saved.category_id, 'CAT_SPR');

  // The uploaded file is served by the same server.
  const img = await fetch(base + saved.img);
  assert.equal(img.status, 200);
  assert.deepEqual(Buffer.from(await img.arrayBuffer()), png);

  const list = await catalog();
  const p = list.find(x => x.sku === 'AQUA-001');
  assert.ok(p, 'new product is in the customer catalog');
  assert.equal(p.category, 'spares');
  assert.equal(p.dealer_price, 8500);
  assert.equal(p.mrp, 12000);
  assert.ok(p.created_at);
  assert.equal('purchase_price' in p, false);
  assert.ok(list.some(x => x.id === 'NULL_STATUS'), 'NULL status counts as active, as in the admin panel');

  const adminList = (await (await fetch(`${base}/api/admin/products`, { headers: { Authorization: `Bearer ${token}` } })).json()).products;
  assert.equal(adminList.find(x => x.sku === 'AQUA-001').purchase_price, 7500);
});

test('bulk upload: valid rows saved, invalid and duplicate rows reported', async () => {
  const res = await admin('/api/admin/products/bulk', { products: [
    { stock_quantity: 5, name: 'Bulk Membrane 80', sku: 'BULK-M80', category: 'membranes', brand: 'Aqua Mars', purchase_price: 500, price: 700, mrp: 950 },
    { stock_quantity: 5, name: 'Bulk Valve', sku: 'BULK-V1', category: 'Spare Parts & Valves', brand: 'Aqua Mars', purchase_price: 50, price: 80, mrp: 120 },
    { stock_quantity: 5, name: 'Dup in sheet', sku: 'BULK-V1', category: 'spares', brand: 'X', purchase_price: 1, price: 2, mrp: 3 },
    { stock_quantity: 5, name: 'Already exists', sku: 'AQUA-001', category: 'spares', brand: 'X', purchase_price: 1, price: 2, mrp: 3 },
    { stock_quantity: 5, name: 'Low MRP', sku: 'BULK-LOW', category: 'spares', brand: 'X', purchase_price: 1, price: 20, mrp: 10 },
    { stock_quantity: 5, name: 'No category', sku: 'BULK-NOCAT', category: 'unknown', brand: 'X', purchase_price: 1, price: 2, mrp: 3 },
  ] });
  assert.equal(res.status, 201);
  const body = await res.json();
  assert.equal(body.importedCount, 2);
  assert.equal(body.skippedCount, 4);
  const list = await catalog();
  assert.equal(list.find(x => x.sku === 'BULK-M80').category, 'membranes');
  assert.equal(list.find(x => x.sku === 'BULK-V1').category, 'spares');
  assert.equal(list.filter(x => x.sku === 'BULK-V1').length, 1, 'no duplicate product');
  assert.equal(list.some(x => x.sku === 'BULK-LOW'), false);
});

test('database image storage serves the same image from any server', async () => {
  process.env.PRODUCT_IMAGE_STORE = 'database';
  try {
    const res = await admin('/api/admin/products', { stock_quantity: 5, name: 'DB Image Pump', sku: 'DB-IMG-1', category: 'spares', brand: 'Aqua Mars', purchase_price: 1, price: 2, mrp: 3, img: dataUrl });
    const saved = (await res.json()).product;
    assert.match(saved.img, /^\/api\/product-images\/img_\d+_[0-9a-f]+\.png$/);
    const img = await fetch(base + saved.img);
    assert.equal(img.status, 200);
    assert.equal(img.headers.get('content-type'), 'image/png');
    assert.deepEqual(Buffer.from(await img.arrayBuffer()), png);
    assert.equal((await fetch(`${base}/api/product-images/img_1_ab.png`)).status, 404);
  } finally {
    delete process.env.PRODUCT_IMAGE_STORE;
  }
});

test('share page: rich preview with image and MRP only, never dealer or purchase price', async () => {
  const p = (await catalog()).find(x => x.sku === 'AQUA-001');
  const res = await fetch(`${base}/share/products/${p.id}`, { headers: { 'X-Forwarded-Proto': 'https' } });
  assert.equal(res.status, 200);
  const html = await res.text();
  const og = name => (html.match(new RegExp(`<meta property="${name}" content="([^"]*)"`)) || [])[1];
  assert.equal(og('og:title'), 'Aqua Mars RO 100 GPD — MRP ₹12,000');
  assert.match(og('og:description'), /MRP ₹12,000 · Brand: Aqua Mars · Category: Spare Parts &amp; Valves · SKU: AQUA-001 — Compact RO unit/);
  assert.match(og('og:image'), /^https:\/\/127\.0\.0\.1:\d+\/uploads\/prod_\d+_\d+\.png$/);
  assert.equal(og('og:image:type'), 'image/png');
  assert.equal(og('og:image:width'), String(png.readUInt32BE(16)));
  assert.equal(og('og:image:height'), String(png.readUInt32BE(20)));
  assert.match(og('og:url'), new RegExp(`/share/products/${p.id}$`));
  assert.match(html, /View product in store/);
  // Dealer price 8,500 and purchase price 7,500 appear nowhere.
  for (const hidden of ['8500', '8,500', '7500', '7,500', 'Dealer Price', 'dealer_price', 'purchase']) {
    assert.equal(html.includes(hidden), false, `share page must not contain ${hidden}`);
  }
  const shareSql = sqlLog.filter(s => s.includes('FROM products p LEFT JOIN categories c'));
  assert.ok(shareSql.length);
  for (const s of shareSql) assert.doesNotMatch(s, /\bprice\b|purchase_price|dealer_price/);

  assert.equal((await fetch(`${base}/share/products/does-not-exist`)).status, 404);
});

test('share page hides inactive products', async () => {
  products.push({ id: 'HIDDEN', category_id: 'CAT_SPR', category_key: 'spares', sku: 'HIDDEN', name: 'Hidden', brand: 'X', purchase_price: 1, price: 2, mrp: 3, img: '', description: '', status: 'inactive', created_at: new Date() });
  assert.equal((await fetch(`${base}/share/products/HIDDEN`)).status, 404);
  assert.equal((await catalog()).some(x => x.id === 'HIDDEN'), false);
});

test('share page: bundled photos use small 800px JPEG previews and a fixed public address', async () => {
  process.env.PUBLIC_BASE_URL = 'https://ro-mobileapp.onrender.com/';
  try {
    const html = await (await fetch(`${base}/share/products/SAMPLE_1`)).text();
    const og = name => (html.match(new RegExp(`<meta property="${name}" content="([^"]*)"`)) || [])[1];
    // RO-MEM-75 is shown in the app as catalog tile 5, so the preview uses it.
    assert.equal(og('og:image'), 'https://ro-mobileapp.onrender.com/share-images/catalog-5.jpg');
    assert.equal(og('og:image:type'), 'image/jpeg');
    assert.equal(og('og:image:width'), '800');
    assert.equal(og('og:image:height'), '800');
    assert.equal(og('og:url'), 'https://ro-mobileapp.onrender.com/share/products/SAMPLE_1');
    assert.equal(html.includes('localhost'), false);
    assert.equal(html.includes('127.0.0.1'), false);
    for (const hidden of ['650', '400']) {
      const at = html.indexOf(hidden);
      assert.equal(at, -1, `price ${hidden} leaked near: ${html.slice(at - 60, at + 20)}`);
    }
  } finally {
    delete process.env.PUBLIC_BASE_URL;
  }
  // The preview image itself is served and small enough for WhatsApp.
  const img = await fetch(`${base}/share-images/catalog-5.jpg`);
  assert.equal(img.status, 200);
  assert.match(img.headers.get('content-type'), /image\/jpeg/);
  assert.ok((await img.arrayBuffer()).byteLength < 300 * 1024);
});

test("each product shares its own picture, never another product's", async () => {
  const add = (id, sku, category_key, category_id, img) => products.push({ id, category_id, category_key, sku, name: id, brand: 'B', purchase_price: 1, price: 2, mrp: 3, img, description: '', status: 'active', created_at: new Date() });
  add('P_CTO', 'RO-FLT-CTO', 'filters', null, 'cat_filter.jpg');
  add('P_INLINE', 'RO-FLT-INLINE', 'filters', null, 'cat_filter.jpg');
  add('P_PUMP', 'RO-PMP-300', 'pumps', null, 'cat_pump.jpg');
  add('P_NEW_SPARE', 'NEW-SPARE-1', 'spares', 'CAT_SPR', 'purifier.jpg');
  const ogImage = async id => {
    const html = await (await fetch(`${base}/share/products/${id}`)).text();
    return (html.match(/<meta property="og:image" content="([^"]*)"/) || [])[1];
  };
  const urls = {
    cto: await ogImage('P_CTO'),
    inline: await ogImage('P_INLINE'),
    pump: await ogImage('P_PUMP'),
    newSpare: await ogImage('P_NEW_SPARE'),
    uploaded: await ogImage((await catalog()).find(x => x.sku === 'AQUA-001').id),
  };
  // Same stored placeholder, different products -> different pictures (as in the app).
  assert.match(urls.cto, /\/share-images\/catalog-0\.jpg$/);
  assert.match(urls.inline, /\/share-images\/catalog-1\.jpg$/);
  assert.match(urls.pump, /\/share-images\/catalog-12\.jpg$/);
  // Unknown SKU: the app's category rule (Spare Parts & Valves -> tile 13).
  assert.match(urls.newSpare, /\/share-images\/catalog-13\.jpg$/);
  // A real uploaded photo is shared as-is.
  assert.match(urls.uploaded, /\/uploads\/prod_\d+_\d+\.png$/);
  for (const u of Object.values(urls)) {
    const res = await fetch(base + new URL(u).pathname);
    assert.equal(res.status, 200, u);
    assert.match(res.headers.get('content-type'), /^image\//, u);
  }
});

test('GET /share/products/:id/image returns each product\'s own image file', async () => {
  const get = async id => {
    const res = await fetch(`${base}/share/products/${id}/image`);
    return { status: res.status, type: res.headers.get('content-type'), cors: res.headers.get('access-control-allow-origin'), disposition: res.headers.get('content-disposition'), bytes: Buffer.from(await res.arrayBuffer()) };
  };
  const tile = n => fs.readFileSync(path.join(root, 'web_preview', 'share-images', `catalog-${n}.jpg`));

  const cto = await get('P_CTO');
  assert.equal(cto.status, 200);
  assert.equal(cto.type, 'image/jpeg');
  assert.equal(cto.cors, '*');
  assert.match(cto.disposition, /filename="RO-FLT-CTO\.jpg"/);
  assert.deepEqual(cto.bytes, tile(0));

  const inline = await get('P_INLINE');
  assert.deepEqual(inline.bytes, tile(1));
  assert.notDeepEqual(inline.bytes, cto.bytes, 'same stored placeholder, different product picture');

  const uploadedId = (await catalog()).find(x => x.sku === 'AQUA-001').id;
  const uploaded = await get(uploadedId);
  assert.equal(uploaded.type, 'image/png');
  assert.deepEqual(uploaded.bytes, png, 'the uploaded photo itself');

  assert.equal((await get('does-not-exist')).status, 404);
  assert.equal((await get('HIDDEN')).status, 404);
});
