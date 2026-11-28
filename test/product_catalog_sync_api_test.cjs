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
  if (s.startsWith('SELECT title FROM categories WHERE key_name = ?')) return [categories.filter(c => c.key_name === params[0]).map(c => ({ title: c.title }))];
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
    return [[{ id: p.id, name: p.name, sku: p.sku, brand: p.brand, mrp: p.mrp, cabinet_price: p.cabinet_price, img: p.img, description: p.description, status: p.status, category_key: p.category_key, category_title: c ? c.title : p.category_key }]];
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
// Cleanup removes only files created during this test. The list of files that
// were already there is taken FIRST, so a setup failure can never make the
// cleanup delete existing (tracked) uploads.
let uploadsRecorded = false;

test.before(async () => {
  for (const dir of [path.join(root, 'web_preview', 'uploads'), path.join(root, 'uploads')]) {
    if (fs.existsSync(dir)) { uploadsDir = uploadsDir || dir; for (const f of fs.readdirSync(dir)) uploadsBefore.add(path.join(dir, f)); }
  }
  uploadsRecorded = true;
  process.env.PORT = '0';
  // Self-contained: no .env needed (e.g. GitHub Actions); a set value is kept.
  process.env.SESSION_SECRET = process.env.SESSION_SECRET || 'test-session-secret-not-for-production';
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
});

