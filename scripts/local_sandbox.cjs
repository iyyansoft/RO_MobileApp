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
    await client.query('ROLLBACK');
  } finally {
    client.release();
    await live.end();
  }
  return tables;
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

async function startSandbox({ port = 8091, catalog = 'sample', migrated = true, quiet = false, liveSnapshot = false, snapshotLoader = readLiveSnapshot, pdfImport = false, storageBrowse = false } = {}) {
  const { PGlite } = require('@electric-sql/pglite');
  const { citext } = require('@electric-sql/pglite/contrib/citext');
  const bcrypt = require('bcryptjs');
  const db = new PGlite({ extensions: { citext } });
  await db.exec(read('supabase_migration.sql'));
  await db.exec(read('shop_app_migration.sql'));
  if (migrated) for (const file of PHASE1) await db.exec(read(file));
  else await db.exec('DROP TABLE public.shop_order_assignments');

  let seeded;
  let credentials = null;
  let snapshot = null;
  let adminFromEnv = null;
  if (liveSnapshot) {
    const tables = await snapshotLoader();
    blockRealDatabaseConnections();
    // The admin login stays the one in .env; it is read here and never printed.
    const envFile = path.join(root, '.env');
    const parsed = fs.existsSync(envFile) ? require(path.join(root, 'node_modules', 'dotenv')).parse(fs.readFileSync(envFile)) : {};
    adminFromEnv = { email: process.env.ADMIN_EMAIL || parsed.ADMIN_EMAIL || '', password: process.env.ADMIN_PASSWORD || parsed.ADMIN_PASSWORD || '' };
    if (!adminFromEnv.email || !adminFromEnv.password) throw new Error('ADMIN_EMAIL / ADMIN_PASSWORD are not set in .env');
    snapshot = { tables: await loadSnapshot(db, tables) };
    snapshot.ordersAssignedToShop = await assignOrdersToOnlyShop(db);
    seeded = { categories: snapshot.tables.categories || 0, products: snapshot.tables.products || 0 };
  } else {
    seeded = await seedCatalog(db, catalog);
    credentials = {
      admin: { email: 'sandbox-admin@example.test', password: crypto.randomBytes(9).toString('base64url') },
      shop: { loginId: 'SANDBOX', password: crypto.randomBytes(9).toString('base64url'), shopName: 'ROSHOP' },
    };
    await db.query(`INSERT INTO shop_employees (id, employee_id, shop_name, full_name, password_hash, active)
      VALUES ($1, $2, $3, 'Sandbox Employee', $4, TRUE)`,
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
  require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: { ...realDb, pool, testConnection: async () => true } };
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
  helper('/__sandbox/outbox', (req, res) => res.json({ success: true, outbox }));
  if (credentials) helper('/__sandbox/credentials', (req, res) => res.json({ success: true, credentials }));
  if (!server.listening) await new Promise(resolve => server.once('listening', resolve));
  if (quiet) console.log = log;

  let pdf = null;
  if (pdfImport) {
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
  return {
    db, pool, outbox, credentials, seeded, server, snapshot, pdf,
    port: server.address().port,
    close: async () => { server.closeAllConnections?.(); await new Promise(r => server.close(r)); },
  };
}

module.exports = { startSandbox, commandOf };

if (require.main === module) {
  const arg = name => process.argv.find(a => a.startsWith(`--${name}`));
  const catalog = (arg('catalog') || '--catalog=sample').split('=')[1];
  const liveSnapshot = Boolean(arg('live-snapshot'));
  // --port=8095 runs a second copy next to one already on 8091.
  const port = Number((arg('port') || '').split('=')[1]) || 8091;
  const storageBrowse = Boolean(arg('storage-browse'));
  startSandbox({ port, catalog, migrated: !arg('pre-migration'), quiet: true, liveSnapshot, pdfImport: Boolean(arg('pdf-import')), storageBrowse })
    .then(s => {
      console.log(`Sandbox backend on http://localhost:${s.port} (isolated in-memory database, emails captured)`);
      if (liveSnapshot) {
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
