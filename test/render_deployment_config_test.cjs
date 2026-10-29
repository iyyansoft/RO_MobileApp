const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const server = fs.readFileSync(path.join(root, 'server.js'), 'utf8');
const database = fs.readFileSync(path.join(root, 'db.js'), 'utf8');
const emailProvider = fs.readFileSync(path.join(root, 'email_provider.js'), 'utf8');
const envExample = fs.readFileSync(path.join(root, '.env.example'), 'utf8');
const ignore = fs.readFileSync(path.join(root, '.gitignore'), 'utf8');

test('Render server binds the assigned port on all interfaces', () => {
  assert.match(server, /const PORT = process\.env\.PORT/);
  assert.match(server, /app\.listen\(PORT,\s*['"]0\.0\.0\.0['"]/);
});

test('production startup requires Supabase and non-default authentication secrets', () => {
  for (const variable of ['SESSION_SECRET', 'SUPABASE_DB_URL', 'SUPABASE_DB_SSL_CA', 'SUPABASE_URL',
    'SUPABASE_PUBLISHABLE_KEY', 'SHOP_EMPLOYEE_SESSION_SECRET', 'ADMIN_EMAIL', 'ADMIN_PASSWORD']) {
    assert.ok(server.includes(variable), `production startup should validate ${variable}`);
  }
  assert.doesNotMatch(server, /process\.env\.(SESSION_SECRET|ADMIN_EMAIL|ADMIN_PASSWORD)\s*\|\|\s*['"][^'"]+['"]/);
  assert.match(server, /SUPABASE_PUBLISHABLE_KEY\s*\|\|\s*process\.env\.SUPABASE_ANON_KEY/);
});

test('PostgreSQL TLS verification remains required and hosted CA paths are portable', () => {
  assert.match(database, /rejectUnauthorized:\s*true/);
  assert.match(database, /path\.join\(__dirname,\s*file\)/);
  assert.match(envExample, /^SUPABASE_DB_SSL_CA_FILE=certs\/supabase-root\.crt$/m);
  assert.doesNotMatch(envExample, /[A-Z]:\\/i);
});

test('transactional email uses HTTPS and SMTP fallback requires certificate verification', () => {
  assert.match(emailProvider, /https:\/\/api\.brevo\.com\/v3\/smtp\/email/);
  assert.match(emailProvider, /tls:\s*\{\s*rejectUnauthorized:\s*true\s*\}/);
  assert.match(emailProvider, /requireTLS:\s*true/);
  assert.doesNotMatch(emailProvider, /rejectUnauthorized:\s*false/);
  assert.match(envExample, /^BREVO_API_KEY=$/m);
  assert.match(envExample, /^BREVO_SENDER_EMAIL=$/m);
  assert.match(server, /BREVO_API_KEY and BREVO_SENDER_EMAIL/);
});

test('environment template contains placeholders only and sensitive local files are ignored', () => {
  assert.match(envExample, /^SUPABASE_DB_URL=postgresql:\/\/<USERNAME>:<PASSWORD>@<SUPABASE_SESSION_POOLER_HOST>/m);
  assert.match(ignore, /^\.env\*$/m);
  assert.match(ignore, /^!\.env\.example$/m);
  assert.match(ignore, /^\*_db\.json$/m);
  assert.match(ignore, /^\*service[-_]role\*$/m);
});
