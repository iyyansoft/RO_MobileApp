// Deployment safety:
//  - /health reports the Git commit Render deployed (RENDER_GIT_COMMIT).
//  - The backend refuses to start on a developer computer against a remote
//    (Production) database unless ALLOW_LOCAL_PRODUCTION_DB=yes.
//  - db.js reports local vs remote without ever connecting.
// Every case runs in its own child process with a FAKE database module, so
// nothing here can reach a real database.
const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const root = path.join(__dirname, '..');

/** Starts server.js in a child process with a fake db whose target is `remote`. */
function startServer(env, { remote = false } = {}) {
  const script = `
    const path = require('node:path');
    const root = ${JSON.stringify(root)};
    const dbPath = require.resolve(path.join(root, 'db'));
    require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: {
      pool: { query: async () => [[{ ok: 1 }]], end: async () => {} },
      testConnection: async () => true,
      connectionTarget: () => ({ remote: ${remote} }),
    } };
    console.log = () => {};
    const { server } = require(path.join(root, 'server.js'));
    const done = async () => {
      const res = await fetch('http://127.0.0.1:' + server.address().port + '/health');
      process.stdout.write('HEALTH ' + res.headers.get('cache-control') + ' ' + JSON.stringify(await res.json()) + '\\n');
      process.exit(0);
    };
    server.listening ? done() : server.once('listening', done);
  `;
  const childEnv = {
    ...process.env,
    PORT: '0', SESSION_SECRET: 'test-session-secret', ADMIN_EMAIL: 'admin@test.local', ADMIN_PASSWORD: 'test-password',
    NODE_ENV: 'test', RENDER: '', RENDER_SERVICE_ID: '', RENDER_GIT_COMMIT: '', ALLOW_LOCAL_PRODUCTION_DB: '',
    ...env,
  };
  const result = spawnSync(process.execPath, ['-e', script], { cwd: root, env: childEnv, encoding: 'utf8', timeout: 60000 });
  const health = (result.stdout.match(/^HEALTH (\S+) (.*)$/m) || []);
  return { status: result.status, stderr: result.stderr, cacheControl: health[1], health: health[2] ? JSON.parse(health[2]) : null };
}

test('remote database on a developer computer: the backend refuses to start', () => {
  const r = startServer({}, { remote: true });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /Refusing to start: this backend is not running on Render but is configured for a remote \(Production\) database/);
  assert.match(r.stderr, /ALLOW_LOCAL_PRODUCTION_DB=yes/);
  assert.equal(r.health, null, 'never listened');
});

test('remote database on Render starts, and /health reports the deployed commit', () => {
  const sha = '69689a3e3851b0a98697abe1e0828f76d86a4607';
  const r = startServer({ RENDER: 'true', RENDER_GIT_COMMIT: sha }, { remote: true });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.health, { status: 'ok', commit: sha });
  assert.equal(r.cacheControl, 'no-store');
  // Either Render variable is enough, so a deploy can never lock itself out.
  assert.equal(startServer({ RENDER_SERVICE_ID: 'srv-abc123' }, { remote: true }).status, 0);
  assert.equal(startServer({ RENDER: 'True' }, { remote: true }).status, 0);
});

test('explicit override ALLOW_LOCAL_PRODUCTION_DB=yes starts; other values do not', () => {
  assert.equal(startServer({ ALLOW_LOCAL_PRODUCTION_DB: 'yes' }, { remote: true }).status, 0);
  for (const value of ['1', 'true', 'YES ']) {
    assert.notEqual(startServer({ ALLOW_LOCAL_PRODUCTION_DB: value }, { remote: true }).status, 0, value);
  }
});

test('local database starts normally; /health commit is null off Render or when invalid', () => {
  let r = startServer({}, { remote: false });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.health, { status: 'ok', commit: null });
  r = startServer({ RENDER: 'true', RENDER_GIT_COMMIT: 'not-a-sha<script>' }, { remote: false });
  assert.deepEqual(r.health, { status: 'ok', commit: null });
});

test('db.js reports local vs remote from its configuration without connecting', () => {
  const target = env => {
    const r = spawnSync(process.execPath, ['-e', `process.stdout.write(JSON.stringify(require(${JSON.stringify(path.join(root, 'db.js'))}).connectionTarget()))`], {
      cwd: root, encoding: 'utf8', timeout: 30000,
      env: { ...process.env, SUPABASE_DB_URL: '', DATABASE_URL: '', PGHOST: '', SUPABASE_DB_HOST: '', ...env },
    });
    assert.equal(r.status, 0, r.stderr);
    return JSON.parse(r.stdout);
  };
  assert.deepEqual(target({ SUPABASE_DB_URL: 'postgresql://u:p@remote-db.example.com:5432/postgres' }), { remote: true });
  assert.deepEqual(target({ SUPABASE_DB_URL: 'postgresql://u:p@127.0.0.1:54322/postgres' }), { remote: false });
  assert.deepEqual(target({ SUPABASE_DB_URL: 'postgresql://u:p@localhost:5432/postgres' }), { remote: false });
  assert.deepEqual(target({ PGHOST: 'db.example.com' }), { remote: true });
  assert.deepEqual(target({ SUPABASE_DB_URL: '' , DATABASE_URL: '', PGHOST: '', SUPABASE_DB_HOST: ' ' }), { remote: false });
});
