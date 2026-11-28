// Local sandbox: the REAL backend (server.js, every route) on an isolated,
// in-memory PostgreSQL built from the project's own schema files.
//
// Nothing is written to the live database and no email is sent:
//  - db.js is replaced by an in-memory PGlite database,
//  - email_provider.js is replaced by an outbox kept in memory,
//  - admin / session secrets are random test values for this run only.
//
//   node scripts/local_sandbox.cjs                 # port 8091, sample catalog
//   node scripts/local_sandbox.cjs --catalog=live  # copy products/categories
//                                                  # from the live DB (read-only)
//   node scripts/local_sandbox.cjs --pre-migration # today's live schema
//   node scripts/local_sandbox.cjs --live-snapshot [--pdf-import]
//       real accounts, locally: ONE read-only snapshot of the live database
//       (dealers with their existing bcrypt password hashes, shop employees,
//       addresses, orders, carts, rewards, tickets, supply records, catalogue)
//       loaded into memory only. Real logins work with their usual passwords;
//       the admin login is ADMIN_EMAIL / ADMIN_PASSWORD from .env. After the
//       snapshot every live database connection is blocked, every other .env
//       value is blanked, emails are captured and it listens on 127.0.0.1 only.
//       --pdf-import also applies the prepared PDF catalogue import (memory only).
//   --storage-browse (any mode): keep SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY so the
//       Admin "Choose from Supabase" picker can list Storage pictures (list only).
//   --data-dir=<folder> (any mode): keep this sandbox's database on disk in
//       <folder> (use a git-ignored one, e.g. backups/sandbox_db/8106), so local
//       orders, rewards and Admin changes survive a restart. The first start fills
//       it as usual and writes <folder>/sandbox_ready.json; every later start opens
//       that database as it is: no schema, no snapshot, no Production read at all.
//       A non-empty folder without sandbox_ready.json is refused and left untouched.
//   --seed-from=<backup.json> (with a new --data-dir): fill the new database from
//       a sandbox backup (sandbox_8106_full.json format) instead of Production.
//       Every table's row count and fingerprint must match the backup exactly, or
//       the start fails and the folder is not marked ready.
//
// Sandbox-only endpoints (only exist in this process):
//   GET  /__sandbox/outbox       captured emails (OTP codes etc.)
//   GET  /__sandbox/credentials  test admin + shop employee logins (not in --live-snapshot)
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const PHASE1 = [
  'supabase/staging/008_shop_order_assignments.sql',
  'supabase/staging/006_product_images.sql',
  'supabase/staging/007_stock_movements.sql',
  'supabase/staging/009_product_cabinet_price.sql',
  'supabase/staging/010_reward_ledger.sql',
  'supabase/staging/011_bulk_orders.sql',
];

/** Main statement of a query (WITH ... INSERT counts as INSERT). */
function commandOf(sql) {
  const text = String(sql).trim();
  const first = (text.match(/^[A-Za-z]+/) || [''])[0].toUpperCase();
  if (first !== 'WITH') return first;
  let depth = 0;
  for (let i = 4; i < text.length; i++) {
    const c = text[i];
    if (c === '(') depth++;
    else if (c === ')') depth--;
    else if (depth === 0) {
      const m = text.slice(i).match(/^(SELECT|INSERT|UPDATE|DELETE)\b/i);
      if (m) return m[1].toUpperCase();
    }
  }
  return 'SELECT';
}

function createPool(db) {
  const { toPostgresPlaceholders, adaptResult, normalizeDatabaseError } = require(path.join(root, 'db.js'));
  const run = async (sql, values = []) => {
    try {
      const result = await db.query(toPostgresPlaceholders(sql), Array.from(values || []));
      return adaptResult({ ...result, command: commandOf(sql), rowCount: result.affectedRows ?? result.rows.length });
    } catch (error) {
      throw normalizeDatabaseError(error);
    }
  };
  // PGlite is a single connection: transactions are serialised so two
  // requests can never share one.
  let chain = Promise.resolve();
  const getConnection = async () => {
    let release;
    const turn = new Promise(resolve => { release = resolve; });
    const previous = chain;
    chain = chain.then(() => turn);
    await previous;
    let released = false;
    return {
      query: run,
      beginTransaction: () => db.exec('BEGIN'),
      commit: () => db.exec('COMMIT'),
      rollback: () => db.exec('ROLLBACK'),
      release() { if (!released) { released = true; release(); } },
    };
  };
  const raw = {
    connect: async () => {
      const conn = await getConnection();
      return { query: (text, values) => db.query(text, values ? Array.from(values) : undefined), release: () => conn.release() };
    },
  };
  return { query: run, getConnection, raw, end: async () => {} };
}

