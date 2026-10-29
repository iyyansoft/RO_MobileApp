// Read-only Supabase schema inventory. This intentionally returns no business
// row contents and runs every catalog query inside a READ ONLY transaction.
require('dotenv').config();

const {pool} = require('../db');
const path = require('node:path');

const expectedProjectRef = 'czegmfzntnfpwaxgczds';

function configuredTargetMatchesExistingProject() {
  const projectUrl = process.env.SUPABASE_URL;
  if (!projectUrl) return false;
  try {
    const publicHost = new URL(projectUrl).hostname;
    if (publicHost !== `${expectedProjectRef}.supabase.co`) return false;
    const dbUrl = process.env.SUPABASE_DB_URL || process.env.DATABASE_URL;
    if (dbUrl) {
      const parsed = new URL(dbUrl);
      const hostname = parsed.hostname.toLowerCase();
      const username = decodeURIComponent(parsed.username).toLowerCase();
      return hostname === `db.${expectedProjectRef}.supabase.co` ||
        (hostname.endsWith('.pooler.supabase.com') &&
          username.includes(expectedProjectRef));
    }
    const host = process.env.PGHOST || process.env.SUPABASE_DB_HOST || '';
    const username = process.env.PGUSER || process.env.SUPABASE_DB_USER || '';
    return host.toLowerCase() === `db.${expectedProjectRef}.supabase.co` ||
      (host.toLowerCase().endsWith('.pooler.supabase.com') &&
        username.toLowerCase().includes(expectedProjectRef));
  } catch (_) {
    return false;
  }
}

async function main() {
  if (!configuredTargetMatchesExistingProject()) {
    console.error(JSON.stringify({
      connected: false,
      readOnly: true,
      projectTargetMatches: false,
      errorCode: 'PROJECT_TARGET_NOT_VERIFIED',
    }));
    process.exitCode = 1;
    await pool.end();
    return;
  }
  let client;
  try {
    client = await pool.raw.connect();
    await client.query('BEGIN READ ONLY');
    const tables = await client.query(`
      SELECT c.relname AS table_name,
             c.relrowsecurity AS rls_enabled
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v')
      ORDER BY c.relname
    `);
    const columns = await client.query(`
      SELECT table_name, column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_schema = 'public'
      ORDER BY table_name, ordinal_position
    `);
    const policies = await client.query(`
      SELECT tablename, policyname, roles, cmd
      FROM pg_policies
      WHERE schemaname IN ('public', 'storage')
      ORDER BY schemaname, tablename, policyname
    `);
    const storage = await client.query(`
      SELECT id, name, public, file_size_limit, allowed_mime_types
      FROM storage.buckets
      ORDER BY id
    `);
    const storageObjects = await client.query(`
      SELECT c.relrowsecurity AS rls_enabled
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'storage' AND c.relname = 'objects'
    `);
    const functions = await client.query(`
      SELECT p.proname AS function_name,
             pg_get_function_identity_arguments(p.oid) AS arguments,
             p.prosecdef AS security_definer
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
      ORDER BY p.proname, arguments
    `);
    const tableData = [];
    for (const {table_name} of tables.rows) {
      const identifier = `"${String(table_name).replaceAll('"', '""')}"`;
      const {rows} = await client.query(
        `SELECT EXISTS (SELECT 1 FROM public.${identifier} LIMIT 1) AS has_rows`,
      );
      tableData.push({table_name, has_rows: rows[0]?.has_rows === true});
    }
    await client.query('ROLLBACK');
    console.log(JSON.stringify({
      connected: true,
      readOnly: true,
      projectTargetMatches: true,
      tables: tables.rows,
      tableData,
      columns: columns.rows,
      policies: policies.rows,
      storageBuckets: storage.rows,
      storageObjectsRls: storageObjects.rows[0]?.rls_enabled ?? null,
      functions: functions.rows,
    }, null, 2));
  } catch (error) {
    if (client) {
      try { await client.query('ROLLBACK'); } catch (_) {}
    }
    // Connection details and provider error messages may contain sensitive
    // host/user data, so only the error code/name is reported.
    console.error(JSON.stringify({
      connected: false,
      readOnly: true,
      errorCode: error.code || error.name || 'UNKNOWN',
      syscall: error.syscall || null,
      pathBasename: error.path ? path.basename(error.path) : null,
    }));
    process.exitCode = 1;
  } finally {
    if (client) client.release();
    await pool.end();
  }
}

main();
