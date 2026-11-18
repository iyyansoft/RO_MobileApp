const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../server.js'), 'utf8');
const start = source.indexOf("app.post('/api/admin/products/bulk'");
const end = source.indexOf("app.put('/api/admin/products/", start);
const block = source.slice(start, end);
const handlerCode = block.slice(block.indexOf('async (req, res) => {'), block.lastIndexOf('});') + 1);
const priceRuleStart = source.indexOf('function productPriceError(');
const priceRuleEnd = /\r?\n}\r?\n/.exec(source.slice(priceRuleStart));
const productPriceError = vm.runInNewContext(
  `(${source.slice(priceRuleStart, priceRuleStart + priceRuleEnd.index + priceRuleEnd[0].trimEnd().length)})`,
);

async function save({ offline = false, rejectSecond = false, products } = {}) {
  let mirrored = null;
  const inserts = [];
  const handler = vm.runInNewContext(`(${handlerCode})`, {
    pool: { query: async (sql, values) => {
      if (offline) throw new Error('Connection refused');
      if (sql.includes('INSERT INTO products')) {
        inserts.push(values);
        if (rejectSecond && values[3] === 'SECOND') throw new Error('Write failed');
        return [{ affectedRows: 1 }];
      }
      if (sql.startsWith('SELECT id, key_name, title FROM categories')) return [[{ id: 'category-1', key_name: 'membranes', title: 'Membranes' }]];
      return [[]];
    } },
    saveUploadedFile: (image) => image,
    storeProductImage: async (image) => image,
    productPriceError,
    console: { error() {}, warn() {} },
  });
  const response = { statusCode: 200, body: null, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
  await handler({ body: { products: products ?? ['FIRST', 'SECOND'].map((sku) => ({ sku, name: sku, category: 'membranes', purchase_price: 500, price: 900, mrp: 1200, moq: '2', stock_quantity: 12, desc: 'Details', img: 'https://example.test/image.png' })) } }, response);
  return { response, mirrored, inserts };
}

test('unavailable PostgreSQL never creates JSON-only products', async () => {
  const { response, mirrored, inserts } = await save({ offline: true });
  assert.equal(response.statusCode, 503);
  assert.equal(response.body.success, false);
  assert.equal(mirrored, null);
  assert.equal(inserts.length, 0);
});
test('all rows preserve separate prices and stock in PostgreSQL inserts without a local mirror', async () => {
  const { response, mirrored, inserts } = await save();
  assert.equal(response.body.importedCount, 2);
  assert.equal(mirrored, null);
  for (const values of inserts) {
    assert.equal(values[6], 500);
    assert.equal(values[7], 900);
    assert.equal(values[18], 12);
  }
});
test('bulk import accepts Product Name and Product Description aliases and stores the description', async () => {
  const { response, inserts } = await save({ products: [{
    sku: 'ALIAS-1',
    productName: 'Alias product name',
    productDescription: 'Long product description from the upload sheet',
    category: 'membranes',
    price: 900,
  }] });
  assert.equal(response.body.importedCount, 1);
  assert.equal(inserts.length, 1);
  assert.equal(inserts[0][4], 'Alias product name');
  assert.equal(inserts[0][13], 'Long product description from the upload sheet');
});
test('partial PostgreSQL failures report only confirmed products as imported', async () => {
  const { response, mirrored } = await save({ rejectSecond: true });
  assert.equal(response.body.importedCount, 1);
  assert.equal(response.body.skippedCount, 1);
  assert.equal(mirrored, null);
  assert.deepEqual(Array.from(response.body.imported, (row) => row.sku), ['FIRST']);
  assert.equal(response.body.skipped[0].sku, 'SECOND');
});

test('rows whose MRP is below the dealer price are skipped with a reason', async () => {
  const { response, inserts } = await save({ products: [
    { sku: 'OK-1', name: 'Valid', category: 'membranes', purchase_price: 7500, price: 8500, mrp: 12000 },
    { sku: 'LOW-MRP', name: 'Bad MRP', category: 'membranes', purchase_price: 7500, price: 8500, mrp: 8000 },
    { sku: 'NEG-COST', name: 'Bad cost', category: 'membranes', purchase_price: -1, price: 8500, mrp: 12000 },
  ] });
  assert.equal(response.body.importedCount, 1);
  assert.deepEqual(inserts.map((v) => v[3]), ['OK-1']);
  assert.deepEqual([...response.body.skipped.map((s) => s.sku)].sort(), ['LOW-MRP', 'NEG-COST']);
  assert.match(response.body.skipped.find((s) => s.sku === 'LOW-MRP').reason, /MRP cannot be lower/);
});
