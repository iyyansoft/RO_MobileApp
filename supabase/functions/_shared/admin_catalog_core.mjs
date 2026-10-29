export class AdminCatalogError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export const adminCatalogCors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function response(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...adminCatalogCors, 'Content-Type': 'application/json' },
  });
}

const text = (value, fallback = '') => String(value ?? fallback).trim();
const optionalNumber = (value, fallback, label) => {
  if (value === undefined || value === null || value === '') return fallback;
  const number = Number(value);
  if (!Number.isFinite(number)) throw new AdminCatalogError(400, `${label} must be a valid number.`);
  return number;
};
const boundedInteger = (value, fallback, label) => {
  const number = optionalNumber(value, fallback, label);
  if (!Number.isSafeInteger(number) || number < 0 || number > 2147483647) {
    throw new AdminCatalogError(400, `${label} must be a nonnegative whole number.`);
  }
  return number;
};

function bulkNumber(input, aliases, fallback, label) {
  const alias = aliases.find(key =>
    Object.hasOwn(input, key) && input[key] !== null && input[key] !== '' &&
    !(typeof input[key] === 'string' && !input[key].trim()),
  );
  if (alias === undefined) return fallback;
  const value = input[alias];
  if (!['number', 'string'].includes(typeof value) || (typeof value === 'string' && !value.trim())) {
    throw new AdminCatalogError(400, `${label} must be a valid number.`);
  }
  if (typeof value === 'string' && !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(value.trim())) {
    throw new AdminCatalogError(400, `${label} must be a valid number.`);
  }
  const number = Number(value);
  if (!Number.isFinite(number)) throw new AdminCatalogError(400, `${label} must be a valid number.`);
  return number;
}

function firstPresent(input, aliases, fallback = undefined) {
  for (const key of aliases) {
    if (Object.hasOwn(input, key) && input[key] !== undefined && input[key] !== null &&
        !(typeof input[key] === 'string' && !input[key].trim())) return input[key];
  }
  return fallback;
}

export function isTrustedAdmin(user) {
  return Boolean(user?.id && user?.email_confirmed_at && user?.app_metadata?.role === 'admin');
}

