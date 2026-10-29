const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

async function loadCore() {
  return import('../supabase/functions/_shared/admin_catalog_core.mjs');
}

const verifiedAdmin = {
  id: 'admin-1',
  email_confirmed_at: '2026-01-01T00:00:00Z',
  app_metadata: { role: 'admin' },
};

function request(body, headers = {}) {
  return new Request('https://local.test/admin-catalog', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

test('admin catalog rejects missing, unverified and non-admin identities', async () => {
  const { createAdminCatalogHandler } = await loadCore();
  const handler = createAdminCatalogHandler({
    authenticate: async req => req.headers.get('x-test-user') === 'admin'
      ? verifiedAdmin
      : req.headers.get('x-test-user') === 'unverified'
        ? { ...verifiedAdmin, email_confirmed_at: null }
        : req.headers.get('x-test-user') === 'dealer'
          ? { ...verifiedAdmin, app_metadata: { role: 'dealer' } }
          : null,
    repository: {},
  });

  assert.equal((await handler(request({ action: 'list_products' }))).status, 401);
  assert.equal((await handler(request({ action: 'list_products' }, { 'x-test-user': 'unverified' }))).status, 401);
  assert.equal((await handler(request({ action: 'list_products' }, { 'x-test-user': 'dealer' }))).status, 403);
});

test('verified admin can invoke every supported CRUD/list operation', async () => {
  const { createAdminCatalogHandler } = await loadCore();
  const calls = [];
  const repository = Object.fromEntries([
    ['listProducts', async () => ({ count: 0, products: [] })],
    ['createProduct', async values => ({ id: 'p1', values })],
    ['updateProduct', async (id, values) => ({ id, values })],
    ['deactivateProduct', async id => ({ product: { id, status: 'inactive' } })],
    ['listCategories', async () => ({ count: 0, categories: [] })],
    ['createCategory', async (values, userId) => ({ id: 'c1', values, userId })],
    ['updateCategory', async (id, values, userId) => ({ id, values, userId })],
    ['deleteCategory', async (id, userId) => ({ id, userId })],
  ].map(([name, implementation]) => [name, async (...args) => {
    calls.push([name, ...args]);
    return implementation(...args);
  }]));
  const handler = createAdminCatalogHandler({
    authenticate: async () => verifiedAdmin,
    repository,
  });
  const actions = [
    ['list_products'],
    ['create_product', null, { sku: 'A1' }],
    ['update_product', 'p1', { sku: 'A1' }],
    ['deactivate_product', 'p1'],
    ['list_categories'],
    ['create_category', null, { key_name: 'ro' }],
    ['update_category', 'c1', { key_name: 'ro' }],
    ['delete_category', 'c1'],
  ];
  for (const [action, targetId, values] of actions) {
    const response = await handler(request({ action, targetId, values }));
    assert.ok(response.status >= 200 && response.status < 300, `${action}: ${response.status}`);
    assert.equal((await response.json()).success, true);
  }
  assert.equal(calls.length, 8);
  assert.deepEqual(calls.find(([name]) => name === 'createCategory').at(-1), 'admin-1');
});

test('validation and unsupported operations fail before repository writes', async () => {
  const { createAdminCatalogHandler, normalizeProductInput, normalizeCategoryInput, normalizeBulkProductInput } = await loadCore();
  let writes = 0;
  const handler = createAdminCatalogHandler({
    authenticate: async () => verifiedAdmin,
    repository: { createProduct: async values => {
      normalizeProductInput(values);
      writes += 1;
    } },
  });
  assert.equal((await handler(request({ action: 'not_supported' }))).status, 400);
  assert.equal((await handler(request({ action: 'create_product', values: { sku: 'invalid sku' } }))).status, 400);
  assert.equal(writes, 0);
  assert.throws(() => normalizeProductInput({ name: 'x', sku: 'bad sku', category: 'x', price: 1, mrp: 2 }), /valid SKU/);
  assert.throws(() => normalizeProductInput({ name: 'x', sku: 'SKU-1', category: 'x', price: 0, mrp: 2 }), /dealer price/);
  assert.throws(() => normalizeCategoryInput({ title: '', key_name: 'valid' }), /title is required/);
  const normalized = normalizeBulkProductInput({
    productName: 'RO Membrane', sku_code: 'mem-001', category_name: 'membranes',
    purchasePrice: '500', dealerPrice: '900', mrp: '1250', stock: '12', moq: 'MOQ: 2 Units',
    productDescription: 'Long-life membrane', imageUrl: 'https://example.test/membrane.png',
  });
  assert.equal(normalized.name, 'RO Membrane');
  assert.equal(normalized.sku, 'MEM-001');
  assert.equal(normalized.purchase_price, 500);
  assert.equal(normalized.price, 900);
  assert.equal(normalized.moq, 'MOQ: 2 Units');
  assert.equal(normalized.description, 'Long-life membrane');
  assert.throws(() => normalizeBulkProductInput({ name: 'x', sku: 'X1', category: 'c', price: '9oops' }), /Dealer price must be a valid number/);
  assert.throws(() => normalizeBulkProductInput({ name: 42, sku: 'X1', category: 'c', price: 9 }), /Product name must be text/);
  assert.throws(() => normalizeBulkProductInput({ name: 'x', sku: 'X1', category: 'c', price: 9, badge: 4 }), /Badge must be text/);
  assert.throws(() => normalizeBulkProductInput({ name: 'x', sku: 'X1', category: 'c', price: 9.999 }), /two decimal places/);
  assert.throws(() => normalizeBulkProductInput({ name: 'x', sku: 'X1', category: 'c', price: 9, rating: 'x'.repeat(65) }), /Rating must be at most 64/);
  assert.throws(() => normalizeBulkProductInput({ name: 'x', sku: 'X1', category: 'c', price: 9, moq: '2.5' }), /MOQ must be a positive whole number/);
});

test('bulk row preparation skips duplicates and invalid rows without coercing malformed fields', async () => {
  const { prepareBulkProductRows } = await loadCore();
  const result = prepareBulkProductRows([
    { name: 'Membrane', sku: 'mem-1', category: 'membranes', price: 500 },
    { name: 'Duplicate', sku: 'MEM-1', category: 'membranes', price: 600 },
    { name: 'Invalid', sku: 'BAD-1', category: 'membranes', price: '500abc' },
  ]);
  assert.equal(result.rows.length, 1);
  assert.equal(result.rows[0].values.sku, 'MEM-1');
  assert.equal(result.skipped.length, 2);
  assert.match(result.skipped[0].reason, /duplicate SKU/i);
  assert.match(result.skipped[1].reason, /valid number/i);
  assert.throws(() => prepareBulkProductRows(Array(201).fill({})), /200 products/);
});

test('bulk action is server-admin authorized and returns retry-safe failure responses', async () => {
  const { createAdminCatalogHandler } = await loadCore();
  let attempts = 0;
  const handler = createAdminCatalogHandler({
    authenticate: async request => request.headers.get('x-role') === 'admin'
      ? verifiedAdmin
      : { ...verifiedAdmin, app_metadata: { role: 'dealer' } },
    repository: { bulkImportProducts: async (products, userId) => {
      attempts += 1;
      assert.equal(userId, verifiedAdmin.id);
      if (attempts === 1) throw new Error('database secret detail');
      return { importedCount: products.length, skippedCount: 0, imported: products, skipped: [], replayed: false };
    } },
  });
  const payload = { action: 'bulk_import_products', values: { products: [{ sku: 'SKU-1' }] } };
  assert.equal((await handler(request(payload, { 'x-role': 'dealer' }))).status, 403);
  const failed = await handler(request(payload, { 'x-role': 'admin' }));
  assert.equal(failed.status, 500);
  assert.doesNotMatch(JSON.stringify(await failed.json()), /database secret detail/);
  const retry = await handler(request(payload, { 'x-role': 'admin' }));
  assert.equal(retry.status, 201);
  assert.equal((await retry.json()).importedCount, 1);
  assert.equal(attempts, 2);
});

test('request size, image type and image payload are validated', async () => {
  const { createAdminCatalogHandler, parseImageDataUrl } = await loadCore();
  const handler = createAdminCatalogHandler({
    authenticate: async () => verifiedAdmin,
    repository: {},
  });
  const tooLarge = new Request('https://local.test/admin-catalog', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'list_products', data: 'x'.repeat(8 * 1024 * 1024) }),
  });
  assert.equal((await handler(tooLarge)).status, 413);
  assert.throws(() => parseImageDataUrl('data:text/plain;base64,YQ=='), /JPG, PNG or WEBP/);
  assert.throws(() => parseImageDataUrl(`data:image/png;base64,${'A'.repeat(7 * 1024 * 1024)}`), /smaller than 5 MB/);
  assert.equal(parseImageDataUrl('https://example.test/image.png'), null);
});

