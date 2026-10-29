export class AdminOrdersError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

const response = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: {...cors, 'Content-Type': 'application/json'},
});

const PAGE_SIZE = 250;
const MAX_ORDERS = 20000;
const MAX_ROWS = 50000;
const ORDER_COLUMNS = 'order_id,user_email,user_name,user_business,created_at,subtotal,discount,gst,delivery_fee,grand_total,payment_method,payment_status,delivery_address,delivery_note,status,invoice_number';
const ITEM_COLUMNS = 'id,order_id,product_id,product_name,brand,unit_price,quantity,moq,img_src,sku';
const DELIVERY_COLUMNS = 'order_item_id,order_id,delivered,delivery_confirmed,delivered_quantity,undelivered_quantity,refund_status,delivered_at,recorded_by';
const LEGACY_DELIVERY_COLUMNS = 'order_item_id,order_id,delivered,delivered_quantity,undelivered_quantity,refund_status,delivered_at,recorded_by';

function isMissingColumn(error) {
  return ['42703', 'PGRST204'].includes(String(error?.code ?? ''));
}

function isMissingRelation(error) {
  return ['42P01', 'PGRST205'].includes(String(error?.code ?? ''));
}

function toNumber(value, fallback = 0) {
  const number = Number(value ?? fallback);
  if (!Number.isFinite(number)) {
    throw new AdminOrdersError(503, 'Order data could not be loaded.');
  }
  return number;
}

