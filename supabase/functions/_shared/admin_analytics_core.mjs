export class AdminAnalyticsError extends Error {
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

const PAGE_SIZE = 500;
const MAX_ROWS = 50000;
const ORDER_COLUMNS = 'order_id,grand_total,status,created_at';
const ITEM_COLUMNS = 'order_id,product_id,sku,product_name,brand,unit_price,quantity,img_src';
const PRODUCT_COLUMNS = 'id,sku,name,category_key,img,stock_quantity,min_stock';

function isVerifiedAdmin(user) {
  return Boolean(user?.id && user.email_confirmed_at && user.app_metadata?.role === 'admin');
}

function toNumber(value, fallback = 0) {
  const number = Number(value ?? fallback);
  if (!Number.isFinite(number)) throw new AdminAnalyticsError(503, 'Analytics could not be generated.');
  return number;
}

async function readAll(service, table, columns) {
  const rows = [];
  for (let offset = 0; ; offset += PAGE_SIZE) {
    const {data, error} = await service.from(table).select(columns).range(offset, offset + PAGE_SIZE - 1);
    if (error) throw new AdminAnalyticsError(503, 'Analytics could not be generated.');
    const page = data ?? [];
    if (rows.length + page.length > MAX_ROWS) {
      throw new AdminAnalyticsError(503, 'Analytics dataset exceeds the supported limit.');
    }
    rows.push(...page);
    if (page.length < PAGE_SIZE) return rows;
  }
}

function validDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new AdminAnalyticsError(503, 'Analytics could not be generated.');
  return date;
}

