const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const databaseSource = fs.readFileSync(path.join(root, 'db.js'), 'utf8');
const migrationSource = fs.readFileSync(path.join(root, 'supabase_migration.sql'), 'utf8');
const importSource = fs.readFileSync(path.join(root, 'supabase_data_import.sql'), 'utf8');

test('backend uses pg and does not apply schema or data-import SQL during startup', () => {
  assert.match(databaseSource, /require\('pg'\)/);
  assert.doesNotMatch(databaseSource, /mysql2|ensureSchema|ensureDataMigration|CREATE TABLE|ALTER TABLE|supabase_data_import/);
  assert.match(databaseSource, /SUPABASE_DB_URL/);
  assert.match(migrationSource, /CREATE TABLE IF NOT EXISTS public\.payment_sessions/);
  assert.match(importSource, /DO \$target_empty\$/);
});

test('database environment example keeps the Supabase URI server-side', () => {
  const envExample = fs.readFileSync(path.join(root, '.env.example'), 'utf8');
  assert.match(envExample, /^SUPABASE_DB_URL=postgresql:/m);
  assert.doesNotMatch(envExample, /^DB_PASSWORD=/m);
});
