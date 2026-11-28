// The local sandbox's Admin page: no full-width orange banner, a small LOCAL
// badge instead. Added by scripts/local_sandbox.cjs only; the shared
// web_preview/admin.html (Render, 8110 Production Admin) is unchanged.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { startSandbox } = require('../scripts/local_sandbox.cjs');

const CHROME = ['C:/Program Files/Google/Chrome/Application/chrome.exe', '/usr/bin/google-chrome', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']
  .find(p => fs.existsSync(p));
let sandbox;
let base;

test.before(async () => {
  sandbox = await startSandbox({ port: 0, quiet: true, localLook: true });
  base = `http://localhost:${sandbox.port}`;
});
test.after(async () => { await sandbox?.close(); });

test('the sandbox Admin page gets the local look; the shared admin.html does not have it', async () => {
  for (const url of ['/admin', '/admin/', '/admin/dashboard']) {
    const html = await (await fetch(base + url)).text();
    assert.match(html, /window\.__ADMIN_ENV = \{ mode: "local-test" \}/, url);
    assert.match(html, /\.admin-env-banner\.local-test \{ display: none !important; \}/, url);
    assert.match(html, /sandbox-local-badge/, url);
    assert.equal(html.match(/id="sandbox-local-admin"/g).length, 1, `${url}: added once`);
  }
  const shared = fs.readFileSync(path.join(__dirname, '..', 'web_preview', 'admin.html'), 'utf8');
  assert.doesNotMatch(shared, /sandbox-local-admin|sandbox-local-badge/);
  // API answers are untouched.
  const api = await fetch(base + '/api/products');
  assert.equal(api.status, 200);
  assert.doesNotMatch(await api.text(), /sandbox-local-admin/);
});

test('in a browser: each order shows its first product picture left of the Order ID (+N, fallbacks, search kept)', { skip: CHROME ? false : 'Chrome not installed' }, async () => {
  const db = sandbox.db;
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=', 'base64');
  const pic = id => `/api/product-images/img_1764230400_${id}.png`;
  for (const id of ['aa01', 'bb02', 'cc02', 'ee05']) {
    await db.query(`INSERT INTO product_images (id, content_type, bytes) VALUES ($1, 'image/png', $2)`, [`img_1764230400_${id}`, png]);
  }
  const products = (await db.query('SELECT id FROM products ORDER BY id LIMIT 3')).rows.map(r => r.id);
  // A product whose own picture is used when the order line saved none.
  await db.query('UPDATE products SET img = $2 WHERE id = $1', [products[2], pic('ee05')]);
  await db.query(`INSERT INTO users (id, email, mobile, name, password_hash, email_verified, business_name, status, is_approved, reward_points)
    VALUES ('user_thumbs', 'thumbs@example.test', '9000000555', 'Thumb Dealer', 'x', TRUE, 'Thumbs', 'approved', TRUE, 0)`);
  const orders = {
    ORDA01: [[products[0], 'First Filter', pic('aa01')]],
    ORDB02: [[products[1], 'Second Membrane', pic('bb02')], [products[0], 'Other', pic('cc02')], [products[2], 'Third', '']],
    ORDC03: [['gone_product', 'Removed Product', '']],
    ORDD04: [[products[0], 'Broken Picture', '/api/product-images/img_1764230400_dead.png']],
    ORDE05: [[products[2], 'Uses Product Picture', 'purifier.jpg']],
  };
  let n = 0;
  for (const [orderId, lines] of Object.entries(orders)) {
    n += 1;
    await db.query(`INSERT INTO orders (order_id, user_id, user_email, user_name, delivery_address, invoice_number, subtotal, grand_total, status, payment_status, payment_method, created_at)
      VALUES ($1, 'user_thumbs', 'thumbs@example.test', 'Thumb Dealer', 'Chennai', $2, 100, 100, 'Processing & Dispatched', 'due_on_delivery', 'Cash on Delivery', now() - ($3 || ' minutes')::interval)`, [orderId, `INV-${orderId}`, String(n)]);
    for (const [productId, name, img] of lines) {
      await db.query('INSERT INTO order_items (order_id, product_id, product_name, unit_price, quantity, sku, img_src) VALUES ($1, $2, $3, 50, 1, $4, $5)', [orderId, productId, name, '', img]);
    }
  }

  const puppeteer = require('puppeteer-core');
  const browser = await puppeteer.launch({ executablePath: CHROME, headless: 'new', args: process.env.CI ? ['--no-sandbox'] : [] });
  try {
    for (const width of [1280, 390]) {
      const page = await browser.newPage();
      await page.setViewport({ width, height: 800 });
      await page.goto(`${base}/admin`, { waitUntil: 'networkidle0' });
      const { admin } = sandbox.credentials;
      await page.type('#adminEmailInput', admin.email);
      await page.type('#adminPasswordInput', admin.password);
      await Promise.all([page.waitForResponse(r => r.url().includes('/api/admin/products')), page.keyboard.press('Enter')]);
      await page.evaluate(() => window.switchSection('orders', null));
      await page.waitForFunction(() => document.querySelectorAll('#ordersTableBody .order-id-cell').length === 5);
      await page.waitForFunction(() => !document.querySelector('#ordersTableBody img[src*="dead"]'), { timeout: 5000 });
      const rows = await page.evaluate(() => [...document.querySelectorAll('#ordersTableBody tr')].map(tr => {
        const cell = tr.cells[0].querySelector('.order-id-cell');
        const thumb = cell.querySelector('.order-thumb');
        const img = thumb.querySelector('img');
        const box = (img || thumb.querySelector('.order-thumb-fallback')).getBoundingClientRect();
        const code = cell.querySelector('code').getBoundingClientRect();
        return {
          id: cell.querySelector('code').textContent,
          src: img ? new URL(img.src).pathname : null,
          alt: img ? img.alt : null,
          loaded: img ? img.complete && img.naturalWidth > 0 : null,
          fit: img ? getComputedStyle(img).objectFit : null,
          fallback: thumb.querySelector('.order-thumb-fallback')?.getAttribute('aria-label') || null,
          more: thumb.querySelector('.order-thumb-more')?.textContent || null,
          size: [Math.round(box.width), Math.round(box.height)],
          leftOfId: box.right <= code.left,
          centred: Math.abs((box.top + box.bottom) / 2 - (code.top + code.bottom) / 2) <= 2,
          statusSelect: Boolean(tr.querySelector('.order-status-select')),
        };
      }));
      const byId = Object.fromEntries(rows.map(r => [r.id, r]));
      assert.deepEqual(Object.keys(byId).sort(), Object.keys(orders).sort(), `${width}px: one row per order`);
      for (const r of rows) {
        assert.deepEqual(r.size, [48, 48], `${width}px ${r.id}: 48 x 48`);
        assert.ok(r.leftOfId && r.centred, `${width}px ${r.id}: left of the Order ID, vertically centred`);
        assert.ok(r.statusSelect, `${width}px ${r.id}: order actions kept`);
      }
      assert.equal(byId.ORDA01.src, '/api/product-images/img_1764230400_aa01.png');
      assert.equal(byId.ORDA01.alt, 'Product image: First Filter');
      assert.equal(byId.ORDA01.loaded, true);
      assert.equal(byId.ORDA01.fit, 'cover');
      assert.equal(byId.ORDA01.more, null);
      assert.equal(byId.ORDB02.src, '/api/product-images/img_1764230400_bb02.png', 'first product of a multi-product order');
      assert.equal(byId.ORDB02.more, '+2');
      assert.equal(byId.ORDC03.fallback, 'No product image: Removed Product');
      assert.equal(byId.ORDD04.fallback, 'No product image: Broken Picture', 'a picture that fails to load falls back');
      assert.equal(byId.ORDE05.src, '/api/product-images/img_1764230400_ee05.png', "no saved picture: the same product's own picture");

      // Search keeps working and the filtered row is decorated again.
      await page.type('#orderSearchInput', 'ORDB02');
      await page.evaluate(() => document.getElementById('orderSearchInput').dispatchEvent(new Event('input', { bubbles: true })));
      await page.waitForFunction(() => document.querySelectorAll('#ordersTableBody tr').length === 1);
      const filtered = await page.evaluate(() => ({ id: document.querySelector('#ordersTableBody code').textContent, thumbs: document.querySelectorAll('#ordersTableBody .order-thumb').length }));
      assert.deepEqual(filtered, { id: 'ORDB02', thumbs: 1 });
      await page.close();
    }
  } finally {
    await browser.close();
  }
});

test('in a browser: no orange banner or gap, no badge on the sign-in card, a small LOCAL badge in the header', { skip: CHROME ? false : 'Chrome not installed' }, async () => {
  const puppeteer = require('puppeteer-core');
  const browser = await puppeteer.launch({ executablePath: CHROME, headless: 'new', args: process.env.CI ? ['--no-sandbox'] : [] });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1280, height: 800 });
    await page.goto(`${base}/admin`, { waitUntil: 'networkidle0' });
    const login = await page.evaluate(() => ({
      bannerShown: getComputedStyle(document.getElementById('adminEnvBanner')).display !== 'none',
      bannerText: document.getElementById('adminEnvBanner').textContent,
      paddingTop: getComputedStyle(document.body).paddingTop,
      badges: document.querySelectorAll('.login-card .sandbox-local-badge').length,
      cardText: document.querySelector('.login-header').innerText.replace(/\s+/g, ' ').trim(),
      title: document.title,
    }));
    assert.equal(login.bannerShown, false, 'orange banner hidden');
    assert.match(login.bannerText, /^LOCAL TEST COPY/, 'the page still knows it is the local copy');
    assert.equal(login.paddingTop, '0px', 'no empty gap where the banner was');
    assert.equal(login.badges, 0, 'no environment badge on the sign-in card');
    assert.equal(login.cardText, 'RO Wholesale Admin Portal Security Login');
    assert.match(login.title, /^LOCAL · /);

    const { admin } = sandbox.credentials;
    await page.type('#adminEmailInput', admin.email);
    await page.type('#adminPasswordInput', admin.password);
    await Promise.all([page.waitForResponse(r => r.url().includes('/api/admin/orders')), page.keyboard.press('Enter')]);
    const header = await page.evaluate(() => ({
      badge: [...document.querySelectorAll('.header-right .sandbox-local-badge')].map(b => b.offsetParent !== null && b.textContent),
      role: document.querySelector('.admin-profile-pill .role').textContent,
      sidebarTop: getComputedStyle(document.querySelector('.sidebar')).top,
    }));
    assert.deepEqual(header.badge, ['LOCAL']);
    assert.equal(header.role, 'Local sandbox · not Production');
    assert.equal(header.sidebarTop, '0px');
  } finally {
    await browser.close();
  }
});
