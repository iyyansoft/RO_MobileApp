// One-purpose additive migration runner. Requires explicit local opt-in.
const fs = require('node:fs');
const path = require('node:path');
const { pool } = require('../db');

(async () => {
  let client;
  try {
    if (process.env.APPLY_SHOP_APP_MIGRATION !== 'YES') {
      throw Object.assign(new Error('Set APPLY_SHOP_APP_MIGRATION=YES to confirm this additive migration.'), { code: 'CONFIRMATION_REQUIRED' });
    }
    client = await pool.raw.connect();
    const preflight = await client.query(`SELECT
      to_regclass('public.users') AS users,
      to_regclass('public.products') AS products,
      to_regclass('public.categories') AS categories,
      to_regclass('public.orders') AS orders,
      to_regclass('public.order_items') AS order_items`);
    const base = preflight.rows[0];
    if (Object.values(base).some(value => value == null)) {
      throw Object.assign(new Error('Required RO app tables were not all found; migration was not applied.'), { code: 'BASE_SCHEMA_MISMATCH' });
    }
    const sql = fs.readFileSync(path.join(__dirname, '..', 'shop_app_migration.sql'), 'utf8');
    await client.query(sql);
    console.log('Shop App additive PostgreSQL migration applied successfully.');
  } catch (error) {
    if (client) await client.query('ROLLBACK').catch(() => {});
    console.error(error.code || 'SHOP_MIGRATION_FAILED');
    process.exitCode = 1;
  } finally {
    client?.release();
    await pool.end();
  }
})();
