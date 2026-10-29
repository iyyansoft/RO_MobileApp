require('dotenv').config();

const fs = require('node:fs');
const path = require('node:path');
const { Pool, types } = require('pg');
const parsePgConnectionString = require('pg-connection-string').parse;

// MySQL DATETIME columns were migrated as PostgreSQL timestamp without time
// zone. Interpret those values as UTC to preserve the app's previous UTC pool
// behavior when creating ISO timestamps in API responses.
types.setTypeParser(1114, value => new Date(`${value.replace(' ', 'T')}Z`));

const connectionString = process.env.SUPABASE_DB_URL || process.env.DATABASE_URL;
const hasDiscreteConfig = Boolean(process.env.PGHOST || process.env.SUPABASE_DB_HOST);
const sslCaFile = process.env.SUPABASE_DB_SSL_CA_FILE;
// Render/Linux deployments can supply the public Supabase CA directly as a
// multiline secret, or use a repository-relative certificate path. Never use
// a developer-machine absolute path in the hosted service configuration.
const sslCaInline = process.env.SUPABASE_DB_SSL_CA;
const parsedConnection = connectionString
  ? parsePostgresConnectionString(connectionString)
  : { config: {}, ca: undefined };
const connectionConfig = parsedConnection.config;
const sslCa = resolveSslCa({ inline: sslCaInline, file: sslCaFile, connectionCa: parsedConnection.ca });
// node-postgres reparses `connectionString` after applying other options, which
// can discard a supplied CA. Parse it here, then pass discrete fields only.
const pgPool = new Pool({
  ...connectionConfig,
  ...(hasDiscreteConfig ? {
    host: process.env.PGHOST || process.env.SUPABASE_DB_HOST,
    port: Number(process.env.PGPORT || process.env.SUPABASE_DB_PORT || 5432),
    user: process.env.PGUSER || process.env.SUPABASE_DB_USER,
    password: process.env.PGPASSWORD || process.env.SUPABASE_DB_PASSWORD,
    database: process.env.PGDATABASE || process.env.SUPABASE_DB_NAME || 'postgres'
  } : {}),
  max: Number.parseInt(process.env.DB_CONNECTION_LIMIT || '10', 10),
  connectionTimeoutMillis: Number.parseInt(process.env.DB_CONNECTION_TIMEOUT_MS || '5000', 10),
  idleTimeoutMillis: Number.parseInt(process.env.DB_IDLE_TIMEOUT_MS || '30000', 10),
  // Keep TLS and certificate/hostname verification mandatory. If Supabase
  // requires its project CA, set SUPABASE_DB_SSL_CA to the PEM text or point
  // SUPABASE_DB_SSL_CA_FILE at a repository-relative CA file. Both options keep
  // certificate-chain and hostname verification enabled.
  ssl: {
    rejectUnauthorized: true,
    ...(sslCa ? { ca: sslCa } : {})
  }
});

function parsePostgresConnectionString(value) {
  const url = new URL(value);
  // The pool's explicit TLS options below are authoritative. Normalize any URI
  // sslmode to verified mode while parsing so weak modes cannot override them.
  url.searchParams.set('sslmode', 'verify-full');
  const config = parsePgConnectionString(url.toString());
  const ca = config.ssl?.ca;
  delete config.ssl;
  return { config, ca };
}

function resolveSslCa({ inline, file, connectionCa, platform = process.platform, projectDir = __dirname, fileSystem = fs } = {}) {
  if (inline) return inline.replace(/\\n/g, '\n');
  if (!file) return connectionCa;
  const isWindowsAbsolute = path.win32.isAbsolute(file);
  const isPlatformAbsolute = platform === 'win32' ? isWindowsAbsolute : path.posix.isAbsolute(file);
  if (platform !== 'win32' && isWindowsAbsolute && !path.posix.isAbsolute(file)) {
    throw new Error('SUPABASE_DB_SSL_CA_FILE must be a project-relative path on Linux (for example: certs/supabase-root.crt).');
  }
  const certificatePath = isPlatformAbsolute
    ? file
    : (platform === process.platform
      ? path.resolve(projectDir, file)
      : (platform === 'win32' ? path.win32.resolve(projectDir, file) : path.posix.resolve(projectDir, file)));
  return fileSystem.readFileSync(certificatePath, 'utf8');
}
pgPool.on('error', error => {
  // Avoid leaking connection details or ending the process on an idle socket error.
  console.error('[SUPABASE POSTGRES] Idle connection error:', error.code || error.name);
});

