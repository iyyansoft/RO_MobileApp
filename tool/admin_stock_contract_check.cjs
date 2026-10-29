// Executes only the three stock mutation handlers against in-memory doubles.
// No server is started and no user files, databases, or networks are accessed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');
const markers = ['// Admin Endpoint: Add New Product', '// Admin Endpoint: Bulk Import Products', '// Admin Endpoint: Edit Product', '// Admin Endpoint: Delete Product'];
const handlers = {};
let products = [];
let queries = [];
const sandbox = {
  app: { post(route, middleware, handler) { handlers[route] = handler; }, put(route, middleware, handler) { handlers[route] = handler; } },
  requireAdminAuth() {},
  loadJsonProducts: () => structuredClone(products),
  saveJsonProducts: rows => { products = structuredClone(rows); },
  saveUploadedFile: value => value,
  pool: { async query(sql, values) { queries.push({ sql, values }); return [[]]; } },
  console: { log() {}, warn() {}, error() {} },
};
vm.createContext(sandbox);
for (let index = 0; index < 3; index++) {
  const start = source.indexOf(markers[index]);
  const end = source.indexOf(markers[index + 1], start);
  assert(start >= 0 && end > start, 'Handler markers must exist');
  vm.runInContext(source.slice(start, end), sandbox);
}
const base = { name: 'Test product', sku: 'TEST-1', category: 'spares', price: 100 };
async function invoke(route, body, seed = []) {
  products = structuredClone(seed); queries = [];
  const response = { code: 200, status(code) { this.code = code; return this; }, json(value) { this.body = value; return this; } };
  await handlers[route]({ body, params: { id: 'existing' } }, response);
  for (const { sql, values } of queries) {
    if (values) assert.equal((sql.match(/\?/g) || []).length, values.length, 'SQL placeholders match stock bind values');
  }
  return response;
}
(async () => {
  for (const invalid of [-1, 1.5, '', null, true, [], {}, 'bad', 2147483648]) {
    for (const field of ['stock_quantity', 'min_stock']) {
      const response = await invoke('/api/admin/products', { ...base, [field]: invalid });
      assert.equal(response.code, 400, `Reject ${field}=${invalid}`);
      assert.equal(products.length, 0, 'Invalid product is never persisted');
    }
  }
  let response = await invoke('/api/admin/products', { ...base, stock_quantity: 0, min_stock: '2' });
  assert.equal(response.code, 201);
  assert.equal(products[0].stock_quantity, 0);
  assert.equal(products[0].min_stock, 2);
  assert.deepEqual(Array.from(queries.find(query => query.sql.includes('INSERT INTO products')).values.slice(-2)), [0, 2]);
  const seed = [{ ...base, id: 'existing', stock_quantity: 7, min_stock: 3 }];
  response = await invoke('/api/admin/products/:id', base, seed);
  assert.equal(response.code, 200);
  assert.equal(products[0].stock_quantity, 7, 'Omitted stock survives editing');
  assert.equal(products[0].min_stock, 3);
  response = await invoke('/api/admin/products/:id', { ...base, stock_quantity: 0, min_stock: 0 }, seed);
  assert.equal(response.code, 200);
  assert.equal(products[0].stock_quantity, 0, 'Zero inventory is preserved');
  response = await invoke('/api/admin/products/:id', { ...base, stock_quantity: -1 }, seed);
  assert.equal(response.code, 400);
  assert.equal(products[0].stock_quantity, 7);
  response = await invoke('/api/admin/products/bulk', { products: [
    { ...base, stock_quantity: 11, min_stock: 4 },
    { ...base, sku: 'BAD', stock_quantity: 1.2 },
    { ...base, sku: 'DEFAULT' },
  ] });
  assert.equal(response.code, 201);
  assert.equal(response.body.importedCount, 2);
  assert.equal(response.body.skippedCount, 1);
  assert.equal(products.find(product => product.sku === 'TEST-1').stock_quantity, 11);
  assert.equal(products.find(product => product.sku === 'TEST-1').min_stock, 4);
  assert.equal(products.find(product => product.sku === 'DEFAULT').stock_quantity, 50);
  assert.equal(products.find(product => product.sku === 'DEFAULT').min_stock, 10);
  console.log('Admin stock contracts passed: validation, zero/default/preserved inventory, JSON and SQL persistence, bulk skipped rows.');
})().catch(error => { console.error(error); process.exitCode = 1; });
