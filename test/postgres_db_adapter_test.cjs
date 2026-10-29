const { test } = require('node:test');
const assert = require('node:assert/strict');
const { types } = require('pg');
const { pool, toPostgresPlaceholders, adaptResult, normalizeDatabaseError, parsePostgresConnectionString, resolveSslCa } = require('../db');

test('Supabase PostgreSQL pool always requires verified TLS', () => {
  assert.equal(pool.raw.options.ssl.rejectUnauthorized, true);
  assert.equal(pool.raw.options.ssl.checkServerIdentity, undefined);
});

test('connection URL SSL modes cannot replace explicit verified TLS configuration', () => {
  const parsed = parsePostgresConnectionString('postgresql://user:pass@pooler.example.com:5432/postgres?sslmode=disable');
  assert.equal(parsed.config.ssl, undefined);
  assert.equal(parsed.config.host, 'pooler.example.com');
  assert.equal(parsed.config.port, '5432');
  assert.equal(parsed.config.database, 'postgres');
});

test('inline CA values support escaped newlines for hosted environment variables', () => {
  assert.equal(resolveSslCa({ inline: '-----BEGIN CERTIFICATE-----\\npublic-ca\\n-----END CERTIFICATE-----' }),
    '-----BEGIN CERTIFICATE-----\npublic-ca\n-----END CERTIFICATE-----');
});

test('relative CA file paths resolve from the application directory', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const caPath = path.join(__dirname, '..', 'certs', 'supabase-root.crt');
  assert.ok(fs.existsSync(caPath), 'the repository Supabase CA certificate should be present');
  assert.equal(resolveSslCa({ file: 'certs/supabase-root.crt' }), fs.readFileSync(caPath, 'utf8'));
});

test('SQL binds positional values with PostgreSQL placeholders while preserving quoted question marks', () => {
  const sql = "SELECT ?, '?' AS marker, \"?\" AS \"odd?alias\" -- ? ignored\nWHERE id = ? /* ? ignored */";
  assert.equal(
    toPostgresPlaceholders(sql),
    "SELECT $1, '?' AS marker, \"?\" AS \"odd?alias\" -- ? ignored\nWHERE id = $2 /* ? ignored */"
  );
});

test('camelCase SQL aliases remain camelCase in PostgreSQL query results', () => {
  assert.equal(toPostgresPlaceholders('SELECT COUNT(*) AS totalUsers FROM users'), 'SELECT COUNT(*) AS "totalUsers" FROM users');
  assert.equal(toPostgresPlaceholders('SELECT id AS user_id FROM users'), 'SELECT id AS user_id FROM users');
  assert.equal(toPostgresPlaceholders("SELECT 'AS totalUsers ?' AS note"), "SELECT 'AS totalUsers ?' AS note");
});

test('PostgreSQL SELECT rows retain the existing route-module tuple interface', () => {
  const rows = [{ id: 'dealer' }];
  const fields = [{ name: 'id' }];
  assert.deepEqual(adaptResult({ command: 'SELECT', rows, fields, rowCount: 1 }), [rows, fields]);
});

test('PostgreSQL mutation metadata preserves affectedRows and generated insertId', () => {
  const fields = [{ name: 'id' }];
  assert.deepEqual(adaptResult({ command: 'INSERT', rows: [{ id: '41' }], fields, rowCount: 1 }), [
    { affectedRows: 1, changedRows: 1, insertId: '41', rows: [{ id: '41' }] }, fields
  ]);
  assert.equal(adaptResult({ command: 'DELETE', rows: [], fields: [], rowCount: 2 })[0].affectedRows, 2);
});

test('PostgreSQL constraint and schema errors map to existing API error categories', () => {
  const duplicate = normalizeDatabaseError(Object.assign(new Error('duplicate'), { code: '23505' }));
  assert.equal(duplicate.code, 'ER_DUP_ENTRY');
  assert.equal(duplicate.postgresCode, '23505');
  const missingTable = normalizeDatabaseError(Object.assign(new Error('missing'), { code: '42P01' }));
  assert.equal(missingTable.code, 'ER_NO_SUCH_TABLE');
});

test('timestamp without time zone values are interpreted as UTC for API serialization', () => {
  const parsed = types.getTypeParser(1114)('2026-10-12 10:30:00');
  assert.equal(parsed.toISOString(), '2026-10-12T10:30:00.000Z');
});
