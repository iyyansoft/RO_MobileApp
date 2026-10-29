// One-time, guarded fresh setup. Old databases are never dropped or accessed.
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {execFile}=require('node:child_process');
const {promisify}=require('node:util');
const mysql=require('mysql2/promise');
const dotenv=require('dotenv');
const {categories,products}=require('./sample_catalog.cjs');
const root=path.resolve(__dirname,'..');
const backup=JSON.parse(fs.readFileSync(path.join(root,'build/fresh-reset-backup.json'),'utf8').replace(/^\uFEFF/,''));
const statePath=path.join(root,'build/fresh-ro-state.json');
const run=promisify(execFile);
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function verifyBackup(checkActive=false) {
 if(!backup.verified) throw Error('Verified backup is required');
 const manifest=JSON.parse(fs.readFileSync(path.join(backup.path,'manifest.json'),'utf8').replace(/^\uFEFF/,''));
 for(const record of manifest) {
  if(hash(path.join(backup.path,record.file)).toUpperCase()!==record.sha256) throw Error('Backup verification failed');
  if(checkActive && hash(path.join(root,record.file)).toUpperCase()!==record.sha256) throw Error('Active data changed after backup; create a new verified backup before activation');
 }
}
function save(state){fs.writeFileSync(statePath,JSON.stringify(state));console.log(JSON.stringify(state));}
async function main(){
 verifyBackup();
 const stage=process.argv[2];
 if(stage==='create') {
  if(fs.existsSync(statePath)) throw Error('Fresh setup state already exists; inspect it before continuing');
  const suffix=path.basename(backup.path).replace('fresh-reset-','');
  const container='ro-wholesale-mysql-'+suffix,volume='ro-wholesale-data-'+suffix;
  const envFile=path.join(backup.path,'mysql-bootstrap.env');
  fs.writeFileSync(envFile,`MYSQL_ROOT_PASSWORD=${crypto.randomBytes(32).toString('hex')}\nMYSQL_DATABASE=ro_wholesale_db\nMYSQL_USER=ro_app\nMYSQL_PASSWORD=${crypto.randomBytes(32).toString('hex')}\nMYSQL_INITDB_SKIP_TZINFO=1\n`);
  await run('docker',['run','--detach','--restart','unless-stopped','--name',container,'--label','ro.wholesale=fresh-local-db','--publish','127.0.0.1:3307:3306','--env-file',envFile,'--volume',volume+':/var/lib/mysql','mysql:8.4','--character-set-server=utf8mb4','--collation-server=utf8mb4_unicode_ci']);
  save({stage:'created',container,volume,port:3307,backupPath:backup.path});
  return;
 }
 if(stage!=='activate') throw Error('Expected create or activate stage');
 verifyBackup(true);
 const state=JSON.parse(fs.readFileSync(statePath));
 if(state.stage!=='created') throw Error('Activation is allowed only for the newly created empty instance');
 const secrets=dotenv.parse(fs.readFileSync(path.join(backup.path,'mysql-bootstrap.env')));
 let conn;
 for(let attempt=0;attempt<60;attempt++) {
  try {conn=await mysql.createConnection({host:'127.0.0.1',port:3307,user:'ro_app',password:secrets.MYSQL_PASSWORD,database:'ro_wholesale_db',connectTimeout:2000});break;}
  catch(error){if(attempt===59) throw Object.assign(Error('Fresh MySQL initialization failed'),{code:error.code});await new Promise(resolve=>setTimeout(resolve,1000));}
 }
 try {
  const [existing]=await conn.query('SHOW TABLES');
  if(existing.length) throw Error('Refusing to seed a database that already contains tables');
  const statements=fs.readFileSync(path.join(root,'schema.sql'),'utf8').split(/;\s*$/m).map(s=>s.replace(/^\s*--.*$/gm,'').trim()).filter(s=>s&&!/^CREATE DATABASE|^USE /i.test(s));
  for(const statement of statements) await conn.query(statement);
  await conn.query('ALTER TABLE user_addresses ADD COLUMN gst_number VARCHAR(64) NULL');
  await conn.beginTransaction();
  for(const c of categories) await conn.query('INSERT INTO categories (id,key_name,title,badge_text,icon_color,image_url,display_order) VALUES (?,?,?,?,?,?,?)',[c.id,c.key_name,c.title,c.badge_text,c.icon_color,c.image_url,c.display_order]);
  for(const p of products) await conn.query('INSERT INTO products (id,category_id,category_key,sku,name,brand,purchase_price,price,mrp,moq,badge,rating,img,description,specs_json,features_json,applications,stock_quantity,min_stock,status) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[p.id,p.category_id,p.category,p.sku,p.name,p.brand,p.purchase_price,p.price,p.mrp,p.moq,p.badge,p.rating,p.img,p.desc,JSON.stringify(p.specs),JSON.stringify(p.features),p.applications,p.stock_quantity,p.min_stock,p.status]);
  await conn.commit();
  const [counts]=await conn.query('SELECT category_key,COUNT(*) AS products FROM products GROUP BY category_key');
  if(counts.length!==6||counts.some(c=>c.products!==3)) throw Error('Fresh catalog validation failed');
  // Only these four backed-up active app files are replaced. No original database is deleted.
  fs.writeFileSync(path.join(root,'products_db.json'),JSON.stringify(products,null,2));
  fs.writeFileSync(path.join(root,'categories_db.json'),JSON.stringify(categories,null,2));
  fs.writeFileSync(path.join(root,'users_db.json'),'{}\n');
  fs.writeFileSync(path.join(root,'orders_db.json'),'{}\n');
  const envPath=path.join(root,'.env');let envText=fs.readFileSync(envPath,'utf8');
  for(const [key,value] of Object.entries({DB_HOST:'127.0.0.1',DB_PORT:'3307',DB_USER:'ro_app',DB_PASSWORD:secrets.MYSQL_PASSWORD,DB_NAME:'ro_wholesale_db',SESSION_SECRET:crypto.randomBytes(32).toString('hex'),AUTO_APPLY_SCHEMA:'true'})){
   const pattern=new RegExp('^'+key+'=.*$','m');envText=pattern.test(envText)?envText.replace(pattern,()=>key+'='+value):envText+'\n'+key+'='+value+'\n';
  }
  fs.writeFileSync(envPath,envText);
  save({...state,stage:'active',categories:6,products:18,dealers:0,orders:0});
 }finally{if(conn)await conn.end();}
}
main().catch(error=>{console.error(JSON.stringify({success:false,code:error.code||'SETUP_FAILED',message:error.message?.includes('password')?'Setup failed; secrets hidden.':error.message}));process.exitCode=1;});
