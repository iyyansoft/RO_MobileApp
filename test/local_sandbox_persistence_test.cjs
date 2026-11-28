// scripts/local_sandbox.cjs --data-dir / --seed-from: one local database shared
// by the Shop App and the Admin Panel that survives a restart (even a hard
// kill). Every sandbox here runs in its own child process (this same file with
// PERSIST_CHILD set) on a stand-in snapshot: nothing reaches Production.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const DEALER = 'persist.dealer@example.test';
const DEALER_PASSWORD = 'Persist#Pass2026';
const ADMIN = { email: 'owner@example.test', password: 'Admin#Pass2026' };

// ---------------------------------------------------------------- child side
if (process.env.PERSIST_CHILD) {
  const cfg = JSON.parse(process.env.PERSIST_CHILD);
  process.env.ADMIN_EMAIL = ADMIN.email;
  process.env.ADMIN_PASSWORD = ADMIN.password;
  const bcrypt = require('bcryptjs');
  const { startSandbox, dumpDatabase } = require('../scripts/local_sandbox.cjs');
  const snapshotLoader = async () => {
    if (cfg.loaderMustNotRun) throw new Error('snapshot loader was called for a kept database');
    return {
      categories: [{ id: 'CAT_MEM', key_name: 'membranes', title: 'Membranes', display_order: 0 }],
      products: [{ id: 'prod_mem_1', category_id: 'CAT_MEM', category_key: 'membranes', sku: 'MEM-1', name: 'Membrane 80 GPD', brand: 'X', price: '1000.00', mrp: '1500.00', stock_quantity: 50, status: 'active' }],
      users: [{ id: 'user_persist_1', email: DEALER, mobile: '9000000099', name: 'Persist Dealer', password_hash: await bcrypt.hash(DEALER_PASSWORD, 10), email_verified: true, business_name: 'Persist Water', status: 'approved', is_approved: true, reward_points: 0, created_at: '2026-11-01 10:00:00' }],
      user_addresses: [{ id: 'ADDR_P1', user_id: 'user_persist_1', full_name: 'Persist Dealer', street: '1 Test Road', city: 'Chennai', state: 'Tamil Nadu', pincode: '600001', is_default: true }],
      // An uploaded picture: binary data must survive the backup as bytes.
      product_images: [{ id: 'img_1764230400_ab12', content_type: 'image/png', bytes: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff, 0x5c, 0x78]), created_at: '2026-11-01 10:00:00+00' }],
      shop_employees: [{ id: 'a3c1d9b0-0000-4000-8000-000000000001', employee_id: 'ROSHOP01', shop_name: 'ROSHOP', full_name: 'Shop Staff', password_hash: await bcrypt.hash('Shop#Pass2026', 10), active: true }],
    };
  };
  startSandbox({ port: 0, quiet: true, liveSnapshot: !cfg.seedFrom, snapshotLoader, dataDir: cfg.dataDir, seedFrom: cfg.seedFrom || '' })
    .then(s => {
      process.stdout.write(`READY ${JSON.stringify({ port: s.port, kept: s.persistent?.kept, seedVerified: s.snapshot?.seedVerified })}\n`);
      process.stdin.on('data', async chunk => {
        const [cmd, file] = String(chunk).trim().split(' ');
        if (cmd === 'dump') {
          fs.writeFileSync(file, JSON.stringify(await dumpDatabase(s.db)));
          process.stdout.write('DUMPED\n');
        }
      });
    })
    .catch(error => { process.stdout.write(`FAILED ${error.message}\n`); process.exit(1); });
  return;
}

// --------------------------------------------------------------- parent side
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sandbox-persist-'));
const children = new Set();
test.after(() => {
  for (const c of children) c.kill('SIGKILL');
  fs.rmSync(tmp, { recursive: true, force: true });
});