async function seedCatalog(db, source) {
  let categories;
  let products;
  if (source === 'live') {
    // Read-only copy of the live catalogue (no customers, orders or staff).
    require(path.join(root, 'node_modules', 'dotenv')).config({ path: path.join(root, '.env') });
    const { Pool } = require('pg');
    const live = require(path.join(root, 'db.js')).pool;
    const [cRows] = await live.query('SELECT * FROM categories ORDER BY display_order');
    const [pRows] = await live.query('SELECT * FROM products');
    await live.end();
    categories = cRows;
    products = pRows;
    void Pool;
  } else {
    const sample = require(path.join(root, 'tool', 'sample_catalog.cjs'));
    categories = sample.categories;
    products = sample.products.map(p => ({ ...p, category_key: p.category, description: p.desc, specs_json: JSON.stringify(p.specs), features_json: JSON.stringify(p.features) }));
  }
  for (const c of categories) {
    await db.query(`INSERT INTO categories (id, key_name, title, image_url, icon_color, badge_text, display_order, description)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8) ON CONFLICT (id) DO NOTHING`,
    [c.id, c.key_name, c.title, c.image_url || '', c.icon_color || '#0F62FE', c.badge_text || '', c.display_order || 0, c.description || '']);
  }
  for (const p of products) {
    await db.query(`INSERT INTO products (id, category_id, category_key, sku, name, brand, purchase_price, price, mrp, moq, badge, rating, img, description, specs_json, features_json, applications, stock_quantity, min_stock, status)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20) ON CONFLICT (id) DO NOTHING`,
    [p.id, p.category_id || null, p.category_key, p.sku, p.name, p.brand || 'RO Wholesale', Number(p.purchase_price || 0), Number(p.price), Number(p.mrp),
      p.moq || 'MOQ: 1 Unit', p.badge || '', String(p.rating || '0'), p.img || '', p.description || '',
      typeof p.specs_json === 'string' ? p.specs_json : JSON.stringify(p.specs_json || {}),
      typeof p.features_json === 'string' ? p.features_json : JSON.stringify(p.features_json || []),
      p.applications || '', Number(p.stock_quantity ?? 50), Number(p.min_stock ?? 10), p.status || 'active']);
  }
  if (source === 'live') {
    // Keep the live values exactly (no 'RO Wholesale' / rating / MOQ defaults) and
    // copy the later columns too (Cabinet Price, Bulk Orders), so the Admin form
    // in this local copy shows what production has.
    const have = new Set((await db.query(`SELECT column_name FROM information_schema.columns WHERE table_name = 'products'`)).rows.map(r => r.column_name));
    const cols = ['brand', 'rating', 'moq', 'cabinet_price', 'bulk_price', 'bulk_min_qty', 'bulk_step', 'bulk_pack_label'].filter(c => have.has(c));
    for (const p of products) {
      const present = cols.filter(c => c in p);
      if (!present.length) continue;
      await db.query(`UPDATE products SET ${present.map((c, i) => `${c} = $${i + 2}`).join(', ')} WHERE id = $1`, [p.id, ...present.map(c => p[c])]);
    }
  }
  return { categories: categories.length, products: products.length };
}

// One-time sign-in codes are short-lived and not needed locally.
const SNAPSHOT_SKIP = new Set(['otp_codes']);
// date, timestamp, timestamptz, time, timetz: the database's own text, so the
// copy holds exactly the stored values.
const RAW_DATE_TIME_OIDS = new Set([1082, 1114, 1184, 1083, 1266]);

/** ONE read-only, consistent snapshot of every live table (kept in memory only). */
async function readLiveSnapshot() {
  require(path.join(root, 'node_modules', 'dotenv')).config({ path: path.join(root, '.env') });
  const pg = require('pg');
  const types = { getTypeParser: (oid, format) => (RAW_DATE_TIME_OIDS.has(oid) ? value => value : pg.types.getTypeParser(oid, format)) };
  const live = require(path.join(root, 'db.js')).pool;
  const client = await live.raw.connect();
  const tables = {};
  try {
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const names = (await client.query(`SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name`)).rows.map(r => r.table_name);
    for (const name of names) {
      if (SNAPSHOT_SKIP.has(name)) continue;
      tables[name] = (await client.query({ text: `SELECT * FROM public."${name.replace(/"/g, '""')}"`, types })).rows;
    }
    // What this Local Admin starts from, as exact text, from the same snapshot.
    // scripts/data-migrations/capture.cjs uses it so that only fields changed
    // here are captured (a stale local value never undoes a newer Production one).
    const base = {};
    for (const name of ['products', 'categories']) {
      if (!names.includes(name)) continue;
      const columns = (await client.query(`SELECT attname FROM pg_attribute WHERE attrelid = 'public.${name}'::regclass AND attnum > 0 AND NOT attisdropped ORDER BY attnum`)).rows.map(r => r.attname);
      base[name] = { columns, rows: (await client.query(`SELECT ${columns.map(c => `"${c}"::text AS "${c}"`).join(', ')} FROM public.${name} ORDER BY id`)).rows };
    }
    await client.query('ROLLBACK');
    saveSandboxBase(base);
  } finally {
    client.release();
    await live.end();
  }
  return tables;
}

