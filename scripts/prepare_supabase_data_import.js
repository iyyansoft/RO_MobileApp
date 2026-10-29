// Offline MySQL dump converter for the checked-in RO app backup.
// This script uses only local files and never opens a database connection.
// It intentionally reports schema/row metadata only; it never logs row values.

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '..');
const backupPath = path.join(
  root,
  'backup_ro_wholesale_db_20261012_163051_99e252.sql',
);
const schemaPath = path.join(root, 'supabase_migration.sql');
const outputPath = path.join(root, 'supabase_data_import.sql');
const allowReplace = process.argv.includes('--replace');
const expectedCounts = {
  cart_items: 4,
  categories: 6,
  order_items: 7,
  orders: 7,
  otp_codes: 0,
  payment_sessions: 0,
  products: 19,
  rewards_history: 7,
  support_tickets: 0,
  user_addresses: 10,
  users: 9,
};
const importOrder = [
  'users',
  'categories',
  'products',
  'orders',
  'user_addresses',
  'order_items',
  'rewards_history',
  'otp_codes',
  'support_tickets',
  'cart_items',
  'payment_sessions',
];

if (!fs.existsSync(backupPath) || !fs.existsSync(schemaPath)) {
  throw new Error('Required backup or Supabase schema file is missing.');
}
if (fs.existsSync(outputPath) && !allowReplace) {
  throw new Error('Output exists; pass --replace only to rebuild this generated import.');
}

const backupBuffer = fs.readFileSync(backupPath);
let backupText;
try {
  // Buffer.toString('utf8') silently replaces invalid byte sequences with U+FFFD.
  // A strict decode prevents text corruption from being mistaken for a valid import.
  backupText = new TextDecoder('utf-8', { fatal: true }).decode(backupBuffer);
} catch {
  throw new Error('Source backup is not valid UTF-8; conversion stopped without emitting row data.');
}
const schemaText = fs.readFileSync(schemaPath, 'utf8');
const sourceLines = backupText.split(/\r?\n/);
const sourceTables = new Map();

for (let i = 0; i < sourceLines.length; i += 1) {
  const tableMatch = sourceLines[i].match(/^CREATE TABLE `([^`]+)`/);
  if (!tableMatch) continue;
  const columns = [];
  for (i += 1; i < sourceLines.length && !/^\) ENGINE=/.test(sourceLines[i]); i += 1) {
    const columnMatch = sourceLines[i].match(/^\s*`([^`]+)`\s+.+?,?\s*$/);
    if (columnMatch) columns.push(columnMatch[1]);
  }
  sourceTables.set(tableMatch[1], columns);
}

const targetTables = new Map();
const targetTableRegex = /CREATE TABLE IF NOT EXISTS public\.([a-z_]+) \(([\s\S]*?)\n\);/g;
let tableMatch;
while ((tableMatch = targetTableRegex.exec(schemaText))) {
  const columns = new Map();
  for (const line of tableMatch[2].split(/\r?\n/)) {
    const columnMatch = line.match(/^  ([a-z_]+)\s+(.+?)(?:,)?\s*$/);
    if (!columnMatch || ['CONSTRAINT', 'PRIMARY', 'UNIQUE', 'CHECK'].includes(columnMatch[1].toUpperCase())) {
      continue;
    }
    columns.set(columnMatch[1], columnMatch[2].replace(/,\s*$/, ''));
  }
  targetTables.set(tableMatch[1], columns);
}

const tableNames = Object.keys(expectedCounts).sort();
if (sourceTables.size !== 11 || targetTables.size !== 11 ||
    tableNames.some((name) => !sourceTables.has(name) || !targetTables.has(name))) {
  throw new Error('Table definitions do not match between backup and target schema.');
}
for (const table of tableNames) {
  const sourceColumns = sourceTables.get(table);
  const targetColumns = targetTables.get(table);
  const missing = sourceColumns.filter((column) => !targetColumns.has(column));
  const extra = [...targetColumns.keys()].filter((column) => !sourceColumns.includes(column));
  if (missing.length || extra.length) {
    throw new Error(`Column mismatch in ${table}; missing=${missing.join(',')}; target-only=${extra.join(',')}`);
  }
}

