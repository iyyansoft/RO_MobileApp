const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const sql = (name) => fs.readFileSync(path.join(root, 'supabase', 'staging', name), 'utf8');
const profileSql = sql('002_dealer_profile_addresses.sql');
const cartSql = sql('003_dealer_cart.sql');
const historySql = sql('004_dealer_order_history.sql');
const stagingReadme = fs.readFileSync(path.join(root, 'supabase', 'staging', 'README.md'), 'utf8');
const profileRepo = fs.readFileSync(path.join(root, 'lib', 'core', 'supabase', 'supabase_dealer_data_repository.dart'), 'utf8');
const cartProvider = fs.readFileSync(path.join(root, 'lib', 'features', 'cart', 'presentation', 'providers', 'cart_provider.dart'), 'utf8');
const profileScreen = fs.readFileSync(path.join(root, 'lib', 'features', 'profile', 'presentation', 'screens', 'profile_screen.dart'), 'utf8');
const config = fs.readFileSync(path.join(root, 'lib', 'core', 'supabase', 'supabase_config.dart'), 'utf8');
const expressServer = fs.readFileSync(path.join(root, 'server.js'), 'utf8');
const migrationPlan = fs.readFileSync(path.join(root, 'SUPABASE_STAGING_MIGRATION_PLAN.md'), 'utf8');

test('profile/address stage links verified Auth identities without approving dealers', () => {
  assert.match(profileSql, /Users\/address RLS policies already exist; inspect and reconcile/);
  assert.match(profileSql, /tablename IN \('users','user_addresses'\)\s*\)/);
  assert.match(profileSql, /v_auth\.email_confirmed_at IS NULL/);
  assert.match(profileSql, /auth_user_id=auth\.uid\(\)/);
  assert.match(profileSql, /'pending',false/);
  assert.doesNotMatch(profileSql, /'approved',true/);
  assert.match(profileSql, /ro_users_self_read/);
  assert.match(profileSql, /ro_addresses_self_read/);
  assert.match(profileSql, /ro_addresses_self_delete/);
  assert.match(profileSql, /ro_update_current_dealer_profile/);
  assert.match(profileSql, /current_dealer_id\(\)/);
  assert.match(profileSql, /ro_save_dealer_address/);
  assert.match(profileSql, /ro_set_default_dealer_address/);
  assert.doesNotMatch(profileSql, /shop_order_assignments/);
  assert.doesNotMatch(profileSql, /\b(?:DROP\s+TABLE|TRUNCATE|DELETE\s+FROM)\b/i);
});

test('Express fallback keeps new password and Google dealers pending until approval', () => {
  const signupStart = expressServer.indexOf('// 3. Sign Up Endpoint');
  const signupEnd = expressServer.indexOf('// 4. Password Login Endpoint', signupStart);
  const signupRoute = expressServer.slice(signupStart, signupEnd);
  const googleStart = expressServer.indexOf("app.post('/api/auth/google-signin'");
  const googleEnd = expressServer.indexOf('// ADMIN AUTHENTICATION & SECURITY SYSTEM', googleStart);
  const googleRoute = expressServer.slice(googleStart, googleEnd);
  assert.match(signupRoute, /'pending', FALSE, 0/i);
  assert.doesNotMatch(signupRoute, /'approved',\s*TRUE/i);
  assert.match(googleRoute, /'pending', FALSE, 0/i);
  assert.match(expressServer, /user\.status !== 'approved'[\s\S]*?awaiting admin approval/);
  assert.match(expressServer, /user\.isApproved !== true/);
  assert.match(profileSql, /'pending',false/);
  assert.doesNotMatch(migrationPlan, /current Express signup and Google-signup handlers set new rows with `status='approved'`/);
});

