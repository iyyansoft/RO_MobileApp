// Admin "Choose from Supabase": read-only listing of ro-product-images/<folder>,
// admin-only, allowed folders only, encoded public URLs, the service key never
// leaves the server, and a chosen URL is saved exactly as given.
// Uses a fake Supabase URL/key and a stubbed fetch: no real Storage call is made.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { startSandbox } = require('../scripts/local_sandbox.cjs');
const { storagePublicUrl, storageListRequest, listStorageImages, listStorageFolders, categoryFolders, productImageProblem, PAGE_SIZE, CATEGORY_FOLDERS } = require('../storage_images');

const FAKE_URL = 'https://fakeproject.supabase.test';
const FAKE_KEY = 'test-service-key-never-sent-to-browser';
const file = (name, size = 1234, type = 'image/jpeg') => ({ id: `id-${name}`, name, metadata: { size, mimetype: type }, updated_at: '2026-11-21T00:00:00Z' });
const CABINETS = [
  file('Aqua 2090 -premium gray602 - Copy.webp', 22000, 'image/webp'),
  file('Aqua roma grey.jpg'), file('Dolphin king.jpg'), file('Canix white.jpg'),
  file('shoppingAqua 2090-black-203 - Copy.webp'), file('shoppingAqua 2090-black-203.webp'),
  file('notes.txt', 10, 'text/plain'),
  { id: null, name: 'subfolder', metadata: null },
];

test('public URLs encode spaces and special characters per path segment', () => {
  assert.equal(storagePublicUrl(FAKE_URL + '/', 'cabinets/Aqua 2090 -premium gray602 - Copy.webp'),
    `${FAKE_URL}/storage/v1/object/public/ro-product-images/cabinets/Aqua%202090%20-premium%20gray602%20-%20Copy.webp`);
  assert.equal(storagePublicUrl(FAKE_URL, 'pdf-catalog/A#1?x&y+z.jpg'),
    `${FAKE_URL}/storage/v1/object/public/ro-product-images/pdf-catalog/A%231%3Fx%26y%2Bz.jpg`);
});

const ROOT = [{ id: null, name: 'booster-pumps' }, { id: null, name: 'cabinets' }, { id: null, name: 'membrane' }, { id: null, name: 'pdf-catalog' }, file('stray.jpg')];

test('folders come from the bucket; category defaults prefer the matching folder', async () => {
  const fetchImpl = async (url, init) => ({ ok: true, json: async () => (JSON.parse(init.body).prefix === '' ? ROOT : []) });
  assert.deepEqual(await listStorageFolders({ supabaseUrl: FAKE_URL, serviceKey: FAKE_KEY, fetchImpl }), ['booster-pumps', 'cabinets', 'membrane', 'pdf-catalog']);
  const defaults = categoryFolders(['booster-pumps', 'cabinets', 'membrane', 'pdf-catalog']);
  assert.equal(defaults.pumps, 'booster-pumps');
  assert.equal(defaults.membranes, 'membrane');
  assert.equal(defaults.cabinets, 'cabinets');
  assert.equal(defaults.filters, 'pdf-catalog');
  assert.equal(categoryFolders(['cabinets', 'pdf-catalog']).pumps, 'pdf-catalog', 'falls back when booster-pumps does not exist');
  assert.equal(storageListRequest({ folder: 'booster-pumps' }, ['booster-pumps', 'cabinets']).folder, 'booster-pumps');
  assert.match(storageListRequest({ folder: 'booster-pumps' }, ['cabinets']).error, /Unknown folder/, 'only folders that exist');
});