test('unexpected repository failures return sanitized errors', async () => {
  const { createAdminCatalogHandler } = await loadCore();
  const handler = createAdminCatalogHandler({
    authenticate: async () => verifiedAdmin,
    repository: { listProducts: async () => { throw new Error('sensitive database detail'); } },
  });
  const response = await handler(request({ action: 'list_products' }));
  assert.equal(response.status, 500);
  assert.deepEqual(await response.json(), { success: false, error: 'Catalog operation could not be completed.' });
});

test('bulk import SQL draft uses a service-only idempotency ledger and one transactional RPC', () => {
  const sql = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'drafts', 'unreconciled', '20261030_admin_bulk_import.sql'), 'utf8');
  assert.match(sql, /PRIMARY KEY \(admin_user_id, request_hash\)/);
  assert.match(sql, /pg_advisory_xact_lock/);
  assert.match(sql, /RETURN v_cached \|\| jsonb_build_object\('replayed', true\)/);
  assert.match(sql, /INSERT INTO public\.admin_bulk_import_requests/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.ro_admin_bulk_import_products[\s\S]*TO service_role/);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.ro_admin_bulk_import_products[\s\S]*FROM PUBLIC, anon, authenticated/);
  assert.doesNotMatch(sql, /ON CONFLICT\s*\(\s*lower\(sku\)\s*\)\s*DO\s+UPDATE/i);
  assert.match(sql, /EXCEPTION WHEN unique_violation/);
  assert.match(sql, /GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME/);
  assert.match(sql, /IS DISTINCT FROM 'array'/);
  assert.match(sql, /IS DISTINCT FROM 'object'/);
  assert.match(sql, /v_price \* 100 <> trunc\(v_price \* 100\)/);
  assert.match(sql, /CREATE TABLE IF NOT EXISTS public\.admin_bulk_import_requests/);
  assert.doesNotMatch(sql, /DROP TABLE|TRUNCATE/i);
});