function startChild(cfg) {
  const child = spawn(process.execPath, [__filename], { env: { ...process.env, PERSIST_CHILD: JSON.stringify(cfg) }, stdio: ['pipe', 'pipe', 'inherit'] });
  children.add(child);
  let out = '';
  const waitFor = word => new Promise((resolve, reject) => {
    const check = () => {
      const line = out.split('\n').find(l => l.startsWith(word) || l.startsWith('FAILED'));
      if (!line) return;
      child.stdout.off('data', onData);
      line.startsWith('FAILED') ? reject(new Error(line)) : resolve(line.slice(word.length).trim());
    };
    const onData = d => { out += d; check(); };
    child.stdout.on('data', onData);
    child.once('exit', code => reject(new Error(`sandbox exited (${code}): ${out}`)));
    check();
  });
  return {
    child,
    ready: waitFor('READY').then(JSON.parse),
    dump: async file => { child.stdin.write(`dump ${file}\n`); await waitFor('DUMPED'); },
    // Hard kill: the same as stopping the process from Task Manager.
    kill: () => new Promise(resolve => { child.once('exit', resolve); child.kill('SIGKILL'); children.delete(child); }),
  };
}

function client(port) {
  const base = `http://127.0.0.1:${port}`;
  const http = async (method, url, body, token) => {
    const res = await fetch(base + url, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: res.status, body: await res.json().catch(() => null) };
  };
  return {
    http,
    dealerLogin: async () => (await http('POST', '/api/auth/login', { identifier: DEALER, password: DEALER_PASSWORD })).body,
    adminToken: async () => (await http('POST', '/api/admin/login', ADMIN)).body.token,
    async placeOrder(quantity) {
      const login = await this.dealerLogin();
      const add = await http('POST', '/api/cart/add', { userId: login.user.id, productId: 'prod_mem_1', quantity }, login.token);
      assert.equal(add.status, 200, JSON.stringify(add.body));
      const order = await http('POST', '/api/user/orders/create', {
        email: DEALER, paymentMethod: 'Cash on Delivery', deliveryAddress: '1 Test Road, Chennai', items: [{ id: 'prod_mem_1', quantity }],
      }, login.token);
      assert.equal(order.status, 200, JSON.stringify(order.body));
      return order.body.orderId || order.body.order?.orderId;
    },
    async adminOrders() { return (await http('GET', '/api/admin/orders', null, await this.adminToken())).body.orders; },
    async dealerOrders() { const l = await this.dealerLogin(); return (await http('GET', `/api/user/orders?email=${encodeURIComponent(DEALER)}`, null, l.token)).body.orders; },
    async rewards() { const l = await this.dealerLogin(); return (await http('GET', `/api/user/rewards?email=${encodeURIComponent(DEALER)}`, null, l.token)).body; },
    async products() { return (await http('GET', '/api/products')).body.products; },
  };
}

const dataDir = path.join(tmp, 'db');
const dumpFile = path.join(tmp, 'backup.json');
let firstOrder;
let secondOrder;
let pointsAfterFirst;

test('one order is saved once and is the same in the Shop App and the Admin Panel; Admin status reaches the Shop App', async () => {
  const sb = startChild({ dataDir });
  const { port, kept } = await sb.ready;
  assert.equal(kept, false, 'first start fills a new database');
  assert.ok(fs.existsSync(path.join(dataDir, 'sandbox_ready.json')));
  const api = client(port);
  firstOrder = await api.placeOrder(2);
  assert.match(String(firstOrder), /^[A-Z0-9]{6}$/);

  const adminList = await api.adminOrders();
  assert.equal(adminList.length, 1, 'saved once');
  const a = adminList[0];
  assert.equal(a.orderId, firstOrder);
  assert.equal(a.userEmail, DEALER);
  assert.equal(a.paymentMethod, 'Cash on Delivery');
  assert.deepEqual(a.items.map(i => [i.id, Number(i.quantity), i.numericPrice]), [['prod_mem_1', 2, 1000]]);

  const shopList = await api.dealerOrders();
  assert.equal(shopList.length, 1);
  const d = shopList[0];
  assert.equal(String(d.orderId || d.id), firstOrder);
  assert.equal(Number(d.grandTotal ?? d.total), Number(a.grandTotal), 'same total in both apps');
  assert.equal(d.status, a.orderStatus, 'same order status in both apps');

  const token = await api.adminToken();
  const change = await api.http('PUT', `/api/admin/orders/${firstOrder}/status`, { status: 'Pending' }, token);
  assert.equal(change.status, 200, JSON.stringify(change.body));
  assert.equal((await api.dealerOrders())[0].status, 'Pending', 'Admin status change shows in the Shop App');
  assert.equal((await api.adminOrders())[0].orderStatus, 'Pending');

  const rewards = await api.rewards();
  assert.ok(rewards.availablePoints > 0, 'reward points credited for the order');
  pointsAfterFirst = rewards.availablePoints;
  await sb.kill();
});