test('a saved image must be one URL / path / file name', () => {
  for (const ok of ['', 'purifier.jpg', '/api/product-images/img_1_ab.jpg', '/uploads/prod_1.jpg', 'data:image/png;base64,AAA',
    `${FAKE_URL}/storage/v1/object/public/ro-product-images/booster-pumps/Max%20flow%20pump%201%20year%20warranty%20100%20gpd.jpg`]) assert.equal(productImageProblem(ok), null, ok);
  assert.match(productImageProblem('https://czeg.https://x.supabase.co/a.jpgupabase.co/b.jpg'), /two addresses joined/);
  assert.match(productImageProblem('https://x.supabase.co/a b.jpg'), /spaces/);
  assert.match(productImageProblem('x.jpg https://a.co/b.jpg'), /spaces/);
  assert.match(productImageProblem('ftp://a.co/b.jpg'), /https:\/\//);
  assert.match(productImageProblem('https://'), /not a valid/);
});

test('folder requests are checked; offsets are checked', () => {
  assert.deepEqual(storageListRequest({ folder: 'cabinets' }), { folder: 'cabinets', search: '', offset: 0 });
  assert.equal(storageListRequest({ folder: 'pdf-catalog', offset: '100', search: ' aqua ' }).search, 'aqua');
  for (const folder of ['', 'other', '../cabinets', 'cabinets/../x', 'cabinets/']) assert.match(storageListRequest({ folder }).error, /Unknown folder/, folder);
  for (const offset of ['-1', '1.5', 'abc', '999999']) assert.match(storageListRequest({ folder: 'cabinets', offset }).error, /offset/, offset);
  assert.equal(CATEGORY_FOLDERS.cabinets, 'cabinets', 'fallback defaults when the bucket cannot be listed');
  for (const key of ['systems', 'membranes', 'filters', 'pumps', 'pipes', 'spares']) assert.equal(CATEGORY_FOLDERS[key], 'pdf-catalog', key);
});

test('listing sends a read-only list request and returns pictures only, with paging', async () => {
  const calls = [];
  const fetchImpl = async (url, init) => { calls.push({ url, init }); return { ok: true, json: async () => CABINETS }; };
  const page = await listStorageImages({ supabaseUrl: FAKE_URL, serviceKey: FAKE_KEY, folder: 'cabinets', offset: 0, fetchImpl });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `${FAKE_URL}/storage/v1/object/list/ro-product-images`);
  assert.equal(calls[0].init.method, 'POST');
  assert.deepEqual(JSON.parse(calls[0].init.body), { prefix: 'cabinets/', limit: PAGE_SIZE, offset: 0, sortBy: { column: 'name', order: 'asc' } });
  // Search matches anywhere in the name, any case (Storage itself only matches the start).
  const found = await listStorageImages({ supabaseUrl: FAKE_URL, serviceKey: FAKE_KEY, folder: 'cabinets', search: 'ROMA', fetchImpl });
  assert.deepEqual(found.images.map(i => i.name), ['Aqua roma grey.jpg']);
  const aqua = await listStorageImages({ supabaseUrl: FAKE_URL, serviceKey: FAKE_KEY, folder: 'cabinets', search: 'aqua', fetchImpl });
  assert.equal(aqua.images.length, 4);
  assert.equal(aqua.hasMore, false);
  assert.deepEqual(page.images.map(i => i.name), CABINETS.slice(0, 6).map(f => f.name), 'folders and non-pictures skipped');
  assert.equal(page.images[1].url, `${FAKE_URL}/storage/v1/object/public/ro-product-images/cabinets/Aqua%20roma%20grey.jpg`);
  assert.equal(page.images[1].path, 'cabinets/Aqua roma grey.jpg', 'original file name kept');
  assert.equal(page.hasMore, false);
  assert.equal(page.nextOffset, CABINETS.length);
  const full = Array.from({ length: PAGE_SIZE }, (_, i) => file(`p${i}.jpg`));
  const more = await listStorageImages({ supabaseUrl: FAKE_URL, serviceKey: FAKE_KEY, folder: 'pdf-catalog', offset: 100, fetchImpl: async () => ({ ok: true, json: async () => full }) });
  assert.equal(more.hasMore, true);
  assert.equal(more.nextOffset, 200);
  await assert.rejects(listStorageImages({ supabaseUrl: FAKE_URL, serviceKey: FAKE_KEY, folder: 'cabinets', fetchImpl: async () => ({ ok: false, status: 403 }) }), /HTTP 403/);
  await assert.rejects(listStorageImages({ supabaseUrl: FAKE_URL, serviceKey: FAKE_KEY, folder: '../x', fetchImpl: async () => { throw new Error('must not be called'); } }), /Unknown folder/);
  const source = fs.readFileSync(path.join(__dirname, '..', 'storage_images.js'), 'utf8');
  assert.doesNotMatch(source, /object\/(upload|move|copy|remove)|method: '(DELETE|PUT)'/, 'module never writes to Storage');
});

