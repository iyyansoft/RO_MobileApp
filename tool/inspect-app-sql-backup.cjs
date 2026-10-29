// Read-only SQL dump inspection. Outputs counts/integrity only, never row data or secrets.
const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');
const filename = process.argv[2] || path.join(__dirname, '..', 'backup_local_mysql_2026.sql');
const source = fs.readFileSync(filename);
const encoding = source[0] === 0xff && source[1] === 0xfe ? 'utf16le' : 'utf8';
const sql = source.toString(encoding).replace(/^\uFEFF/, '');
const tables = new Map();
for (const match of sql.matchAll(/CREATE TABLE `([^`]+)` \(([\s\S]*?)\) ENGINE[^;]*;/g)) {
  tables.set(match[1], { columns: [...match[2].matchAll(/^\s*`([^`]+)`\s/gm)].map(m => m[1]), rows: [] });
}
function splitRows(values) {
  const rows = []; let quote = false, escaped = false, depth = 0, cell = '', row;
  const decode = value => {
    value = value.trim();
    if (value === 'NULL') return null;
    if (value.startsWith("'")) return value.slice(1, -1).replace(/''/g, "'").replace(/\\(.)/gs, (_, c) => ({ n:'\n', r:'\r', t:'\t', '0':'\0' }[c] ?? c));
    return value;
  };
  for (const character of values) {
    if (escaped) { cell += character; escaped = false; continue; }
    if (quote && character === '\\') { cell += character; escaped = true; continue; }
    if (character === "'") { quote = !quote; cell += character; continue; }
    if (!quote && character === '(') { depth++; if (depth === 1) { row=[]; cell=''; continue; } }
    if (!quote && character === ')') { depth--; if (depth === 0) { row.push(decode(cell)); rows.push(row); cell=''; continue; } }
    if (!quote && character === ',' && depth === 1) { row.push(decode(cell)); cell=''; continue; }
    if (depth > 0) cell += character;
  }
  if (quote || depth !== 0) throw Error('Incomplete INSERT statement');
  return rows;
}
for (const match of sql.matchAll(/^INSERT INTO `([^`]+)` VALUES ([\s\S]*?);\s*$/gm)) {
  const table = tables.get(match[1]);
  if (!table) throw Error('INSERT has no matching CREATE TABLE');
  for (const row of splitRows(match[2])) {
    if (row.length !== table.columns.length) throw Error('INSERT column count mismatch in ' + match[1]);
    table.rows.push(Object.fromEntries(table.columns.map((column, index) => [column, row[index]])));
  }
}
const required = ['users','user_addresses','categories','products','orders','order_items','rewards_history','otp_codes','support_tickets','cart_items'];
const rows = table => tables.get(table)?.rows || [];
const orderIds = new Set(rows('orders').map(row => row.order_id));
const userIds = new Set(rows('users').map(row => row.id));
const productIds = new Set(rows('products').map(row => row.id));
const result = {
  file: filename, bytes: source.length, encoding, sha256: crypto.createHash('sha256').update(source).digest('hex'),
  databaseDeclaration: sql.match(/(?:CREATE DATABASE.*?|USE\s+)`([^`]+)`/i)?.[1] || sql.match(/^-- Host:.*Database:\s*(\S+)/m)?.[1] || null,
  tableRowCounts: Object.fromEntries([...tables].map(([name, table]) => [name, table.rows.length])),
  requiredTablesPresent: required.every(name => tables.has(name)),
  orderItemsWithoutOrder: rows('order_items').filter(row => !orderIds.has(row.order_id)).length,
  ordersWithoutDealer: rows('orders').filter(row => row.user_id && !userIds.has(row.user_id)).length,
  orderItemsWithoutProduct: rows('order_items').filter(row => row.product_id && !productIds.has(row.product_id)).length,
  addressesWithoutDealer: rows('user_addresses').filter(row => !userIds.has(row.user_id)).length,
  latestOrder: rows('orders').map(row => row.created_at).sort().at(-1),
  latestDealer: rows('users').map(row => row.created_at).sort().at(-1),
  checkoutSchemaUpdatesRequired: !tables.get('orders')?.columns.includes('with_gst') || !tables.has('payment_sessions'),
};
console.log(JSON.stringify(result, null, 2));
