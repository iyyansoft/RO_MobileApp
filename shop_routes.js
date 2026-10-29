const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const { signEmployeeToken, verifyEmployeeToken, allocateDeliveryValues } = require('./shop_service');

module.exports = function installShopRoutes(app, pool, secret, requireAdminAuth) {
  const failedEmployeeLogins = new Map();
  async function hasDeliveryConfirmationColumn(queryable) {
    const [rows] = await queryable.query(`SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'shop_delivery_items'
        AND column_name = 'delivery_confirmed'
    ) AS available`);
    return rows[0]?.available === true;
  }
  function deliveryConfirmedExpression(alias, hasColumn) {
    return hasColumn
      ? `COALESCE(${alias}.delivery_confirmed, FALSE)`
      // Older Shop App databases stored the employee confirmation in `delivered`.
      : `COALESCE(${alias}.delivered, FALSE)`;
  }
  async function requireEmployee(req, res, next) {
    const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    const identity = verifyEmployeeToken(token, secret);
    if (!identity) return res.status(401).json({ success: false, error: 'Employee session expired. Please sign in again.' });
    try {
      const [rows] = await pool.query('SELECT active, shop_name, full_name, employee_id FROM shop_employees WHERE id = ? LIMIT 1', [identity.sub]);
      if (!rows[0] || rows[0].active !== true) return res.status(401).json({ success: false, error: 'Employee account is inactive.' });
      req.shopEmployee = { ...identity, shopName: rows[0].shop_name || '', name: rows[0].full_name, employeeId: rows[0].employee_id };
      return next();
    } catch (error) {
      console.error('[SHOP AUTHORIZATION ERROR]', error.code || error.name);
      return res.status(503).json({ success: false, error: 'Employee authorization is temporarily unavailable.' });
    }
  }

  app.post('/api/shop/auth/login', async (req, res) => {
    try {
      const employeeId = String(req.body.loginId || req.body.employeeId || '').trim().toUpperCase();
      const password = String(req.body.password || '');
      if (!employeeId || !password) return res.status(400).json({ success: false, error: 'Enter your Login ID and password.' });
      if (!/^[A-Z0-9][A-Z0-9._-]{2,31}$/.test(employeeId)) return res.status(400).json({ success: false, error: 'Login ID must be 3–32 characters using letters, numbers, dot, underscore, or hyphen.' });
      const attemptKey = `${req.ip || req.socket.remoteAddress}:${employeeId}`;
      const previousAttempt = failedEmployeeLogins.get(attemptKey);
      if (previousAttempt && previousAttempt.lockedUntil > Date.now()) {
        return res.status(429).json({ success: false, error: 'Too many sign-in attempts. Try again in 15 minutes.' });
      }
      const [rows] = await pool.query('SELECT id, employee_id, shop_name, full_name, password_hash, active FROM shop_employees WHERE employee_id = ? LIMIT 1', [employeeId]);
      const employee = rows[0];
      if (!employee || employee.active !== true || !(await bcrypt.compare(password, employee.password_hash))) {
        const current = previousAttempt && previousAttempt.windowStarted > Date.now() - 15 * 60 * 1000
          ? previousAttempt
          : { failures: 0, windowStarted: Date.now(), lockedUntil: 0 };
        current.failures++;
        if (current.failures >= 5) current.lockedUntil = Date.now() + 15 * 60 * 1000;
        failedEmployeeLogins.set(attemptKey, current);
        return res.status(401).json({ success: false, error: 'Invalid Login ID or password.' });
      }
      failedEmployeeLogins.delete(attemptKey);
      return res.json({ success: true, token: signEmployeeToken(employee, secret), employee: { id: employee.id, employeeId: employee.employee_id, loginId: employee.employee_id, shopName: employee.shop_name || '', name: employee.full_name, role: 'shop_employee' } });
    } catch (error) {
      console.error('[SHOP AUTH ERROR]', error.code || error.name);
      return res.status(503).json({ success: false, error: 'Employee sign in is temporarily unavailable.' });
    }
  });

  app.get('/api/shop/auth/session', requireEmployee, async (req, res) => {
    try {
      const [rows] = await pool.query('SELECT id, employee_id, shop_name, full_name, active FROM shop_employees WHERE id = ? LIMIT 1', [req.shopEmployee.sub]);
      if (!rows[0] || rows[0].active !== true) return res.status(401).json({ success: false, error: 'Employee account is inactive.' });
      const employee = rows[0];
      return res.json({ success: true, employee: { id: employee.id, employeeId: employee.employee_id, loginId: employee.employee_id, shopName: employee.shop_name || '', name: employee.full_name, role: 'shop_employee' } });
    } catch (error) {
      console.error('[SHOP SESSION ERROR]', error.code || error.name);
      return res.status(503).json({ success: false, error: 'Employee session could not be verified.' });
    }
  });

  app.get('/api/shop/dashboard', requireEmployee, async (req, res) => {
    try {
      const [rows] = await pool.query(`
        SELECT
          COALESCE(SUM(CASE WHEN o.created_at::date = CURRENT_DATE THEN d.delivered_amount ELSE 0 END), 0) AS today_sales,
          COALESCE(SUM(CASE WHEN date_trunc('month', o.created_at) = date_trunc('month', CURRENT_TIMESTAMP) THEN d.delivered_amount ELSE 0 END), 0) AS monthly_sales,
          COUNT(DISTINCT CASE WHEN o.created_at::date = CURRENT_DATE THEN o.order_id END) AS today_orders,
          (SELECT COUNT(*) FROM shop_product_enquiries WHERE status = 'new') AS new_enquiries
        FROM orders o
        JOIN order_items oi ON oi.order_id = o.order_id
        LEFT JOIN shop_delivery_items d ON d.order_item_id = oi.id`);
      const item = rows[0] || {};
      return res.json({ success: true, shop: { name: req.shopEmployee.shopName, employeeName: req.shopEmployee.name, loginId: req.shopEmployee.employeeId }, metrics: { todaySales: Number(item.today_sales || 0), monthlySales: Number(item.monthly_sales || 0), todayOrders: Number(item.today_orders || 0), newEnquiries: Number(item.new_enquiries || 0) } });
    } catch (error) {
      console.error('[SHOP DASHBOARD ERROR]', error.code || error.name);
      return res.status(503).json({ success: false, error: 'Shop dashboard data is unavailable.' });
    }
  });

  app.get('/api/shop/orders', requireEmployee, async (req, res) => {
    try {
      const search = `%${String(req.query.search || '').trim()}%`;
      const status = String(req.query.status || '').trim().toLowerCase();
      const from = String(req.query.from || '').trim();
      const to = String(req.query.to || '').trim();
      if ((from && !/^\d{4}-\d{2}-\d{2}$/.test(from)) || (to && !/^\d{4}-\d{2}-\d{2}$/.test(to)) || (from && to && from > to)) {
        return res.status(400).json({ success: false, error: 'Use a valid order date range in YYYY-MM-DD format.' });
      }
      const [assignmentMetadata] = await pool.query("SELECT to_regclass('public.shop_order_assignments') IS NOT NULL AS available");
      const assignmentAvailable = assignmentMetadata[0]?.available === true;
      const hasConfirmationColumn = await hasDeliveryConfirmationColumn(pool);
      const shopName = String(req.shopEmployee.shopName || '');
      let assignmentFilter = '';
      const queryValues = [search, status, from, to];
      const [shopCountRows] = await pool.query(`SELECT COUNT(DISTINCT lower(shop_name))::int AS shop_count,
          COUNT(DISTINCT lower(shop_name)) FILTER (WHERE lower(shop_name) = lower(?))::int AS matching_shop_count
        FROM shop_employees WHERE active = TRUE AND shop_name IS NOT NULL AND btrim(shop_name) <> ''`, [shopName]);
      const onlyEmployeeShop = Number(shopCountRows[0]?.shop_count || 0) === 1
        && Number(shopCountRows[0]?.matching_shop_count || 0) === 1;
      if (assignmentAvailable) {
        if (onlyEmployeeShop) {
          assignmentFilter = `AND (
            EXISTS (SELECT 1 FROM shop_order_assignments soa WHERE soa.order_id = o.order_id AND lower(soa.shop_name) = lower(?))
            OR (NOT EXISTS (SELECT 1 FROM shop_order_assignments soa WHERE soa.order_id = o.order_id)
              AND EXISTS (SELECT 1 FROM shop_employees se WHERE se.active = TRUE AND lower(se.shop_name) = lower(?)))
          )`;
          queryValues.push(shopName, shopName);
        } else {
          assignmentFilter = 'AND EXISTS (SELECT 1 FROM shop_order_assignments soa WHERE soa.order_id = o.order_id AND lower(soa.shop_name) = lower(?))';
          queryValues.push(shopName);
        }
      } else {
        if (!onlyEmployeeShop) {
          return res.status(503).json({ success: false, error: 'Shop assignment is not configured for multiple shops. Ask an administrator to assign orders.' });
        }
      }
      const confirmedD = deliveryConfirmedExpression('d', hasConfirmationColumn);
      const confirmedSd = deliveryConfirmedExpression('sd', hasConfirmationColumn);
      const [orders] = await pool.query(`
        SELECT o.order_id, o.user_name, o.user_business, o.user_email, o.created_at, o.payment_method, o.payment_status, o.grand_total, o.subtotal, o.discount, o.gst, o.status,
          COUNT(oi.id)::int AS item_count,
          COALESCE(SUM(oi.unit_price * oi.quantity), 0) AS item_total,
          COUNT(d.order_item_id) FILTER (WHERE ${confirmedD} = TRUE)::int AS delivered_count
        FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
        LEFT JOIN shop_delivery_items d ON d.order_item_id = oi.id
        WHERE ($1 = '%%' OR o.order_id ILIKE $1 OR o.user_name ILIKE $1 OR COALESCE(o.user_business, '') ILIKE $1 OR EXISTS (SELECT 1 FROM order_items si WHERE si.order_id=o.order_id AND si.product_name ILIKE $1))
          AND ($2 = '' OR lower(o.status) = $2
            OR ($2 = 'delivered' AND NOT EXISTS (SELECT 1 FROM order_items si LEFT JOIN shop_delivery_items sd ON sd.order_item_id = si.id WHERE si.order_id = o.order_id AND (NOT ${confirmedSd} OR COALESCE(sd.delivered_quantity, 0) < si.quantity)))
            OR ($2 = 'partially delivered' AND (SELECT COALESCE(SUM(CASE WHEN ${confirmedSd} THEN sd.delivered_quantity ELSE 0 END), 0) FROM order_items si LEFT JOIN shop_delivery_items sd ON sd.order_item_id = si.id WHERE si.order_id = o.order_id) > 0 AND (SELECT COALESCE(SUM(CASE WHEN ${confirmedSd} THEN sd.delivered_quantity ELSE 0 END), 0) FROM order_items si LEFT JOIN shop_delivery_items sd ON sd.order_item_id = si.id WHERE si.order_id = o.order_id) < (SELECT COALESCE(SUM(si.quantity), 0) FROM order_items si WHERE si.order_id = o.order_id))
            OR ($2 = 'pending' AND NOT EXISTS (SELECT 1 FROM shop_delivery_items sd WHERE sd.order_id = o.order_id AND ${confirmedSd} = TRUE AND sd.delivered_quantity > 0))
            OR ($2 = 'undelivered' AND EXISTS (SELECT 1 FROM shop_delivery_items sd WHERE sd.order_id = o.order_id) AND NOT EXISTS (SELECT 1 FROM shop_delivery_items sd WHERE sd.order_id = o.order_id AND ${confirmedSd} = TRUE AND sd.delivered_quantity > 0)))
          AND ($3 = '' OR o.created_at::date >= $3::date)
          AND ($4 = '' OR o.created_at::date <= $4::date)
          ${assignmentFilter}
        GROUP BY o.order_id ORDER BY o.created_at DESC LIMIT 500`, queryValues);
      const result = [];
      const confirmedItem = deliveryConfirmedExpression('d', hasConfirmationColumn);
      for (const order of orders) {
        const [items] = await pool.query(`SELECT oi.id::text AS id, oi.product_id, oi.product_name, oi.brand, oi.sku, oi.unit_price, oi.quantity, oi.img_src,
            COALESCE(d.delivered, FALSE) AS delivered, ${confirmedItem} AS delivery_confirmed,
            COALESCE(d.delivered_quantity, CASE WHEN d.delivered THEN oi.quantity ELSE 0 END) AS delivered_quantity,
            COALESCE(d.undelivered_quantity, oi.quantity - CASE WHEN d.delivered THEN oi.quantity ELSE 0 END) AS undelivered_quantity, d.delivered_at,
            COALESCE(d.refund_amount, 0) AS refund_amount, COALESCE(d.delivered_amount, 0) AS delivered_amount
          FROM order_items oi JOIN orders o ON o.order_id = oi.order_id LEFT JOIN shop_delivery_items d ON d.order_item_id = oi.id WHERE oi.order_id = ? ORDER BY oi.id`, [order.order_id]);
        const allocated = allocateDeliveryValues(items, order).allocated;
        const orderedQuantity = items.reduce((sum, item) => sum + Number(item.quantity || 0), 0);
        const confirmedQuantity = items.reduce((sum, item) => sum + (item.delivery_confirmed === true ? Number(item.delivered_quantity || 0) : 0), 0);
        const deliveryStatus = order.status === 'Cancelled' ? 'Cancelled'
          : confirmedQuantity <= 0 ? 'Pending'
            : confirmedQuantity >= orderedQuantity ? 'Delivered' : 'Partially Delivered';
        result.push({ orderId: order.order_id, vendorName: order.user_name, companyName: order.user_business || '', email: order.user_email, orderDate: order.created_at, paymentMethod: order.payment_method, paymentStatus: order.payment_status, total: Number(order.grand_total || 0), value: Number(order.item_total || 0), status: deliveryStatus, items: items.map((item, index) => ({ id: item.id, productId: item.product_id, name: item.product_name, brand: item.brand || '', sku: item.sku || '', unitPrice: Number(item.unit_price), quantity: Number(item.quantity), image: item.img_src || '', delivered: item.delivery_confirmed === true, deliveryConfirmed: item.delivery_confirmed === true, deliveredQuantity: Number(item.delivered_quantity || 0), undeliveredQuantity: Number(item.quantity) - (item.delivery_confirmed === true ? Number(item.delivered_quantity || 0) : 0), deliveredAt: item.delivered_at, lineValue: allocated[index].allocatedValue, refundAmount: allocated[index].refundValue, deliveredAmount: allocated[index].deliveredValue })) });
      }
      return res.json({ success: true, orders: result });
    } catch (error) {
      const code = error.code || error.name;
      console.error('[SHOP ORDERS ERROR]', code);
      const message = ['42P01', '42703', 'ER_NO_SUCH_TABLE', 'ER_BAD_FIELD_ERROR'].includes(code)
        ? 'Shop order storage is missing a required database field. Ask an administrator to apply the Shop App schema update.'
        : ['08000', '08003', '08006', 'ECONNREFUSED', 'ETIMEDOUT', 'ECONNRESET'].includes(code)
          ? 'The order database is temporarily unreachable. Please retry.'
          : 'Orders could not be loaded right now. Please retry.';
      return res.status(503).json({ success: false, error: message, code });
    }
  });

  app.post('/api/shop/orders/:orderId/delivery', requireEmployee, async (req, res) => {
    let conn;
    try {
      conn = await pool.getConnection();
      const selections = req.body.items;
      const mode = String(req.body.mode || 'confirm').toLowerCase();
      if (!['submit', 'confirm'].includes(mode)) return res.status(400).json({ success: false, error: 'Choose Submit Order or Confirm Delivery.' });
      if (!Array.isArray(selections) || !selections.length || selections.some(item => !Number.isInteger(Number(item.orderItemId)) || (item.deliveredQuantity == null && typeof item.delivered !== 'boolean') || (item.deliveredQuantity != null && (!Number.isInteger(Number(item.deliveredQuantity)) || Number(item.deliveredQuantity) < 0)))) {
        return res.status(400).json({ success: false, error: 'Enter a whole delivery quantity for every order item.' });
      }
      const requestedStatuses = selections.map(item => {
        const fromBoolean = typeof item.deliveryConfirmed === 'boolean'
          ? item.deliveryConfirmed
          : typeof item.delivered === 'boolean' ? item.delivered : null;
        const rawStatus = item.deliveryStatus == null ? null : String(item.deliveryStatus).trim().toLowerCase().replace(/[\s-]+/g, '_');
        const fromStatus = rawStatus == null ? null
          : ['delivered', 'fully_delivered'].includes(rawStatus) ? true
            : ['not_delivered', 'undelivered', 'pending'].includes(rawStatus) ? false : undefined;
        if (fromStatus === undefined || (fromBoolean != null && fromStatus != null && fromBoolean !== fromStatus)) return undefined;
        return fromBoolean ?? fromStatus;
      });
      if (requestedStatuses.some(status => typeof status !== 'boolean')) {
        return res.status(400).json({ success: false, error: 'Select delivery status for each order item.' });
      }
      await conn.beginTransaction();
      const [assignmentMetadata] = await conn.query("SELECT to_regclass('public.shop_order_assignments') IS NOT NULL AS available");
      const hasConfirmationColumn = await hasDeliveryConfirmationColumn(conn);
      let orderRows;
      if (assignmentMetadata[0]?.available === true) {
        const shopName = String(req.shopEmployee.shopName || '');
        const [shopCountRows] = await conn.query(`SELECT COUNT(DISTINCT lower(shop_name))::int AS shop_count
          FROM shop_employees WHERE active = TRUE AND shop_name IS NOT NULL AND btrim(shop_name) <> ''`);
        if (Number(shopCountRows[0]?.shop_count || 0) === 1) {
          [orderRows] = await conn.query(`SELECT o.order_id, o.status, o.subtotal, o.discount, o.gst, o.payment_method, o.payment_status
            FROM orders o WHERE o.order_id = ? AND (
              EXISTS (SELECT 1 FROM shop_order_assignments soa WHERE soa.order_id = o.order_id AND lower(soa.shop_name) = lower(?))
              OR (NOT EXISTS (SELECT 1 FROM shop_order_assignments soa WHERE soa.order_id = o.order_id)
                AND EXISTS (SELECT 1 FROM shop_employees se WHERE se.active = TRUE AND lower(se.shop_name) = lower(?)))
            ) FOR UPDATE OF o`, [req.params.orderId, shopName, shopName]);
        } else {
          [orderRows] = await conn.query(`SELECT o.order_id, o.status, o.subtotal, o.discount, o.gst, o.payment_method, o.payment_status
            FROM orders o JOIN shop_order_assignments soa ON soa.order_id = o.order_id
            WHERE o.order_id = ? AND lower(soa.shop_name) = lower(?) FOR UPDATE OF o`, [req.params.orderId, shopName]);
        }
      } else {
        const shopName = String(req.shopEmployee.shopName || '');
        [orderRows] = await conn.query(`SELECT o.order_id, o.status, o.subtotal, o.discount, o.gst, o.payment_method, o.payment_status
          FROM orders o WHERE o.order_id = ?
            AND (SELECT COUNT(DISTINCT lower(shop_name)) FROM shop_employees WHERE active = TRUE AND shop_name IS NOT NULL AND btrim(shop_name) <> '') = 1
            AND EXISTS (SELECT 1 FROM shop_employees se WHERE se.active = TRUE AND lower(se.shop_name) = lower(?))
          FOR UPDATE OF o`, [req.params.orderId, shopName]);
      }
      if (!orderRows[0]) { await conn.rollback(); return res.status(404).json({ success: false, error: 'Order not found.' }); }
      const [orderItems] = await conn.query('SELECT id, unit_price, quantity FROM order_items WHERE order_id = ? ORDER BY id', [req.params.orderId]);
      const itemById = new Map(orderItems.map(item => [Number(item.id), item]));
      const submitted = new Map(selections.map((item, index) => {
        const orderItem = itemById.get(Number(item.orderItemId));
        const quantity = item.deliveredQuantity == null
          ? (item.delivered ? Number(orderItem?.quantity || 0) : 0)
          : Number(item.deliveredQuantity);
        return [Number(item.orderItemId), { quantity, requestedConfirmation: requestedStatuses[index] }];
      }));
      if (selections.length !== orderItems.length || orderItems.length !== submitted.size || orderItems.some(item => !submitted.has(Number(item.id)))) {
        await conn.rollback();
        return res.status(400).json({ success: false, error: 'Delivery update must include every product in this order.' });
      }
      if (orderItems.some(item => submitted.get(Number(item.id)).quantity > Number(item.quantity))) {
        await conn.rollback();
        return res.status(400).json({ success: false, error: 'Delivered quantity cannot exceed the ordered quantity.' });
      }
      const [existingDeliveries] = await conn.query(`SELECT order_item_id, delivered_quantity, ${deliveryConfirmedExpression('shop_delivery_items', hasConfirmationColumn)} AS delivery_confirmed, refund_status FROM shop_delivery_items WHERE order_id = ? FOR UPDATE`, [req.params.orderId]);
      const existingById = new Map(existingDeliveries.map(row => [Number(row.order_item_id), row]));
      const refundAlreadyProcessed = existingDeliveries.some(row => row.refund_status === 'refunded');
      if (refundAlreadyProcessed && orderItems.some(item => Number(existingById.get(Number(item.id))?.delivered_quantity || 0) !== submitted.get(Number(item.id)).quantity)) {
        await conn.rollback();
        return res.status(409).json({ success: false, error: 'A refund has already been recorded for this delivery. Contact an administrator before changing delivered quantities.' });
      }
      const deliveryConfirmedById = new Map();
      for (const item of orderItems) {
        const itemId = Number(item.id);
        const previous = existingById.get(itemId);
        const proposed = submitted.get(itemId);
        const confirmed = mode === 'confirm'
          ? proposed.requestedConfirmation
          : previous?.delivery_confirmed === true;
        if (confirmed && proposed.quantity <= 0) {
          await conn.rollback();
          return res.status(400).json({ success: false, error: 'A product must have a positive actual quantity before its delivery can be confirmed.' });
        }
        if (previous?.delivery_confirmed === true && (!confirmed || proposed.quantity < Number(previous.delivered_quantity || 0))) {
          await conn.rollback();
          return res.status(409).json({ success: false, error: 'A confirmed delivery cannot be unchecked or reduced.' });
        }
        deliveryConfirmedById.set(itemId, confirmed);
      }
      if (mode === 'confirm' && ![...deliveryConfirmedById.values()].some(Boolean)) {
        await conn.rollback();
        return res.status(400).json({ success: false, error: 'Confirm at least one product that has actually been delivered.' });
      }
      // Preserve the employee's entered quantity even while it is only available,
      // but only confirmed physical handovers contribute to delivery/refund totals.
      const calculationItems = orderItems.map(item => ({
        ...item,
        deliveredQuantity: deliveryConfirmedById.get(Number(item.id))
          ? submitted.get(Number(item.id)).quantity
          : 0,
      }));
      const totals = allocateDeliveryValues(calculationItems, orderRows[0]);
      const allocationById = new Map(totals.allocated.map((item, index) => [Number(orderItems[index].id), item]));
      for (const item of orderItems) {
        const delivery = allocationById.get(Number(item.id));
        const itemDeliveryConfirmed = deliveryConfirmedById.get(Number(item.id));
        const fullyDelivered = delivery.fullyDelivered && itemDeliveryConfirmed;
        const deliveryColumns = hasConfirmationColumn
          ? ', delivery_confirmed'
          : '';
        const deliveryValuesSql = hasConfirmationColumn
          ? ', ?'
          : '';
        const confirmationUpdate = hasConfirmationColumn
          ? ', delivery_confirmed = EXCLUDED.delivery_confirmed'
          : '';
        const deliveredFlag = hasConfirmationColumn ? fullyDelivered : itemDeliveryConfirmed;
        await conn.query(`INSERT INTO shop_delivery_items (order_item_id, order_id, delivered, delivered_quantity, undelivered_quantity, delivered_amount, refund_amount, refund_status, recorded_by, delivered_at, updated_at${deliveryColumns})
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CASE WHEN ? THEN CURRENT_TIMESTAMP ELSE NULL END, CURRENT_TIMESTAMP${deliveryValuesSql})
          ON CONFLICT (order_item_id) DO UPDATE SET delivered = EXCLUDED.delivered, delivered_quantity = EXCLUDED.delivered_quantity, undelivered_quantity = EXCLUDED.undelivered_quantity, delivered_amount = EXCLUDED.delivered_amount, refund_amount = EXCLUDED.refund_amount, refund_status = CASE WHEN shop_delivery_items.refund_status = 'refunded' AND EXCLUDED.refund_amount > 0 THEN shop_delivery_items.refund_status ELSE EXCLUDED.refund_status END, recorded_by = EXCLUDED.recorded_by, delivered_at = CASE WHEN ${hasConfirmationColumn ? 'EXCLUDED.delivery_confirmed' : 'EXCLUDED.delivered'} THEN COALESCE(shop_delivery_items.delivered_at, CURRENT_TIMESTAMP) ELSE NULL END${confirmationUpdate}, updated_at = CURRENT_TIMESTAMP`,
        [item.id, req.params.orderId, deliveredFlag, submitted.get(Number(item.id)).quantity, delivery.undeliveredQuantity, delivery.deliveredValue, delivery.refundValue, delivery.refundValue > 0 ? 'pending_admin_review' : 'not_required', req.shopEmployee.sub, itemDeliveryConfirmed, ...(hasConfirmationColumn ? [itemDeliveryConfirmed] : [])]);
      }
      const [deliveryRows] = await conn.query(`SELECT oi.id, oi.unit_price, oi.quantity, COALESCE(d.delivered_quantity, 0) AS delivered_quantity, ${deliveryConfirmedExpression('d', hasConfirmationColumn)} AS delivery_confirmed FROM order_items oi LEFT JOIN shop_delivery_items d ON d.order_item_id = oi.id WHERE oi.order_id = ?`, [req.params.orderId]);
      const savedTotals = allocateDeliveryValues(deliveryRows.map(item => ({ ...item, deliveredQuantity: item.delivery_confirmed ? Number(item.delivered_quantity) : 0 })), orderRows[0]);
      const deliveredAll = savedTotals.totalQuantity > 0 && savedTotals.totalDeliveredQuantity === savedTotals.totalQuantity;
      const deliveredNone = savedTotals.totalDeliveredQuantity === 0;
      const status = deliveredAll ? 'Delivered' : deliveredNone ? 'Pending' : 'Partially Delivered';
      const isCod = ['cod', 'cash on delivery'].includes(String(orderRows[0].payment_method || '').trim().toLowerCase());
      const requestedCashCollection = req.body.cashCollected === true;
      if (requestedCashCollection && (!isCod || !deliveredAll)) {
        await conn.rollback();
        return res.status(400).json({ success: false, error: 'Cash can be confirmed only for a fully delivered Cash on Delivery order.' });
      }
      // Collection is an explicit employee attestation. Persist it using the
      // existing payment_status column, inside the same order/delivery transaction.
      if (requestedCashCollection && String(orderRows[0].payment_status || '').toLowerCase() !== 'paid') {
        await conn.query("UPDATE orders SET payment_status = 'paid' WHERE order_id = ? AND lower(payment_method) IN ('cod', 'cash on delivery')", [req.params.orderId]);
      }
      const cashCollected = isCod && (requestedCashCollection || String(orderRows[0].payment_status || '').toLowerCase() === 'paid');
      if (mode === 'confirm' && !deliveredAll && savedTotals.refundAmount > 0 && !refundAlreadyProcessed) {
        await conn.query(`INSERT INTO shop_admin_notifications (order_id, employee_id, notification_type, message, refund_amount, created_at)
          VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
          ON CONFLICT (order_id) DO UPDATE SET employee_id = EXCLUDED.employee_id, message = EXCLUDED.message, refund_amount = EXCLUDED.refund_amount, read_at = NULL, created_at = CURRENT_TIMESTAMP`,
        [req.params.orderId, req.shopEmployee.sub, deliveredNone ? 'undelivered_refund' : 'partial_delivery', `${deliveredNone ? 'Undelivered order' : 'Partial delivery'} recorded for order ${req.params.orderId}. Refund pending review.`, savedTotals.refundAmount]);
      } else if (deliveredAll) {
        await conn.query('DELETE FROM shop_admin_notifications WHERE order_id = ?', [req.params.orderId]);
      }
      await conn.commit();
      return res.json({ success: true, status, paymentStatus: cashCollected ? 'paid' : orderRows[0].payment_status, cashCollected, deliveredQuantity: savedTotals.totalDeliveredQuantity, undeliveredQuantity: savedTotals.totalQuantity - savedTotals.totalDeliveredQuantity, deliveredValue: savedTotals.deliveredValue, refundAmount: savedTotals.refundAmount, refundStatus: refundAlreadyProcessed && savedTotals.refundAmount > 0 ? 'refunded' : savedTotals.refundAmount > 0 ? 'pending_admin_review' : 'not_required', message: cashCollected ? 'Cash collection and delivery details saved.' : 'Delivery details saved. Refund remains for admin review.' });
    } catch (error) {
      if (conn) await conn.rollback().catch(() => {});
      console.error('[SHOP DELIVERY ERROR]', error.code || error.name);
      return res.status(503).json({ success: false, error: 'Delivery details could not be saved.' });
    } finally { conn?.release(); }
  });

  app.get('/api/shop/products', requireEmployee, async (req, res) => {
    try {
      const search = `%${String(req.query.search || '').trim()}%`;
      const category = String(req.query.category || '').trim();
      const availability = String(req.query.availability || '').trim();
      const [rows] = await pool.query(`SELECT p.id, p.name, p.sku, p.brand, p.price, p.mrp, p.category_key, p.img, p.stock_quantity, p.status, c.title AS category_name, c.image_url AS category_image
        FROM products p LEFT JOIN categories c ON c.key_name = p.category_key
        WHERE (p.name ILIKE ? OR p.sku ILIKE ? OR COALESCE(p.brand, '') ILIKE ?)
          AND (? = '' OR p.category_key = ? OR c.title = ?)
          AND (? = '' OR (? = 'in_stock' AND p.stock_quantity > 0) OR (? = 'out_of_stock' AND p.stock_quantity <= 0))
          AND lower(COALESCE(p.status, 'active')) <> 'inactive' ORDER BY p.category_key, p.name LIMIT 500`, [search, search, search, category, category, category, availability, availability, availability]);
      return res.json({ success: true, products: rows.map(row => ({ ...row, price: Number(row.price), mrp: Number(row.mrp), stock: Number(row.stock_quantity), image: row.img || row.category_image || '' })) });
    } catch (error) {
      console.error('[SHOP PRODUCTS ERROR]', error.code || error.name);
      return res.status(503).json({ success: false, error: 'Product data is temporarily unavailable.' });
    }
  });

  app.get('/api/shop/categories', requireEmployee, async (_req, res) => {
    try {
      const [rows] = await pool.query(`SELECT c.id, c.key_name, c.title, c.image_url, COUNT(p.id)::int AS product_count
        FROM categories c LEFT JOIN products p ON p.category_key = c.key_name AND lower(COALESCE(p.status, 'active')) <> 'inactive'
        GROUP BY c.id ORDER BY c.display_order, c.title`);
      return res.json({ success: true, categories: rows });
    } catch (error) {
      console.error('[SHOP CATEGORIES ERROR]', error.code || error.name);
      return res.status(503).json({ success: false, error: 'Product categories are temporarily unavailable.' });
    }
  });

  app.post('/api/shop/enquiries', requireEmployee, async (req, res) => {
    try {
      const input = req.body || {};
      const values = ['customerName', 'companyName', 'contactNumber', 'category', 'productName', 'requiredQuantity'].map(key => String(input[key] || '').trim());
      if (values.some(value => !value) || !/^\+?[0-9 ()-]{7,20}$/.test(values[2]) || !Number.isInteger(Number(values[5])) || Number(values[5]) <= 0) {
        return res.status(400).json({ success: false, error: 'Enter customer, company, valid contact, category, product and a positive quantity.' });
      }
      const id = crypto.randomUUID();
      await pool.query(`INSERT INTO shop_product_enquiries (id, employee_id, customer_name, company_name, contact_number, category, product_name, required_quantity, remarks, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'new')`, [id, req.shopEmployee.sub, ...values.slice(0, 5), Number(values[5]), String(input.remarks || '').trim() || null]);
      return res.status(201).json({ success: true, enquiryId: id, message: 'Product enquiry sent to the admin team.' });
    } catch (error) {
      console.error('[SHOP ENQUIRY ERROR]', error.code || error.name);
      return res.status(503).json({ success: false, error: 'Enquiry could not be saved.' });
    }
  });

  app.get('/api/shop/reports', requireEmployee, async (req, res) => {
    try {
      const from = String(req.query.from || '').trim();
      const to = String(req.query.to || '').trim();
      const product = String(req.query.product || '').trim();
      const requestedPeriod = String(req.query.period || 'daily').toLowerCase();
      if (!['daily', 'monthly', 'product'].includes(requestedPeriod)) return res.status(400).json({ success: false, error: 'Choose daily, monthly, or product report grouping.' });
      if (from && !/^\d{4}-\d{2}-\d{2}$/.test(from) || to && !/^\d{4}-\d{2}-\d{2}$/.test(to)) return res.status(400).json({ success: false, error: 'Use YYYY-MM-DD for report dates.' });
      const dateExpression = requestedPeriod === 'monthly' ? "date_trunc('month', o.created_at)::date" : 'o.created_at::date';
      const dateSelection = requestedPeriod === 'product' ? 'NULL::date AS sale_date' : `${dateExpression} AS sale_date`;
      const groupDate = requestedPeriod === 'product' ? '' : `${dateExpression},`;
      const [rows] = await pool.query(`SELECT ${dateSelection}, oi.product_id, oi.product_name, oi.sku,
          SUM(COALESCE(d.delivered_quantity, CASE WHEN d.delivered THEN oi.quantity ELSE 0 END))::int AS quantity_sold,
          SUM(COALESCE(d.delivered_amount, 0)) AS delivered_amount,
          SUM(COALESCE(d.refund_amount, oi.unit_price * oi.quantity)) AS pending_amount,
          SUM(COALESCE(d.refund_amount, 0)) AS refund_amount
        FROM orders o JOIN order_items oi ON oi.order_id = o.order_id LEFT JOIN shop_delivery_items d ON d.order_item_id = oi.id
        WHERE (? = '' OR o.created_at::date >= ?::date) AND (? = '' OR o.created_at::date <= ?::date)
          AND (? = '' OR oi.product_id = ? OR oi.sku = ? OR oi.product_name ILIKE ?)
        GROUP BY ${groupDate} oi.product_id, oi.product_name, oi.sku ORDER BY sale_date DESC NULLS LAST, oi.product_name`, [from, from || null, to, to || null, product, product, product, `%${product}%`]);
      const rowsSafe = rows.map(row => ({ ...row, quantitySold: Number(row.quantity_sold), deliveredAmount: Number(row.delivered_amount || 0), pendingAmount: Number(row.pending_amount || 0), refundAmount: Number(row.refund_amount || 0) }));
      return res.json({ success: true, period: requestedPeriod, rows: rowsSafe, totals: rowsSafe.reduce((sum, row) => ({ quantitySold: sum.quantitySold + row.quantitySold, deliveredAmount: sum.deliveredAmount + row.deliveredAmount, pendingAmount: sum.pendingAmount + row.pendingAmount, refundAmount: sum.refundAmount + row.refundAmount }), { quantitySold: 0, deliveredAmount: 0, pendingAmount: 0, refundAmount: 0 }) });
    } catch (error) {
      console.error('[SHOP REPORT ERROR]', error.code || error.name);
      return res.status(503).json({ success: false, error: 'Sales report is temporarily unavailable.' });
    }
  });

  // Admin-only employee provisioning stores only a password hash.
  app.get('/api/admin/shop/employees', requireAdminAuth, async (_req, res) => {
    try {
      const [rows] = await pool.query('SELECT id, employee_id, shop_name, full_name, active, created_at FROM shop_employees ORDER BY created_at DESC');
      return res.json({ success: true, employees: rows });
    } catch (error) { console.error('[ADMIN SHOP EMPLOYEES ERROR]', error.code || error.name); return res.status(503).json({ success: false, error: 'Employee list is unavailable.' }); }
  });
  app.put('/api/admin/shop/orders/:orderId/assignment', requireAdminAuth, async (req, res) => {
    const shopName = String(req.body.shopName || '').trim();
    try {
      const [orderRows] = await pool.query('SELECT order_id FROM orders WHERE order_id = ?', [req.params.orderId]);
      if (!orderRows.length) return res.status(404).json({ success: false, error: 'Order not found.' });
      const [assignmentMetadata] = await pool.query("SELECT to_regclass('public.shop_order_assignments') IS NOT NULL AS available");
      if (assignmentMetadata[0]?.available !== true) {
        const [activeShops] = await pool.query(`SELECT DISTINCT shop_name FROM shop_employees
          WHERE active = TRUE AND shop_name IS NOT NULL AND btrim(shop_name) <> '' ORDER BY shop_name`);
        const uniqueShops = [...new Map(activeShops.map(row => [String(row.shop_name).toLowerCase(), row.shop_name])).values()];
        if (uniqueShops.length !== 1) return res.status(503).json({ success: false, error: 'Shop assignment storage is unavailable; an administrator must restore the assignment table before routing multiple shops.' });
        if (shopName && shopName.toLowerCase() !== String(uniqueShops[0]).toLowerCase()) return res.status(400).json({ success: false, error: 'Only the single active shop can receive orders until shop assignments are configured.' });
        return res.json({ success: true, shopName: uniqueShops[0], message: 'Orders are automatically routed to the only active shop.' });
      }
      if (!shopName) {
        await pool.query('DELETE FROM shop_order_assignments WHERE order_id = ?', [req.params.orderId]);
        return res.json({ success: true, shopName: null, message: 'Shop assignment removed.' });
      }
      const [employeeRows] = await pool.query('SELECT id FROM shop_employees WHERE active = TRUE AND lower(shop_name) = lower(?) LIMIT 1', [shopName]);
      if (!employeeRows.length) return res.status(400).json({ success: false, error: 'Choose an active shop employee account.' });
      await pool.query(`INSERT INTO shop_order_assignments (order_id, shop_name, assigned_by, assigned_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT (order_id) DO UPDATE SET shop_name = EXCLUDED.shop_name, assigned_by = EXCLUDED.assigned_by, assigned_at = CURRENT_TIMESTAMP`,
      [req.params.orderId, shopName, null]);
      return res.json({ success: true, shopName, message: 'Order assigned to shop.' });
    } catch (error) {
      console.error('[ADMIN SHOP ORDER ASSIGNMENT ERROR]', error.code || error.name);
      return res.status(503).json({ success: false, error: 'Shop assignment could not be saved.' });
    }
  });
  app.post('/api/admin/shop/employees', requireAdminAuth, async (req, res) => {
    try {
      const shopName = String(req.body.shopName || '').trim();
      const employeeId = String(req.body.loginId || '').trim().toUpperCase();
      const password = String(req.body.password || '');
      const fullName = String(req.body.fullName || shopName).trim();
      if (shopName.length < 2 || shopName.length > 191) return res.status(400).json({ success: false, error: 'Enter a shop name between 2 and 191 characters.' });
      if (!/^[A-Z0-9][A-Z0-9._-]{2,31}$/.test(employeeId)) return res.status(400).json({ success: false, error: 'Login ID must be 3–32 characters using letters, numbers, dot, underscore, or hyphen.' });
      if (password.length < 10 || password.length > 128) return res.status(400).json({ success: false, error: 'Password must be between 10 and 128 characters.' });
      if (fullName.length < 2 || fullName.length > 128) return res.status(400).json({ success: false, error: 'Employee display name must be between 2 and 128 characters.' });
      const id = crypto.randomUUID();
      const passwordHash = await bcrypt.hash(password, 12);
      await pool.query('INSERT INTO shop_employees (id, employee_id, shop_name, full_name, password_hash, active) VALUES (?, ?, ?, ?, ?, TRUE)', [id, employeeId, shopName, fullName, passwordHash]);
      return res.status(201).json({ success: true, employee: { id, employeeId, loginId: employeeId, shopName, fullName }, message: 'Shop employee account created.' });
    } catch (error) {
      console.error('[ADMIN SHOP EMPLOYEE CREATE ERROR]', error.code || error.name);
      if (error.code === 'ER_DUP_ENTRY') return res.status(409).json({ success: false, error: 'That Login ID is already in use. Choose another one.' });
      return res.status(503).json({ success: false, error: 'Employee account could not be created.' });
    }
  });
  app.put('/api/admin/shop/employees/:id/active', requireAdminAuth, async (req, res) => {
    try {
      if (typeof req.body.active !== 'boolean') return res.status(400).json({ success: false, error: 'Active status must be true or false.' });
      const [result] = await pool.query('UPDATE shop_employees SET active = ? WHERE id = ?', [req.body.active, req.params.id]);
      if (!result.affectedRows) return res.status(404).json({ success: false, error: 'Employee not found.' });
      return res.json({ success: true, message: req.body.active ? 'Employee activated.' : 'Employee access disabled.' });
    } catch (error) { console.error('[ADMIN SHOP EMPLOYEE UPDATE ERROR]', error.code || error.name); return res.status(503).json({ success: false, error: 'Employee access could not be updated.' }); }
  });
  app.get('/api/admin/shop/enquiries', requireAdminAuth, async (_req, res) => {
    try {
      const [rows] = await pool.query(`SELECT e.*, se.employee_id AS submitted_by FROM shop_product_enquiries e LEFT JOIN shop_employees se ON se.id = e.employee_id ORDER BY e.created_at DESC LIMIT 500`);
      return res.json({ success: true, enquiries: rows });
    } catch (error) { console.error('[ADMIN SHOP ENQUIRIES ERROR]', error.code || error.name); return res.status(503).json({ success: false, error: 'Shop enquiries are unavailable.' }); }
  });
  app.get('/api/admin/shop/notifications', requireAdminAuth, async (_req, res) => {
    try {
      const [rows] = await pool.query(`SELECT n.id, n.order_id, n.notification_type, n.message, n.refund_amount, n.created_at, n.read_at, se.employee_id, se.full_name
        FROM shop_admin_notifications n LEFT JOIN shop_employees se ON se.id = n.employee_id ORDER BY n.created_at DESC LIMIT 250`);
      return res.json({ success: true, notifications: rows });
    } catch (error) { console.error('[ADMIN SHOP NOTIFICATIONS ERROR]', error.code || error.name); return res.status(503).json({ success: false, error: 'Shop delivery notifications are unavailable.' }); }
  });
  app.put('/api/admin/shop/orders/:orderId/refund', requireAdminAuth, async (req, res) => {
    const refundStatus = String(req.body.status || '').trim();
    if (!['pending_admin_review', 'refunded'].includes(refundStatus)) return res.status(400).json({ success: false, error: 'Choose pending review or refunded.' });
    try {
      const reference = String(req.body.reference || '').trim() || null;
      const notes = String(req.body.notes || '').trim() || null;
      const [result] = await pool.query(`UPDATE shop_delivery_items SET refund_status = ?, refund_reference = ?, refund_notes = ?, updated_at = CURRENT_TIMESTAMP WHERE order_id = ? AND refund_amount > 0`, [refundStatus, reference, notes, req.params.orderId]);
      if (!result.affectedRows) return res.status(404).json({ success: false, error: 'No refund record exists for this order.' });
      return res.json({ success: true, message: refundStatus === 'refunded' ? 'Refund details recorded.' : 'Refund returned to pending review.' });
    } catch (error) { console.error('[ADMIN SHOP REFUND ERROR]', error.code || error.name); return res.status(503).json({ success: false, error: 'Refund details could not be saved.' }); }
  });
};