function splitTuple(body) {
  const values = [];
  let start = 0;
  let quoted = false;
  for (let i = 0; i < body.length; i += 1) {
    const char = body[i];
    if (quoted && char === '\\') {
      i += 1;
      continue;
    }
    if (char === "'") {
      if (quoted && body[i + 1] === "'") {
        i += 1;
        continue;
      }
      quoted = !quoted;
    } else if (char === ',' && !quoted) {
      values.push(body.slice(start, i).trim());
      start = i + 1;
    }
  }
  if (quoted) throw new Error('Unterminated string literal in source backup.');
  values.push(body.slice(start).trim());
  return values;
}

function decodeMysqlString(token) {
  if (token.length < 2 || token[0] !== "'" || token.at(-1) !== "'") {
    throw new Error('Unsupported MySQL string literal in source backup.');
  }
  let value = '';
  for (let i = 1; i < token.length - 1; i += 1) {
    const char = token[i];
    if (char === '\\') {
      if (++i >= token.length - 1) throw new Error('Invalid trailing escape in source backup.');
      const escaped = token[i];
      const escapes = {
        '0': '\0', b: '\b', t: '\t', n: '\n', r: '\r', f: '\f', v: '\v',
        Z: String.fromCharCode(26),
        '\\': '\\', "'": "'", '"': '"',
      };
      value += Object.prototype.hasOwnProperty.call(escapes, escaped) ? escapes[escaped] : escaped;
    } else if (char === "'" && token[i + 1] === "'") {
      value += "'";
      i += 1;
    } else {
      value += char;
    }
  }
  return value;
}

function parseLiteral(token) {
  if (/^NULL$/i.test(token)) return { kind: 'null', value: null };
  if (token.startsWith("'") && token.endsWith("'")) {
    return { kind: 'string', value: decodeMysqlString(token) };
  }
  if (/^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(token)) {
    return { kind: 'number', value: token };
  }
  throw new Error('Unsupported MySQL value literal; conversion stopped without emitting row data.');
}

function pgString(value) {
  if (value.includes('\0')) {
    throw new Error('Source contains a NUL character that PostgreSQL text cannot store.');
  }
  return "E'" + value
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "''")
    .replace(/\x08/g, '\\b')
    .replace(/\t/g, '\\t')
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/\f/g, '\\f')
    .replace(/\v/g, '\\v')
    .replace(new RegExp(String.fromCharCode(26), 'g'), '\\032') + "'";
}

function render(value, targetType, table, column) {
  if (value.kind === 'null') return 'NULL';
  const type = targetType.toLowerCase();
  if (type.startsWith('boolean')) {
    if (value.kind !== 'number' || !['0', '1'].includes(value.value)) {
      throw new Error(`Unexpected boolean encoding in ${table}.${column}.`);
    }
    return value.value === '1' ? 'TRUE' : 'FALSE';
  }
  if (type.startsWith('json')) {
    if (value.kind !== 'string') throw new Error(`Unexpected JSON encoding in ${table}.${column}.`);
    JSON.parse(value.value);
    return `${pgString(value.value)}::json`;
  }
  if (type.startsWith('extensions.citext')) {
    if (value.kind !== 'string' || [...value.value].length > 191) {
      throw new Error(`Invalid email value for target field ${table}.${column}.`);
    }
    return `${pgString(value.value)}::extensions.citext`;
  }
  const varchar = type.match(/^varchar\((\d+)\)/);
  if (varchar) {
    if (value.kind !== 'string' || [...value.value].length > Number(varchar[1])) {
      throw new Error(`Text value exceeds target width in ${table}.${column}.`);
    }
    return `${pgString(value.value)}::varchar(${varchar[1]})`;
  }
  if (type.startsWith('text')) {
    if (value.kind !== 'string') throw new Error(`Unexpected text encoding in ${table}.${column}.`);
    return `${pgString(value.value)}::text`;
  }
  if (type.startsWith('timestamp')) {
    if (value.kind !== 'string' || !/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{1,6})?$/.test(value.value)) {
      throw new Error(`Unsupported timestamp encoding in ${table}.${column}; no row data emitted.`);
    }
    const [date, time] = value.value.split(' ');
    const [year, month, day] = date.split('-').map(Number);
    const [hour, minute, second] = time.split(':');
    const parsed = new Date(`${date}T${time}Z`);
    if (year < 1 || Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 19) !== `${date}T${time.slice(0, 8)}` ||
        Number(hour) > 23 || Number(minute) > 59 || Number(second.slice(0, 2)) > 59) {
      throw new Error(`Invalid/zero MySQL date in ${table}.${column}; manual conversion is required.`);
    }
    return `${pgString(value.value)}::timestamp without time zone`;
  }
  if (value.kind === 'number') return value.value;
  return pgString(value.value);
}

