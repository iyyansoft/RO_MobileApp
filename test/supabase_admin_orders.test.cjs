const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  AdminOrdersError,
  createAdminOrdersHandler,
  createAdminOrdersRepository,
} = require('../supabase/functions/_shared/admin_orders_core.mjs');

const admin = {id: 'admin-auth', email_confirmed_at: 'confirmed', app_metadata: {role: 'admin'}};

function fakeService({tables = {}, missingDeliveryConfirmed = false, errors = {}} = {}) {
  const calls = [];
  class Query {
    constructor(table) { this.table = table; this.filters = []; this.rangeValue = null; }
    select(columns) { this.columns = columns; this.call = {table: this.table, columns}; calls.push(this.call); return this; }
    order(column, options) { this.ordering = [column, options]; if (this.call) this.call.order = [column, options]; return this; }
    in(column, values) { this.filters.push(row => values.map(String).includes(String(row[column]))); return this; }
    eq(column, value) { this.filters.push(row => row[column] === value); return this; }
    not(column, operator, value) {
      if (operator === 'is' && value === null) this.filters.push(row => row[column] != null);
      return this;
    }
    range(from, to) { this.rangeValue = [from, to]; if (this.call) this.call.range = [from, to]; return this.execute(); }
    async execute() {
      if (errors[this.table]) return {data: null, error: {code: 'XX000', message: 'sensitive db detail'}};
      if (this.table === 'shop_delivery_items' && missingDeliveryConfirmed && this.columns.includes('delivery_confirmed')) {
        return {data: null, error: {code: '42703', message: 'column unavailable'}};
      }
      let rows = [...(tables[this.table] ?? [])];
      for (const filter of this.filters) rows = rows.filter(filter);
      if (this.ordering) {
        const [column, options] = this.ordering;
        rows.sort((a, b) => String(a[column]).localeCompare(String(b[column])) * (options?.ascending === false ? -1 : 1));
      }
      if (this.rangeValue) rows = rows.slice(this.rangeValue[0], this.rangeValue[1] + 1);
      return {data: rows, error: null};
    }
    then(resolve, reject) { return this.execute().then(resolve, reject); }
  }
  return {calls, from(table) { return new Query(table); }};
}

const orders = [
  {
    order_id: 'RO-1', user_email: 'one@example.test', user_name: 'One', user_business: 'One Co',
    created_at: '2026-10-01T10:00:00Z', subtotal: '2350.00', discount: '0', gst: '0',
    delivery_fee: '0', grand_total: '2350.00', payment_method: 'COD', payment_status: 'pending',
    delivery_address: 'A', delivery_note: '', status: 'Processing', invoice_number: 'I-1',
    pan_number: 'never select', purchase_price: 'never select',
  },
  {
    order_id: 'RO-2', user_email: 'two@example.test', user_name: 'Two', user_business: 'Two Co',
    created_at: '2026-10-02T10:00:00Z', subtotal: '50', discount: '0', gst: '0',
    delivery_fee: '0', grand_total: '50', payment_method: 'Cash on Delivery', payment_status: 'paid',
    delivery_address: 'B', delivery_note: '', status: 'Delivered', invoice_number: 'I-2',
  },
];
const items = [
  {id: 1, order_id: 'RO-1', product_id: 'p1', product_name: 'Membrane', brand: 'Aqua', unit_price: '650.00', quantity: 3, img_src: 'membrane.png'},
  {id: 2, order_id: 'RO-1', product_id: 'p2', product_name: 'Filter', brand: null, unit_price: '200.00', quantity: 2, img_src: null},
  {id: 3, order_id: 'RO-2', product_id: 'p3', product_name: 'Pipe', brand: 'Aqua', unit_price: '50.00', quantity: 1, img_src: ''},
];

