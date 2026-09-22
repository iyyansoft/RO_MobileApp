const fs = require('fs');
const path = require('path');
const mysql = require('d:/RO_Mobile_App/node_modules/mysql2/promise');
require('d:/RO_Mobile_App/node_modules/dotenv').config({ path: 'd:/RO_Mobile_App/.env' });

async function runJsonToMysqlMigration() {
  console.log('================================================================');
  console.log('📦 RO WHOLESALE DEALER APP - JSON TO MYSQL MIGRATION SCRIPT');
  console.log('================================================================\n');

  const dbConfig = {
    host: process.env.DB_HOST || '127.0.0.1',
    port: parseInt(process.env.DB_PORT || '3307', 10),
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'ro_wholesale_db'
  };

  console.log(`Connecting to MySQL DB: ${dbConfig.database} on ${dbConfig.host}:${dbConfig.port}...`);

  let pool;
  try {
    // 1. Ensure database exists
    const rootConn = await mysql.createConnection({
      host: dbConfig.host,
      port: dbConfig.port,
      user: dbConfig.user,
      password: dbConfig.password
    });
    await rootConn.query(`CREATE DATABASE IF NOT EXISTS \`${dbConfig.database}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;`);
    await rootConn.end();

    // 2. Initialize connection pool
    pool = mysql.createPool({
      ...dbConfig,
      waitForConnections: true,
      connectionLimit: 10,
      queueLimit: 0
    });

    console.log('✅ Connected to MySQL Database Pool.');

    // 3. Ensure tables exist by running schema.sql
    const schemaSql = fs.readFileSync('d:/RO_Mobile_App/schema.sql', 'utf8');
    const statements = schemaSql.split(/;\s*$/m).map(s => s.trim()).filter(s => s.length > 0);
    for (const stmt of statements) {
      if (stmt.toLowerCase().startsWith('create database') || stmt.toLowerCase().startsWith('use ')) continue;
      await pool.query(stmt);
    }
    console.log('✅ MySQL schema verified (all 9 tables ready).\n');

  } catch (err) {
    console.error('❌ Failed to connect or initialize MySQL schema:', err.message);
    process.exit(1);
  }

  // Tracking Counts
  const jsonCounts = { users: 0, addresses: 0, products: 0, orders: 0, orderItems: 0, rewards: 0 };
  const mysqlCounts = { users: 0, addresses: 0, products: 0, orders: 0, orderItems: 0, rewards: 0 };
  const migrationErrors = [];

  // ==========================================================================
  // STEP A: MIGRATE CATEGORIES & PRODUCTS CATALOG
  // ==========================================================================
  console.log('--- 1. Migrating Product Categories & Catalog ---');
  try {
    const categoriesData = [
      { id: 'CAT_SYS', key_name: 'systems', title: 'RO Systems', badge_text: '🔥 B2B WHOLESALE', icon_color: '#0F62FE', image_url: 'purifier.jpg', display_order: 1 },
      { id: 'CAT_MEM', key_name: 'membranes', title: 'Membranes', badge_text: '💧 75-4040 GPD', icon_color: '#8B5CF6', image_url: 'membrane.jpg', display_order: 2 },
      { id: 'CAT_FLT', key_name: 'filters', title: 'Filters & Cartridges', badge_text: '🧪 CTO & SEDIMENT', icon_color: '#10B981', image_url: 'cat_filter.jpg', display_order: 3 },
      { id: 'CAT_PMP', key_name: 'pumps', title: 'Booster Pumps', badge_text: '⚡ 100-300 GPD', icon_color: '#D97706', image_url: 'cat_pump.jpg', display_order: 4 },
      { id: 'CAT_SPR', key_name: 'spares', title: 'Spare Parts & Valves', badge_text: '🔧 VALVES & SMPS', icon_color: '#DB2777', image_url: 'cat_spares.jpg', display_order: 5 },
      { id: 'CAT_PIP', key_name: 'pipes', title: 'Pipes & Tubing', badge_text: '🚰 PE TUBING', icon_color: '#0284C7', image_url: 'cat_spares.jpg', display_order: 6 },
      { id: 'CAT_ACC', key_name: 'accessories', title: 'Accessories & Fittings', badge_text: '📦 CONNECTORS', icon_color: '#0D9488', image_url: 'cat_spares.jpg', display_order: 7 }
    ];

    for (const cat of categoriesData) {
      await pool.query(
        `INSERT INTO categories (id, key_name, title, badge_text, icon_color, image_url, display_order)
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE title=VALUES(title), badge_text=VALUES(badge_text), icon_color=VALUES(icon_color), image_url=VALUES(image_url), display_order=VALUES(display_order)`,
        [cat.id, cat.key_name, cat.title, cat.badge_text, cat.icon_color, cat.image_url, cat.display_order]
      );
    }

    // Extract products array from app.js / catalog definition
    const appJsContent = fs.readFileSync('d:/RO_Mobile_App/web_preview/app.js', 'utf8');
    const match = appJsContent.match(/const catalogProducts = (\[[\s\S]*?\]);/);
    let catalogProducts = [];
    if (match && match[1]) {
      try {
        catalogProducts = eval(match[1]);
      } catch (e) {
        console.warn('Notice parsing catalogProducts from app.js:', e.message);
      }
    }

    jsonCounts.products = catalogProducts.length;

    for (const p of catalogProducts) {
      const categoryIdMap = {
        systems: 'CAT_SYS',
        membranes: 'CAT_MEM',
        filters: 'CAT_FLT',
        pumps: 'CAT_PMP',
        spares: 'CAT_SPR',
        pipes: 'CAT_PIP',
        accessories: 'CAT_ACC'
      };
      const catId = categoryIdMap[p.category] || 'CAT_SPR';

      await pool.query(
        `INSERT INTO products 
         (id, category_id, category_key, sku, name, brand, price, mrp, moq, badge, rating, img, description, specs_json, features_json, applications)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE 
         category_id=VALUES(category_id), category_key=VALUES(category_key), name=VALUES(name), brand=VALUES(brand),
         price=VALUES(price), mrp=VALUES(mrp), moq=VALUES(moq), badge=VALUES(badge), rating=VALUES(rating),
         img=VALUES(img), description=VALUES(description), specs_json=VALUES(specs_json), features_json=VALUES(features_json), applications=VALUES(applications)`,
        [
          p.id, catId, p.category, p.sku || p.id, p.name, p.brand,
          p.price, p.mrp, p.moq, p.badge, p.rating, p.img,
          p.desc || '', JSON.stringify(p.specs || {}), JSON.stringify(p.features || []), p.applications || ''
        ]
      );
    }
    console.log(`✅ Migrated ${catalogProducts.length} catalog products into MySQL.`);
  } catch (err) {
    console.error('❌ Error migrating categories/products:', err.message);
    migrationErrors.push({ section: 'Products', error: err.message });
  }

  // ==========================================================================
  // STEP B: MIGRATE USERS & ADDRESSES
  // ==========================================================================
  console.log('\n--- 2. Migrating Users & Addresses ---');
  let usersData = {};
  if (fs.existsSync('d:/RO_Mobile_App/users_db.json')) {
    try {
      usersData = JSON.parse(fs.readFileSync('d:/RO_Mobile_App/users_db.json', 'utf8'));
    } catch (e) {
      console.error('Error reading users_db.json:', e.message);
    }
  }

  const userKeys = Object.keys(usersData);
  jsonCounts.users = userKeys.length;

  for (const emailKey of userKeys) {
    const user = usersData[emailKey];
    const userId = user.id || `DEALER_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const email = (user.email || emailKey).toLowerCase().trim();
    const mobile = user.mobile ? user.mobile.trim() : null;
    const name = user.name || user.owner || 'Dealer User';
    const passwordHash = user.passwordHash || user.password || '';
    const businessName = user.business || user.businessName || null;
    const ownerName = user.owner || user.name || null;
    const address = user.address || null;
    const status = user.status || 'approved';
    const isApproved = user.isApproved !== undefined ? (user.isApproved ? 1 : 0) : 1;
    const rewardPoints = user.rewardPoints || 0;
    const createdAt = user.createdAt ? new Date(user.createdAt) : new Date();

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      // 1. Insert or Update User
      await conn.query(
        `INSERT INTO users (id, email, mobile, name, password_hash, business_name, owner_name, address, status, is_approved, reward_points, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE 
         mobile=VALUES(mobile), name=VALUES(name), password_hash=VALUES(password_hash), business_name=VALUES(business_name),
         owner_name=VALUES(owner_name), address=VALUES(address), status=VALUES(status), is_approved=VALUES(is_approved), reward_points=VALUES(reward_points)`,
        [userId, email, mobile, name, passwordHash, businessName, ownerName, address, status, isApproved, rewardPoints, createdAt]
      );

      // 2. Insert Addresses
      const addresses = user.addresses || [];
      jsonCounts.addresses += addresses.length;

      for (const addr of addresses) {
        const addrId = addr.id || `ADDR_${Date.now()}_${Math.floor(Math.random()*1000)}`;
        const label = addr.label || 'Main Warehouse';
        const addrBus = addr.businessName || businessName;
        const street = addr.street || address || '';
        const city = addr.city || 'Chennai';
        const state = addr.state || 'Tamil Nadu';
        const pincode = addr.pincode || '600098';
        const phone = addr.phone || mobile;
        const isDefault = addr.isDefault ? 1 : 0;

        await conn.query(
          `INSERT INTO user_addresses (id, user_id, label, business_name, street, city, state, pincode, phone, is_default, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON DUPLICATE KEY UPDATE
           label=VALUES(label), business_name=VALUES(business_name), street=VALUES(street), city=VALUES(city),
           state=VALUES(state), pincode=VALUES(pincode), phone=VALUES(phone), is_default=VALUES(is_default)`,
          [addrId, userId, label, addrBus, street, city, state, pincode, phone, isDefault, createdAt]
        );
      }

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      console.error(`❌ Error migrating user ${email}:`, err.message);
      migrationErrors.push({ section: 'Users', record: email, error: err.message });
    } finally {
      conn.release();
    }
  }

  console.log(`✅ Migrated ${userKeys.length} users and nested address records into MySQL.`);

  // ==========================================================================
  // STEP C: MIGRATE ORDERS & ORDER ITEMS
  // ==========================================================================
  console.log('\n--- 3. Migrating Orders & Line Items ---');
  let ordersData = {};
  if (fs.existsSync('d:/RO_Mobile_App/orders_db.json')) {
    try {
      ordersData = JSON.parse(fs.readFileSync('d:/RO_Mobile_App/orders_db.json', 'utf8'));
    } catch (e) {
      console.error('Error reading orders_db.json:', e.message);
    }
  }

  const orderKeys = Object.keys(ordersData);
  jsonCounts.orders = orderKeys.length;

  for (const orderKey of orderKeys) {
    const order = ordersData[orderKey];
    const orderId = order.orderId || orderKey;
    const userEmail = (order.userEmail || '').toLowerCase().trim();
    const userName = order.userName || '';
    const userBusiness = order.userBusiness || '';
    const subtotal = order.subtotal || 0;
    const discount = order.discount || 0;
    const gst = order.gst || 0;
    const deliveryFee = order.deliveryFee || 0;
    const grandTotal = order.grandTotal || 0;
    const paymentMethod = order.paymentMethod || 'UPI Direct QR Transfer';
    const deliveryAddress = order.deliveryAddress || '';
    const deliveryNote = order.deliveryNote || '';
    const status = order.status || 'Processing & Dispatched';
    const invoiceNumber = order.invoiceNumber || `INV-2026-${Math.floor(Math.random()*9000+1000)}`;
    const createdAt = order.createdAt ? new Date(order.createdAt) : new Date();

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      // Lookup matching user_id in users table
      const [userRows] = await conn.query(`SELECT id FROM users WHERE email = ?`, [userEmail]);
      const userId = userRows.length > 0 ? userRows[0].id : null;

      // 1. Insert or Update Order Header
      await conn.query(
        `INSERT INTO orders 
         (order_id, user_id, user_email, user_name, user_business, subtotal, discount, gst, delivery_fee, grand_total, payment_method, delivery_address, delivery_note, status, invoice_number, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
         user_id=VALUES(user_id), user_name=VALUES(user_name), user_business=VALUES(user_business), subtotal=VALUES(subtotal),
         discount=VALUES(discount), gst=VALUES(gst), delivery_fee=VALUES(delivery_fee), grand_total=VALUES(grand_total),
         payment_method=VALUES(payment_method), delivery_address=VALUES(delivery_address), delivery_note=VALUES(delivery_note),
         status=VALUES(status), invoice_number=VALUES(invoice_number)`,
        [orderId, userId, userEmail, userName, userBusiness, subtotal, discount, gst, deliveryFee, grandTotal, paymentMethod, deliveryAddress, deliveryNote, status, invoiceNumber, createdAt]
      );

      // 2. Insert Order Items
      const items = order.items || [];
      jsonCounts.orderItems += items.length;

      // Clear existing items for re-run safety
      await conn.query(`DELETE FROM order_items WHERE order_id = ?`, [orderId]);

      for (const item of items) {
        const prodId = item.id || item.sku || null;
        const prodName = item.name || 'RO Wholesale Product';
        const brand = item.brand || 'RO Wholesale';
        const unitPrice = item.numericPrice || parseFloat((item.price || '0').toString().replace(/[^\d.]/g, '')) || 0;
        const quantity = item.quantity || 1;
        const moq = item.moq || '';
        const imgSrc = item.imgSrc || item.img || '';
        const sku = item.sku || item.id || '';

        await conn.query(
          `INSERT INTO order_items (order_id, product_id, product_name, brand, unit_price, quantity, moq, img_src, sku)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [orderId, prodId, prodName, brand, unitPrice, quantity, moq, imgSrc, sku]
        );
      }

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      console.error(`❌ Error migrating order ${orderId}:`, err.message);
      migrationErrors.push({ section: 'Orders', record: orderId, error: err.message });
    } finally {
      conn.release();
    }
  }

  console.log(`✅ Migrated ${orderKeys.length} orders and line items into MySQL.`);

  // ==========================================================================
  // STEP D: MIGRATE REWARDS HISTORY (AFTER ORDERS NOW EXIST)
  // ==========================================================================
  console.log('\n--- 4. Migrating Rewards History ---');
  for (const emailKey of userKeys) {
    const user = usersData[emailKey];
    const userEmail = (user.email || emailKey).toLowerCase().trim();
    const rewardsHistory = user.rewardsHistory || [];
    jsonCounts.rewards += rewardsHistory.length;

    if (rewardsHistory.length === 0) continue;

    const [uRows] = await pool.query(`SELECT id FROM users WHERE email = ?`, [userEmail]);
    if (uRows.length === 0) continue;
    const userId = uRows[0].id;

    for (const r of rewardsHistory) {
      const rawOrderId = r.orderId || null;
      let validOrderId = null;
      if (rawOrderId) {
        const [oRows] = await pool.query(`SELECT order_id FROM orders WHERE order_id = ?`, [rawOrderId]);
        if (oRows.length > 0) {
          validOrderId = oRows[0].order_id;
        }
      }

      const orderAmount = r.orderAmount || 0;
      const pointsEarned = r.pointsEarned || 0;
      const date = r.date ? new Date(r.date) : new Date();

      const [existing] = await pool.query(
        `SELECT id FROM rewards_history WHERE user_id = ? AND (order_id = ? OR (order_id IS NULL AND ? IS NULL)) AND points_earned = ?`,
        [userId, validOrderId, validOrderId, pointsEarned]
      );
      if (existing.length === 0) {
        await pool.query(
          `INSERT INTO rewards_history (user_id, order_id, order_amount, points_earned, created_at)
           VALUES (?, ?, ?, ?, ?)`,
          [userId, validOrderId, orderAmount, pointsEarned, date]
        );
      }
    }
  }
  console.log('✅ Migrated rewards history into MySQL.');

  // ==========================================================================
  // STEP E: FINAL VERIFICATION & RECORD COUNTS REPORT
  // ==========================================================================
  console.log('\n================================================================');
  console.log('📊 MIGRATION VERIFICATION REPORT (JSON vs MYSQL)');
  console.log('================================================================');

  try {
    const [[{ uCount }]] = await pool.query('SELECT COUNT(*) as uCount FROM users');
    const [[{ aCount }]] = await pool.query('SELECT COUNT(*) as aCount FROM user_addresses');
    const [[{ pCount }]] = await pool.query('SELECT COUNT(*) as pCount FROM products');
    const [[{ oCount }]] = await pool.query('SELECT COUNT(*) as oCount FROM orders');
    const [[{ iCount }]] = await pool.query('SELECT COUNT(*) as iCount FROM order_items');
    const [[{ rCount }]] = await pool.query('SELECT COUNT(*) as rCount FROM rewards_history');

    mysqlCounts.users = uCount;
    mysqlCounts.addresses = aCount;
    mysqlCounts.products = pCount;
    mysqlCounts.orders = oCount;
    mysqlCounts.orderItems = iCount;
    mysqlCounts.rewards = rCount;

    console.log(`Users:        JSON = ${jsonCounts.users} | MySQL = ${mysqlCounts.users} | Match: ${jsonCounts.users === mysqlCounts.users ? '✅ MATCH' : '⚠️ DIFFERENCE'}`);
    console.log(`Addresses:    JSON = ${jsonCounts.addresses} | MySQL = ${mysqlCounts.addresses} | Match: ${jsonCounts.addresses === mysqlCounts.addresses ? '✅ MATCH' : '⚠️ DIFFERENCE'}`);
    console.log(`Products:     JSON = ${jsonCounts.products} | MySQL = ${mysqlCounts.products} | Match: ${jsonCounts.products === mysqlCounts.products ? '✅ MATCH' : '⚠️ DIFFERENCE'}`);
    console.log(`Orders:       JSON = ${jsonCounts.orders} | MySQL = ${mysqlCounts.orders} | Match: ${jsonCounts.orders === mysqlCounts.orders ? '✅ MATCH' : '⚠️ DIFFERENCE'}`);
    console.log(`Order Items:  JSON = ${jsonCounts.orderItems} | MySQL = ${mysqlCounts.orderItems} | Match: ${jsonCounts.orderItems === mysqlCounts.orderItems ? '✅ MATCH' : '⚠️ DIFFERENCE'}`);
    console.log(`Rewards Logs: JSON = ${jsonCounts.rewards} | MySQL = ${mysqlCounts.rewards} | Match: ${jsonCounts.rewards === mysqlCounts.rewards ? '✅ MATCH' : '⚠️ DIFFERENCE'}`);

    if (migrationErrors.length === 0) {
      console.log('\n🎉 ALL DATA MIGRATED WITH 100% SUCCESS AND ZERO ERRORS!');
    } else {
      console.log(`\n⚠️ MIGRATION COMPLETED WITH ${migrationErrors.length} ERRORS:`);
      console.log(JSON.stringify(migrationErrors, null, 2));
    }
  } catch (err) {
    console.error('Error fetching MySQL counts:', err.message);
  }

  process.exit(0);
}

runJsonToMysqlMigration();
