const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(
  path.join(root, 'supabase', 'staging', '001_catalog_read.sql'),
  'utf8',
);
const provider = fs.readFileSync(
  path.join(root, 'lib', 'features', 'products', 'presentation', 'providers', 'product_provider.dart'),
  'utf8',
);
const config = fs.readFileSync(
  path.join(root, 'lib', 'core', 'supabase', 'supabase_config.dart'),
  'utf8',
);

test('catalog draft is additive and limited to existing catalog access', () => {
  assert.match(migration, /BEGIN;/);
  assert.match(migration, /COMMIT;/);
  assert.doesNotMatch(migration, /\b(?:DROP\s+TABLE|TRUNCATE|DELETE\s+FROM|INSERT\s+INTO)\b/i);
  assert.doesNotMatch(migration, /CREATE\s+TABLE/i);
  assert.match(migration, /ALTER TABLE public\.products ENABLE ROW LEVEL SECURITY/);
  assert.match(migration, /ALTER TABLE public\.categories ENABLE ROW LEVEL SECURITY/);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON TABLE public\.products, public\.categories/);
});

test('public product projection and grants exclude purchase cost and all writes', () => {
  const viewStart = migration.indexOf('CREATE OR REPLACE VIEW public.catalog_products');
  const viewEnd = migration.indexOf('REVOKE ALL PRIVILEGES ON TABLE public.catalog_products', viewStart);
  assert.notEqual(viewStart, -1);
  assert.notEqual(viewEnd, -1);
  const viewSql = migration.slice(viewStart, viewEnd);
  assert.match(viewSql, /security_invoker\s*=\s*true/i);
  assert.doesNotMatch(viewSql, /purchase_price/i);
  assert.match(viewSql, /p\.price AS dealer_price/);
  assert.match(viewSql, /WHERE p\.status <> 'inactive'/);
  assert.match(migration, /GRANT SELECT ON TABLE public\.catalog_products TO anon, authenticated/);
  assert.doesNotMatch(migration, /GRANT\s+(?:ALL|INSERT|UPDATE|DELETE|TRUNCATE)/i);
});

test('RLS policy preflight rejects unrelated permissive policies and client grants are least privilege', () => {
  assert.match(migration, /Unreviewed or incompatible catalog RLS policy exists/);
  assert.match(migration, /CREATE POLICY ro_products_active_read/);
  assert.match(migration, /CREATE POLICY ro_categories_read/);
  assert.match(migration, /GRANT SELECT \([\s\S]*?\) ON TABLE public\.products TO anon, authenticated/);
  const productGrant = migration.match(/GRANT SELECT \(([\s\S]*?)\) ON TABLE public\.products TO anon, authenticated/);
  assert.ok(productGrant);
  assert.doesNotMatch(productGrant[1], /purchase_price/i);
  assert.match(migration, /security[-_]invoker views/i);
});

test('Flutter catalog uses an explicit public projection, Express sort order, and a disabled default flag', () => {
  assert.match(provider, /from\('catalog_products'\)[\s\S]*?\.select\([\s\S]*?dealer_price[\s\S]*?\.order\('category_key', ascending:\s*true\)[\s\S]*?\.order\('name', ascending:\s*true\)/);
  assert.match(provider, /from\('categories'\)[\s\S]*?\.select\([\s\S]*?\.order\('display_order', ascending:\s*true\)/);
  assert.doesNotMatch(provider, /purchase_price/);
  assert.match(config, /USE_SUPABASE_CATALOG'[\s\S]*?defaultValue:\s*false/);
});
