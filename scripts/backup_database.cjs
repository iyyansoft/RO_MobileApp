// Read-only backup of every table in the public schema to
// backups/<timestamp>/<table>.json plus manifest.json (row counts).
// Never writes to the database. Contains customer data and password hashes:
// keep the folder private (it is git-ignored).
//
//   node scripts/backup_database.cjs
const fs = require('node:fs');
const path = require('node:path');
const { pool } = require('../db');

// date, timestamp, timestamptz, time, timetz: keep the database's own text.
const RAW_DATE_TIME_OIDS = new Set([1082, 1114, 1184, 1083, 1266]);
const rawDateTimeTypes = {
  getTypeParser(oid, format) {
    if (RAW_DATE_TIME_OIDS.has(oid)) return value => value;
    return require('pg').types.getTypeParser(oid, format);
  },
};

async function backupDatabase({ outDir } = {}) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dir = outDir || path.join(__dirname, '..', 'backups', stamp);
  fs.mkdirSync(dir, { recursive: true });
  const client = await pool.raw.connect();
  const manifest = { createdAt: new Date().toISOString(), dateTimes: 'database-text', tables: {} };
  try {
    // One consistent snapshot of all tables.
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const tables = await client.query(`SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name`);
    for (const { table_name: table } of tables.rows) {
      // Dates and times are saved exactly as the database stores them (text).
      // Converting them to JavaScript dates would shift "timestamp without
      // time zone" values by the computer's own time zone (5h30 in India)
      // when the backup is restored.
      const rows = await client.query({ text: `SELECT * FROM public."${table.replace(/"/g, '""')}"`, types: rawDateTimeTypes });
      // bytea arrives as a Buffer (pg) or a Uint8Array (PGlite); keep the bytes.
      fs.writeFileSync(path.join(dir, `${table}.json`), JSON.stringify(rows.rows, function replacer(key, value) {
        const raw = this[key];
        return ArrayBuffer.isView(raw) ? { $base64: Buffer.from(raw.buffer, raw.byteOffset, raw.byteLength).toString('base64') } : value;
      }));
      manifest.tables[table] = rows.rowCount;
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify(manifest, null, 2));
  return { dir, manifest };
}

module.exports = { backupDatabase };

if (require.main === module) {
  backupDatabase()
    .then(({ dir, manifest }) => {
      const total = Object.values(manifest.tables).reduce((sum, n) => sum + n, 0);
      console.log(`Backup written to ${dir}: ${Object.keys(manifest.tables).length} tables, ${total} rows.`);
    })
    .catch(error => { console.error('BACKUP_FAILED', error.code || error.message); process.exitCode = 1; })
    .finally(() => pool.end());
}
