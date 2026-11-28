const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const databaseSource = fs.readFileSync(path.join(root, 'db.js'), 'utf8');
const migrationSource = fs.readFileSync(path.join(root, 'supabase_migration.sql'), 'utf8');
// supabase_data_import.sql is git-ignored (local data export): its check is
// skipped where the file is absent (e.g. GitHub Actions).
const importPath = path.join(root, 'supabase_data_import.sql');
const importSource = fs.existsSync(importPath) ? fs.readFileSync(importPath, 'utf8') : null;

test('backend uses pg and does not apply schema or data-import SQL during startup', () => {
  assert.match(databaseSource, /require\('pg'\)/);
  assert.doesNotMatch(databaseSource, /mysql2|ensureSchema|ensureDataMigration|CREATE TABLE|ALTER TABLE|supabase_data_import/);
  assert.match(databaseSource, /SUPABASE_DB_URL/);
  assert.match(migrationSource, /CREATE TABLE IF NOT EXISTS public\.payment_sessions/);
});

test('data-import SQL refuses to run on a non-empty database', { skip: importSource ? false : 'needs git-ignored local file: supabase_data_import.sql' }, () => {
  assert.match(importSource, /DO \$target_empty\$/);
});

test('database environment example keeps the Supabase URI server-side', () => {
  const envExample = fs.readFileSync(path.join(root, '.env.example'), 'utf8');
  assert.match(envExample, /^SUPABASE_DB_URL=postgresql:\/\/<USERNAME>:<PASSWORD>@<SUPABASE_SESSION_POOLER_HOST>:5432\/postgres\?sslmode=verify-full$/m);
  assert.doesNotMatch(envExample, /^DB_PASSWORD=/m);
});