export function normalizeProductInput(input, { existing = null } = {}) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new AdminCatalogError(400, 'Product details are required.');
  }
  const name = text(input.name, existing?.name);
  const sku = text(input.sku, existing?.sku).toUpperCase();
  const category = text(input.category ?? input.category_key, existing?.category_key);
  const brand = text(input.brand, existing?.brand || 'RO Wholesale');
  const price = optionalNumber(input.price ?? input.dealer_price, existing?.price, 'Dealer price');
  const purchasePrice = optionalNumber(
    input.purchase_price ?? input.purchasePrice,
    existing?.purchase_price ?? 0,
    'Purchase price',
  );
  const mrp = optionalNumber(input.mrp, existing?.mrp ?? (price * 1.25), 'MRP');
  const stock = boundedInteger(input.stock_quantity ?? input.stock, existing?.stock_quantity ?? 50, 'Stock');
  const minStock = boundedInteger(input.min_stock ?? input.minStock, existing?.min_stock ?? 10, 'Minimum stock');
  if (!name || name.length > 512) throw new AdminCatalogError(400, 'Product name is required and must be at most 512 characters.');
  if (!/^[A-Z0-9][A-Z0-9._/-]{0,63}$/.test(sku)) throw new AdminCatalogError(400, 'Enter a valid SKU (letters, numbers, dot, underscore, slash or hyphen).');
  if (!category) throw new AdminCatalogError(400, 'Select an existing product category.');
  if (brand.length > 255) throw new AdminCatalogError(400, 'Brand must be at most 255 characters.');
  if (price === undefined || price <= 0 || price > 99999999.99) throw new AdminCatalogError(400, 'Enter a valid positive dealer price.');
  if (purchasePrice < 0 || purchasePrice > 99999999.99) throw new AdminCatalogError(400, 'Purchase price must be nonnegative.');
  if (mrp === undefined || mrp <= 0 || mrp > 99999999.99) throw new AdminCatalogError(400, 'Enter a valid positive MRP.');
  for (const [value, label] of [[input.badge, 'Badge'], [input.rating, 'Rating']]) {
    if (value !== undefined && value !== null && String(value).length > 64) {
      throw new AdminCatalogError(400, `${label} must be at most 64 characters.`);
    }
  }
  for (const [value, label] of [[price, 'Dealer price'], [purchasePrice, 'Purchase price'], [mrp, 'MRP']]) {
    if (Math.abs(value * 100 - Math.round(value * 100)) > 1e-7) {
      throw new AdminCatalogError(400, `${label} can have at most two decimal places.`);
    }
  }

  let specs = input.specs ?? existing?.specs_json ?? {};
  if (typeof specs === 'string') {
    try { specs = specs.trim() ? JSON.parse(specs) : {}; }
    catch { specs = { Specification: specs.trim() }; }
  }
  if (!specs || typeof specs !== 'object' || Array.isArray(specs)) {
    throw new AdminCatalogError(400, 'Specifications must be a JSON object.');
  }
  let features = input.features ?? existing?.features_json ?? [];
  if (typeof features === 'string') features = features.split(/[\n,]+/).map(value => value.trim()).filter(Boolean);
  if (!Array.isArray(features)) throw new AdminCatalogError(400, 'Features must be a list.');

  const rawMoq = input.moq === undefined ? existing?.moq : input.moq;
  const moq = rawMoq == null || String(rawMoq).trim() === ''
    ? 'MOQ: 1 Unit'
    : /^MOQ:/i.test(String(rawMoq).trim()) ? String(rawMoq).trim() : `MOQ: ${String(rawMoq).trim()}`;
  if (moq.length > 64) throw new AdminCatalogError(400, 'MOQ must be at most 64 characters.');
  const status = input.status === undefined
    ? existing?.status || 'active'
    : text(input.status).toLowerCase();
  if (!['active', 'inactive'].includes(status)) {
    throw new AdminCatalogError(400, 'Product status must be active or inactive.');
  }
  return {
    name, sku, category, brand,
    purchase_price: purchasePrice,
    price, mrp, moq,
    badge: text(input.badge, existing?.badge),
    rating: text(input.rating, existing?.rating || '★★★★★ (5.0)'),
    img: input.img === undefined && input.image === undefined
      ? text(existing?.img || 'purifier.jpg')
      : text(input.img ?? input.image),
    description: text(input.desc ?? input.description, existing?.description),
    specs_json: specs,
    features_json: features,
    applications: text(input.applications, existing?.applications || 'Commercial & Domestic Water Plants'),
    stock_quantity: stock,
    min_stock: minStock,
    status,
  };
}

