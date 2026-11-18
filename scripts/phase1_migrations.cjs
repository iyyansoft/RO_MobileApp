// Phase 1 database changes, applied safely.
//
// Default (no flags): READ-ONLY dry run. Reports what exists, what each
// migration would create, and what data the follow-up step would touch.
//
//   node scripts/phase1_migrations.cjs
//
// Apply (only after approval): takes a full backup first, then applies each
// additive migration in its own transaction, then assigns existing
// unassigned orders to the only active shop.
//
//   APPLY_PHASE1_MIGRATIONS=YES node scripts/phase1_migrations.cjs --apply
//
// IMPORTANT: deploy the backend containing the fixed shop_routes.js BEFORE
// applying 008 to the live database (the old Current Orders query fails once
// shop_order_assignments exists).
const fs = require('node:fs');
const path = require('node:path');
const { pool } = require('../db');
const { backupDatabase } = require('./backup_database.cjs');

const root = path.join(__dirname, '..');
const MIGRATIONS = [
  { file: 'supabase/staging/008_shop_order_assignments.sql', table: 'shop_order_assignments', purpose: 'order -> shop assignment (item 2)' },
  { file: 'supabase/staging/006_product_images.sql', table: 'product_images', purpose: 'permanent image storage (item 4)' },
  { file: 'supabase/staging/007_stock_movements.sql', table: 'stock_movements', purpose: 'stock ledger + never-negative rule (item 1)' },
];

async function exists(client, table) {
  const result = await client.query('SELECT to_regclass($1) IS NOT NULL AS available', [`public.${table}`]);
  return result.rows[0].available === true;
}

async function report(client) {
  const lines = [];
  for (const migration of MIGRATIONS) {
    lines.push(`${(await exists(client, migration.table)) ? 'already present' : 'WILL CREATE   '}  ${migration.table.padEnd(24)} ${migration.purpose}`);
  }
  const shops = await client.query(`SELECT DISTINCT ON (lower(shop_name)) shop_name FROM shop_employees
    WHERE active = TRUE AND shop_name IS NOT NULL AND btrim(shop_name) <> '' ORDER BY lower(shop_name), shop_name`);
  const orders = await client.query('SELECT COUNT(*)::int AS n FROM orders');
  const assigned = (await exists(client, 'shop_order_assignments'))
    ? (await client.query('SELECT COUNT(*)::int AS n FROM shop_order_assignments')).rows[0].n
    : 0;
  const negative = await client.query('SELECT COUNT(*)::int AS n FROM products WHERE stock_quantity < 0');
  const diskImages = await client.query(`SELECT
      (SELECT COUNT(*) FROM products WHERE img LIKE '/uploads/%' OR img LIKE 'uploads/%')::int AS products,
      (SELECT COUNT(*) FROM categories WHERE image_url LIKE '/uploads/%' OR image_url LIKE 'uploads/%')::int AS categories`);
  lines.push('');
  lines.push(`Active shops: ${shops.rows.map(r => r.shop_name).join(', ') || 'none'}`);
  lines.push(`Orders: ${orders.rows[0].n} total, ${assigned} assigned -> ${orders.rows[0].n - assigned} would be assigned to ${shops.rows.length === 1 ? `"${shops.rows[0].shop_name}"` : '(needs SHOP_NAME: more than one shop)'}`);
  lines.push(`Products with negative stock (left as is; rule applies to new changes): ${negative.rows[0].n}`);
  lines.push(`Images stored on server disk (would be lost on deploy): ${diskImages.rows[0].products} product(s), ${diskImages.rows[0].categories} category(ies)`);
  return { lines, shops: shops.rows };
}

(async () => {
  const apply = process.argv.includes('--apply');
  let client;
  try {
    client = await pool.raw.connect();
    const before = await report(client);
    console.log(`Phase 1 database changes — ${apply ? 'APPLY' : 'DRY RUN (read-only)'}\n`);
    console.log(before.lines.join('\n'));
    if (!apply) {
      console.log('\nNothing was changed. To apply after approval: APPLY_PHASE1_MIGRATIONS=YES node scripts/phase1_migrations.cjs --apply');
      return;
    }
    if (process.env.APPLY_PHASE1_MIGRATIONS !== 'YES') {
      throw Object.assign(new Error('Set APPLY_PHASE1_MIGRATIONS=YES to confirm.'), { code: 'CONFIRMATION_REQUIRED' });
    }
    client.release();
    client = null;
    const { dir } = await backupDatabase();
    console.log(`\nBackup written to ${dir}`);
    client = await pool.raw.connect();
    for (const migration of MIGRATIONS) {
      await client.query(fs.readFileSync(path.join(root, migration.file), 'utf8'));
      console.log(`Applied ${migration.file}`);
    }
    const shopName = String(process.env.SHOP_NAME || '').trim()
      || (before.shops.length === 1 ? before.shops[0].shop_name : '');
    if (!shopName) {
      console.log('More than one active shop: existing orders were not assigned (set SHOP_NAME to choose).');
    } else {
      await client.query('BEGIN');
      const result = await client.query(`INSERT INTO shop_order_assignments (order_id, shop_name, assigned_at)
        SELECT o.order_id, $1, CURRENT_TIMESTAMP FROM orders o
        WHERE NOT EXISTS (SELECT 1 FROM shop_order_assignments soa WHERE soa.order_id = o.order_id)
        ON CONFLICT (order_id) DO NOTHING`, [shopName]);
      await client.query('COMMIT');
      console.log(`Assigned ${result.rowCount} existing order(s) to "${shopName}".`);
    }
    console.log('\nAfter:\n' + (await report(client)).lines.join('\n'));
  } catch (error) {
    if (client) await client.query('ROLLBACK').catch(() => {});
    console.error(error.code || 'PHASE1_MIGRATION_FAILED', error.message);
    process.exitCode = 1;
  } finally {
    client?.release();
    await pool.end();
  }
})();
