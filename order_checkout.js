const crypto = require('crypto');
const { quoteCheckout, verifyDealerToken, razorpayRequest, verifyCapturedPayment } = require('./checkout_service');

module.exports = function installCheckout(app, pool, secret, findUser) {
  function idempotentOrderId(userId, requestId) {
    const digest = crypto.createHash('sha256').update(`ro-checkout:${userId}:${requestId}`).digest();
    // Format the deterministic digest as a UUID so it fits the existing RO order ID column.
    digest[6] = (digest[6] & 0x0f) | 0x50;
    digest[8] = (digest[8] & 0x3f) | 0x80;
    const hex = digest.subarray(0, 16).toString('hex');
    const uuid = `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
    return `RO-${uuid}`;
  }
  function identity(req) {
    const user = verifyDealerToken(String(req.headers.authorization || '').replace(/^Bearer /, ''), secret);
    if (!user || user.email !== String(req.body.email || '').trim().toLowerCase()) {
      const error = new Error('Please log in again before checkout.'); error.status = 401; throw error;
    }
    return user;
  }
  async function routeOrderToShop(conn, orderId) {
    const [assignmentTable] = await conn.query("SELECT to_regclass('public.shop_order_assignments') IS NOT NULL AS available");
    const hasAssignments = assignmentTable[0]?.available === true;
    if (hasAssignments) {
      const [existing] = await conn.query('SELECT shop_name FROM shop_order_assignments WHERE order_id = ?', [orderId]);
      if (existing[0]?.shop_name) return existing[0].shop_name;
    }
    const [shops] = await conn.query(`SELECT shop_name FROM shop_employees
      WHERE active = TRUE AND shop_name IS NOT NULL AND btrim(shop_name) <> ''
      GROUP BY lower(shop_name), shop_name`);
    const shopNames = [...new Map(shops.map(row => [String(row.shop_name).toLowerCase(), row.shop_name])).values()];
    const defaultShop = String(process.env.SHOP_DEFAULT_NAME || '').trim();
    let assignedShop = null;
    if (defaultShop) {
      assignedShop = shopNames.find(name => name.toLowerCase() === defaultShop.toLowerCase()) || null;
      if (!assignedShop) {
        const error = new Error('Configured default shop does not match an active shop account.'); error.status = 503; throw error;
      }
    } else if (shopNames.length === 1) {
      assignedShop = shopNames[0];
    } else if (shopNames.length > 1) {
      const error = new Error('This order cannot be routed because more than one shop is active. Configure SHOP_DEFAULT_NAME or assign orders in Admin before checkout is enabled.'); error.status = 503; throw error;
    }
    if (shopNames.length > 1 && !hasAssignments) {
      const error = new Error('Shop assignment storage is unavailable for multiple shops.'); error.status = 503; throw error;
    }
    if (assignedShop && hasAssignments) {
      await conn.query(`INSERT INTO shop_order_assignments (order_id, shop_name, assigned_at)
        VALUES (?, ?, CURRENT_TIMESTAMP) ON CONFLICT (order_id) DO NOTHING`, [orderId, assignedShop]);
    }
    return assignedShop;
  }
  const handleError = (res, error) => {
    if (error.status) return res.status(error.status).json({ success: false, error: error.message });
    const connectionErrors = ['ECONNREFUSED', 'ETIMEDOUT', 'ENOTFOUND', 'ECONNRESET', 'PROTOCOL_CONNECTION_LOST', '08000', '08003', '08006', 'ER_CON_COUNT_ERROR'];
    let status = 500, message = 'The order could not be saved to the database. Please contact the store administrator.';
    if (connectionErrors.includes(error.code)) {
      status = 503; message = 'The database is unavailable. Your order has not been saved. Please retry.';
    } else if (['ER_ACCESS_DENIED_ERROR', 'ER_DBACCESS_DENIED_ERROR'].includes(error.code)) {
      status = 503; message = 'The backend cannot authenticate with the database. The store administrator must correct the database credentials.';
    } else if (['ER_BAD_DB_ERROR', 'ER_NO_SUCH_TABLE', 'ER_BAD_FIELD_ERROR'].includes(error.code)) {
      status = 503; message = 'The checkout database schema needs to be updated by the store administrator.';
    }
    // Log only the error identifier, never SQL parameter values or credentials.
    console.error('[CHECKOUT DATABASE ERROR]', error.code || error.name);
    return res.status(status).json({ success: false, error: message, code: error.code || 'ORDER_SAVE_FAILED' });
  };
  app.post('/api/payments/razorpay/order', async (req, res) => {
    try {
      const user = identity(req);
      if (!process.env.RAZORPAY_KEY_ID || !process.env.RAZORPAY_KEY_SECRET) {
        const error = new Error('Razorpay is not configured. Contact the store administrator or select Cash on Delivery.'); error.status = 503; throw error;
      }
      const [products] = await pool.query('SELECT * FROM products');
      const payload = quoteCheckout({ ...req.body, paymentMethod: 'Razorpay' }, products);
      // Reuse an unpaid checkout after a network interruption. Paid sessions are finalized separately.
      const [pending] = await pool.query('SELECT * FROM payment_sessions WHERE user_email = ? AND local_order_id IS NULL ORDER BY created_at DESC LIMIT 1', [user.email]);
      let gateway;
      if (pending.length && pending[0].payload_json === JSON.stringify(payload)) gateway = { id: pending[0].id, amount: Number(pending[0].amount), currency: 'INR' };
      else {
        gateway = await razorpayRequest('orders', 'POST', { amount: Math.round(payload.grandTotal * 100), currency: 'INR', receipt: crypto.randomUUID().replaceAll('-', ''), notes: { email: user.email } });
        await pool.query('INSERT INTO payment_sessions (id, user_email, amount, payload_json) VALUES (?, ?, ?, ?)', [gateway.id, user.email, gateway.amount, JSON.stringify(payload)]);
      }
      res.json({ success: true, order: { id: gateway.id, amount: gateway.amount, currency: gateway.currency, key: process.env.RAZORPAY_KEY_ID } });
    } catch (error) { handleError(res, error); }
  });
  app.post('/api/user/orders/create', async (req, res) => {
    let conn;
    try {
      const identityUser = identity(req);
      const user = await findUser(identityUser.email);
      if (!user) { const error = new Error('Registered account not found.'); error.status = 401; throw error; }
      if (!['Cash on Delivery', 'Razorpay'].includes(req.body.paymentMethod)) { const error = new Error('Select Cash on Delivery or Razorpay.'); error.status = 400; throw error; }
      conn = await pool.getConnection();
      await conn.beginTransaction();
      let payload, session;
      if (req.body.paymentMethod === 'Razorpay') {
        const [sessions] = await conn.query('SELECT * FROM payment_sessions WHERE id = ? AND user_email = ? FOR UPDATE', [req.body.razorpay_order_id, user.email]);
        session = sessions[0];
        if (!session) { const error = new Error('Payment checkout was not found.'); error.status = 400; throw error; }
        if (session.local_order_id) {
          const assignedShop = await routeOrderToShop(conn, session.local_order_id);
          await conn.commit();
          return res.json({ success: true, order: { orderId: session.local_order_id, paymentStatus: 'paid' }, assignedShopName: assignedShop || null });
        }
        await verifyCapturedPayment(session, req.body.razorpay_payment_id, req.body.razorpay_signature);
        payload = JSON.parse(session.payload_json);
      } else {
        const [products] = await conn.query('SELECT * FROM products');
        payload = quoteCheckout(req.body, products);
      }
      const requestId = !session && typeof req.body.checkoutRequestId === 'string'
        ? req.body.checkoutRequestId.trim()
        : '';
      if (requestId && !/^[a-f0-9-]{32,36}$/i.test(requestId)) {
        const error = new Error('Checkout retry identifier is invalid. Please retry checkout.'); error.status = 400; throw error;
      }
      const orderId = session?.local_order_id || (requestId
        ? idempotentOrderId(user.id, requestId)
        : `RO-${crypto.randomUUID()}`);
      if (requestId) {
        // Serialize retries that carry the same key so concurrent requests
        // return the first committed order instead of racing on its PK.
        await conn.query('SELECT pg_advisory_xact_lock(hashtextextended(?, 0))', [orderId]);
        const [existingRows] = await conn.query('SELECT order_id, payment_status FROM orders WHERE order_id = ? AND user_id = ? FOR UPDATE', [orderId, user.id]);
        if (existingRows[0]) {
          const assignedShop = await routeOrderToShop(conn, orderId);
          await conn.commit();
          return res.json({ success: true, idempotent: true, order: { orderId, paymentStatus: existingRows[0].payment_status }, assignedShopName: assignedShop || null });
        }
      }
      const invoiceNumber = `INV-${crypto.randomUUID()}`;
      const delivery = typeof payload.deliveryAddress === 'object' ? JSON.stringify(payload.deliveryAddress) : payload.deliveryAddress;
      if (!delivery) { const error = new Error('Delivery address is required.'); error.status = 400; throw error; }
      const billing = payload.sameAsDelivery !== false ? delivery : JSON.stringify(payload.billingAddress || {});
      const paymentStatus = session ? 'paid' : 'due_on_delivery';
      await conn.query(`INSERT INTO orders (order_id, user_id, user_email, user_name, user_business, subtotal, discount, gst, delivery_fee, grand_total, payment_method, delivery_address, billing_address, company_name, gstin, pan_number, same_as_delivery, delivery_note, status, invoice_number, with_gst, payment_status, razorpay_payment_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [orderId, user.id, user.email, user.name, user.business || '', payload.subtotal, payload.discount, payload.gst, payload.deliveryFee, payload.grandTotal, payload.paymentMethod, delivery, billing, payload.companyName || '', payload.gstin, payload.panNumber || '', payload.sameAsDelivery !== false, payload.deliveryNote || '', 'Processing & Dispatched', invoiceNumber, Boolean(payload.withGst), paymentStatus, session ? req.body.razorpay_payment_id : null]);
      for (const item of payload.items) await conn.query('INSERT INTO order_items (order_id, product_id, product_name, brand, unit_price, quantity, img_src) VALUES (?, ?, ?, ?, ?, ?, ?)', [orderId, item.id, item.name, item.brand || '', item.numericPrice, item.quantity, item.imgSrc]);
      const pointsEarned = Math.floor(payload.grandTotal * .05);
      await conn.query('UPDATE users SET reward_points = reward_points + ? WHERE id = ?', [pointsEarned, user.id]);
      await conn.query('INSERT INTO rewards_history (user_id, order_id, order_amount, points_earned) VALUES (?, ?, ?, ?)', [user.id, orderId, payload.grandTotal, pointsEarned]);
      if (session) await conn.query('UPDATE payment_sessions SET payment_id = ?, local_order_id = ? WHERE id = ?', [req.body.razorpay_payment_id, orderId, session.id]);
      const assignedShop = await routeOrderToShop(conn, orderId);
      await conn.commit();
      const order = { ...payload, orderId, userEmail: user.email, userName: user.name, userBusiness: user.business || '', deliveryAddress: delivery, billingAddress: billing, invoiceNumber, status: 'Processing & Dispatched', paymentStatus, createdAt: new Date().toISOString() };
      res.json({ success: true, order, pointsEarned, assignedShopName: assignedShop || null });
    } catch (error) { if (conn) await conn.rollback().catch(() => {}); handleError(res, error); }
    finally { if (conn) conn.release(); }
  });
};
