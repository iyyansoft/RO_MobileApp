// Reads the password from a local masked prompt over stdin, never command arguments.
const fs = require('node:fs');
const path = require('node:path');
const mysql = require('mysql2/promise');
const dotenv = require('dotenv');
const root = path.resolve(__dirname, '..');
const statusPath = path.join(root, 'build', 'mysql-credential-status.json');
let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', async () => {
  let connection;
  try {
    const { password } = JSON.parse(input);
    input = '';
    if (typeof password !== 'string' || !password) throw Object.assign(Error(), { code: 'PASSWORD_REQUIRED' });
    const envPath = path.join(root, '.env');
    const original = fs.readFileSync(envPath, 'utf8');
    const env = dotenv.parse(original);
    // dotenv supports three literal quote delimiters. Verify exact round-trip before writing.
    const quote = ["'", '"', '`'].find(character => !password.includes(character));
    if (!quote || /[\r\n]/.test(password)) throw Object.assign(Error(), { code: 'PASSWORD_QUOTING_UNSUPPORTED' });
    const encoded = quote + password + quote;
    if (dotenv.parse('DB_PASSWORD=' + encoded).DB_PASSWORD !== password) throw Object.assign(Error(), { code: 'PASSWORD_QUOTING_UNSUPPORTED' });
    connection = await mysql.createConnection({ host: env.DB_HOST || '127.0.0.1', port: 3306, user: env.DB_USER || 'root', password, database: env.DB_NAME || 'ro_wholesale_db', connectTimeout: 5000 });
    const [[verified]] = await connection.query('SELECT CURRENT_USER() AS account, DATABASE() AS database_name, @@port AS port');
    let updated = original;
    for (const [key, value] of Object.entries({DB_PORT:'3306', DB_PASSWORD:encoded})) {
      const pattern = new RegExp('^' + key + '=.*$', 'm');
      updated = pattern.test(updated) ? updated.replace(pattern, () => key + '=' + value) : updated + '\n' + key + '=' + value + '\n';
    }
    if (dotenv.parse(updated).DB_PASSWORD !== password) throw Object.assign(Error(), { code: 'DUPLICATE_PASSWORD_SETTING' });
    // Preserve the existing file and its ACL; no password-bearing backup or log is generated.
    fs.writeFileSync(envPath, updated);
    const result = { configured: true, ...verified };
    fs.writeFileSync(statusPath, JSON.stringify(result));
    process.stdout.write(JSON.stringify(result));
  } catch (error) {
    const result = { configured: false, code: error.code || 'CONFIGURATION_FAILED' };
    fs.writeFileSync(statusPath, JSON.stringify(result));
    process.stdout.write(JSON.stringify(result));
    process.exitCode = 1;
  } finally { if (connection) await connection.end(); }
});