// Canonicalize historical Excel/CSV header aliases on the trusted server.
// Frontend preview validation is useful for UX, but never authorizes a row.
export function normalizeBulkProductInput(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new AdminCatalogError(400, 'Product row must be an object.');
  }
  const name = firstPresent(input, ['name', 'product_name', 'productName', 'title', 'details', 'product_details']);
  const sku = firstPresent(input, ['sku', 'sku_code', 'product_code']);
  const category = firstPresent(input, ['category', 'category_key', 'category_name', 'category_id']);
  for (const [value, label] of [[name, 'Product name'], [sku, 'SKU'], [category, 'Category']]) {
    if (value !== undefined && typeof value !== 'string') throw new AdminCatalogError(400, `${label} must be text.`);
  }
  for (const [value, label] of [
    [firstPresent(input, ['brand']), 'Brand'],
    [firstPresent(input, ['img', 'image', 'image_url', 'imageUrl']), 'Image'],
    [firstPresent(input, ['desc', 'product_description', 'productDescription', 'description']), 'Description'],
    [firstPresent(input, ['status']), 'Status'],
    [firstPresent(input, ['badge']), 'Badge'],
    [firstPresent(input, ['rating']), 'Rating'],
    [firstPresent(input, ['applications']), 'Applications'],
  ]) {
    if (value !== undefined && typeof value !== 'string') throw new AdminCatalogError(400, `${label} must be text.`);
  }
  const dealerPrice = bulkNumber(input, ['price', 'dealer_price', 'dealerPrice'], 0, 'Dealer price');
  const purchasePrice = bulkNumber(input, ['purchase_price', 'purchasePrice', 'purchase'], 0, 'Purchase price');
  const mrp = bulkNumber(input, ['mrp', 'list_price'], dealerPrice * 1.25, 'MRP');
  const stock = bulkNumber(input, ['stock_quantity', 'stock', 'quantity'], 50, 'Stock');
  const minStock = bulkNumber(input, ['min_stock', 'minStock'], 10, 'Minimum stock');
  const brand = firstPresent(input, ['brand'], 'RO Wholesale');
  const rawMoq = firstPresent(input, ['moq', 'minimum_order_quantity'], '1');
  if (!['string', 'number'].includes(typeof rawMoq)) {
    throw new AdminCatalogError(400, 'MOQ must be a positive whole number.');
  }
  const moqText = String(rawMoq).trim();
  const moqMatch = /^(?:MOQ\s*:\s*)?(\d+)(?:\s*(?:unit|units|pcs|pieces))?$/i.exec(moqText);
  if (!moqMatch || Number(moqMatch[1]) < 1 || Number(moqMatch[1]) > 2147483647) {
    throw new AdminCatalogError(400, 'MOQ must be a positive whole number.');
  }
  const moq = /^MOQ\s*:/i.test(moqText)
    ? `MOQ: ${moqText.replace(/^MOQ\s*:\s*/i, '')}`
    : `MOQ: ${moqMatch[1]} Unit`;
  const image = firstPresent(input, ['img', 'image', 'image_url', 'imageUrl'], '');
  const description = firstPresent(input, ['desc', 'product_description', 'productDescription', 'description'], '');
  let specs = firstPresent(input, ['specs', 'specifications'], {});
  if (typeof specs === 'string') {
    try { specs = JSON.parse(specs); }
    catch { throw new AdminCatalogError(400, 'Specifications must contain valid JSON.'); }
  }
  if (!specs || typeof specs !== 'object' || Array.isArray(specs)) {
    throw new AdminCatalogError(400, 'Specifications must be a JSON object.');
  }
  const features = firstPresent(input, ['features'], []);
  if (typeof features !== 'string' && !Array.isArray(features)) {
    throw new AdminCatalogError(400, 'Features must be a list or comma-separated text.');
  }
  if (Array.isArray(features) && features.some(feature => typeof feature !== 'string')) {
    throw new AdminCatalogError(400, 'Each product feature must be text.');
  }
  const normalized = normalizeProductInput({
    name,
    sku,
    category,
    brand,
    purchase_price: purchasePrice,
    price: dealerPrice,
    mrp,
    stock_quantity: stock,
    min_stock: minStock,
    moq,
    img: image,
    desc: description,
    badge: firstPresent(input, ['badge'], ''),
    rating: firstPresent(input, ['rating'], undefined),
    specs,
    features,
    applications: firstPresent(input, ['applications'], undefined),
    status: firstPresent(input, ['status'], 'active'),
  });
  if (stock > 2147483647 || minStock > 2147483647) {
    throw new AdminCatalogError(400, 'Stock values must fit a nonnegative whole number.');
  }
  return normalized;
}

export function prepareBulkProductRows(input) {
  if (!Array.isArray(input) || input.length === 0) {
    throw new AdminCatalogError(400, 'No product rows provided for bulk import.');
  }
  if (input.length > 200) throw new AdminCatalogError(413, 'Import at most 200 products per batch.');
  const rows = [];
  const skipped = [];
  const seenSkus = new Set();
  input.forEach((raw, index) => {
    let sku = '';
    try {
      const values = normalizeBulkProductInput(raw);
      sku = values.sku;
      if (seenSkus.has(sku)) {
        skipped.push({ sku, reason: `Row ${index + 1}: duplicate SKU "${sku}" appears more than once in this file.` });
        return;
      }
      seenSkus.add(sku);
      rows.push({ sourceIndex: index + 1, values });
    } catch (error) {
      if (!(error instanceof AdminCatalogError)) throw error;
      const rawSku = raw && typeof raw === 'object' && !Array.isArray(raw)
        ? String(raw.sku ?? raw.sku_code ?? '').trim().toUpperCase()
        : '';
      skipped.push({ sku: sku || rawSku || 'UNKNOWN', reason: `Row ${index + 1}: ${error.message}` });
    }
  });
  return { rows, skipped };
}