const legacyErrorCodes = {
  '23505': 'ER_DUP_ENTRY',
  '23503': 'ER_NO_REFERENCED_ROW_2',
  '23514': 'ER_CHECK_CONSTRAINT_VIOLATED',
  '22001': 'ER_DATA_TOO_LONG',
  '22P02': 'ER_TRUNCATED_WRONG_VALUE',
  '28P01': 'ER_ACCESS_DENIED_ERROR',
  '42501': 'ER_DBACCESS_DENIED_ERROR',
  '3D000': 'ER_BAD_DB_ERROR',
  '42P01': 'ER_NO_SUCH_TABLE',
  '42703': 'ER_BAD_FIELD_ERROR',
  '53300': 'ER_CON_COUNT_ERROR'
};

function normalizeDatabaseError(error) {
  if (error && legacyErrorCodes[error.code]) {
    error.postgresCode = error.code;
    error.code = legacyErrorCodes[error.postgresCode];
  }
  return error;
}

// Convert positional MySQL placeholders without touching question marks in
// quoted strings, identifiers, or SQL comments. All application values remain
// bound parameters; no user input is interpolated into SQL text.
function toPostgresPlaceholders(sql) {
  let output = '';
  let index = 0;
  let state = 'normal';
  for (let i = 0; i < sql.length; i += 1) {
    const char = sql[i];
    const next = sql[i + 1];
    if (state === 'single') {
      output += char;
      if (char === "'" && next === "'") { output += next; i += 1; }
      else if (char === "'") state = 'normal';
      else if (char === '\\' && next) { output += next; i += 1; }
      continue;
    }
    if (state === 'double') {
      output += char;
      if (char === '"' && next === '"') { output += next; i += 1; }
      else if (char === '"') state = 'normal';
      continue;
    }
    if (state === 'line-comment') {
      output += char;
      if (char === '\n') state = 'normal';
      continue;
    }
    if (state === 'block-comment') {
      output += char;
      if (char === '*' && next === '/') { output += next; i += 1; state = 'normal'; }
      continue;
    }
    if (char === "'") { state = 'single'; output += char; continue; }
    if (char === '"') { state = 'double'; output += char; continue; }
    if (char === '-' && next === '-') { state = 'line-comment'; output += char + next; i += 1; continue; }
    if (char === '/' && next === '*') { state = 'block-comment'; output += char + next; i += 1; continue; }
    const aliasMatch = sql.slice(i).match(/^(AS)(\s+)([A-Za-z_][A-Za-z0-9_]*)\b/i);
    if (aliasMatch && /[A-Z]/.test(aliasMatch[3])) {
      output += `${aliasMatch[1]}${aliasMatch[2]}"${aliasMatch[3]}"`;
      i += aliasMatch[0].length - 1;
      continue;
    }
    if (char === '?') { output += `$${++index}`; continue; }
    output += char;
  }
  return output;
}

function adaptResult(result) {
  if (result.command === 'SELECT' || result.command === 'SHOW') {
    return [result.rows, result.fields];
  }
  const insertedId = result.rows && result.rows[0] && result.rows[0].id;
  return [{
    affectedRows: result.rowCount || 0,
    changedRows: result.rowCount || 0,
    insertId: insertedId == null ? 0 : insertedId,
    rows: result.rows || []
  }, result.fields];
}

async function runQuery(client, sql, values = []) {
  try {
    const result = await client.query(toPostgresPlaceholders(sql), values);
    return adaptResult(result);
  } catch (error) {
    throw normalizeDatabaseError(error);
  }
}

class PostgresConnection {
  constructor(client) { this.client = client; }
  query(sql, values) { return runQuery(this.client, sql, values); }
  async control(statement) {
    try { return await this.client.query(statement); }
    catch (error) { throw normalizeDatabaseError(error); }
  }
  beginTransaction() { return this.control('BEGIN'); }
  commit() { return this.control('COMMIT'); }
  rollback() { return this.control('ROLLBACK'); }
  release() { this.client.release(); }
}

// Keep the existing route modules' pool/connection interface while using the
// PostgreSQL driver and result metadata.
const pool = {
  query: (sql, values) => runQuery(pgPool, sql, values),
  getConnection: async () => {
    try { return new PostgresConnection(await pgPool.connect()); }
    catch (error) { throw normalizeDatabaseError(error); }
  },
  end: () => pgPool.end(),
  raw: pgPool
};

async function testConnection() {
  if (!connectionString && !hasDiscreteConfig) {
    console.error('[SUPABASE POSTGRES] Set SUPABASE_DB_URL (or PGHOST/PGUSER/PGPASSWORD) in the backend environment.');
    return false;
  }
  try {
    await pgPool.query('SELECT 1');
    console.log('[SUPABASE POSTGRES] PostgreSQL connection is ready.');
    return true;
  } catch (error) {
    normalizeDatabaseError(error);
    // Never log a connection string, username, or password.
    console.error('[SUPABASE POSTGRES] Connection failed:', error.code || error.name);
    return false;
  }
}

module.exports = {
  pool,
  testConnection,
  toPostgresPlaceholders,
  adaptResult,
  normalizeDatabaseError,
  parsePostgresConnectionString,
  resolveSslCa
};
