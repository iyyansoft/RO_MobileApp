const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const audit = fs.readFileSync(
  path.join(__dirname, '..', 'scripts', 'inspect-supabase-schema-readonly.cjs'),
  'utf8',
);

test('Supabase schema audit is project-guarded, read-only, and includes Storage metadata', () => {
  assert.match(audit, /expectedProjectRef\s*=\s*'czegmfzntnfpwaxgczds'/);
  assert.match(audit, /BEGIN READ ONLY/);
  assert.match(audit, /ROLLBACK/);
  assert.match(audit, /FROM storage\.buckets/);
  assert.match(audit, /n\.nspname = 'storage' AND c\.relname = 'objects'/);
  assert.match(audit, /schemaname IN \('public', 'storage'\)/);
  assert.match(audit, /errorCode:\s*error\.code\s*\|\|\s*error\.name/);
});
