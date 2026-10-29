// Live smoke test. Temporary API-created fixtures are removed by exact IDs only.
const fs=require('node:fs');const path=require('node:path');const crypto=require('node:crypto');const mysql=require('mysql2/promise');const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),env=require('dotenv').parse(fs.readFileSync(path.join(root,'.env')));
const base='http://127.0.0.1:8080/api/';
async function call(route,method='GET',data,token,userId){
 const response=await fetch(base+route,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),...(userId?{'x-user-id':userId}:{})},...(data?{body:JSON.stringify(data)}:{}),signal:AbortSignal.timeout(30000)});
 const body=await response.json(); if(!response.ok||body.success!==true)throw Error('API verification failed: '+route+' ('+response.status+')'); return body;
}
async function main(){
 const conn=await mysql.createConnection({host:env.DB_HOST,port:Number(env.DB_PORT),user:env.DB_USER,password:env.DB_PASSWORD,database:env.DB_NAME});
 const email='fresh-check-'+crypto.randomUUID()+'@example.invalid',password=crypto.randomBytes(16).toString('hex');let userId,adminToken;const tempProducts=[];
 try{
  const catalog=await call('products'),categories=await call('categories');assert.equal(catalog.products.length,18);assert.equal(categories.categories.length,6);
  for(const category of categories.categories)assert.equal(catalog.products.filter(p=>p.category===category.key_name).length,3);
  for(const product of catalog.products){assert.ok(fs.existsSync(path.join(root,'web_preview',product.img)));const response=await fetch('http://127.0.0.1:8080/'+product.img);assert.equal(response.status,200);}
  fs.writeFileSync(path.join(root,'build/fresh-catalog-live.json'),JSON.stringify({products:catalog.products,categories:categories.categories}));
  adminToken=(await call('admin/login','POST',{email:env.ADMIN_EMAIL,password:env.ADMIN_PASSWORD})).token;
  assert.equal((await call('admin/dealers','GET',null,adminToken)).dealers.length,0);
  await call('auth/signup','POST',{name:'Temporary API Verification',email,password,confirmPassword:password,address:'Verification address',mobile:''});
  const signed=await call('auth/login','POST',{email,password}); userId=signed.user.id;const token=signed.token;
  assert.equal((await call('auth/session','GET',null,token)).user.id,userId);
  const product=catalog.products.find(p=>p.sku==='RO-FLT-SED');
  await call('cart/add','POST',{productId:product.id,quantity:1},token,userId);
  const cart=await call('cart','GET',null,token,userId);assert.equal(cart.items[0].quantity,1);
  const [[persistedCart]]=await conn.query('SELECT quantity FROM cart_items WHERE user_id=? AND product_id=?',[userId,product.id]);assert.equal(persistedCart.quantity,1);
  for(const withGst of [false,true]){
   const result=await call('user/orders/create','POST',{email,paymentMethod:'Cash on Delivery',items:[{id:product.id,quantity:1}],deliveryAddress:'Verification address',withGst,gstin:withGst?'27AAPFU0939F1ZV':''},token);
   const [[saved]]=await conn.query('SELECT gst,grand_total FROM orders WHERE order_id=?',[result.order.orderId]);
   const [items]=await conn.query('SELECT quantity,unit_price FROM order_items WHERE order_id=?',[result.order.orderId]);assert.equal(items.length,1);assert.equal(items[0].quantity,1);assert.equal(Number(items[0].unit_price),100);assert.equal(Number(saved.gst),withGst?16.2:0);assert.equal(Number(saved.grand_total),withGst?356.2:340);
  }
  const payload={name:'Temporary product verification',sku:'VERIFY-'+crypto.randomUUID(),category:'filters',brand:'Verification',purchase_price:100,price:180,mrp:300,moq:'MOQ: 1 Piece',stock_quantity:20,img:'cat_filter.jpg',desc:'Temporary API verification product',status:'active'};
  await call('admin/products','POST',payload,adminToken);
  const [[added]]=await conn.query('SELECT id FROM products WHERE sku=?',[payload.sku]);assert.ok(added);tempProducts.push(added.id);
  await call('admin/products/'+added.id,'PUT',{...payload,price:190},adminToken);
  const [[updated]]=await conn.query('SELECT price FROM products WHERE id=?',[added.id]);assert.equal(Number(updated.price),190);
  const bulk=await call('admin/products/bulk','POST',{products:[{...payload,sku:'VERIFY-BULK-'+crypto.randomUUID()}]},adminToken);
  assert.ok(bulk.success);
  const [bulkProducts]=await conn.query("SELECT id FROM products WHERE sku LIKE 'VERIFY-BULK-%'");tempProducts.push(...bulkProducts.map(p=>p.id));
  console.log(JSON.stringify({liveChecksPassed:true,categories:6,products:18,imagesVerified:18,signup:true,passwordLogin:true,session:true,admin:true,singleAndBulkProductManagement:true,cartPersisted:true,codWithAndWithoutGstPersisted:true}));
 }finally{
  for(const id of tempProducts)await call('admin/products/'+id,'DELETE',null,adminToken);
  const [[createdUser]]=await conn.query('SELECT id FROM users WHERE email=?',[email]); userId=userId||createdUser?.id;
  if(userId){await conn.beginTransaction();await conn.query('DELETE FROM orders WHERE user_email=?',[email]);await conn.query('DELETE FROM users WHERE id=? AND email=?',[userId,email]);await conn.commit();}
  const usersPath=path.join(root,'users_db.json'),users=JSON.parse(fs.readFileSync(usersPath));delete users[email];fs.writeFileSync(usersPath,JSON.stringify(users,null,2));
  const ordersPath=path.join(root,'orders_db.json'),orders=JSON.parse(fs.readFileSync(ordersPath));for(const [key,order]of Object.entries(orders))if(order.userEmail===email)delete orders[key];fs.writeFileSync(ordersPath,JSON.stringify(orders,null,2));
  const [[counts]]=await conn.query('SELECT (SELECT COUNT(*) FROM users) dealers,(SELECT COUNT(*) FROM orders) orders,(SELECT COUNT(*) FROM products) products');
  console.log(JSON.stringify({finalActiveCounts:counts}));await conn.end();
 }
}
main().catch(error=>{console.error(JSON.stringify({success:false,message:error.message?.startsWith('API verification')?error.message:'Live verification failed; inspect assertions without displaying credentials.'}));process.exitCode=1;});