test('profile client writes only allow-listed fields and retains Express fallback', () => {
  assert.match(profileRepo, /static Map<String, dynamic> profileUpdateValues/);
  assert.match(profileRepo, /rpc\(\s*'ro_update_current_dealer_profile'/);
  assert.doesNotMatch(profileRepo, /from\('users'\)[\s\S]*?\.update\(values\)/);
  assert.match(profileScreen, /if \(SupabaseConfig\.dealerDataSessionActive\)[\s\S]*?updateDealerProfile/);
  assert.match(profileScreen, /'user\/update-profile'/);
  assert.match(config, /USE_SUPABASE_DEALER_DATA'[\s\S]*?defaultValue:\s*false/);
});

test('cart stage scopes all client access and writes through stock-checked RPCs', () => {
  assert.match(cartSql, /Cart RLS policies already exist; inspect and reconcile/);
  assert.match(cartSql, /Existing cart\/product schema is incompatible/);
  assert.match(cartSql, /non-partial unique index on \(user_id, product_id\)/);
  assert.match(cartSql, /i\.indisunique[\s\S]*?i\.indpred IS NULL AND i\.indnkeyatts=2/);
  assert.match(cartSql, /Cart RPC names already exist; inspect their signatures and privileges/);
  assert.match(cartSql, /Cart request ledger already exists; inspect and reconcile/);
  assert.match(cartSql, /ro_cart_self_read/);
  assert.match(cartSql, /ro_cart_self_delete/);
  assert.match(cartSql, /user_id=public\.current_dealer_id\(\)/);
  assert.match(cartSql, /FOR UPDATE/);
  assert.match(cartSql, /Requested quantity exceeds available stock/);
  assert.match(cartSql, /REVOKE ALL ON FUNCTION public\.ro_add_cart_item/);
  assert.match(cartSql, /REVOKE ALL ON FUNCTION public\.ro_update_cart_item/);
  assert.match(cartSql, /ro_add_cart_item\(\s*p_product_id varchar,p_quantity integer,p_request_id uuid\s*\)\s+RETURNS void/);
  assert.match(cartSql, /ro_cart_add_requests/);
  assert.match(cartSql, /ON CONFLICT\(user_id,request_id\) DO NOTHING/);
  assert.match(cartSql, /Cart request ID was reused with different contents/);
  assert.match(cartSql, /ro_update_cart_item\(p_product_id varchar,p_quantity integer\)\s+RETURNS void/);
  assert.doesNotMatch(cartSql, /RETURNS public\.cart_items/);
  assert.doesNotMatch(cartSql, /GRANT\s+(?:ALL|INSERT|UPDATE)\s+ON\s+public\.cart_items/i);
});

test('cart client uses the safe catalog projection, dealer RPCs, and default Express fallback', () => {
  assert.match(profileRepo, /from\('cart_items'\)[\s\S]*?\.select\('product_id,quantity'\)/);
  const catalogLoadStart = profileRepo.indexOf("from('catalog_products')");
  const catalogLoadEnd = profileRepo.indexOf(".inFilter('id'", catalogLoadStart);
  assert.notEqual(catalogLoadStart, -1);
  assert.notEqual(catalogLoadEnd, -1);
  const catalogLoad = profileRepo.slice(catalogLoadStart, catalogLoadEnd);
  assert.match(catalogLoad, /dealer_price/);
  assert.doesNotMatch(catalogLoad, /purchase_price/);
  assert.match(profileRepo, /rpc\(\s*'ro_add_cart_item'/);
  assert.match(profileRepo, /'p_request_id': requestId/);
  assert.match(profileRepo, /FlutterSecureStorage/);
  assert.match(profileRepo, /_pendingCartAddKey/);
  assert.match(profileRepo, /rpc\(\s*'ro_update_cart_item'/);
  assert.match(profileRepo, /from\('cart_items'\)[\s\S]*?\.delete\(\)/);
  assert.match(cartProvider, /if \(SupabaseConfig\.dealerDataSessionActive\)[\s\S]*?repository\.addCartItem/);
  assert.match(cartProvider, /await api\.delete\('cart\/clear'/);
  assert.match(config, /USE_SUPABASE_DEALER_DATA'[\s\S]*?defaultValue:\s*false/);
});

test('order-history stage is dealer-read-only and leaves order/payment writes unavailable', () => {
  assert.match(historySql, /Dealer-history RLS policies already exist; inspect and reconcile/);
  assert.match(historySql, /Order-history schema is incompatible; missing columns/);
  assert.match(historySql, /ro_orders_self_read/);
  assert.match(historySql, /ro_order_items_self_read/);
  assert.match(historySql, /ro_rewards_self_read/);
  assert.match(historySql, /current_verified_auth_email\(\)/);
  assert.match(historySql, /email_confirmed_at IS NOT NULL/);
  assert.doesNotMatch(historySql, /auth\.jwt\(\)->>'email'/);
  assert.match(historySql, /user_id=public\.current_dealer_id\(\)/);
  assert.match(historySql, /ro_create_support_ticket/);
  assert.match(historySql, /delivery_fee,grand_total,with_gst,payment_status/);
  assert.doesNotMatch(historySql, /GRANT\s+(?:ALL|INSERT|UPDATE|DELETE)\s+ON\s+public\.(orders|order_items|rewards_history)/i);
  assert.doesNotMatch(historySql, /payment_id|razorpay|service_role/i);
});

test('GST invoice metadata reads use owner-scoped orders while preserving the Express fallback', () => {
  assert.match(profileRepo, /Future<Map<String, dynamic>> loadGstInvoices/);
  const invoiceRead = profileRepo.slice(
    profileRepo.indexOf('Future<Map<String, dynamic>> loadGstInvoices'),
    profileRepo.indexOf('Future<void> createSupportTicket'),
  );
  assert.match(invoiceRead, /\.eq\('user_id', userId\)/);
  assert.match(invoiceRead, /\.isFilter\('user_id', null\)/);
  assert.match(invoiceRead, /\.eq\('with_gst', true\)/);
  assert.match(profileScreen, /loadGstInvoices\(user\.id, email\)/);
  assert.match(profileScreen, /'user\/gst-invoices'/);
});

test('unreconciled feature drafts are outside the Supabase CLI migration directory', () => {
  const migrations = fs.readdirSync(path.join(root, 'supabase', 'migrations'));
  assert.deepEqual(migrations.filter((name) => name.endsWith('.sql')), []);
  for (const name of [
    '20261026_auth_rls_storage.sql',
    '20261027_secure_checkout.sql',
    '20261028_checkout_refund_reconciliation.sql',
    '20261029_admin_catalog.sql',
    '20261030_admin_bulk_import.sql',
  ]) {
    assert.ok(fs.existsSync(path.join(root, 'supabase', 'drafts', 'unreconciled', name)));
  }
});

test('staging SQL is not treated as project-targeted without independent staging verification', () => {
  for (const migration of [sql('001_catalog_read.sql'), profileSql, cartSql, historySql]) {
    assert.match(migration, /Project-target identity is NOT encoded|Project-target identity is not encoded/i);
    assert.match(migration.replace(/^\s*--\s?/gm, ''), /independently\s+verify staging/i);
  }
  assert.match(stagingReadme, /not project-targeted/i);
  assert.match(stagingReadme, /Do not run them in the SQL Editor or with `supabase db push` until staging has been independently identified/i);
  assert.match(stagingReadme, /No stage has been executed against production or remote staging/i);
});

test('every declared Express /api route is present in the migration inventory', () => {
  const inventory = fs.readFileSync(path.join(root, 'MIGRATION_ENDPOINT_INVENTORY.md'), 'utf8');
  const routes = [];
  for (const file of ['server.js', 'order_checkout.js', 'shop_routes.js']) {
    const source = fs.readFileSync(path.join(root, file), 'utf8');
    const declarations = /app\.(get|post|put|patch|delete)\(\s*(\[[\s\S]*?\]|'[^']*')/g;
    for (const declaration of source.matchAll(declarations)) {
      for (const pathMatch of declaration[2].matchAll(/'([^']+)'/g)) {
        if (pathMatch[1].startsWith('/api/')) {
          routes.push({ method: declaration[1].toUpperCase(), path: pathMatch[1] });
        }
      }
    }
  }
  assert.equal(routes.length, 66, 'update the inventory when the Express API surface changes');
  const inventoryRouteRows = inventory
    .split(/\r?\n/)
    .filter((line) => /^\|\s*(GET|POST|PUT|PATCH|DELETE) `\/api\//.test(line));
  assert.equal(inventoryRouteRows.length, 66,
    'list every concrete method/path separately, including aliases');
  const inventoryLines = inventory.split(/\r?\n/);
  const missing = routes.filter(({ method, path: route }) =>
    !inventoryLines.some((line) => line.includes(`| ${method} `) && line.includes(route)));
  assert.deepEqual(missing, []);
});