function dayKey(date) {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}-${String(date.getUTCDate()).padStart(2, '0')}`;
}

function formatDay(date) {
  return new Intl.DateTimeFormat('en-US', {month: 'short', day: 'numeric', timeZone: 'UTC'}).format(date);
}

function formatMonth(date) {
  return new Intl.DateTimeFormat('en-US', {month: 'short', year: '2-digit', timeZone: 'UTC'}).format(date);
}

function makeChart(validOrders, period, now) {
  const labels = [];
  const revenueData = [];
  const orderCountData = [];
  const buckets = [];
  if (period === 'daily') {
    for (let i = 6; i >= 0; i--) {
      const date = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - i));
      const key = dayKey(date);
      labels.push(formatDay(date));
      buckets.push(order => dayKey(order.date) === key);
    }
  } else if (period === 'weekly') {
    for (let i = 3; i >= 0; i--) {
      const end = now.getTime() - i * 7 * 86400000;
      const start = end - 7 * 86400000;
      labels.push(`Week ${4 - i}`);
      buckets.push(order => order.date.getTime() >= start && order.date.getTime() < end);
    }
  } else if (period === 'monthly') {
    for (let i = 5; i >= 0; i--) {
      const date = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1));
      labels.push(formatMonth(date));
      buckets.push(order => order.date.getUTCMonth() === date.getUTCMonth() && order.date.getUTCFullYear() === date.getUTCFullYear());
    }
  } else {
    for (let i = 2; i >= 0; i--) {
      const year = now.getUTCFullYear() - i;
      labels.push(String(year));
      buckets.push(order => order.date.getUTCFullYear() === year);
    }
  }
  for (const matches of buckets) {
    const orders = validOrders.filter(matches);
    revenueData.push(orders.reduce((sum, order) => sum + order.amount, 0));
    orderCountData.push(orders.length);
  }
  return {labels, revenueData, orderCountData};
}

function buildTopProducts(orders, itemsByOrder) {
  const sales = new Map();
  for (const order of orders) {
    for (const item of itemsByOrder.get(String(order.order_id)) ?? []) {
      const key = String(item.product_id ?? item.sku ?? item.product_name ?? 'unknown');
      const quantity = Math.trunc(toNumber(item.quantity, 1));
      const price = toNumber(item.unit_price);
      const existing = sales.get(key) ?? {
        id: item.product_id ?? item.sku ?? item.product_name,
        name: item.product_name,
        category: item.brand || 'RO Spares',
        img: item.img_src || 'purifier.jpg',
        unitsSold: 0,
        totalRevenue: 0,
      };
      existing.unitsSold += quantity;
      existing.totalRevenue += price * quantity;
      sales.set(key, existing);
    }
  }
  return [...sales.values()].sort((a, b) => b.unitsSold - a.unitsSold).slice(0, 5);
}

export function createAdminAnalyticsRepository(service, {clock = () => new Date()} = {}) {
  return {
    async getAnalytics(period = 'daily') {
      const normalizedPeriod = ['daily', 'weekly', 'monthly'].includes(String(period).toLowerCase())
        ? String(period).toLowerCase() : 'yearly';
      const [rawOrders, products] = await Promise.all([
        readAll(service, 'orders', ORDER_COLUMNS),
        readAll(service, 'products', PRODUCT_COLUMNS),
      ]);
      const rawItems = [];
      const orderIds = rawOrders.map(order => String(order.order_id));
      for (let start = 0; start < orderIds.length; start += 50) {
        const ids = orderIds.slice(start, start + 50);
        for (let offset = 0; ; offset += PAGE_SIZE) {
          const {data, error} = await service.from('order_items').select(ITEM_COLUMNS)
            .in('order_id', ids).range(offset, offset + PAGE_SIZE - 1);
          if (error) throw new AdminAnalyticsError(503, 'Analytics could not be generated.');
          const page = data ?? [];
          rawItems.push(...page);
          if (rawItems.length > MAX_ROWS) throw new AdminAnalyticsError(503, 'Analytics dataset exceeds the supported limit.');
          if (page.length < PAGE_SIZE) break;
        }
      }
      const itemsByOrder = new Map(orderIds.map(id => [id, []]));
      for (const item of rawItems) itemsByOrder.get(String(item.order_id))?.push(item);
      const orders = rawOrders.map(order => ({
        ...order,
        date: validDate(order.created_at),
        amount: toNumber(order.grand_total),
      }));
      const validOrders = orders.filter(order => String(order.status ?? '').toLowerCase() !== 'cancelled');
      const now = validDate(clock());
      const today = dayKey(now);
      const todayRevenue = validOrders.filter(order => dayKey(order.date) === today)
        .reduce((sum, order) => sum + order.amount, 0);
      const monthRevenue = validOrders.filter(order => order.date.getUTCMonth() === now.getUTCMonth() && order.date.getUTCFullYear() === now.getUTCFullYear())
        .reduce((sum, order) => sum + order.amount, 0);
      const totalRevenue = validOrders.reduce((sum, order) => sum + order.amount, 0);
      const lowStock = products.map(product => ({
        id: product.id,
        sku: product.sku,
        name: product.name,
        category: product.category_key,
        img: product.img,
        stock: Math.trunc(toNumber(product.stock_quantity, 50)),
        minStock: Math.trunc(toNumber(product.min_stock, 10)),
      })).filter(product => product.stock <= product.minStock)
        .sort((a, b) => a.stock - b.stock);
      return {
        success: true,
        revenue: {
          todayRevenue,
          monthRevenue,
          totalRevenue,
          totalOrders: orders.length,
          avgOrderValue: validOrders.length ? Math.floor(totalRevenue / validOrders.length + 0.5) : 0,
        },
        chart: makeChart(validOrders, normalizedPeriod, now),
        topProducts: buildTopProducts(validOrders, itemsByOrder),
        lowStock,
      };
    },
  };
}

export function createAdminAnalyticsHandler({authenticate, repository}) {
  return async request => {
    if (request.method === 'OPTIONS') return response({ok: true});
    if (request.method !== 'GET') return response({success: false, error: 'Method not allowed.'}, 405);
    try {
      const user = await authenticate(request);
      if (!user?.id || !user.email_confirmed_at) throw new AdminAnalyticsError(401, 'A verified sign-in is required.');
      if (!isVerifiedAdmin(user)) throw new AdminAnalyticsError(403, 'A verified administrator account is required.');
      const period = new URL(request.url).searchParams.get('period') ?? 'daily';
      return response(await repository.getAnalytics(period));
    } catch (error) {
      const status = error instanceof AdminAnalyticsError ? error.status : 500;
      const message = error instanceof AdminAnalyticsError ? error.message : 'Analytics could not be generated.';
      console.error('[SUPABASE ADMIN ANALYTICS]', `HTTP_${status}`);
      return response({success: false, error: message}, status);
    }
  };
}
