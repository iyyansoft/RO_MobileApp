// Explicit live verification: saves ONE real COD order for the selected existing account/product.
// Usage: node tool/verify-checkout-mysql.cjs registered-email existing-SKU
const fs = require('node:fs');
const mysql = require('mysql2/promise');
const dotenv = require('dotenv');
const {createDealerToken, quoteCheckout, validGstin} = require('../checkout_service');
const env = dotenv.parse(fs.readFileSync(require('node:path').join(__dirname, '..', '.env')));
const [email, sku] = process.argv.slice(2);
async function main() {
  if (!email || !sku) throw Object.assign(Error(), {code:'EXISTING_EMAIL_AND_SKU_REQUIRED'});
  const conn = await mysql.createConnection({host:env.DB_HOST||'127.0.0.1',port:Number(env.DB_PORT||3306),user:env.DB_USER||'root',password:env.DB_PASSWORD||'',database:env.DB_NAME||'ro_wholesale_db',connectTimeout:5000});
  try {
    const [[user]] = await conn.query('SELECT * FROM users WHERE email = ?', [email.trim().toLowerCase()]);
    const [[product]] = await conn.query("SELECT * FROM products WHERE sku = ? AND status = 'active' AND stock_quantity >= 1", [sku]);
    if (!user || user.status === 'rejected') throw Object.assign(Error(), {code:'REGISTERED_ACCOUNT_NOT_AVAILABLE'});
    if (!product) throw Object.assign(Error(), {code:'EXISTING_PRODUCT_NOT_AVAILABLE'});
    const [[address]] = await conn.query('SELECT * FROM user_addresses WHERE user_id = ? ORDER BY is_default DESC, created_at DESC LIMIT 1', [user.id]);
    if (!address?.street && !user.address) throw Object.assign(Error(), {code:'SAVED_DELIVERY_ADDRESS_REQUIRED'});
    const payload = quoteCheckout({email:user.email,items:[{id:product.id,quantity:1}],paymentMethod:'Cash on Delivery',withGst:validGstin(user.gst_number),gstin:user.gst_number||'',companyName:user.business_name||'',sameAsDelivery:true,deliveryAddress: address ? {name:address.full_name||user.name,mobile:address.phone||user.mobile||'',address:address.street,city:address.city,state:address.state,pincode:address.pincode} : user.address}, [product]);
    const token = createDealerToken(user, env.SESSION_SECRET || 'RO_WHOLESALE_SECRET_KEY_2026');
    const response = await fetch(`http://127.0.0.1:${env.PORT||8080}/api/user/orders/create`, {method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify(payload),signal:AbortSignal.timeout(30000)});
    const result = await response.json();
    if (!response.ok || result.success !== true || !result.order?.orderId) throw Object.assign(Error(), {code:result.code||'CHECKOUT_API_FAILED',status:response.status});
    const [[saved]] = await conn.query('SELECT order_id, subtotal, discount, gst, delivery_fee, grand_total, payment_method, with_gst, payment_status FROM orders WHERE order_id = ?', [result.order.orderId]);
    const [items] = await conn.query('SELECT product_id, quantity, unit_price FROM order_items WHERE order_id = ?', [result.order.orderId]);
    if (!saved || items.length !== 1 || String(items[0].product_id) !== String(product.id) || items[0].quantity !== 1 || Number(items[0].unit_price) !== Number(product.price) || Number(saved.grand_total) !== payload.grandTotal) throw Object.assign(Error(), {code:'PERSISTED_ORDER_VERIFICATION_FAILED',orderId:result.order.orderId});
    console.log(JSON.stringify({verified:true,orderId:saved.order_id,itemCount:items.length,quantity:items[0].quantity,subtotal:Number(saved.subtotal),discount:Number(saved.discount),gst:Number(saved.gst),deliveryFee:Number(saved.delivery_fee),grandTotal:Number(saved.grand_total),paymentMethod:saved.payment_method,paymentStatus:saved.payment_status}));
  } finally {await conn.end();}
}
main().catch(error=>{console.error(JSON.stringify({verified:false,code:error.code||'VERIFICATION_FAILED',...(error.status?{status:error.status}:{}),...(error.orderId?{orderId:error.orderId}:{})}));process.exitCode=1;});
