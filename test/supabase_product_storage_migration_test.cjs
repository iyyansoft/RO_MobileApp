const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const sql = fs.readFileSync(
  path.join(__dirname, '..', 'supabase', 'staging', '005_product_image_storage.sql'),
  'utf8',
);

test('product image Storage draft only creates a missing, exact public read bucket', () => {
  assert.match(sql, /BEGIN;[\s\S]*COMMIT;/);
  assert.match(sql, /FROM storage\.buckets[\s\S]*FOR UPDATE/);
  assert.match(sql, /INSERT INTO storage\.buckets/);
  assert.match(sql, /ON CONFLICT \(id\) DO NOTHING/);
  assert.match(sql, /ro-product-images/);
  assert.match(sql, /5242880/);
  assert.match(sql, /image\/jpeg/);
  assert.match(sql, /image\/png/);
  assert.match(sql, /image\/webp/);
  assert.match(sql, /configuration is incompatible/);
  assert.doesNotMatch(sql, /^\s*(?:UPDATE|DELETE|TRUNCATE|ALTER|DROP)\s/im);
  assert.doesNotMatch(sql, /^\s*CREATE\s+POLICY\b/im);
});