/** backups/sandbox_base/<time>/base_*.json (git-ignored) + LATEST.txt. */
function saveSandboxBase(base) {
  if (!base.products || !base.categories) return;
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dir = path.join(root, 'backups', 'sandbox_base', stamp);
  fs.mkdirSync(dir, { recursive: true });
  const takenAt = new Date().toISOString();
  for (const name of ['products', 'categories']) {
    fs.writeFileSync(path.join(dir, `base_${name}.json`), JSON.stringify({ takenAt, ...base[name] }));
  }
  fs.writeFileSync(path.join(root, 'backups', 'sandbox_base', 'LATEST.txt'), `${stamp}\n`);
}

/** After the snapshot nothing in this process may open a connection to a real database. */
function blockRealDatabaseConnections() {
  const pg = require('pg');
  const refuse = () => Promise.reject(new Error('Live database access is disabled in the local sandbox.'));
  pg.Client.prototype.connect = refuse;
  pg.Pool.prototype.connect = refuse;
  pg.Pool.prototype.query = refuse;
}

/** Loads snapshot rows as they are (same ids, hashes, statuses, links). */
async function loadSnapshot(db, tables) {
  const loaded = {};
  const present = Object.keys(tables).filter(Boolean);
  for (const name of present) {
    const exists = (await db.query(`SELECT to_regclass($1) AS t`, [`public.${name}`])).rows[0].t;
    if (!exists) throw new Error(`table ${name} is not in the local schema`);
  }
  await db.exec(`TRUNCATE ${present.map(n => `public."${n}"`).join(', ')} RESTART IDENTITY CASCADE`);
  await db.exec("SET session_replication_role = 'replica'");
  try {
    for (const name of present) {
      for (const row of tables[name]) {
        const cols = Object.keys(row);
        const values = cols.map(c => (row[c] !== null && typeof row[c] === 'object' && !Buffer.isBuffer(row[c]) && !(row[c] instanceof Uint8Array) ? JSON.stringify(row[c]) : row[c]));
        await db.query(`INSERT INTO public."${name}" (${cols.map(c => `"${c}"`).join(', ')}) OVERRIDING SYSTEM VALUE
          VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, values);
      }
      loaded[name] = tables[name].length;
    }
  } finally {
    await db.exec("SET session_replication_role = 'origin'");
  }
  // New local rows continue after the copied ids.
  const serials = (await db.query(`SELECT table_name, column_name FROM information_schema.columns
    WHERE table_schema = 'public' AND (is_identity = 'YES' OR column_default LIKE 'nextval(%')`)).rows;
  for (const { table_name: t, column_name: c } of serials) {
    await db.query(`SELECT setval(pg_get_serial_sequence($1, $2), GREATEST((SELECT COALESCE(MAX("${c}"), 0) FROM public."${t}"), 1))`, [`public.${t}`, c]);
  }
  return loaded;
}

// Local Admin look, added only by this sandbox process to the page it serves
// (web_preview/admin.html, server.js, Render and the 8110 Production Admin are
// unchanged): no full-width orange banner; a small LOCAL badge in the header
// after sign-in and "LOCAL ·" in the tab title (nothing on the sign-in card).
const LOCAL_ADMIN_LOOK = `<style id="sandbox-local-admin">
  .admin-env-banner.local-test { display: none !important; }
  body.has-env-banner { padding-top: 0 !important; }
  body.has-env-banner .sidebar { top: 0 !important; height: 100vh !important; }
  .sandbox-local-badge { display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 999px;
    background: #FEF3C7; color: #92400E; border: 1px solid #F59E0B; font-size: 12px; font-weight: 700; letter-spacing: .06em; white-space: nowrap; }
</style>
<script id="sandbox-local-admin-badge">
  document.addEventListener('DOMContentLoaded', () => {
    const badge = text => { const b = document.createElement('span'); b.className = 'sandbox-local-badge'; b.title = 'Local sandbox on this computer: not Production'; b.textContent = text; return b; };
    document.querySelector('.header-right')?.prepend(badge('LOCAL'));
    const role = document.querySelector('.admin-profile-pill .role');
    if (role) role.textContent = 'Local sandbox · not Production';
    document.title = 'LOCAL · ' + document.title;
  });
</script>
<style id="sandbox-order-thumbs">
  .order-id-cell { display: flex; align-items: center; gap: 12px; white-space: nowrap; }
  .order-thumb { position: relative; flex: 0 0 48px; width: 48px; height: 48px; }
  .order-thumb img, .order-thumb .order-thumb-fallback { width: 48px; height: 48px; border-radius: 8px; border: 1px solid #E2E8F0; background: #F8FAFC; display: block; }
  .order-thumb img { object-fit: cover; }
  .order-thumb .order-thumb-fallback { display: flex; align-items: center; justify-content: center; color: #94A3B8; font-size: 18px; }
  .order-thumb-more { position: absolute; right: -6px; bottom: -6px; min-width: 20px; padding: 1px 5px; border-radius: 999px; background: #1E40AF; color: #fff;
    border: 2px solid #fff; font-size: 10px; font-weight: 700; line-height: 14px; text-align: center; }
</style>
<script id="sandbox-order-thumbs-script">
  // Orders table: the first product's picture left of each Order ID, "+N" for
  // more products. Uses the image saved on the order line (imgSrc, already in
  // the /api/admin/orders answer) or, if that is missing, the same product's
  // picture from the product list the page already loaded. No extra requests.
  (function () {
    var usable = function (s) { s = String(s || '').trim(); return /^(https?:\\/\\/|\\/)/i.test(s) ? s : ''; };
    function thumbSrc(item) {
      var saved = usable(item && item.imgSrc);
      if (saved) return saved;
      var list = typeof allProducts !== 'undefined' && Array.isArray(allProducts) ? allProducts : [];
      var product = list.find(function (p) { return item && String(p.id) === String(item.id); });
      return usable(product && product.img);
    }
    function fallback(label) {
      var f = document.createElement('span');
      f.className = 'order-thumb-fallback';
      f.setAttribute('role', 'img');
      f.setAttribute('aria-label', label);
      f.title = label;
      f.innerHTML = '<i class="fa-solid fa-box-open" aria-hidden="true"></i>';
      return f;
    }
    function decorate(row, orders) {
      var cell = row.cells && row.cells[0];
      var code = cell && cell.querySelector(':scope > code');
      if (!code || cell.querySelector('.order-id-cell')) return;
      var order = orders.find(function (o) { return String(o.orderId) === code.textContent.trim(); });
      if (!order) return;
      var items = Array.isArray(order.items) ? order.items : [];
      var first = items[0];
      var thumb = document.createElement('span');
      thumb.className = 'order-thumb';
      var src = thumbSrc(first);
      var name = (first && first.name) || 'product';
      if (src) {
        var img = document.createElement('img');
        img.width = 48; img.height = 48; img.loading = 'lazy'; img.decoding = 'async';
        img.alt = 'Product image: ' + name;
        img.addEventListener('error', function () { img.replaceWith(fallback('No product image: ' + name)); }, { once: true });
        img.src = src;
        thumb.appendChild(img);
      } else {
        thumb.appendChild(fallback(first ? 'No product image: ' + name : 'No products in this order'));
      }
      if (items.length > 1) {
        var more = document.createElement('span');
        more.className = 'order-thumb-more';
        more.textContent = '+' + (items.length - 1);
        more.title = (items.length - 1) + ' more product(s) in this order';
        thumb.appendChild(more);
      }
      var wrap = document.createElement('div');
      wrap.className = 'order-id-cell';
      wrap.appendChild(thumb);
      wrap.appendChild(code);
      cell.appendChild(wrap);
    }
    function decorateAll(body) {
      var orders = typeof allOrders !== 'undefined' && Array.isArray(allOrders) ? allOrders : [];
      Array.prototype.forEach.call(body.rows, function (row) { decorate(row, orders); });
    }
    document.addEventListener('DOMContentLoaded', function () {
      var body = document.getElementById('ordersTableBody');
      if (!body) return;
      new MutationObserver(function () { decorateAll(body); }).observe(body, { childList: true });
      decorateAll(body);
    });
  })();
</script>`;

function localAdminLook(req, res, next) {
  if (req.method !== 'GET' || !/^\/admin(\/|$)/.test(req.path)) return next();
  const send = res.send;
  res.send = function sendWithLocalLook(body) {
    if (typeof body === 'string' && body.includes('window.__ADMIN_ENV = { mode: "local-test" }')) body = body.replace('</head>', `${LOCAL_ADMIN_LOOK}\n</head>`);
    return send.call(this, body);
  };
  next();
}

// --data-dir: written only once the database is complete.
const READY_FILE = 'sandbox_ready.json';

/** null (in memory), { existing: false } (new, empty folder) or { existing: true, info }. */
function persistentState(dataDir) {
  if (!dataDir) return null;
  const ready = path.join(dataDir, READY_FILE);
  if (fs.existsSync(ready)) return { existing: true, info: JSON.parse(fs.readFileSync(ready, 'utf8')) };
  if (fs.existsSync(dataDir) && fs.readdirSync(dataDir).length) {
    throw new Error(`${dataDir} is not empty and has no ${READY_FILE}, so it is not a finished sandbox database. It was left untouched; use an empty folder.`);
  }
  return { existing: false };
}

/** Row count + md5 of every row's text, per table (same as the 8106 backups). */
async function tableFingerprints(db, names) {
  const out = {};
  for (const name of names) {
    const r = (await db.query(`SELECT count(*)::int AS n, md5(COALESCE(string_agg(x::text, '|' ORDER BY x::text), '')) AS h
      FROM public."${name.replace(/"/g, '""')}" x`)).rows[0];
    out[name] = { count: r.n, md5: r.h };
  }
  return out;
}

/** A sandbox backup file: table -> rows (every value as database text) and the expected fingerprints. */
function readDumpFile(file) {
  const dump = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!dump || typeof dump.tables !== 'object') throw new Error(`${file} is not a sandbox backup`);
  const tables = {};
  const expected = {};
  for (const [name, t] of Object.entries(dump.tables)) {
    // Binary columns (uploaded pictures) are stored as \x... hex text; the
    // database driver needs them as bytes.
    const binary = (t.columns || []).filter(c => c.type === 'bytea').map(c => c.name);
    tables[name] = binary.length
      ? t.rows.map(row => {
        const copy = { ...row };
        for (const c of binary) if (typeof copy[c] === 'string' && copy[c].startsWith('\\x')) copy[c] = Buffer.from(copy[c].slice(2), 'hex');
        return copy;
      })
      : t.rows;
    expected[name] = { count: t.count, md5: t.md5 };
  }
  return { tables, expected, takenAt: dump.takenAt || null };
}

/** Full copy of a sandbox database in the backup format readDumpFile() reads. */
async function dumpDatabase(db) {
  const q = async sql => (await db.query(sql)).rows;
  const out = { takenAt: new Date().toISOString(), source: `local sandbox (pid ${process.pid})`, tables: {} };
  out.extensions = (await q('SELECT extname FROM pg_extension ORDER BY 1')).map(r => r.extname);
  const names = (await q(`SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY 1`)).map(r => r.table_name);
  const prints = await tableFingerprints(db, names);
  for (const t of names) {
    const reg = `'public."${t.replace(/"/g, '""')}"'::regclass`;
    const columns = await q(`SELECT a.attname AS name, format_type(a.atttypid, a.atttypmod) AS type, a.attnotnull AS notnull
      FROM pg_attribute a WHERE a.attrelid = ${reg} AND a.attnum > 0 AND NOT a.attisdropped ORDER BY a.attnum`);
    const constraints = await q(`SELECT conname, contype, pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conrelid = ${reg} ORDER BY contype, conname`);
    const rows = await q(`SELECT ${columns.map(c => `"${c.name}"::text AS "${c.name}"`).join(', ')} FROM public."${t}"`);
    out.tables[t] = { columns, constraints, rows, count: prints[t].count, md5: prints[t].md5 };
  }
  return out;
}

/** Table counts for the start-up message. */
async function currentCounts(db) {
  const out = {};
  for (const t of ['users', 'shop_employees', 'orders', 'order_items', 'user_addresses', 'products', 'rewards_history']) {
    if ((await db.query('SELECT to_regclass($1) AS t', [`public.${t}`])).rows[0].t) {
      out[t] = (await db.query(`SELECT count(*)::int AS n FROM public."${t}"`)).rows[0].n;
    }
  }
  return out;
}

/** Same rule as the Phase 1 migration: with one active shop, existing orders go to it. */
async function assignOrdersToOnlyShop(db) {
  const exists = (await db.query(`SELECT to_regclass('public.shop_order_assignments') AS t`)).rows[0].t;
  if (!exists) return 0;
  const shops = (await db.query('SELECT DISTINCT shop_name FROM shop_employees WHERE active = TRUE')).rows;
  if (shops.length !== 1) return 0;
  const result = await db.query(`INSERT INTO shop_order_assignments (order_id, shop_name, assigned_at)
    SELECT order_id, $1, CURRENT_TIMESTAMP FROM orders ON CONFLICT (order_id) DO NOTHING`, [shops[0].shop_name]);
  return result.affectedRows || 0;
}

/** Blank every .env value except the ones this run keeps (dotenv never overrides a set key). */
function isolateFromEnvFile(keep = []) {
  const file = path.join(root, '.env');
  if (!fs.existsSync(file)) return;
  const parsed = require(path.join(root, 'node_modules', 'dotenv')).parse(fs.readFileSync(file));
  for (const key of Object.keys(parsed)) if (!keep.includes(key)) process.env[key] = '';
}

async function startSandbox({ port = 8091, catalog = 'sample', migrated = true, quiet = false, liveSnapshot = false, snapshotLoader = readLiveSnapshot, pdfImport = false, storageBrowse = false, dataDir = '', seedFrom = '', localLook = false } = {}) {
  const { PGlite } = require('@electric-sql/pglite');
  const { citext } = require('@electric-sql/pglite/contrib/citext');
  const bcrypt = require('bcryptjs');
  const persist = persistentState(dataDir);
  if (seedFrom && !persist) throw new Error('--seed-from needs --data-dir (a new, empty folder)');
  if (seedFrom && persist.existing) throw new Error(`${dataDir} already holds a sandbox database; --seed-from only fills a new, empty folder.`);
  const kept = persist?.existing === true;
  // A kept database opens the way it was made; a backup of the 8106 sandbox
  // holds real accounts, so it runs like --live-snapshot (localhost only).
  if (kept) liveSnapshot = persist.info.liveSnapshot === true;
  if (seedFrom) liveSnapshot = true;
  if (persist && !kept) fs.mkdirSync(dataDir, { recursive: true });
  const db = new PGlite(persist ? { dataDir: path.join(dataDir, 'pgdata'), extensions: { citext } } : { extensions: { citext } });
  if (!kept) {
    await db.exec(read('supabase_migration.sql'));
    await db.exec(read('shop_app_migration.sql'));
    if (migrated) for (const file of PHASE1) await db.exec(read(file));
    else await db.exec('DROP TABLE public.shop_order_assignments');
  }

  let seeded;
  let credentials = null;
  let snapshot = null;
  let adminFromEnv = null;
  if (liveSnapshot) {
    // Kept database: nothing is read from anywhere. Backup: the file only.
    const seed = seedFrom ? readDumpFile(seedFrom) : null;
    const tables = kept ? null : seed ? seed.tables : await snapshotLoader();
    blockRealDatabaseConnections();
    // The admin login stays the one in .env; it is read here and never printed.
    const envFile = path.join(root, '.env');
    const parsed = fs.existsSync(envFile) ? require(path.join(root, 'node_modules', 'dotenv')).parse(fs.readFileSync(envFile)) : {};
    adminFromEnv = { email: process.env.ADMIN_EMAIL || parsed.ADMIN_EMAIL || '', password: process.env.ADMIN_PASSWORD || parsed.ADMIN_PASSWORD || '' };
    if (!adminFromEnv.email || !adminFromEnv.password) throw new Error('ADMIN_EMAIL / ADMIN_PASSWORD are not set in .env');
    if (kept) {
      snapshot = { tables: await currentCounts(db), kept: true, createdAt: persist.info.createdAt, source: persist.info.source };
    } else {
      snapshot = { tables: await loadSnapshot(db, tables) };
      if (seed) {
        // Exactly the backed-up rows, or no start (and the folder is not marked ready).
        const now = await tableFingerprints(db, Object.keys(seed.expected));
        const wrong = Object.keys(seed.expected).filter(t => now[t].count !== seed.expected[t].count || now[t].md5 !== seed.expected[t].md5);
        if (wrong.length) throw new Error(`Restored rows differ from ${seedFrom} in: ${wrong.join(', ')}`);
        snapshot.seedVerified = Object.keys(seed.expected).length;
      }
      snapshot.ordersAssignedToShop = await assignOrdersToOnlyShop(db);
    }
    seeded = { categories: snapshot.tables.categories || 0, products: snapshot.tables.products || 0 };
  } else {
    seeded = kept ? await currentCounts(db) : await seedCatalog(db, catalog);
    credentials = {
      admin: { email: 'sandbox-admin@example.test', password: crypto.randomBytes(9).toString('base64url') },
      shop: { loginId: 'SANDBOX', password: crypto.randomBytes(9).toString('base64url'), shopName: 'ROSHOP' },
    };
    // A kept database already has this employee: only its new test password is set.
    await db.query(`INSERT INTO shop_employees (id, employee_id, shop_name, full_name, password_hash, active)
      VALUES ($1, $2, $3, 'Sandbox Employee', $4, TRUE)
      ON CONFLICT (employee_id) DO UPDATE SET password_hash = EXCLUDED.password_hash`,
    [crypto.randomUUID(), credentials.shop.loginId, credentials.shop.shopName, await bcrypt.hash(credentials.shop.password, 10)]);
  }

  // Isolate from .env: every value there is blanked except the admin login in
  // --live-snapshot (no database URL, Supabase key, mail or payment settings).
  // --storage-browse also keeps the Supabase URL and Storage key so the Admin
  // "Choose from Supabase" picker can LIST pictures (server.js only ever lists;
  // the database connection stays blocked and blank).
  isolateFromEnvFile([...(liveSnapshot ? ['ADMIN_EMAIL', 'ADMIN_PASSWORD'] : []), ...(storageBrowse ? ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'] : [])]);
  const admin = adminFromEnv || credentials.admin;
  Object.assign(process.env, {
    PORT: String(port),
    // The Admin Panel here always shows "LOCAL TEST COPY" (never Production).
    ADMIN_ENV_LABEL: 'local-test',
    ...(liveSnapshot ? { RO_LISTEN_HOST: '127.0.0.1' } : {}),
    // PDF catalogue preview: its stock is 0 (no inventory in the PDFs), so stock
    // checks are off here only. order_rules.js ignores this whenever a real
    // database is configured, and stock values are never changed.
    ...(pdfImport ? { RO_PREVIEW_IGNORE_STOCK: '1' } : { RO_PREVIEW_IGNORE_STOCK: '' }),
    ADMIN_EMAIL: admin.email,
    ADMIN_PASSWORD: admin.password,
    SESSION_SECRET: crypto.randomBytes(32).toString('hex'),
    ADMIN_SESSION_SECRET: crypto.randomBytes(32).toString('hex'),
    SHOP_EMPLOYEE_SESSION_SECRET: crypto.randomBytes(32).toString('hex'),
    SUPABASE_DB_URL: '', DATABASE_URL: '', PGHOST: '', SUPABASE_DB_HOST: '',
    BREVO_API_KEY: 'sandbox-capture', BREVO_SENDER_EMAIL: 'no-reply@example.test',
    SMTP_HOST: '', SMTP_USER: '', SMTP_PASS: '',
    RAZORPAY_KEY_ID: '', RAZORPAY_KEY_SECRET: '',
    API_RATE_LIMIT_PER_MINUTE: process.env.API_RATE_LIMIT_PER_MINUTE || '5000',
  });

  const pool = createPool(db);
  const outbox = [];
  const dbPath = require.resolve(path.join(root, 'db.js'));
  const realDb = require(dbPath);
  require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: { ...realDb, pool, testConnection: async () => true, connectionTarget: () => ({ remote: false }) } };
  const emailPath = require.resolve(path.join(root, 'email_provider.js'));
  const realEmail = require(emailPath);
  require.cache[emailPath] = {
    id: emailPath, filename: emailPath, loaded: true,
    exports: {
      ...realEmail,
      createEmailSender: () => async message => {
        outbox.push({ to: message.to, subject: message.subject, text: message.text, at: new Date().toISOString() });
        // Same shape as the real Brevo/SMTP sender.
        return { accepted: [message.to], provider: 'sandbox-outbox' };
      },
    },
  };

  const log = console.log;
  if (quiet) console.log = () => {};
  const { app, server } = require(path.join(root, 'server.js'));
  // Sandbox-only helpers; registered before the SPA catch-all would answer.
  const stack = app._router?.stack || app.router?.stack;
  const helper = (route, handler) => {
    app.get(route, handler);
    if (!stack) return;
    // Move it just ahead of the SPA catch-all (app.get('*')).
    const layer = stack.pop();
    const catchAll = stack.findIndex(l => l.route && l.route.path === '*');
    stack.splice(catchAll >= 0 ? catchAll : stack.length, 0, layer);
  };
  // localLook: the command line turns it on; in-process tests (some act as a
  // fake Production behind the 8110 proxy) get the page exactly as admin.html.
  if (localLook && stack) {
    // Runs before server.js's /admin route (just after Express sets up req/res).
    app.use(localAdminLook);
    const layer = stack.pop();
    stack.splice(stack.findIndex(l => l.name === 'expressInit') + 1, 0, layer);
  }
  helper('/__sandbox/outbox', (req, res) => res.json({ success: true, outbox }));
  if (credentials) helper('/__sandbox/credentials', (req, res) => res.json({ success: true, credentials }));
  if (!server.listening) await new Promise(resolve => server.once('listening', resolve));
  if (quiet) console.log = log;

  let pdf = null;
  // A kept database already has the import from its first start.
  if (pdfImport && !kept) {
    // The prepared PDF import, applied to this in-memory copy only. Pictures
    // are served from assets/product_pdfs/extracted until they are in Storage.
    const express = require('express');
    app.use('/__pdf_images', express.static(path.join(root, 'assets', 'product_pdfs', 'extracted', 'images')));
    if (stack) {
      const layer = stack.pop();
      const catchAll = stack.findIndex(l => l.route && l.route.path === '*');
      stack.splice(catchAll >= 0 ? catchAll : stack.length, 0, layer);
    }
    const imp = require(path.join(root, 'scripts', 'pdf_catalog_import.cjs'));
    const q = async (sql, params) => (await db.query(sql, params)).rows;
    const plan = imp.loadPlanData();
    const info = await imp.inspectDatabase(q, plan);
    if (info.errors.length) throw new Error(`PDF import check failed: ${info.errors.join('; ')}`);
    // Site-relative picture paths: they resolve against whichever address the
    // app uses for this backend (localhost on the web, 10.0.2.2 on the Android
    // emulator). Production uses the public Supabase Storage URLs instead.
    const base = `http://localhost:${server.address().port}`;
    const rows = imp.productRows(plan.toImport, info.categoryIdByKey, base).map(r => ({ ...r, img: `/__pdf_images/${r.sku}.jpg` }));
    pdf = await imp.applyDatabaseChanges(db, { rows, expectedSampleIds: info.samples.map(s => s.id), expectedGenuineIds: info.genuine.map(g => g.id) });
    // The Cabinet category and its 41 products (local copy only).
    const cab = require(path.join(root, 'scripts', 'cabinet_import.cjs'));
    // Production has had the Cabinet category since the live Cabinet
    // migration; only add it when the snapshot does not have it yet.
    const hasCabinet = (await db.query(`SELECT 1 FROM categories WHERE id = 'CAT_CAB' OR LOWER(key_name) = 'cabinets'`)).rows.length > 0;
    pdf.cabinet = hasCabinet ? { inserted: 0, alreadyPresent: true } : await cab.applyCabinetImport(db, cab.loadData());
    // Bulk Orders offers from the PDFs (scripts/extract_bulk_pricing.cjs);
    // only rows marked 'bulk' (the rest are held for review).
    const bulkFile = path.join(root, 'assets', 'product_pdfs', 'extracted', 'bulk_pricing.json');
    pdf.bulk = 0;
    if (migrated && fs.existsSync(bulkFile)) {
      for (const r of JSON.parse(fs.readFileSync(bulkFile, 'utf8')).products.filter(x => x.status === 'bulk')) {
        const res = await db.query(`UPDATE products SET bulk_price = $2, bulk_min_qty = $3, bulk_step = $4, bulk_pack_label = $5 WHERE id = $1`,
          [r.product_id, r.box_price, r.min_qty, r.step, r.pack_label]);
        pdf.bulk += res.affectedRows || 0;
      }
    }
  }
  if (persist && !kept) {
    fs.writeFileSync(path.join(dataDir, READY_FILE), JSON.stringify({
      createdAt: new Date().toISOString(),
      liveSnapshot,
      source: seedFrom ? `backup ${path.basename(path.dirname(path.resolve(seedFrom)))}/${path.basename(seedFrom)}` : liveSnapshot ? 'live snapshot (read once)' : `${catalog} catalogue`,
      tables: snapshot ? snapshot.tables : seeded,
    }, null, 1));
  }
  return {
    db, pool, outbox, credentials, seeded, server, snapshot, pdf,
    persistent: persist ? { dataDir, kept } : null,
    port: server.address().port,
    close: async () => {
      server.closeAllConnections?.();
      await new Promise(r => server.close(r));
      if (persist) await db.close();
    },
  };
}

module.exports = { startSandbox, commandOf, dumpDatabase, readDumpFile, tableFingerprints };

if (require.main === module) {
  const arg = name => process.argv.find(a => a.startsWith(`--${name}`));
  const catalog = (arg('catalog') || '--catalog=sample').split('=')[1];
  const liveSnapshot = Boolean(arg('live-snapshot'));
  // --port=8095 runs a second copy next to one already on 8091.
  const port = Number((arg('port') || '').split('=')[1]) || 8091;
  const storageBrowse = Boolean(arg('storage-browse'));
  const value = name => { const a = arg(name); return a && a.includes('=') ? path.resolve(a.slice(a.indexOf('=') + 1)) : ''; };
  const dataDir = value('data-dir');
  const seedFrom = value('seed-from');
  startSandbox({ port, catalog, migrated: !arg('pre-migration'), quiet: true, liveSnapshot, pdfImport: Boolean(arg('pdf-import')), storageBrowse, dataDir, seedFrom, localLook: true })
    .then(s => {
      // On Ctrl+C / stop, close the on-disk database cleanly (committed rows are kept either way).
      for (const signal of ['SIGINT', 'SIGTERM', 'SIGBREAK']) process.once(signal, () => s.close().finally(() => process.exit(0)));
      console.log(`Sandbox backend on http://localhost:${s.port} (isolated ${s.persistent ? `database kept on disk in ${dataDir}` : 'in-memory database'}, emails captured)`);
      if (s.persistent?.kept) {
        const t = s.snapshot ? s.snapshot.tables : s.seeded;
        console.log(`Kept local database opened as it is (no Production read; live access blocked): ${t.users || 0} dealers, ${t.orders || 0} orders, ${t.order_items || 0} order lines, ${t.rewards_history || 0} reward entries, ${t.products || 0} products. First filled ${s.snapshot?.createdAt || ''} from ${s.snapshot?.source || 'the sample catalogue'}.`);
        if (s.snapshot) console.log('Logins: real dealer and shop accounts with their usual passwords; admin = ADMIN_EMAIL from .env. Listening on 127.0.0.1 only.');
        else console.log(`Test logins: GET http://localhost:${s.port}/__sandbox/credentials`);
      } else if (seedFrom) {
        const t = s.snapshot.tables;
        console.log(`Filled from backup ${seedFrom} (no Production read; live access blocked): ${s.snapshot.seedVerified} tables match the backup exactly; ${t.users || 0} dealers, ${t.orders || 0} orders, ${t.order_items || 0} order lines, ${t.products || 0} products`);
        console.log('Logins: real dealer and shop accounts with their usual passwords; admin = ADMIN_EMAIL from .env. Listening on 127.0.0.1 only.');
      } else if (liveSnapshot) {
        const t = s.snapshot.tables;
        console.log(`Live snapshot (read once, read-only; live access now blocked): ${t.users || 0} dealers, ${t.shop_employees || 0} shop employees, ${t.orders || 0} orders, ${t.order_items || 0} order lines, ${t.user_addresses || 0} addresses, ${t.products || 0} products`);
        console.log('Logins: real dealer and shop accounts with their usual passwords; admin = ADMIN_EMAIL from .env. Listening on 127.0.0.1 only.');
      } else {
        console.log(`Catalogue: ${s.seeded.products} products, ${s.seeded.categories} categories (${catalog})`);
        console.log(`Test logins: GET http://localhost:${s.port}/__sandbox/credentials`);
      }
      if (s.pdf) console.log(`PDF import (local copy only): ${s.pdf.deleted} SAMPLE_ removed, ${s.pdf.inserted} PDF products added, ${s.pdf.skuFilled} order-line SKUs filled; Cabinet category with ${s.pdf.cabinet.inserted} products; ${s.pdf.bulk} Bulk Orders offers`);
      if (storageBrowse) console.log('Storage browsing: on (read-only listing of ro-product-images/cabinets and /pdf-catalog for the Admin picker)');
      console.log(`Schema: ${arg('pre-migration') ? "today's live schema" : 'after the Phase 1 migration'}`);
    })
    .catch(error => { console.error('SANDBOX_FAILED', error); process.exit(1); });
}
