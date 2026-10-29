// Runs Shop read APIs against PostgreSQL without inserting or updating rows.
// The employee gate is stubbed only to test the read queries when no employee
// account has been provisioned yet. Output is limited to route names/counts.
const crypto = require('node:crypto');
const express = require('express');
const { pool: databasePool } = require('../db');
const installShopRoutes = require('../shop_routes');
const { signEmployeeToken } = require('../shop_service');

(async () => {
  const app = express();
  app.use(express.json());
  const pool = {
    query(sql, values) {
      if (sql.startsWith('SELECT active FROM shop_employees')) return Promise.resolve([[{ active: true }]]);
      return databasePool.query(sql, values);
    },
    getConnection: (...args) => databasePool.getConnection(...args),
  };
  const secret = crypto.randomBytes(32).toString('hex');
  installShopRoutes(app, pool, secret, (_req, res) => res.status(401).json({ success: false }));
  const server = await new Promise(resolve => {
    const instance = app.listen(0, '127.0.0.1', () => resolve(instance));
  });
  try {
    const token = signEmployeeToken({ id: crypto.randomUUID(), employee_id: 'SHOP-READONLY-CHECK' }, secret);
    const checks = [
      ['dashboard', '/api/shop/dashboard'],
      ['orders', '/api/shop/orders'],
      ['products', '/api/shop/products'],
      ['categories', '/api/shop/categories'],
      ['reports', '/api/shop/reports?period=daily'],
      ['monthly_reports', '/api/shop/reports?period=monthly'],
      ['product_reports', '/api/shop/reports?period=product'],
    ];
    const results = {};
    for (const [name, route] of checks) {
      const response = await fetch(`http://127.0.0.1:${server.address().port}${route}`, { headers: { Authorization: `Bearer ${token}` } });
      const body = await response.json();
      if (!response.ok || body.success !== true) throw Object.assign(new Error('Shop read endpoint failed.'), { code: response.status || 'INVALID_RESPONSE', route: name });
      const list = body.products || body.categories || body.orders || body.rows;
      results[name] = list ? list.length : 'ok';
    }
    console.log(JSON.stringify(results));
  } catch (error) {
    console.error(JSON.stringify({ route: error.route || 'preflight', code: error.code || error.name }));
    process.exitCode = 1;
  } finally {
    await new Promise(resolve => server.close(resolve));
    await databasePool.end();
  }
})();