test('after a hard kill and restart the same order, status and points are still there (no Production read, no duplicates)', async () => {
  const sb = startChild({ dataDir, loaderMustNotRun: true });
  const { port, kept } = await sb.ready;
  assert.equal(kept, true, 'kept database opened as it is');
  const api = client(port);
  const adminList = await api.adminOrders();
  assert.deepEqual(adminList.map(o => o.orderId), [firstOrder]);
  assert.equal(adminList[0].orderStatus, 'Pending');
  assert.equal((await api.dealerOrders())[0].status, 'Pending');
  assert.equal((await api.rewards()).availablePoints, pointsAfterFirst);
  assert.equal((await api.products()).length, 1, 'catalogue not loaded twice');

  secondOrder = await api.placeOrder(1);
  assert.notEqual(secondOrder, firstOrder);
  assert.deepEqual((await api.adminOrders()).map(o => o.orderId).sort(), [firstOrder, secondOrder].sort());
  assert.equal((await api.dealerOrders()).length, 2);
  await sb.dump(dumpFile);
  await sb.kill();
});

test('a new database filled from a backup holds exactly the backed-up orders', async () => {
  const seededDir = path.join(tmp, 'seeded');
  const sb = startChild({ dataDir: seededDir, seedFrom: dumpFile, loaderMustNotRun: true });
  const { port, kept, seedVerified } = await sb.ready;
  assert.equal(kept, false);
  assert.ok(seedVerified > 10, `every table checked (${seedVerified})`);
  const api = client(port);
  assert.deepEqual((await api.adminOrders()).map(o => o.orderId).sort(), [firstOrder, secondOrder].sort());
  assert.equal((await api.dealerOrders()).find(o => String(o.orderId || o.id) === firstOrder).status, 'Pending');
  const pic = await fetch(`http://127.0.0.1:${port}/api/product-images/img_1764230400_ab12.png`);
  assert.equal(pic.status, 200);
  assert.deepEqual([...Buffer.from(await pic.arrayBuffer())], [0x89, 0x50, 0x4e, 0x47, 0x00, 0xff, 0x5c, 0x78], 'picture bytes unchanged');
  await sb.kill();

  // A kept database is never refilled from a backup.
  await assert.rejects(startChild({ dataDir: seededDir, seedFrom: dumpFile }).ready, /already holds a sandbox database/);
});

test('a changed backup is refused and the new folder is not marked ready', async () => {
  const dump = JSON.parse(fs.readFileSync(dumpFile, 'utf8'));
  dump.tables.orders.rows[0].grand_total = '1.00';
  const bad = path.join(tmp, 'bad.json');
  fs.writeFileSync(bad, JSON.stringify(dump));
  const dir = path.join(tmp, 'from-bad');
  await assert.rejects(startChild({ dataDir: dir, seedFrom: bad }).ready, /differ from .* in: orders/);
  assert.equal(fs.existsSync(path.join(dir, 'sandbox_ready.json')), false);
});

test('a folder that is not a finished sandbox database is refused and left untouched', async () => {
  const other = path.join(tmp, 'other');
  fs.mkdirSync(other);
  fs.writeFileSync(path.join(other, 'keep.txt'), 'mine');
  await assert.rejects(startChild({ dataDir: other }).ready, /not a finished sandbox database/);
  assert.deepEqual(fs.readdirSync(other), ['keep.txt']);
  assert.equal(fs.readFileSync(path.join(other, 'keep.txt'), 'utf8'), 'mine');
});
