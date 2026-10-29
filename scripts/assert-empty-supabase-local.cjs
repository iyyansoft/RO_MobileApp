const assert = require('node:assert/strict');
const { Client } = require('pg');

async function main() {
  const rawUrl = process.env.SUPABASE_LOCAL_TEST_DB_URL;
  const target = new URL(rawUrl ?? '');
  assert.ok(['localhost', '127.0.0.1', '::1'].includes(target.hostname),
    'local fixture check refuses non-loopback database hosts');
  assert.equal(target.port, process.env.SUPABASE_LOCAL_TEST_DB_PORT ?? '54332',
    'local fixture check requires the isolated database port');
  assert.equal(target.pathname, '/postgres', 'local fixture check requires the disposable postgres database');
  assert.ok(!rawUrl.includes('czegmfzntnfpwaxgczds'), 'hosted Supabase is forbidden');

  const client = new Client({ connectionString: rawUrl });
  await client.connect();
  try {
    const result = await client.query(`
      SELECT count(*)::int AS count FROM information_schema.tables
      WHERE table_schema='public' AND table_type='BASE TABLE'
    `);
    assert.equal(result.rows[0].count, 0,
      'refuse to overwrite any pre-existing public table in the disposable local database');
  } finally {
    await client.end();
  }
}

main().catch(error => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