test('Admin picker suggests an exact name/SKU match and prefers a clean original', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'web_preview', 'admin.html'), 'utf8');
  const a = html.indexOf('// STORAGE_PICKER_HELPERS_START'), b = html.indexOf('// STORAGE_PICKER_HELPERS_END');
  const { suggestStorageImage, storageNameKey } = new Function(`${html.slice(a, b)}; return { suggestStorageImage, storageNameKey };`)();
  const imgs = CABINETS.slice(0, 6).concat([file('DOM-02.jpg'), file('Aqua 2090 -premium gray602.webp')]);
  assert.equal(suggestStorageImage({ name: 'Aqua roma grey', sku: 'CAB-12' }, imgs), 'Aqua roma grey.jpg');
  assert.equal(suggestStorageImage({ name: 'Dolphin king/ABS', sku: 'CAB-01' }, imgs), 'Dolphin king.jpg');
  assert.equal(suggestStorageImage({ name: 'Aqua 2090 -premium gray602', sku: 'CAB-15' }, imgs), 'Aqua 2090 -premium gray602.webp', 'original preferred over " - Copy"');
  assert.equal(suggestStorageImage({ name: 'Aqua 2090-black-203', sku: 'CAB-17' }, imgs), 'shoppingAqua 2090-black-203.webp');
  assert.equal(suggestStorageImage({ name: '10" Copper Cartridge', sku: 'DOM-02' }, imgs), 'DOM-02.jpg', 'SKU match');
  assert.equal(suggestStorageImage({ name: 'Aqua roma cherry', sku: 'CAB-11' }, imgs), '', 'no guess: grey is not cherry');
  assert.equal(suggestStorageImage({ name: '', sku: '' }, imgs), '');
  assert.equal(storageNameKey('Under sink aquac3 -block'), storageNameKey('Under sink aquac3 block.jpg'));
  assert.match(html, /Choose from Supabase/);
  assert.match(html, /id="singleProdFileInput"/, 'Upload Image still present');
  assert.doesNotMatch(html, /SERVICE_ROLE|service_role/i, 'no service key in the page');
});

