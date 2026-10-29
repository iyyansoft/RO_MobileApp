// Read-only schema preflight for the Shop App. Prints table/column presence only.
const { pool } = require('../db');

(async () => {
  try {
    const result = await pool.raw.query(`
      SELECT table_name, column_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name IN (
          'users', 'products', 'categories', 'orders', 'order_items',
          'shop_employees', 'shop_order_assignments', 'shop_delivery_items', 'shop_admin_notifications',
          'shop_product_enquiries'
        )
      ORDER BY table_name, ordinal_position
    `);
    const names = new Set(result.rows.map(row => row.table_name));
    const columnNames = new Set(result.rows.map(row => `${row.table_name}.${row.column_name}`));
    const required = ['users', 'products', 'categories', 'orders', 'order_items'];
    const existing = ['shop_employees', 'shop_order_assignments', 'shop_delivery_items', 'shop_admin_notifications', 'shop_product_enquiries'];
    console.log(JSON.stringify({
      baseTables: Object.fromEntries(required.map(name => [name, names.has(name)])),
      shopTables: Object.fromEntries(existing.map(name => [name, names.has(name)])),
      requiredShopColumns: {
        deliveryConfirmed: columnNames.has('shop_delivery_items.delivery_confirmed'),
      },
      shopColumns: result.rows.filter(row => row.table_name.startsWith('shop_')).map(row => `${row.table_name}.${row.column_name}`),
    }));
  } catch (error) {
    console.log(error.code || error.name || 'DATABASE_CHECK_FAILED');
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();
