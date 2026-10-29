// Read-only vault credential check. Secret arrives only through stdin.
const mysql = require('mysql2/promise');
let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => raw += chunk);
process.stdin.on('end', async () => {
  let connection;
  try {
    const payload = JSON.parse(raw); raw = '';
    connection = await mysql.createConnection({host:'127.0.0.1',port:3306,user:'root',password:payload.password,connectTimeout:5000});
    const [[account]] = await connection.query('SELECT CURRENT_USER() AS account, @@port AS port');
    const [databases] = await connection.query("SHOW DATABASES LIKE 'ro_wholesale_db'");
    process.stdout.write(JSON.stringify({authenticated:true,...account,appDatabaseExists:databases.length === 1}));
  } catch (error) {
    process.stdout.write(JSON.stringify({authenticated:false,code:error.code||'VERIFICATION_FAILED'}));
  } finally { if (connection) await connection.end(); }
});
