// Admin Panel in a real browser: environment banners, "Saving to / Successfully
// saved to / save failed" statuses, read-back verification, conflicts, network
// failures and the typed-SKU delete. Uses a FAKE Production (the real server.js
// on the in-memory database) behind scripts/admin_production.cjs, plus a tiny
// static server for the wording checks. Nothing talks to the real Render API.
// Skipped when Google Chrome is not installed.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { startSandbox } = require('../scripts/local_sandbox.cjs');
const { startAdminProduction } = require('../scripts/admin_production.cjs');

const CHROME = ['C:/Program Files/Google/Chrome/Application/chrome.exe', '/usr/bin/google-chrome', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']
  .find(p => fs.existsSync(p));
const skip = CHROME ? false : 'Google Chrome is not installed';
const ADMIN_HTML = path.join(__dirname, '..', 'web_preview', 'admin.html');

let fake, proxy, browser, token, staticServer, staticBase;
const staticPuts = [];
test.before(async () => {
  if (skip) return;
  fake = await startSandbox({ port: 0, quiet: true });
  proxy = await startAdminProduction({ port: 0, target: `http://127.0.0.1:${fake.port}`, quiet: true });
  const { email, password } = fake.credentials.admin;
  token = (await (await fetch(`http://127.0.0.1:${proxy.port}/api/admin/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) })).json()).token;
  // Static server: the Admin Panel file as-is, with canned API answers (PUT ok/fail by query).
  staticServer = http.createServer((req, res) => {
    const json = (status, body) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };
    if (req.url.startsWith('/admin')) { res.writeHead(200, { 'content-type': 'text/html' }); return res.end(fs.readFileSync(ADMIN_HTML)); }
    if (req.url.startsWith('/api/admin/session')) return json(200, { success: true, authenticated: true });
    if (req.method === 'PUT') { staticPuts.push(req.url); return req.url.includes('fail') ? json(503, { success: false, error: 'database is unavailable.' }) : json(200, { success: true }); }
    if (req.url.startsWith('/api/')) return json(200, { success: true, products: [], categories: [], dealers: [], orders: [], claims: [], stats: {} });
    res.writeHead(404); res.end();
  });
  await new Promise(r => staticServer.listen(0, '127.0.0.1', r));
  staticBase = `http://127.0.0.1:${staticServer.address().port}`;
  const puppeteer = require('puppeteer-core');
  browser = await puppeteer.launch({ executablePath: CHROME, headless: 'new' });
});
test.after(async () => {
  await browser?.close();
  await proxy?.close();
  await fake?.close();
  if (staticServer) await new Promise(r => staticServer.close(r));
});

async function openAdmin(url, { env, answers = [] } = {}) {
  const page = await browser.newPage();
  await page.setViewport({ width: 1400, height: 900 });
  await page.evaluateOnNewDocument((t, injected) => {
    sessionStorage.setItem('admin_token', t);
    localStorage.setItem('admin_token', t);
    if (injected) window.__ADMIN_ENV = injected;
    window.__statusLog = [];
    document.addEventListener('DOMContentLoaded', () => {
      const text = document.getElementById('writeStatusText');
      new MutationObserver(() => window.__statusLog.push(text.textContent)).observe(text, { childList: true, characterData: true, subtree: true });
    });
  }, token, env || null);
  page.on('dialog', d => d.type() === 'prompt' ? d.accept(answers.shift() ?? '') : d.accept());
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => typeof ADMIN_ENV !== 'undefined' && ADMIN_ENV.mode !== 'detecting', { timeout: 20000 });
  return page;
}
const finalStatus = async page => {
  await page.waitForFunction(() => ['success', 'failed', 'warning'].includes(document.getElementById('writeStatus').dataset.state), { timeout: 20000 });
  return page.evaluate(() => ({ state: document.getElementById('writeStatus').dataset.state, text: document.getElementById('writeStatusText').textContent, log: window.__statusLog }));
};
const row = async id => (await fake.db.query('SELECT * FROM products WHERE id = $1', [id])).rows[0];
async function editProduct(page, id, desc) {
  await page.waitForFunction(i => Array.isArray(allProducts) && allProducts.some(p => p.id === i), { timeout: 20000 }, id);
  await page.evaluate((i, d) => {
    openProductModal(i);
    document.getElementById('prodDesc').value = d;
    const stock = document.getElementById('prodStockQuantity');
    if (!stock.value) stock.value = '5';
  }, id, desc);
}
const submit = page => page.evaluate(() => { hideWriteStatus(); document.getElementById('productForm').requestSubmit(); });
let testProduct;
async function product() {
  if (!testProduct) {
    await fake.db.query(`INSERT INTO products (id, category_id, category_key, sku, name, brand, price, mrp, moq, img, status, stock_quantity, description)
      VALUES ('PDF_E2E_01', (SELECT id FROM categories WHERE key_name = 'membranes'), 'membranes', 'E2E-01', 'E2E Membrane', '', 1200, 2800, '40 nos', '', 'active', 5, 'Original'),
             ('PDF_E2E_02', (SELECT id FROM categories WHERE key_name = 'membranes'), 'membranes', 'E2E-02', 'E2E Delete Me', '', 1200, 2800, '40 nos', '', 'active', 5, 'Original')`);
    testProduct = 'PDF_E2E_01';
  }
  return testProduct;
}

test('Local Admin (proxy) on a test target: banner, Upload Image hidden, Supabase picker kept', { skip }, async () => {
  const page = await openAdmin(`http://127.0.0.1:${proxy.port}/admin`);
  const ui = await page.evaluate(() => ({
    banner: document.getElementById('adminEnvBanner').textContent,
    cls: document.getElementById('adminEnvBanner').className,
    upload: getComputedStyle(document.getElementById('prodUploadImageBtn')).display,
    picker: getComputedStyle(document.getElementById('openStoragePickerBtn')).display,
  }));
  assert.match(ui.banner, /^TEST TARGET \(not Production\): http:\/\/127\.0\.0\.1:\d+$/);
  assert.match(ui.cls, /test-target/);
  assert.equal(ui.upload, 'none');
  assert.notEqual(ui.picker, 'none');
  await page.close();
});

test('a save shows "Saving to…", is read back, then "Successfully saved to…"', { skip }, async () => {
  const id = await product();
  const page = await openAdmin(`http://127.0.0.1:${proxy.port}/admin`);
  await editProduct(page, id, 'Edited in the browser');
  await submit(page);
  const s = await finalStatus(page);
  assert.equal(s.state, 'success', s.text);
  assert.equal(s.text, 'Successfully saved to Test target.');
  assert.ok(s.log.includes('Saving to Test target...'), JSON.stringify(s.log));
  assert.ok(s.log.includes('Confirming the saved data in Test target...'));
  assert.equal((await row(id)).description, 'Edited in the browser');
  assert.equal(await page.evaluate(() => document.getElementById('productModal').style.display), 'none');
  await page.close();
});

test('someone else changed the product after the form was opened: refused, their change kept', { skip }, async () => {
  const id = await product();
  const page = await openAdmin(`http://127.0.0.1:${proxy.port}/admin`);
  await editProduct(page, id, 'My late edit');
  await fake.db.query(`UPDATE products SET description = 'Changed by someone else' WHERE id = $1`, [id]);
  await submit(page);
  const s = await finalStatus(page);
  assert.equal(s.state, 'failed');
  assert.match(s.text, /^Test target save failed\. Changes were not saved\.\nThis product was changed by someone else/);
  assert.equal((await row(id)).description, 'Changed by someone else');
  assert.notEqual(await page.evaluate(() => document.getElementById('productModal').style.display), 'none', 'form stays open');
  await page.close();
});

test('server error: "save failed. Changes were not saved." and nothing changes', { skip }, async () => {
  const id = await product();
  const before = await row(id);
  const page = await openAdmin(`http://127.0.0.1:${proxy.port}/admin`);
  await page.setRequestInterception(true);
  page.on('request', r => (r.method() === 'PUT'
    ? r.respond({ status: 503, contentType: 'application/json', body: JSON.stringify({ success: false, error: 'database is unavailable. Product was not updated.' }) })
    : r.continue()));
  await editProduct(page, id, 'Should not be saved');
  await submit(page);
  const s = await finalStatus(page);
  assert.equal(s.state, 'failed');
  assert.equal(s.text, 'Test target save failed. Changes were not saved.\ndatabase is unavailable. Product was not updated.');
  assert.deepEqual(await row(id), before);
  await page.close();
});

test('server says success but did not save: never shown as success', { skip }, async () => {
  const id = await product();
  const page = await openAdmin(`http://127.0.0.1:${proxy.port}/admin`);
  await page.setRequestInterception(true);
  page.on('request', r => (r.method() === 'PUT'
    ? r.respond({ status: 200, contentType: 'application/json', body: JSON.stringify({ success: true }) })
    : r.continue()));
  await editProduct(page, id, 'Claimed but not saved');
  await submit(page);
  const s = await finalStatus(page);
  assert.equal(s.state, 'warning');
  assert.match(s.text, /reported success, but the read-back does not match \(different: description\)/);
  assert.ok(!s.log.some(t => /^Successfully/.test(t)));
  await page.close();
});

test('network failure: the data is read back; unchanged = "save failed"', { skip }, async () => {
  const id = await product();
  const before = await row(id);
  const page = await openAdmin(`http://127.0.0.1:${proxy.port}/admin`);
  await page.setRequestInterception(true);
  page.on('request', r => (r.method() === 'PUT' ? r.abort('connectionreset') : r.continue()));
  await editProduct(page, id, 'Lost on the way');
  await submit(page);
  const s = await finalStatus(page);
  assert.equal(s.state, 'failed');
  assert.match(s.text, /^Test target save failed\. Changes were not saved\.\nTest target did not answer, and the data is unchanged\.$/);
  assert.ok(s.log.some(t => /Reading the data back/.test(t)));
  assert.deepEqual(await row(id), before);
  await page.close();
});

test('delete needs the exact SKU typed; then it is removed and confirmed', { skip }, async () => {
  await product();
  const page = await openAdmin(`http://127.0.0.1:${proxy.port}/admin`, { answers: ['WRONG', 'e2e-02'] });
  await page.waitForFunction(() => allProducts.some(p => p.id === 'PDF_E2E_02'), { timeout: 20000 });
  await page.evaluate(() => deleteProduct('PDF_E2E_02', 'E2E Delete Me'));
  let s = await finalStatus(page);
  assert.equal(s.state, 'failed');
  assert.match(s.text, /Not deleted: the SKU you typed does not match E2E-02/);
  assert.ok(await row('PDF_E2E_02'), 'still there');
  await page.evaluate(() => { hideWriteStatus(); return deleteProduct('PDF_E2E_02', 'E2E Delete Me'); });
  s = await finalStatus(page);
  assert.equal(s.state, 'success', s.text);
  assert.equal(await row('PDF_E2E_02'), undefined);
  await page.close();
});

test('the local sandbox Admin Panel says LOCAL TEST COPY and never "Production"', { skip }, async () => {
  const id = await product();
  const page = await openAdmin(`http://127.0.0.1:${fake.port}/admin`);
  const ui = await page.evaluate(() => ({ banner: document.getElementById('adminEnvBanner').textContent, upload: getComputedStyle(document.getElementById('prodUploadImageBtn')).display }));
  assert.match(ui.banner, /^LOCAL TEST COPY — changes are NOT saved to Production/);
  assert.notEqual(ui.upload, 'none', 'Upload Image stays available in the test copy');
  await editProduct(page, id, 'Sandbox edit');
  await submit(page);
  const s = await finalStatus(page);
  assert.equal(s.text, 'Successfully saved to the LOCAL TEST COPY only — NOT saved to Production.');
  assert.ok(s.log.includes('Saving to LOCAL TEST COPY...'));
  await page.close();
});

test('real Production wording (no request leaves this computer)', { skip }, async () => {
  const env = { mode: 'production', realProduction: true, target: 'https://ro-mobileapp.onrender.com' };
  const page = await openAdmin(`${staticBase}/admin`, { env });
  const banner = await page.evaluate(() => document.getElementById('adminEnvBanner').textContent);
  assert.equal(banner, '● PRODUCTION — every save goes to the live database and appears in the Web and Android apps');
  // Hidden on the login page, shown again after sign-in.
  const shown = () => page.evaluate(() => getComputedStyle(document.getElementById('adminEnvBanner')).display !== 'none');
  await page.evaluate(() => showAdminLoginScreen());
  assert.equal(await shown(), false, 'no Production banner on the login page');
  await page.evaluate(() => hideAdminLoginScreen());
  assert.equal(await shown(), true, 'Production banner after sign-in');
  await page.evaluate(() => adminWrite({ method: 'PUT', url: '/api/admin/products/fail', body: {}, verify: async () => ({ ok: true }) }));
  let s = await finalStatus(page);
  assert.equal(s.text, 'Production save failed. Changes were not saved.\ndatabase is unavailable.');
  assert.ok(s.log.includes('Saving to Production...'));
  await page.evaluate(() => { hideWriteStatus(); return adminWrite({ method: 'PUT', url: '/api/admin/products/ok', body: {}, verify: async () => ({ ok: true }) }); });
  s = await finalStatus(page);
  assert.equal(s.text, 'Successfully saved to Production.');
  assert.deepEqual(staticPuts, ['/api/admin/products/fail', '/api/admin/products/ok'], 'went to the local static server only');
  await page.close();
});

test('an unidentified local server: banner says so and saving is disabled', { skip }, async () => {
  const before = staticPuts.length;
  const page = await openAdmin(`${staticBase}/admin`);
  const banner = await page.evaluate(() => document.getElementById('adminEnvBanner').textContent);
  assert.match(banner, /^Unknown server — saving is disabled/);
  await page.evaluate(() => adminWrite({ method: 'PUT', url: '/api/admin/products/ok', body: {}, verify: async () => ({ ok: true }) }));
  const s = await finalStatus(page);
  assert.equal(s.state, 'failed');
  assert.match(s.text, /^Saving is disabled/);
  assert.equal(staticPuts.length, before, 'nothing was sent');
  await page.close();
});

test('unreleased local Admin UI: warning banner, save refused by the page AND by the proxy', { skip }, async () => {
  const id = await product();
  const before = await row(id);
  // Target: the fake Production API, but a different deployed /admin page.
  const target = http.createServer(async (req, res) => {
    if (req.url.startsWith('/admin')) { res.writeHead(200, { 'content-type': 'text/html' }); return res.end('<html><head></head><body>older deployed admin</body></html>'); }
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const up = await fetch(`http://127.0.0.1:${fake.port}${req.url}`, { method: req.method, headers: Object.fromEntries(Object.entries(req.headers).filter(([k]) => ['content-type', 'authorization'].includes(k))), body: chunks.length ? Buffer.concat(chunks) : undefined });
    res.writeHead(up.status, { 'content-type': up.headers.get('content-type') || 'application/json' });
    res.end(Buffer.from(await up.arrayBuffer()));
  });
  await new Promise(r => target.listen(0, '127.0.0.1', r));
  const blockedProxy = await startAdminProduction({ port: 0, target: `http://127.0.0.1:${target.address().port}`, quiet: true, uiCheckTimeoutMs: 2000 });
  try {
    const page = await openAdmin(`http://127.0.0.1:${blockedProxy.port}/admin`);
    const banner = await page.evaluate(() => document.getElementById('adminEnvBanner').textContent);
    assert.match(banner, /^⚠ LOCAL UNRELEASED ADMIN UI — This local Admin page differs from the deployed Production Admin/);
    assert.match(banner, /Saving to Test target is disabled\.$/);
    await editProduct(page, id, 'Unreleased UI edit');
    await submit(page);
    const s = await finalStatus(page);
    assert.equal(s.state, 'failed');
    assert.match(s.text, /^Saving is disabled\. This local Admin page differs/);
    // Even if the page's own check were bypassed, the proxy refuses the write.
    const direct = await page.evaluate(async (pid) => {
      const r = await adminFetch(`/api/admin/products/${encodeURIComponent(pid)}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: 'x', sku: 'E2E-01', desc: 'bypass' }) });
      return { status: r.status, body: await r.json() };
    }, id);
    assert.equal(direct.status, 423);
    assert.equal(direct.body.writesBlocked, true);
    assert.deepEqual(await row(id), before, 'nothing changed');
    await page.close();
  } finally {
    await blockedProxy.close();
    target.closeAllConnections();
    await new Promise(r => target.close(r));
  }
});
