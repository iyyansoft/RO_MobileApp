const mysql = require('mysql2/promise');
require('dotenv').config();

// Create MySQL Connection Pool
const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: parseInt(process.env.DB_PORT || '3306', 10),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'ro_wholesale_db',
  waitForConnections: true,
  connectionLimit: parseInt(process.env.DB_CONNECTION_LIMIT || '10', 10),
  queueLimit: 0,
  timezone: '+00:00',
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED === 'true' } : undefined
});

// Helper function to test DB connection
async function testConnection() {
  try {
    const connection = await pool.getConnection();
    console.log('✅ [MYSQL DB] Successfully connected to MySQL database pool');
    connection.release();
    return true;
  } catch (err) {
    console.error('❌ [MYSQL DB] Error connecting to MySQL database:', err.message);
    return false;
  }
}

module.exports = {
  pool,
  testConnection
};