export function normalizeCategoryInput(input, { existing = null } = {}) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new AdminCatalogError(400, 'Category details are required.');
  }
  const title = text(input.title ?? input.name, existing?.title);
  const keyName = text(input.key_name ?? input.key, existing?.key_name)
    .toLowerCase().replace(/\s+/g, '_');
  const displayOrder = boundedInteger(input.display_order, existing?.display_order ?? 1, 'Display order');
  const description = text(input.description, existing?.description);
  const badgeText = text(input.badge_text, existing?.badge_text || '⚡ B2B WHOLESALE');
  const iconColor = text(input.icon_color, existing?.icon_color || '#0F62FE');
  const imageUrl = input.image_url === undefined && input.image === undefined && input.img === undefined
    ? text(existing?.image_url || 'cat_spares.jpg')
    : text(input.image_url ?? input.image ?? input.img);
  if (!title || title.length > 128) throw new AdminCatalogError(400, 'Category title is required and must be at most 128 characters.');
  if (!/^[a-z0-9][a-z0-9_-]{0,63}$/.test(keyName)) throw new AdminCatalogError(400, 'Enter a valid category key.');
  if (badgeText.length > 64 || iconColor.length > 32) throw new AdminCatalogError(400, 'Badge text or icon color is too long.');
  return { title, key_name: keyName, description, badge_text: badgeText, icon_color: iconColor, image_url: imageUrl, display_order: displayOrder };
}

export function parseImageDataUrl(value) {
  const image = String(value ?? '');
  if (!image.startsWith('data:')) return null;
  const match = /^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/=\r\n]+)$/.exec(image);
  if (!match) throw new AdminCatalogError(400, 'Use a JPG, PNG or WEBP image.');
  const base64 = match[2].replace(/\s/g, '');
  const estimatedBytes = Math.floor(base64.length * 3 / 4) - (base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0);
  if (estimatedBytes <= 0 || estimatedBytes > 5 * 1024 * 1024) {
    throw new AdminCatalogError(400, 'Choose an image smaller than 5 MB.');
  }
  return {
    mimeType: `image/${match[1]}`,
    extension: match[1] === 'jpeg' ? 'jpg' : match[1],
    base64,
  };
}

export function createAdminCatalogHandler({ authenticate, repository }) {
  return async request => {
    if (request.method === 'OPTIONS') return response({ ok: true });
    if (request.method !== 'POST') return response({ success: false, error: 'Method not allowed.' }, 405);
    try {
      const user = await authenticate(request);
      if (!user?.id || !user.email_confirmed_at) throw new AdminCatalogError(401, 'A verified sign-in is required.');
      if (!isTrustedAdmin(user)) throw new AdminCatalogError(403, 'A verified administrator account is required.');
      const contentLength = Number(request.headers.get('content-length') ?? 0);
      if (contentLength > 8 * 1024 * 1024) throw new AdminCatalogError(413, 'The catalog request is too large.');
      let body;
      try {
        const rawBody = await request.text();
        if (new TextEncoder().encode(rawBody).byteLength > 8 * 1024 * 1024) {
          throw new AdminCatalogError(413, 'The catalog request is too large.');
        }
        body = JSON.parse(rawBody);
      }
      catch (error) {
        if (error instanceof AdminCatalogError) throw error;
        throw new AdminCatalogError(400, 'Invalid catalog request.');
      }
      if (!body || typeof body !== 'object' || Array.isArray(body)) throw new AdminCatalogError(400, 'Invalid catalog request.');
      const { action, targetId, values } = body;
      switch (action) {
        case 'list_products': return response({ success: true, ...(await repository.listProducts()) });
        case 'create_product': return response({ success: true, message: 'Product created.', product: await repository.createProduct(values) }, 201);
        case 'update_product': return response({ success: true, message: 'Product updated.', product: await repository.updateProduct(targetId, values) });
        case 'deactivate_product': return response({ success: true, message: 'Product removed from the active catalog.', ...(await repository.deactivateProduct(targetId)) });
        case 'list_categories': return response({ success: true, ...(await repository.listCategories()) });
        case 'create_category': return response({ success: true, message: 'Category created.', category: await repository.createCategory(values, user.id) }, 201);
        case 'update_category': return response({ success: true, message: 'Category updated.', category: await repository.updateCategory(targetId, values, user.id) });
        case 'delete_category': return response({ success: true, ...(await repository.deleteCategory(targetId, user.id)) });
        case 'bulk_import_products':
          return response({
            success: true,
            ...(await repository.bulkImportProducts(values?.products, user.id)),
          }, 201);
        default: throw new AdminCatalogError(400, 'Unsupported catalog operation.');
      }
    } catch (error) {
      const status = error instanceof AdminCatalogError ? error.status : 500;
      const message = error instanceof AdminCatalogError ? error.message : 'Catalog operation could not be completed.';
      console.error('[SUPABASE ADMIN CATALOG]', `HTTP_${status}`);
      return response({ success: false, error: message }, status);
    }
  };
}