test('admin orders preserve the Express response shape and calculate only confirmed delivery values', async () => {
  const service = fakeService({tables: {
    orders,
    order_items: items,
    shop_delivery_items: [
      {order_item_id: 1, order_id: 'RO-1', delivered: true, delivery_confirmed: true, delivered_quantity: 2, undelivered_quantity: 1, refund_status: 'pending_admin_review', delivered_at: '2026-10-03T10:00:00Z', recorded_by: 'e1'},
      // A submitted quantity without confirmation is not reported as delivered.
      {order_item_id: 2, order_id: 'RO-1', delivered: false, delivery_confirmed: false, delivered_quantity: 1, undelivered_quantity: 1, refund_status: 'not_required', delivered_at: null, recorded_by: null},
      {order_item_id: 3, order_id: 'RO-2', delivered: true, delivery_confirmed: true, delivered_quantity: 1, undelivered_quantity: 0, refund_status: 'not_required', delivered_at: '2026-10-04T10:00:00Z', recorded_by: 'e2'},
    ],
    shop_employees: [
      {id: 'e1', full_name: 'Employee One', employee_id: 'E1', active: true, shop_name: 'Main'},
      {id: 'e2', full_name: 'Employee Two', employee_id: 'E2', active: true, shop_name: 'Main'},
    ],
  }});
  const result = await createAdminOrdersRepository(service).listOrders();
  assert.equal(result.success, true);
  assert.equal(result.count, 2);
  const partial = result.orders.find(order => order.orderId === 'RO-1');
  assert.equal(partial.status, 'Partially Delivered');
  assert.equal(partial.originalOrderValue, 2350);
  assert.equal(partial.deliveredValue, 1300);
  assert.equal(partial.undeliveredQuantity, 3);
  assert.equal(partial.refundAmount, 1050);
  assert.equal(partial.items[0].actualDeliveredQuantity, 2);
  assert.equal(partial.items[0].deliveredBy, 'Employee One');
  assert.equal(partial.items[1].actualDeliveredQuantity, 0);
  assert.equal(partial.items[1].submittedDeliveryQuantity, 1);
  assert.equal(partial.items[0].dealerPrice, 650);
  assert.equal(partial.shopName, 'Main');
  const cod = result.orders.find(order => order.orderId === 'RO-2');
  assert.equal(cod.status, 'Delivered');
  assert.equal(cod.cashCollected, true);
  assert.equal(cod.cashCollectedBy, 'Employee Two');
  assert.equal(cod.originalOrderValue, 50);
  assert.ok(service.calls.some(call => call.table === 'orders' && call.columns === 'order_id,user_email,user_name,user_business,created_at,subtotal,discount,gst,delivery_fee,grand_total,payment_method,payment_status,delivery_address,delivery_note,status,invoice_number'));
  assert.ok(service.calls.every(call => !/purchase_price|pan_number|password|gstin/i.test(call.columns)));
});

test('legacy delivery schema falls back to delivered without requiring a missing column', async () => {
  const service = fakeService({missingDeliveryConfirmed: true, tables: {
    orders: orders.slice(0, 1), order_items: items.slice(0, 1),
    shop_delivery_items: [{order_item_id: 1, order_id: 'RO-1', delivered: true, delivered_quantity: 1, undelivered_quantity: 2, refund_status: 'pending_admin_review', delivered_at: null, recorded_by: null}],
    shop_employees: [],
  }});
  const result = await createAdminOrdersRepository(service).listOrders();
  assert.equal(result.orders[0].items[0].deliveryConfirmed, true);
  assert.equal(result.orders[0].items[0].actualDeliveredQuantity, 1);
});

test('order and item reads paginate and fail closed when processing limits are exceeded', async () => {
  const many = Array.from({length: 251}, (_, i) => ({...orders[0], order_id: `RO-${i}`}));
  const service = fakeService({tables: {orders: many, order_items: [], shop_delivery_items: [], shop_employees: []}});
  const result = await createAdminOrdersRepository(service).listOrders();
  assert.equal(result.count, 251);
  assert.deepEqual(service.calls.filter(call => call.table === 'orders').map(call => call.range), [[0, 249], [250, 499]]);

  const failed = fakeService({errors: {orders: true}});
  await assert.rejects(createAdminOrdersRepository(failed).listOrders(), error =>
    error instanceof AdminOrdersError && error.status === 503 && error.message === 'Order data could not be loaded.');
});

test('admin orders handler denies anonymous, unverified, and client-only admin claims before reads', async () => {
  let reads = 0;
  const handler = createAdminOrdersHandler({
    authenticate: async request => {
      const value = request.headers.get('x-user');
      return value ? JSON.parse(value) : null;
    },
    repository: {async listOrders() { reads++; return {success: true, count: 0, orders: []}; }},
  });
  for (const [user, status] of [
    [null, 401],
    [{id: 'a', app_metadata: {role: 'admin'}}, 401],
    [{id: 'a', email_confirmed_at: 'yes', app_metadata: {role: 'dealer'}, user_metadata: {role: 'admin'}}, 403],
  ]) {
    const response = await handler(new Request('https://local.test/orders', {
      method: 'GET', headers: user ? {'x-user': JSON.stringify(user)} : {},
    }));
    assert.equal(response.status, status);
  }
  assert.equal(reads, 0);
  const methodDenied = await handler(new Request('https://local.test/orders', {method: 'POST'}));
  assert.equal(methodDenied.status, 405);
  assert.equal(reads, 0);
  const success = await handler(new Request('https://local.test/orders', {
    method: 'GET', headers: {'x-user': JSON.stringify(admin)},
  }));
  assert.equal(success.status, 200);
  assert.deepEqual(await success.json(), {success: true, count: 0, orders: []});
  assert.equal(reads, 1);
});