const rows = Object.fromEntries(tableNames.map((name) => [name, []]));
for (const line of sourceLines) {
  if (!line.startsWith('INSERT INTO `')) continue;
  const insertMatch = line.match(/^INSERT INTO `([^`]+)` VALUES \(([\s\S]*)\);$/);
  if (!insertMatch) throw new Error('Expected one complete row per mysqldump INSERT line.');
  const table = insertMatch[1];
  if (!rows[table]) throw new Error('Unexpected data table in source backup.');
  const columns = sourceTables.get(table);
  const values = splitTuple(insertMatch[2]);
  if (values.length !== columns.length) throw new Error(`Column/value count mismatch in ${table}; row contents withheld.`);
  const targetColumns = targetTables.get(table);
  const rendered = values.map((token, i) => render(parseLiteral(token), targetColumns.get(columns[i]), table, columns[i]));
  rows[table].push(`INSERT INTO public.${table} (${columns.map((column) => `"${column}"`).join(', ')}) VALUES (${rendered.join(', ')});`);
}
for (const table of tableNames) {
  if (rows[table].length !== expectedCounts[table]) {
    throw new Error(`Row-count mismatch for ${table}: expected ${expectedCounts[table]}, parsed ${rows[table].length}.`);
  }
}

const sourceHash = crypto.createHash('sha256').update(backupBuffer).digest('hex').toUpperCase();
const output = [
  '-- DATA-ONLY IMPORT: verified MySQL backup to supabase_migration.sql schema.',
  '-- Source: backup_ro_wholesale_db_20261012_163051_99e252.sql',
  `-- Source SHA-256: ${sourceHash}`,
  '-- Contains personal dealer/order data and password hashes. Restrict access.',
  '-- Run once against a fresh target after supabase_migration.sql; aborts if target tables are non-empty.',
  '-- Import order: users, categories, products, orders, user_addresses, order_items, rewards_history, otp_codes, support_tickets, cart_items, payment_sessions.',
  '-- Explicit identity IDs are preserved; sequences are reset after validation.',
  'BEGIN;',
  'SET LOCAL search_path TO public, extensions;',
  '',
  'DO $target_empty$ BEGIN',
  ...tableNames.map((table) => `  IF EXISTS (SELECT 1 FROM public.${table} LIMIT 1) THEN RAISE EXCEPTION 'Target table public.${table} is not empty; import cancelled.'; END IF;`),
  'END; $target_empty$;',
  '',
];

for (const table of importOrder) {
  if (!rows[table].length) continue;
  output.push(`-- ${table}: ${rows[table].length} rows`, ...rows[table], '');
}
output.push('-- Row-count assertions: mismatch aborts the transaction.', 'DO $row_counts$ BEGIN');
for (const table of tableNames) {
  output.push(`  IF (SELECT COUNT(*) FROM public.${table}) <> ${expectedCounts[table]} THEN RAISE EXCEPTION 'Unexpected imported row count in public.${table}'; END IF;`);
}
output.push('END; $row_counts$;', '', '-- Relationship checks for every foreign key in supabase_migration.sql.', 'DO $foreign_keys$ BEGIN');
output.push("  IF EXISTS (SELECT 1 FROM public.user_addresses a LEFT JOIN public.users u ON u.id=a.user_id WHERE u.id IS NULL) THEN RAISE EXCEPTION 'Orphan user_addresses.user_id'; END IF;");
output.push("  IF EXISTS (SELECT 1 FROM public.products p LEFT JOIN public.categories c ON c.id=p.category_id WHERE p.category_id IS NOT NULL AND c.id IS NULL) THEN RAISE EXCEPTION 'Orphan products.category_id'; END IF;");
output.push("  IF EXISTS (SELECT 1 FROM public.orders o LEFT JOIN public.users u ON u.id=o.user_id WHERE o.user_id IS NOT NULL AND u.id IS NULL) THEN RAISE EXCEPTION 'Orphan orders.user_id'; END IF;");
output.push("  IF EXISTS (SELECT 1 FROM public.order_items i LEFT JOIN public.orders o ON o.order_id=i.order_id WHERE o.order_id IS NULL) THEN RAISE EXCEPTION 'Orphan order_items.order_id'; END IF;");
output.push("  IF EXISTS (SELECT 1 FROM public.rewards_history r LEFT JOIN public.users u ON u.id=r.user_id WHERE u.id IS NULL) THEN RAISE EXCEPTION 'Orphan rewards_history.user_id'; END IF;");
output.push("  IF EXISTS (SELECT 1 FROM public.rewards_history r LEFT JOIN public.orders o ON o.order_id=r.order_id WHERE r.order_id IS NOT NULL AND o.order_id IS NULL) THEN RAISE EXCEPTION 'Orphan rewards_history.order_id'; END IF;");
output.push("  IF EXISTS (SELECT 1 FROM public.support_tickets t LEFT JOIN public.users u ON u.id=t.user_id WHERE t.user_id IS NOT NULL AND u.id IS NULL) THEN RAISE EXCEPTION 'Orphan support_tickets.user_id'; END IF;");
output.push("  IF EXISTS (SELECT 1 FROM public.cart_items c LEFT JOIN public.users u ON u.id=c.user_id WHERE u.id IS NULL) THEN RAISE EXCEPTION 'Orphan cart_items.user_id'; END IF;");
output.push("  IF EXISTS (SELECT 1 FROM public.cart_items c LEFT JOIN public.products p ON p.id=c.product_id WHERE p.id IS NULL) THEN RAISE EXCEPTION 'Orphan cart_items.product_id'; END IF;");
output.push('END; $foreign_keys$;', '', '-- Preserve explicit identity values; next generated IDs will be above MAX(id).');
for (const table of ['order_items', 'rewards_history', 'otp_codes', 'support_tickets', 'cart_items']) {
  output.push(`SELECT setval(pg_get_serial_sequence('public.${table}','id'), COALESCE((SELECT MAX(id) FROM public.${table}),1), EXISTS (SELECT 1 FROM public.${table}));`);
}
output.push('', 'COMMIT;', '');

fs.writeFileSync(outputPath, output.join('\n'), {
  encoding: 'utf8',
  flag: allowReplace ? 'w' : 'wx',
});
console.log(JSON.stringify({
  output: path.basename(outputPath),
  bytes: fs.statSync(outputPath).size,
  sourceSha256: sourceHash,
  rows: expectedCounts,
  totalRows: Object.values(expectedCounts).reduce((sum, count) => sum + count, 0),
  insertStatements: Object.values(rows).reduce((sum, tableRows) => sum + tableRows.length, 0),
}));
