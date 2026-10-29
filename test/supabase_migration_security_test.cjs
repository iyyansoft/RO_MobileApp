const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(
  path.join(__dirname, '..', 'supabase', 'drafts', 'unreconciled', '20261026_auth_rls_storage.sql'),
  'utf8',
);
const dealerRepository = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'core', 'supabase', 'supabase_dealer_data_repository.dart'),
  'utf8',
);
const server = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');

test('Supabase migration is additive and keeps purchase price and credential hashes private', () => {
  assert.doesNotMatch(migration, /\bDROP\s+TABLE\b|\bTRUNCATE\b|\bDELETE\s+FROM\b/i);
  assert.match(migration, /CREATE OR REPLACE VIEW public\.catalog_products/);
  assert.doesNotMatch(migration.slice(migration.indexOf('CREATE OR REPLACE VIEW public.catalog_products'), migration.indexOf('ALTER TABLE public.categories ENABLE')), /purchase_price/i);
  assert.doesNotMatch(migration, /GRANT\s+SELECT\s+ON\s+public\.users\s+TO\s+authenticated/i);
  assert.doesNotMatch(migration, /GRANT\s+SELECT\s*\([^)]*(password_hash|auth_user_id)/is);
  assert.match(migration, /ALTER TABLE public\.users ENABLE ROW LEVEL SECURITY/);
});

test('Supabase Auth profile RPC links only the verified current identity', () => {
  assert.match(migration, /auth\.uid\(\) IS NULL/);
  assert.match(migration, /v_auth\.email_confirmed_at IS NULL/);
  assert.match(migration, /WHERE auth_user_id = auth\.uid\(\)/);
  assert.match(migration, /auth_user_id IS NULL/);
  assert.match(migration, /password_hash, email_verified/);
  assert.match(migration, /'!supabase-auth-managed!'/);
  assert.match(migration, /v_company, v_name, v_address, v_gst, 'pending', false\)/);
  assert.doesNotMatch(migration, /v_company, v_name, v_address, v_gst, 'approved', true\)/);
});

test('dealer data RPCs enforce dealer ownership and bounded cart quantities', () => {
  assert.match(migration, /ro_add_cart_item\([\s\S]*?public\.current_dealer_id\(\)/);
  assert.match(migration, /ro_update_cart_item\([\s\S]*?public\.current_dealer_id\(\)/);
  assert.match(migration, /ro_set_default_dealer_address\([\s\S]*?public\.current_dealer_id\(\)/);
  assert.match(migration, /Requested quantity exceeds available stock/);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.ro_add_cart_item/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.ro_add_cart_item/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.ro_update_cart_item/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.ro_set_default_dealer_address/);
});

test('dealer RLS uses linked ownership and legacy email only for unlinked rows', () => {
  assert.match(migration, /user_id IS NULL AND auth\.jwt\(\)->>'email' IS NOT NULL/);
  assert.doesNotMatch(migration, /user_id = public\.current_dealer_id\(\) OR lower\(user_email/i);
  assert.match(migration, /ro_addresses_self_read/);
  assert.match(migration, /ro_addresses_self_delete/);
  assert.match(migration, /ro_cart_self_delete/);
  assert.match(migration, /ro_rewards_self_read/);
  assert.match(migration, /ro_support_self_read/);
});

test('client grants cannot mutate server-owned business values or identity sequences', () => {
  assert.match(migration, /FROM PUBLIC, anon, authenticated/);
  assert.match(migration, /GRANT SELECT, DELETE ON public\.cart_items TO authenticated/);
  assert.doesNotMatch(migration, /GRANT\s+[^;]*INSERT[^;]*ON public\.cart_items/is);
  assert.doesNotMatch(migration, /GRANT\s+[^;]*UPDATE[^;]*ON public\.cart_items/is);
  assert.doesNotMatch(migration, /GRANT\s+[^;]*(INSERT|UPDATE|DELETE)[^;]*ON public\.(orders|order_items|rewards_history|otp_codes|payment_sessions)/is);
  assert.match(migration, /REVOKE ALL ON SEQUENCE %s FROM PUBLIC, anon, authenticated/);
  assert.match(migration, /ro_create_support_ticket/);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.ro_create_support_ticket/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.ro_create_support_ticket/);
});

test('RLS migration fails closed on unreviewed policies and keeps Storage writes admin-only', () => {
  assert.match(migration, /Unreviewed RLS policy/);
  assert.match(migration, /auth\.jwt\(\)->'app_metadata'->>'role' = 'admin'/);
  assert.doesNotMatch(migration, /auth\.jwt\(\)->'user_metadata'/);
});

test('dealer catalog endpoint never selects or returns purchase price', () => {
  const start = server.indexOf("app.get('/api/products'");
  const end = server.indexOf("app.get('/api/admin/products'", start);
  assert.notEqual(start, -1);
  assert.notEqual(end, -1);
  const publicCatalogRoute = server
    .slice(start, end)
    .replace(/^\s*\/\/.*$/gm, '');
  assert.match(publicCatalogRoute, /SELECT id, category_key/);
  assert.doesNotMatch(publicCatalogRoute, /purchase_price/i);
});

test('dealer-facing migration revokes direct access to all live shop tables', () => {
  for (const table of [
    'shop_employees',
    'shop_order_assignments',
    'shop_delivery_items',
    'shop_admin_notifications',
    'shop_product_enquiries',
  ]) {
    assert.match(migration, new RegExp(`public\\.${table}`, 'i'));
  }
  assert.match(migration, /Unreviewed RLS policy/);
});

test('dealer repository only uses the restricted cart, address, and ticket paths', () => {
  assert.match(dealerRepository, /'ro_update_cart_item'/);
  assert.doesNotMatch(dealerRepository, /from\('cart_items'\)\s*\.update/);
  assert.match(dealerRepository, /'ro_set_default_dealer_address'/);
  assert.match(dealerRepository, /'ro_save_dealer_address'/);
  assert.match(dealerRepository, /'ro_create_support_ticket'/);
  assert.doesNotMatch(dealerRepository, /from\('user_addresses'\)\s*\.upsert/);
  assert.doesNotMatch(dealerRepository, /from\('support_tickets'\)\s*\.insert/);
  assert.doesNotMatch(dealerRepository, /'is_default'\s*:\s*false/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.ro_save_dealer_address/);
});