function isoOrNull(value) {
  if (value == null || value === '') return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function roundMoney(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

// Mirrors Express allocateDeliveryValues using the immutable order-item dealer
// price snapshot. An item counts as delivered only after explicit confirmation.
function allocateDeliveryValues(items) {
  const grossCents = items.map(item => Math.round(
    toNumber(item.unit_price) * Math.max(0, Math.trunc(toNumber(item.quantity))) * 100,
  ));
  let remainingCents = grossCents.reduce((sum, cents) => sum + cents, 0);
  const allocated = items.map((item, index) => {
    const ordered = Math.max(0, Math.trunc(toNumber(item.quantity)));
    const lineCents = index === items.length - 1 ? remainingCents : grossCents[index];
    remainingCents -= lineCents;
    const confirmed = item.shop_delivery_confirmed === true;
    const requested = confirmed ? Math.trunc(toNumber(item.shop_delivered_quantity)) : 0;
    const deliveredQuantity = Math.min(ordered, Math.max(0, requested));
    const deliveredCents = ordered === 0 ? 0
      : deliveredQuantity === ordered ? lineCents
        : Math.round(lineCents * deliveredQuantity / ordered);
    return {
      orderedQuantity: ordered,
      deliveredQuantity,
      undeliveredQuantity: ordered - deliveredQuantity,
      deliveredValue: deliveredCents / 100,
      refundValue: (lineCents - deliveredCents) / 100,
    };
  });
  return allocated;
}

async function readOrders(service) {
  const orders = [];
  for (let offset = 0; ; offset += PAGE_SIZE) {
    const {data, error} = await service.from('orders').select(ORDER_COLUMNS)
      .order('created_at', {ascending: false})
      .range(offset, offset + PAGE_SIZE - 1);
    if (error) throw new AdminOrdersError(503, 'Order data could not be loaded.');
    const page = data ?? [];
    if (orders.length + page.length > MAX_ORDERS) {
      throw new AdminOrdersError(503, 'Order list exceeds the supported limit.');
    }
    orders.push(...page);
    if (page.length < PAGE_SIZE) return orders;
  }
}

async function readItemsForOrders(service, orders) {
  const byOrder = new Map(orders.map(order => [String(order.order_id), []]));
  let totalItemRows = 0;
  for (let start = 0; start < orders.length; start += 50) {
    const orderIds = orders.slice(start, start + 50).map(order => String(order.order_id));
    for (let offset = 0; ; offset += PAGE_SIZE) {
      const {data, error} = await service.from('order_items').select(ITEM_COLUMNS)
        .in('order_id', orderIds).order('id', {ascending: true})
        .range(offset, offset + PAGE_SIZE - 1);
      if (error) throw new AdminOrdersError(503, 'Order data could not be loaded.');
      const page = data ?? [];
      totalItemRows += page.length;
      if (totalItemRows > MAX_ROWS) {
        throw new AdminOrdersError(503, 'Order list exceeds the supported limit.');
      }
      for (const item of page) byOrder.get(String(item.order_id))?.push(item);
      if (page.length < PAGE_SIZE) break;
    }
  }
  return byOrder;
}

async function readDeliveries(service, itemIds) {
  if (!itemIds.length) return new Map();
  const deliveries = new Map();
  let confirmedColumn = true;
  for (let start = 0; start < itemIds.length; start += 200) {
    const batch = itemIds.slice(start, start + 200);
    const query = columns => service.from('shop_delivery_items').select(columns)
      .in('order_item_id', batch).range(0, PAGE_SIZE - 1);
    let result = confirmedColumn
      ? await query(DELIVERY_COLUMNS)
      : await query(LEGACY_DELIVERY_COLUMNS);
    if (result.error && confirmedColumn && isMissingColumn(result.error)) {
      confirmedColumn = false;
      result = await query(LEGACY_DELIVERY_COLUMNS);
    }
    if (result.error && isMissingRelation(result.error)) return new Map();
    if (result.error) throw new AdminOrdersError(503, 'Order data could not be loaded.');
    for (const row of result.data ?? []) {
      deliveries.set(String(row.order_item_id), {
        ...row,
        delivery_confirmed: confirmedColumn ? row.delivery_confirmed === true : row.delivered === true,
      });
    }
  }
  return deliveries;
}

async function readEmployees(service, employeeIds) {
  const uniqueIds = [...new Set(employeeIds.filter(Boolean).map(String))];
  if (!uniqueIds.length) return new Map();
  const employees = new Map();
  for (let start = 0; start < uniqueIds.length; start += 200) {
    const {data, error} = await service.from('shop_employees')
      .select('id,full_name,employee_id').in('id', uniqueIds.slice(start, start + 200));
    if (error && isMissingRelation(error)) return new Map();
    if (error) throw new AdminOrdersError(503, 'Order data could not be loaded.');
    for (const employee of data ?? []) employees.set(String(employee.id), employee);
  }
  return employees;
}

async function readSingleShopFallback(service) {
  const {data, error} = await service.from('shop_employees').select('shop_name,active')
    .eq('active', true).not('shop_name', 'is', null);
  if (error && isMissingRelation(error)) return '';
  if (error) throw new AdminOrdersError(503, 'Order data could not be loaded.');
  const unique = new Map();
  for (const row of data ?? []) {
    const name = String(row.shop_name ?? '').trim();
    if (name) unique.set(name.toLowerCase(), name);
  }
  return unique.size === 1 ? [...unique.values()][0] : '';
}

function formatOrders(orders, byOrder, deliveries, employees, singleShopFallback) {
  return orders.map(order => {
    const rawItems = byOrder.get(String(order.order_id)) ?? [];
    const items = rawItems.map(row => {
      const delivery = deliveries.get(String(row.id));
      return {
        ...row,
        shop_delivery_record_id: delivery?.order_item_id ?? null,
        shop_delivered: delivery?.delivered === true,
        shop_delivery_confirmed: delivery?.delivery_confirmed === true,
        shop_delivered_quantity: delivery?.delivered_quantity ?? 0,
        shop_undelivered_quantity: delivery?.undelivered_quantity ?? 0,
        shop_refund_status: delivery?.refund_status ?? 'not_required',
        shop_delivered_at: delivery?.delivered_at ?? null,
        shop_recorded_by: delivery?.recorded_by ?? null,
      };
    });
    const allocation = allocateDeliveryValues(items);
    const lineItems = items.map((item, index) => {
      const allocationItem = allocation[index];
      const employee = item.shop_recorded_by == null ? null : employees.get(String(item.shop_recorded_by));
      const confirmed = item.shop_delivery_confirmed === true;
      const unitPrice = toNumber(item.unit_price);
      const quantity = allocationItem.orderedQuantity;
      const deliveredQuantity = allocationItem.deliveredQuantity;
      const name = employee?.full_name || employee?.employee_id || null;
      return {
        id: item.product_id,
        orderItemId: String(item.id),
        name: item.product_name,
        brand: item.brand || 'RO Wholesale',
        price: `₹${new Intl.NumberFormat('en-IN', {maximumFractionDigits: 2}).format(unitPrice)}`,
        numericPrice: unitPrice,
        dealerPrice: unitPrice,
        quantity,
        orderedQuantity: quantity,
        actualDeliveredQuantity: confirmed ? deliveredQuantity : 0,
        submittedDeliveryQuantity: Math.max(0, Math.trunc(toNumber(item.shop_delivered_quantity))),
        deliveryConfirmed: confirmed,
        deliveryStatus: !confirmed || deliveredQuantity <= 0 ? 'Pending'
          : deliveredQuantity >= quantity ? 'Delivered' : 'Partially Delivered',
        deliveredAt: confirmed ? item.shop_delivered_at : null,
        deliveredBy: confirmed ? name : null,
        deliveredByEmployeeId: confirmed ? (employee?.employee_id ?? null) : null,
        undeliveredQuantity: allocationItem.undeliveredQuantity,
        deliveredValue: allocationItem.deliveredValue,
        refundAmount: allocationItem.refundValue,
        refundStatus: item.shop_refund_status,
        imgSrc: item.img_src || '',
      };
    });
    const orderDelivery = allocation.reduce((total, line) => ({
      deliveredValue: total.deliveredValue + line.deliveredValue,
      refundAmount: total.refundAmount + line.refundValue,
      deliveredQuantity: total.deliveredQuantity + line.deliveredQuantity,
      totalQuantity: total.totalQuantity + line.orderedQuantity,
    }), {deliveredValue: 0, refundAmount: 0, deliveredQuantity: 0, totalQuantity: 0});
    const deliveryStatus = orderDelivery.deliveredQuantity <= 0 ? 'Pending'
      : orderDelivery.deliveredQuantity >= orderDelivery.totalQuantity ? 'Delivered' : 'Partially Delivered';
    const cashCollected = ['cod', 'cash on delivery'].includes(String(order.payment_method ?? '').trim().toLowerCase())
      && String(order.payment_status ?? '').trim().toLowerCase() === 'paid';
    const confirmedItems = items.filter(item => item.shop_delivery_confirmed && item.shop_delivered_at);
    const maxDeliveredAt = confirmedItems.map(item => isoOrNull(item.shop_delivered_at)).filter(Boolean)
      .sort((a, b) => new Date(b).getTime() - new Date(a).getTime())[0] ?? null;
    const cashCollectors = [...new Set(items.filter(item => item.shop_delivery_confirmed)
      .map(item => {
        const employee = item.shop_recorded_by == null ? null : employees.get(String(item.shop_recorded_by));
        return employee?.full_name || employee?.employee_id || null;
      }).filter(Boolean))];
    const amount = key => toNumber(order[key]);
    return {
      orderId: order.order_id,
      userEmail: order.user_email,
      userName: order.user_name,
      userBusiness: order.user_business,
      orderDate: isoOrNull(order.created_at),
      dueDate: null,
      items: lineItems,
      subtotal: amount('subtotal'),
      discount: amount('discount'),
      gst: amount('gst'),
      deliveryFee: amount('delivery_fee'),
      grandTotal: amount('grand_total'),
      paymentMethod: order.payment_method || 'Cash on Delivery',
      paymentStatus: order.payment_status || 'pending',
      cashCollected,
      cashCollectedAt: cashCollected ? maxDeliveredAt : null,
      cashCollectedBy: cashCollected ? cashCollectors.join(', ') || null : null,
      deliveryAddress: order.delivery_address || '',
      deliveryNote: order.delivery_note || '',
      status: deliveryStatus,
      originalOrderStatus: order.status || 'Processing',
      deliveryStatus,
      shopDeliveryStarted: items.some(item => item.shop_delivery_record_id != null),
      deliveredQuantity: orderDelivery.deliveredQuantity,
      undeliveredQuantity: Math.max(0, orderDelivery.totalQuantity - orderDelivery.deliveredQuantity),
      deliveredValue: roundMoney(orderDelivery.deliveredValue),
      originalOrderValue: roundMoney(items.reduce((sum, item) => sum + toNumber(item.unit_price) * Math.max(0, Math.trunc(toNumber(item.quantity))), 0)),
      refundAmount: roundMoney(orderDelivery.refundAmount),
      deliveredAt: maxDeliveredAt,
      deliveredBy: cashCollectors.join(', ') || null,
      // The audited schema has no shop_order_assignments table. Match Express's
      // single-active-shop fallback without inventing or reading an assignment.
      shopName: singleShopFallback,
      invoiceNumber: order.invoice_number,
      createdAt: isoOrNull(order.created_at) ?? new Date(0).toISOString(),
    };
  });
}

export function createAdminOrdersRepository(service) {
  return {
    async listOrders() {
      const orders = await readOrders(service);
      const byOrder = await readItemsForOrders(service, orders);
      const itemIds = [...byOrder.values()].flat().map(item => String(item.id));
      const deliveries = await readDeliveries(service, itemIds);
      const employeeIds = [...deliveries.values()].map(row => row.recorded_by).filter(Boolean);
      const [employees, singleShopFallback] = await Promise.all([
        readEmployees(service, employeeIds),
        readSingleShopFallback(service),
      ]);
      const formatted = formatOrders(orders, byOrder, deliveries, employees, singleShopFallback);
      return {success: true, count: formatted.length, orders: formatted};
    },
  };
}

export function isVerifiedAdmin(user) {
  return Boolean(user?.id && user.email_confirmed_at && user.app_metadata?.role === 'admin');
}

export function createAdminOrdersHandler({authenticate, repository}) {
  return async request => {
    if (request.method === 'OPTIONS') return response({ok: true});
    if (request.method !== 'GET') return response({success: false, error: 'Method not allowed.'}, 405);
    try {
      const user = await authenticate(request);
      if (!user?.id || !user.email_confirmed_at) {
        throw new AdminOrdersError(401, 'A verified sign-in is required.');
      }
      if (!isVerifiedAdmin(user)) {
        throw new AdminOrdersError(403, 'A verified administrator account is required.');
      }
      return response(await repository.listOrders());
    } catch (error) {
      const status = error instanceof AdminOrdersError ? error.status : 500;
      const message = error instanceof AdminOrdersError ? error.message : 'Order data could not be loaded.';
      console.error('[SUPABASE ADMIN ORDERS]', `HTTP_${status}`);
      return response({success: false, error: message}, status);
    }
  };
}