test.after(async () => {
  // Remove only the image files this test wrote (never anything if the list of
  // existing files was not recorded).
  for (const dir of uploadsRecorded ? [path.join(root, 'web_preview', 'uploads'), path.join(root, 'uploads')] : []) {
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
  // No product / store link on the page (sharing carries no URL).
  assert.doesNotMatch(html, /View product in store|<a\s[^>]*href=/);
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

test('share page: an old demo image name is "no picture yet" (placeholder, no og:image) at a fixed public address', async () => {
  process.env.PUBLIC_BASE_URL = 'https://ro-mobileapp.onrender.com/';
  try {
    const html = await (await fetch(`${base}/share/products/SAMPLE_1`)).text();
    const og = name => (html.match(new RegExp(`<meta property="${name}" content="([^"]*)"`)) || [])[1];
    // SAMPLE_1 still stores the shared demo name membrane.jpg: nothing is
    // substituted (no sprite tile, no other product's photo).
    assert.equal(og('og:image'), undefined);
    assert.equal(html.includes('twitter:image'), false);
    assert.match(html, /<meta name="twitter:card" content="summary">/);
    assert.match(html, /<div class="photo"><img src="data:image\/svg\+xml,/);
    assert.equal(html.includes('catalog-'), false);
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
});

test("each product shares its own picture, never another product's", async () => {
  const add = (id, sku, category_key, category_id, img) => products.push({ id, category_id, category_key, sku, name: id, brand: 'B', purchase_price: 1, price: 2, mrp: 3, img, description: '', status: 'active', created_at: new Date() });
  add('P_CTO', 'RO-FLT-CTO', 'filters', null, 'cat_filter.jpg');
  add('P_INLINE', 'RO-FLT-INLINE', 'filters', null, 'cat_filter.jpg');
  add('P_PUMP', 'RO-PMP-300', 'pumps', null, 'cat_pump.jpg');
  add('P_NEW_SPARE', 'NEW-SPARE-1', 'spares', 'CAT_SPR', 'purifier.jpg');
  add('P_EMPTY', 'NEW-EMPTY-1', 'spares', 'CAT_SPR', '');
  const SUPA = 'https://example.supabase.co/storage/v1/object/public/ro-product-images/pdf-catalog/P-SUPA.jpg';
  add('P_SUPA', 'P-SUPA', 'spares', 'CAT_SPR', SUPA);
  const ogImage = async id => {
    const html = await (await fetch(`${base}/share/products/${id}`)).text();
    return (html.match(/<meta property="og:image" content="([^"]*)"/) || [])[1];
  };
  // Old shared demo names and empty images: no picture, nothing substituted.
  for (const id of ['P_CTO', 'P_INLINE', 'P_PUMP', 'P_NEW_SPARE', 'P_EMPTY']) {
    assert.equal(await ogImage(id), undefined, id);
  }
  // A Supabase Storage address is shared exactly as stored.
  assert.equal(await ogImage('P_SUPA'), SUPA);
  // A real uploaded photo is shared as-is.
  const uploaded = await ogImage((await catalog()).find(x => x.sku === 'AQUA-001').id);
  assert.match(uploaded, /\/uploads\/prod_\d+_\d+\.png$/);
  const res = await fetch(base + new URL(uploaded).pathname);
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /^image\//);
});

test('GET /share/products/:id/image returns each product\'s own image file', async () => {
  const get = async id => {
    const res = await fetch(`${base}/share/products/${id}/image`);
    return { status: res.status, type: res.headers.get('content-type'), cors: res.headers.get('access-control-allow-origin'), disposition: res.headers.get('content-disposition'), bytes: Buffer.from(await res.arrayBuffer()) };
  };
  // No picture yet (old demo name or empty): 404, never a substitute picture.
  for (const id of ['P_CTO', 'P_INLINE', 'P_EMPTY']) assert.equal((await get(id)).status, 404, id);

  const uploadedId = (await catalog()).find(x => x.sku === 'AQUA-001').id;
  const uploaded = await get(uploadedId);
  assert.equal(uploaded.status, 200);
  assert.equal(uploaded.type, 'image/png');
  assert.equal(uploaded.cors, '*');
  assert.match(uploaded.disposition, /filename="AQUA-001\.png"/);
  assert.deepEqual(uploaded.bytes, png, 'the uploaded photo itself');

  assert.equal((await get('does-not-exist')).status, 404);
  assert.equal((await get('HIDDEN')).status, 404);
});

test('share page: category of the page it is shared from (RO Systems lists Cabinet products)', async () => {
  const extra = [
    { id: 'CAT_SYS', key_name: 'systems', title: 'RO Systems', display_order: 1 },
    { id: 'CAT_CAB', key_name: 'cabinets', title: 'Cabinet', display_order: 7 },
  ];
  categories.push(...extra);
  const add = (id, category_key, category_id) => products.push({ id, category_id, category_key, sku: id, name: id, brand: 'B', purchase_price: 1, price: 2, mrp: 3, cabinet_price: category_key === 'cabinets' ? 1850 : null, img: '', description: '', status: 'active', created_at: new Date() });
  add('CTX_CAB', 'cabinets', 'CAT_CAB');
  add('CTX_SYS', 'systems', 'CAT_SYS');
  try {
    const page = async (id, query = '') => {
      const html = await (await fetch(`${base}/share/products/${id}${query}`)).text();
      return {
        html,
        price: (html.match(/<p class="mrp"><small>([^<]*)<\/small>([^<]*)<\/p>/) || []).slice(1).join(' '),
        title: (html.match(/<meta property="og:title" content="([^"]*)"/) || [])[1],
        category: (html.match(/<dt>Category<\/dt><dd>([^<]*)<\/dd>/) || [])[1],
        ogUrl: (html.match(/<meta property="og:url" content="([^"]*)"/) || [])[1],
        links: (html.match(/<a\s[^>]*href=/g) || []).length,
      };
    };
    const fromRo = await page('CTX_CAB', '?view=ro-systems');
    assert.equal(fromRo.category, 'RO Systems');
    assert.match(fromRo.ogUrl, /\/share\/products\/CTX_CAB\?view=ro-systems$/);
    assert.equal(fromRo.links, 0, 'no store link');
    const fromCab = await page('CTX_CAB', '?view=cabinet');
    assert.equal(fromCab.category, 'Cabinet');
    // Shared from the Cabinet page: Cabinet Price only, no MRP / Dealer Price.
    assert.equal(fromCab.price, 'Cabinet Price ₹1,850');
    assert.equal(fromCab.title, 'CTX_CAB — Cabinet Price ₹1,850');
    for (const hidden of ['MRP', 'Dealer Price', '₹3']) assert.equal(fromCab.html.includes(hidden), false, hidden);
    assert.equal(fromRo.price, 'MRP ₹3', 'RO Systems page: MRP');
    assert.equal((await page('CTX_CAB')).price, 'MRP ₹3', 'no page: MRP');
    // A failed picture shows the water-drop placeholder, never another photo.
    assert.equal(fromCab.html.includes('purifier.jpg'), false);
    assert.match(fromCab.html, /onerror="this.onerror=null;this.src='data:image\/svg\+xml,/);
    assert.equal((await page('CTX_CAB')).category, 'Cabinet', 'no page: saved category');
    assert.equal((await page('CTX_SYS', '?view=ro-systems')).category, 'RO Systems');
    // A page never claims products it does not list; unknown values are ignored.
    const membrane = await page('SAMPLE_1', '?view=ro-systems');
    assert.equal(membrane.category, 'Membranes');
    assert.match(membrane.ogUrl, /\/share\/products\/SAMPLE_1$/);
    assert.equal((await page('CTX_SYS', '?view=cabinet')).category, 'RO Systems');
    assert.equal((await page('CTX_CAB', '?view=__proto__')).category, 'Cabinet');
  } finally {
    for (const c of extra) categories.splice(categories.indexOf(c), 1);
    for (const id of ['CTX_CAB', 'CTX_SYS']) products.splice(products.findIndex(p => p.id === id), 1);
  }
});

test('share page: no supplier/distributor references in the shared description', async () => {
  products.push({ id: 'DIST_1', category_id: 'CAT_SPR', category_key: 'spares', sku: 'DIST-1', name: 'Cabinet X', brand: '', purchase_price: 1, price: 2, mrp: 3,
    img: '', status: 'active', created_at: new Date(),
    description: 'Aqua cabinet in black (supplier photo). Distributors describe the Aqua 2090 cabinet as a 10-litre storage cabinet. The supplier lists a 1-year warranty.' });
  try {
    const html = await (await fetch(`${base}/share/products/DIST_1`)).text();
    assert.doesNotMatch(html, /distributor|supplier|price list|\(\s*\)/i);
    assert.match(html, /Aqua cabinet in black\. The Aqua 2090 cabinet is a 10-litre storage cabinet\. It comes with a 1-year warranty\./);
    assert.equal(products.find(p => p.id === 'DIST_1').description.includes('Distributors describe'), true, 'saved data unchanged');
  } finally {
    products.splice(products.findIndex(p => p.id === 'DIST_1'), 1);
  }
});