let sandbox, base, token, realFetch;
const env = {};
test.before(async () => {
  sandbox = await startSandbox({ port: 0, quiet: true });
  base = `http://localhost:${sandbox.port}`;
  const { email, password } = sandbox.credentials.admin;
  token = (await (await fetch(`${base}/api/admin/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) })).json()).token;
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']) env[k] = process.env[k];
  realFetch = global.fetch;
  global.fetch = async (url, init) => {
    if (String(url).startsWith(FAKE_URL)) {
      if (globalThis.__storageFail) return { ok: false, status: 500, json: async () => ({}) };
      return { ok: true, json: async () => (JSON.parse(init.body).prefix === '' ? ROOT : CABINETS) };
    }
    return realFetch(url, init);
  };
});
test.after(async () => {
  global.fetch = realFetch;
  for (const [k, v] of Object.entries(env)) process.env[k] = v;
  await sandbox?.close();
});
const get = async (url, auth = true) => {
  const res = await realFetch(base + url, { headers: auth ? { Authorization: `Bearer ${token}` } : {} });
  const text = await res.text();
  return { status: res.status, text, body: JSON.parse(text) };
};

test('endpoints: admin only; not configured -> 503 with a clear message', async () => {
  process.env.SUPABASE_URL = ''; process.env.SUPABASE_SERVICE_ROLE_KEY = '';
  assert.equal((await get('/api/admin/storage-images?folder=cabinets', false)).status, 401);
  assert.equal((await get('/api/admin/storage-folders', false)).status, 401);
  const folders = await get('/api/admin/storage-folders');
  assert.equal(folders.body.configured, false);
  assert.deepEqual(folders.body.folders, ['cabinets', 'pdf-catalog']);
  const off = await get('/api/admin/storage-images?folder=cabinets');
  assert.equal(off.status, 503);
  assert.match(off.body.error, /not set up/);
});

test('endpoints: list pictures with encoded public URLs; key never in a response; bad folder refused', async () => {
  process.env.SUPABASE_URL = FAKE_URL; process.env.SUPABASE_SERVICE_ROLE_KEY = FAKE_KEY;
  assert.equal((await get('/api/admin/storage-folders')).body.configured, true);
  const res = await get('/api/admin/storage-images?folder=cabinets');
  assert.equal(res.status, 200, res.text);
  assert.equal(res.body.images.length, 6);
  assert.deepEqual((await get('/api/admin/storage-images?folder=cabinets&search=roma%20grey')).body.images.map(i => i.name), ['Aqua roma grey.jpg']);
  assert.ok(res.body.images.every(i => i.url.startsWith(`${FAKE_URL}/storage/v1/object/public/ro-product-images/cabinets/`)));
  assert.ok(!res.text.includes(FAKE_KEY), 'service key not in the response');
  assert.equal((await get('/api/admin/storage-images?folder=../secret')).status, 400);
  globalThis.__storageFail = true;
  const failed = await get('/api/admin/storage-images?folder=pdf-catalog');
  globalThis.__storageFail = false;
  assert.equal(failed.status, 502);
  assert.ok(!failed.text.includes(FAKE_KEY));
});

test('a chosen Supabase URL is saved exactly (no copy, no /api/product-images/)', async () => {
  const url = storagePublicUrl(FAKE_URL, 'cabinets/Aqua roma grey.jpg');
  const before = (await sandbox.db.query(`SELECT * FROM products WHERE sku = 'RO-FLT-CTO'`)).rows[0];
  const imagesBefore = (await sandbox.db.query('SELECT count(*)::int n FROM product_images')).rows[0]?.n;
  const res = await realFetch(`${base}/api/admin/products/${before.id}`, {
    method: 'PUT', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ name: before.name, sku: before.sku, category: before.category_key, price: String(before.price), mrp: String(before.mrp), stock_quantity: before.stock_quantity, moq: before.moq || '', img: url }),
  });
  assert.equal(res.status, 200, await res.text());
  const after = (await sandbox.db.query(`SELECT * FROM products WHERE sku = 'RO-FLT-CTO'`)).rows[0];
  assert.equal(after.img, url);
  assert.equal((await sandbox.db.query('SELECT count(*)::int n FROM product_images')).rows[0]?.n, imagesBefore, 'no picture copied into the database');
  for (const k of ['price', 'mrp', 'stock_quantity', 'description', 'specs_json', 'features_json']) assert.deepEqual(after[k], before[k], k);
  const api = (await (await realFetch(`${base}/api/products`)).json()).products.find(p => p.sku === 'RO-FLT-CTO');
  assert.equal(api.img, url);
});

test('Save stores exactly the URL entered: API, share card and refresh follow it; a joined URL is refused', async () => {
  process.env.SUPABASE_URL = FAKE_URL; process.env.SUPABASE_SERVICE_ROLE_KEY = FAKE_KEY;
  const before = (await sandbox.db.query(`SELECT * FROM products WHERE sku = 'RO-PMP-100'`)).rows[0];
  const put = img => realFetch(`${base}/api/admin/products/${before.id}`, {
    method: 'PUT', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ name: before.name, sku: before.sku, category: before.category_key, price: String(before.price), mrp: String(before.mrp), stock_quantity: before.stock_quantity, moq: before.moq || '', img }),
  });
  const joined = `https://fakeproject.https://fakeproject.supabase.test/x.jpgupabase.test/y.jpg`;
  const refused = await put(joined);
  assert.equal(refused.status, 400);
  assert.match((await refused.json()).error, /two addresses joined/);
  assert.equal((await sandbox.db.query(`SELECT img FROM products WHERE sku = 'RO-PMP-100'`)).rows[0].img, before.img, 'refused value never stored');
  // A valid URL whose file name is a placeholder name ("membrane.jpg") is still used as-is.
  for (const url of [storagePublicUrl(FAKE_URL, 'booster-pumps/Max flow pump 1 year warranty 100 gpd.jpg'), storagePublicUrl(FAKE_URL, 'membrane/membrane.jpg')]) {
    const res = await put(url);
    assert.equal(res.status, 200, await res.text());
    assert.equal((await sandbox.db.query(`SELECT img FROM products WHERE sku = 'RO-PMP-100'`)).rows[0].img, url, 'database = entered URL');
    assert.equal((await (await realFetch(`${base}/api/products`)).json()).products.find(p => p.sku === 'RO-PMP-100').img, url, 'API = database');
    const share = await realFetch(`${base}/share/products/${before.id}/image`, { redirect: 'manual' });
    assert.equal(share.status, 302);
    assert.equal(share.headers.get('location'), url, 'WhatsApp card uses the same URL');
  }
  const bulk = await realFetch(`${base}/api/admin/products/bulk`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ dryRun: true, products: [{ row: 2, name: 'Joined', sku: 'JOINED-1', category: 'spares', price: '10', stock_quantity: '1', image: joined }] }) });
  assert.match(JSON.stringify(await bulk.json()), /two addresses joined/, 'bulk dry run reports it');
});

test('Admin page: pasting a full URL replaces the field; Save checks the image value', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'web_preview', 'admin.html'), 'utf8');
  const a = html.indexOf('// STORAGE_PICKER_HELPERS_START'), b = html.indexOf('// STORAGE_PICKER_HELPERS_END');
  const { pastedImageValue, productImageProblem: pageRule } = new Function(`${html.slice(a, b)}; return { pastedImageValue, productImageProblem };`)();
  assert.equal(pastedImageValue('  https://x.supabase.co/a%20b.jpg \n'), 'https://x.supabase.co/a%20b.jpg');
  assert.equal(pastedImageValue('partial text'), null);
  for (const v of ['', 'purifier.jpg', '/api/product-images/x.jpg', 'https://czeg.https://x.co/a.jpg', 'https://a.co/b c.jpg', 'ftp://a/b'])
    assert.equal(Boolean(pageRule(v)), Boolean(productImageProblem(v)), `page and server agree: ${v}`);
  assert.match(html, /onpaste="handleProductImagePaste\(event\)"/);
  assert.match(html, /const imgProblem = pendingProductImage \? null : productImageProblem\(imgInput.value\)/);
});
