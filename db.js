const mysql = require('mysql2/promise');
require('dotenv').config();

// Create MySQL Connection Pool
const pool = mysql.createPool({
  host: process.env.DB_HOST || process.env.MYSQLHOST || '127.0.0.1',
  port: parseInt(process.env.DB_PORT || process.env.MYSQLPORT || '3306', 10),
  user: process.env.DB_USER || process.env.MYSQLUSER || 'root',
  password: process.env.DB_PASSWORD || process.env.MYSQLPASSWORD || '',
  database: process.env.DB_NAME || process.env.MYSQLDATABASE || 'ro_wholesale_db',
  waitForConnections: true,
  connectionLimit: parseInt(process.env.DB_CONNECTION_LIMIT || '10', 10),
  queueLimit: 0,
  timezone: '+00:00',
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED === 'true' } : undefined
});

// Helper function to safely ensure schema DDL (CREATE TABLE IF NOT EXISTS)
async function ensureSchema() {
  try {
    const fs = require('fs');
    const path = require('path');
    const schemaPath = path.join(__dirname, 'schema.sql');
    if (!fs.existsSync(schemaPath)) return false;

    const schemaSql = fs.readFileSync(schemaPath, 'utf8');
    const statements = schemaSql
      .split(/;\s*$/m)
      .map(s => s.trim())
      .filter(s => s.length > 0);

    for (const stmt of statements) {
      if (stmt.toLowerCase().startsWith('create database') || stmt.toLowerCase().startsWith('use ')) {
        continue;
      }
      await pool.query(stmt);
    }

    const [rows] = await pool.query('SHOW TABLES;');
    const tableNames = rows.map(r => Object.values(r)[0]);
    const expectedTables = [
      'users', 'user_addresses', 'categories', 'products',
      'orders', 'order_items', 'rewards_history', 'otp_codes', 'support_tickets'
    ];
    const foundExpected = expectedTables.filter(t => tableNames.includes(t));

    console.log(`===================================================`);
    console.log(`Railway MySQL schema execution: PASS`);
    console.log(`Expected tables: ${expectedTables.length}`);
    console.log(`Found tables: ${foundExpected.length}`);
    console.log(`===================================================`);
    return foundExpected.length === expectedTables.length;
  } catch (err) {
    console.error('❌ [MYSQL SCHEMA NOTICE] Error applying schema:', err.message);
    return false;
  }
}

// Helper function to safely execute data migration if products/users are empty
async function ensureDataMigration() {
  try {
    const [[{ pCount }]] = await pool.query('SELECT COUNT(*) as pCount FROM products');
    const [[{ uCount }]] = await pool.query('SELECT COUNT(*) as uCount FROM users');

    if (pCount >= 20 && uCount >= 17) {
      console.log(`✅ [MYSQL DATA] Railway MySQL already populated (Products: ${pCount}, Users: ${uCount}). Skipping migration.`);
      return true;
    }

    console.log('📦 [MYSQL DATA] Running automatic one-time JSON -> Railway MySQL Data Migration...');
    const migrationScript = require('./scripts/migrate_json_to_mysql');
    if (typeof migrationScript.runMigrationWithPool === 'function') {
      await migrationScript.runMigrationWithPool(pool);
    }
    return true;
  } catch (err) {
    console.error('❌ [MYSQL DATA NOTICE] Error during data migration:', err.message);
    return false;
  }
}

// Helper function to test DB connection & ensure schema DDL
async function testConnection() {
  try {
    const connection = await pool.getConnection();
    console.log('✅ [MYSQL DB] Successfully connected to MySQL database pool');
    connection.release();

    if (process.env.AUTO_APPLY_SCHEMA === 'true') {
      console.log('⚙️ [MYSQL SCHEMA] AUTO_APPLY_SCHEMA is enabled. Running non-destructive schema checks...');
      await ensureSchema();
    } else {
      console.log('ℹ️ [MYSQL SCHEMA] Automatic schema execution skipped (AUTO_APPLY_SCHEMA!=true).');
    }

    return true;
  } catch (err) {
    console.error('❌ [MYSQL DB] Error connecting to MySQL database:', err.message);
    return false;
  }
}

module.exports = {
  pool,
  testConnection,
  ensureSchema,
  ensureDataMigration
};
