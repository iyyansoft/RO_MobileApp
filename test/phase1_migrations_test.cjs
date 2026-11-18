// The Phase 1 migrations and the backup script, on an in-memory PostgreSQL.
// Proves they are additive, repeatable, and preserve existing rows.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { PGlite } = require('@electric-sql/pglite');
const { citext } = require('@electric-sql/pglite/contrib/citext');
const { toPostgresPlaceholders, adaptResult } = require('../db');

const root = path.join(__dirname, '..');
const sql = file => fs.readFileSync(path.join(root, file), 'utf8');
const MIGRATIONS = [
  'supabase/staging/008_shop_order_assignments.sql',
  'supabase/staging/006_product_images.sql',
  'supabase/staging/007_stock_movements.sql',
];

async function liveLikeDatabase() {
  const db = new PGlite({ extensions: { citext } });
  await db.exec(sql('supabase_migration.sql'));
  // Today's live state: the Shop App tables exist except the assignment one.
  await db.exec(sql('shop_app_migration.sql'));
  await db.exec('DROP TABLE public.shop_order_assignments');
  await db.exec(`INSERT INTO products (id, category_key, sku, name, brand, price, mrp, stock_quantity)
    VALUES ('P1', 'membranes', 'SKU-P1', 'RO Membrane 75 GPD', 'RO Wholesale', 650, 900, 7)`);
  await db.exec(`INSERT INTO users (id, email, name, password_hash) VALUES ('U1', 'priya@example.test', 'Priya', 'x')`);
  await db.exec(`INSERT INTO orders (order_id, user_id, user_email, user_name, subtotal, discount, gst, delivery_fee, grand_total,
      payment_method, delivery_address, invoice_number, status, payment_status)
    VALUES ('OLD001', 'U1', 'priya@example.test', 'Priya', 650, 0, 0, 0, 650, 'Cash on Delivery', 'Chennai', 'INV-OLD', 'Processing & Dispatched', 'due_on_delivery')`);
  await db.exec(`INSERT INTO shop_employees (id, employee_id, shop_name, full_name, password_hash)
    VALUES ('11111111-1111-1111-1111-111111111111', 'IYYAN', 'ROSHOP', 'Iyyan', 'x')`);
  return db;
}

test('migrations are additive, repeatable and keep existing rows', async () => {
  const db = await liveLikeDatabase();
  const before = await db.query('SELECT order_id, status FROM orders');
  const stockBefore = await db.query('SELECT stock_quantity FROM products WHERE id = $1', ['P1']);

  for (const pass of [1, 2]) {
    for (const file of MIGRATIONS) await db.exec(sql(file));
    const tables = await db.query(`SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name IN ('shop_order_assignments', 'product_images', 'stock_movements')
      ORDER BY table_name`);
    assert.deepEqual(tables.rows.map(r => r.table_name), ['product_images', 'shop_order_assignments', 'stock_movements'], `pass ${pass}`);
  }

  // Existing data untouched.
  assert.deepEqual((await db.query('SELECT order_id, status FROM orders')).rows, before.rows);
  assert.deepEqual((await db.query('SELECT stock_quantity FROM products WHERE id = $1', ['P1'])).rows, stockBefore.rows);
  assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM shop_order_assignments')).rows[0].n, 0);

  // The stock rule applies to new changes.
  await assert.rejects(() => db.query('UPDATE products SET stock_quantity = -1 WHERE id = $1', ['P1']), /ck_products_stock_nonnegative/);
  await db.query('UPDATE products SET stock_quantity = 0 WHERE id = $1', ['P1']);
  assert.equal((await db.query('SELECT stock_quantity FROM products WHERE id = $1', ['P1'])).rows[0].stock_quantity, 0);

  // Assignments cascade with their order and reject an unknown one.
  await db.query(`INSERT INTO shop_order_assignments (order_id, shop_name) VALUES ('OLD001', 'ROSHOP')`);
  await assert.rejects(() => db.query(`INSERT INTO shop_order_assignments (order_id, shop_name) VALUES ('NOPE', 'ROSHOP')`), /foreign key/i);
  await db.query(`DELETE FROM orders WHERE order_id = 'OLD001'`);
  assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM shop_order_assignments')).rows[0].n, 0);
});

test('a pre-existing negative stock value is left alone (NOT VALID constraint)', async () => {
  const db = new PGlite({ extensions: { citext } });
  await db.exec(sql('supabase_migration.sql'));
  await db.exec(sql('shop_app_migration.sql'));
  await db.exec(`INSERT INTO products (id, category_key, sku, name, brand, price, mrp, stock_quantity)
    VALUES ('NEG', 'membranes', 'SKU-NEG', 'Oversold', 'RO Wholesale', 10, 20, -3)`);
  await db.exec(sql('supabase/staging/007_stock_movements.sql'));
  assert.equal((await db.query('SELECT stock_quantity FROM products WHERE id = $1', ['NEG'])).rows[0].stock_quantity, -3);
  // New writes still have to be valid.
  await assert.rejects(() => db.query('UPDATE products SET stock_quantity = -4 WHERE id = $1', ['NEG']), /ck_products_stock_nonnegative/);
});

test('backup writes every table, row counts and binary columns', async () => {
  const db = await liveLikeDatabase();
  await db.exec(sql('supabase/staging/006_product_images.sql'));
  await db.query(`INSERT INTO product_images (id, content_type, bytes) VALUES ('img_1_ab', 'image/png', $1)`, [
    new Uint8Array([137, 80, 78, 71]),
  ]);
  const query = async (text, values = []) => {
    const result = await db.query(toPostgresPlaceholders(text), Array.from(values));
    return adaptResult({ ...result, command: text.trim().split(/\s/)[0].toUpperCase(), rowCount: result.affectedRows });
  };
  // Accepts plain SQL text or pg's { text, types } form (the backup asks for
  // date/time columns as raw database text).
  const client = { query: (q, values) => db.query(typeof q === 'string' ? q : q.text, values ? Array.from(values) : undefined), release() {} };
  const dbPath = require.resolve(path.join(root, 'db'));
  const original = require.cache[dbPath];
  require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: { pool: { query, raw: { connect: async () => client }, end: async () => {} } } };
  delete require.cache[require.resolve('../scripts/backup_database.cjs')];
  const { backupDatabase } = require('../scripts/backup_database.cjs');
  const outDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ro-backup-'));
  try {
    const { manifest } = await backupDatabase({ outDir });
    assert.equal(manifest.tables.orders, 1);
    assert.equal(manifest.tables.products, 1);
    assert.equal(manifest.tables.product_images, 1);
    assert.ok(Object.keys(manifest.tables).length > 10, 'every public table');
    const orders = JSON.parse(fs.readFileSync(path.join(outDir, 'orders.json'), 'utf8'));
    assert.equal(orders[0].order_id, 'OLD001');
    const images = JSON.parse(fs.readFileSync(path.join(outDir, 'product_images.json'), 'utf8'));
    assert.equal(Buffer.from(images[0].bytes.$base64, 'base64').toString('hex'), '89504e47');
  } finally {
    fs.rmSync(outDir, { recursive: true, force: true });
    if (original) require.cache[dbPath] = original; else delete require.cache[dbPath];
    delete require.cache[require.resolve('../scripts/backup_database.cjs')];
  }
});
