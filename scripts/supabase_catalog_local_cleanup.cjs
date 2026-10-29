const assert = require('node:assert/strict');

const apiUrl = process.env.SUPABASE_LOCAL_TEST_API_URL;
const anonKey = process.env.SUPABASE_LOCAL_TEST_ANON_KEY;
const serviceKey = process.env.SUPABASE_LOCAL_TEST_SERVICE_ROLE_KEY;

async function main() {
  const api = new URL(apiUrl ?? '');
  assert.ok(['127.0.0.1', 'localhost', '::1'].includes(api.hostname));
  assert.equal(api.port, '54331');
  assert.ok(!apiUrl.includes('czegmfzntnfpwaxgczds'));
  assert.ok(anonKey && serviceKey);
  const response = await fetch(new URL('/storage/v1/object/ro-product-images', api), {
    method: 'DELETE',
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ prefixes: ['local-test/catalog-image.png'] }),
  });
  assert.ok([200, 204, 404].includes(response.status),
    `local image fixture cleanup failed (HTTP ${response.status})`);
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
