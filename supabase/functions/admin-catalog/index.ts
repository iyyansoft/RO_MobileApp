import { createClient, type User } from 'https://esm.sh/@supabase/supabase-js@2';
import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import {
  AdminCatalogError, createAdminCatalogHandler, normalizeCategoryInput,
  normalizeProductInput, parseImageDataUrl,
  prepareBulkProductRows,
} from '../_shared/admin_catalog_core.mjs';

const bucket = 'ro-product-images';

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  // Copy into an owned ArrayBuffer. Newer TypeScript definitions distinguish
  // ArrayBuffer from SharedArrayBuffer-backed Uint8Array views.
  const buffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(buffer).set(bytes);
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', buffer));
  return [...digest].map(value => value.toString(16).padStart(2, '0')).join('');
}

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new AdminCatalogError(503, 'Supabase Admin Catalog is not configured.');
  return value;
}

async function authenticate(request: Request): Promise<User | null> {
  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return null;
  const token = authorization.slice('Bearer '.length).trim();
  if (!token) return null;
  const client = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(token);
  return error ? null : data.user;
}

function serviceClient() {
  return createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

const service = serviceClient();

function databaseError(error: { code?: string } | null, fallback: string): never {
  if (error?.code === '42501') throw new AdminCatalogError(403, 'A verified administrator account is required.');
  if (error?.code === 'P0002') throw new AdminCatalogError(404, 'Catalog record not found.');
  if (error?.code === '23505') throw new AdminCatalogError(409, 'A product SKU or category key already exists.');
  if (error?.code === '23503') throw new AdminCatalogError(409, 'The selected category is still referenced by catalog data.');
  if (error?.code === 'P0001') throw new AdminCatalogError(409, 'The category cannot be deleted until a valid Spares fallback category exists.');
  throw new AdminCatalogError(503, fallback);
}

async function storeImage(
  value: unknown,
  folder: 'products' | 'categories',
  stableForBulk = false,
): Promise<string> {
  const raw = String(value ?? '').trim();
  if (!raw) return '';
  const parsed = parseImageDataUrl(raw);
  if (!parsed) {
    if (/^https:\/\//i.test(raw) ||
        (raw.startsWith('/') && !raw.startsWith('//') && !raw.includes('..') && !raw.includes('\\')) ||
        (/^[A-Za-z0-9._/-]+$/.test(raw) && !raw.includes('..'))) return raw;
    throw new AdminCatalogError(400, 'Image must be uploaded or use an existing image URL.');
  }
  let bytes: Uint8Array;
  try { bytes = Uint8Array.from(atob(parsed.base64), character => character.charCodeAt(0)); }
  catch { throw new AdminCatalogError(400, 'The selected image data is invalid.'); }
  if (!bytes.length || bytes.length > 5 * 1024 * 1024) throw new AdminCatalogError(400, 'Choose an image smaller than 5 MB.');
  const signatureMatches = parsed.extension === 'png'
    ? bytes.length >= 8 && [137, 80, 78, 71, 13, 10, 26, 10].every((value, index) => bytes[index] === value)
    : parsed.extension === 'jpg'
      ? bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255
      : bytes.length >= 12 &&
        String.fromCharCode(...bytes.slice(0, 4)) === 'RIFF' &&
        String.fromCharCode(...bytes.slice(8, 12)) === 'WEBP';
  if (!signatureMatches) throw new AdminCatalogError(400, 'The selected file does not match its image format.');
  let objectName: string = crypto.randomUUID();
  if (stableForBulk) {
    objectName = await sha256Hex(bytes);
  }
  const objectPath = `${folder}/${stableForBulk ? 'bulk/' : ''}${objectName}.${parsed.extension}`;
  const { error } = await service.storage.from(bucket).upload(objectPath, bytes, {
    contentType: parsed.mimeType,
    upsert: stableForBulk,
  });
  if (error) throw new AdminCatalogError(503, 'Product image storage is unavailable. No catalog change was saved.');
  return service.storage.from(bucket).getPublicUrl(objectPath).data.publicUrl;
}

function parseJson(value: unknown, fallback: unknown) {
  if (value && typeof value === 'object') return value;
  if (typeof value === 'string') {
    try { return JSON.parse(value); } catch { return fallback; }
  }
  return fallback;
}

function productApi(row: Record<string, unknown>) {
  return {
    ...row,
    category: row.category_key,
    purchase_price: Number(row.purchase_price ?? 0),
    purchasePrice: Number(row.purchase_price ?? 0),
    price: Number(row.price ?? 0),
    mrp: Number(row.mrp ?? 0),
    desc: row.description ?? '',
    specs: parseJson(row.specs_json, {}),
    features: parseJson(row.features_json, []),
  };
}

function categoryApi(row: Record<string, unknown>) {
  return { ...row, key: row.key_name, image: row.image_url };
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    const object = value as Record<string, unknown>;
    return `{${Object.keys(object).sort().map(key => `${JSON.stringify(key)}:${canonicalJson(object[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

async function requestFingerprint(adminUserId: string, rows: unknown[], skipped: unknown[]) {
  const bytes = new TextEncoder().encode(`${adminUserId}\n${canonicalJson({ rows, skipped })}`);
  return sha256Hex(bytes);
}

async function resolveCategory(value: string) {
  const { data, error } = await service.from('categories')
    .select('id,key_name,title')
    .order('display_order');
  if (error) databaseError(error, 'Categories could not be verified.');
  const wanted = value.trim().toLowerCase();
  const match = (data ?? []).find(row =>
    [row.id, row.key_name, row.title].some(candidate => String(candidate ?? '').trim().toLowerCase() === wanted),
  );
  if (!match) throw new AdminCatalogError(400, 'Select an existing product category.');
  return match;
}

async function findProduct(targetId: string) {
  let query = await service.from('products').select('*').eq('id', targetId).maybeSingle();
  if (query.error) databaseError(query.error, 'Product could not be loaded.');
  if (query.data) return query.data;
  if (/^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$/.test(targetId)) {
    query = await service.from('products').select('*').ilike('sku', targetId).maybeSingle();
    if (query.error) databaseError(query.error, 'Product could not be loaded.');
  }
  if (!query.data) throw new AdminCatalogError(404, 'Product not found.');
  return query.data;
}

async function ensureUniqueSku(sku: string, excludeId?: string) {
  const { data, error } = await service.from('products').select('id').ilike('sku', sku);
  if (error) databaseError(error, 'Product SKU could not be verified.');
  if ((data ?? []).some(row => row.id !== excludeId)) {
    throw new AdminCatalogError(409, `Product SKU "${sku}" is already used.`);
  }
}

async function ensureUniqueCategory(values: { key_name: string; title: string }, excludeId?: string) {
  const { data, error } = await service.from('categories').select('id,key_name,title');
  if (error) databaseError(error, 'Category could not be verified.');
  const duplicate = (data ?? []).find(row => row.id !== excludeId &&
    (String(row.key_name ?? '').toLowerCase() === values.key_name.toLowerCase() ||
     String(row.title ?? '').trim().toLowerCase() === values.title.trim().toLowerCase()));
  if (duplicate) throw new AdminCatalogError(409, 'Category key or name already exists.');
}

const repository = {
  async listProducts() {
    const { data, error } = await service.from('products').select('*').order('created_at', { ascending: false });
    if (error) databaseError(error, 'Product data could not be loaded.');
    const products = (data ?? []).map(row => productApi(row));
    return { count: products.length, products };
  },
  async createProduct(input: Record<string, unknown>) {
    const values = normalizeProductInput(input);
    await ensureUniqueSku(values.sku);
    const category = await resolveCategory(values.category);
    values.img = await storeImage(values.img, 'products');
    const row = {
      id: `prod_${crypto.randomUUID().replaceAll('-', '')}`,
      category_id: category.id,
      category_key: category.key_name,
      sku: values.sku,
      name: values.name,
      brand: values.brand,
      purchase_price: values.purchase_price,
      price: values.price,
      mrp: values.mrp,
      moq: values.moq,
      badge: values.badge,
      rating: values.rating,
      img: values.img || 'purifier.jpg',
      description: values.description,
      specs_json: values.specs_json,
      features_json: values.features_json,
      applications: values.applications,
      status: values.status,
      stock_quantity: values.stock_quantity,
      min_stock: values.min_stock,
    };
    const { data, error } = await service.from('products').insert(row).select('*').single();
    if (error) databaseError(error, 'Product could not be saved.');
    return productApi(data);
  },
  async updateProduct(targetId: string, input: Record<string, unknown>) {
    const existing = await findProduct(String(targetId ?? '').trim());
    const values = normalizeProductInput(input, { existing });
    await ensureUniqueSku(values.sku, String(existing.id));
    const category = await resolveCategory(values.category);
    values.img = await storeImage(values.img, 'products');
    const { data, error } = await service.from('products').update({
      category_id: category.id,
      category_key: category.key_name,
      sku: values.sku,
      name: values.name,
      brand: values.brand,
      purchase_price: values.purchase_price,
      price: values.price,
      mrp: values.mrp,
      moq: values.moq,
      badge: values.badge,
      rating: values.rating,
      img: values.img,
      description: values.description,
      specs_json: values.specs_json,
      features_json: values.features_json,
      applications: values.applications,
      status: values.status,
      stock_quantity: values.stock_quantity,
      min_stock: values.min_stock,
    }).eq('id', existing.id).select('*').single();
    if (error) databaseError(error, 'Product could not be updated.');
    return productApi(data);
  },
  async deactivateProduct(targetId: string) {
    const existing = await findProduct(String(targetId ?? '').trim());
    const { data, error } = await service.from('products').update({ status: 'inactive' })
      .eq('id', existing.id).select('id,name,status').single();
    if (error) databaseError(error, 'Product could not be removed from the active catalog.');
    return { product: data };
  },
  async listCategories() {
    const { data, error } = await service.from('categories').select('*').order('display_order');
    if (error) databaseError(error, 'Category data could not be loaded.');
    const categories = (data ?? []).map(row => categoryApi(row));
    return { count: categories.length, categories };
  },
  async createCategory(input: Record<string, unknown>, adminUserId: string) {
    const values = normalizeCategoryInput(input);
    values.image_url = await storeImage(values.image_url, 'categories');
    const { data, error } = await service.rpc('ro_admin_create_category', {
      p_admin_user_id: adminUserId,
      p_id: `CAT_${crypto.randomUUID().replaceAll('-', '')}`,
      p_values: values,
    });
    if (error) databaseError(error, 'Category could not be saved.');
    return categoryApi(data);
  },
  async updateCategory(targetId: string, input: Record<string, unknown>, adminUserId: string) {
    const { data: all, error } = await service.from('categories').select('*');
    if (error) databaseError(error, 'Category could not be loaded.');
    const target = String(targetId ?? '').trim().toLowerCase();
    const existing = (all ?? []).find(row => String(row.id).toLowerCase() === target || String(row.key_name).toLowerCase() === target);
    if (!existing) throw new AdminCatalogError(404, 'Category not found.');
    const values = normalizeCategoryInput(input, { existing });
    await ensureUniqueCategory(values, String(existing.id));
    values.image_url = await storeImage(values.image_url, 'categories');
    const { data: result, error: rpcError } = await service.rpc('ro_admin_update_category', {
      p_admin_user_id: adminUserId,
      p_category_id: String(existing.id),
      p_values: values,
    });
    if (rpcError) databaseError(rpcError, 'Category and its products could not be updated.');
    return categoryApi(result);
  },
  async deleteCategory(targetId: string, adminUserId: string) {
    const { data, error } = await service.rpc('ro_admin_delete_category', {
      p_admin_user_id: adminUserId,
      p_category_id: String(targetId ?? '').trim(),
    });
    if (error) {
      if (error.code === 'P0001') throw new AdminCatalogError(409, error.message);
      databaseError(error, 'Category could not be deleted.');
    }
    return data;
  },
  async bulkImportProducts(input: unknown, adminUserId: string) {
    const preparedInput = prepareBulkProductRows(input);

    const { data: categories, error: categoryError } = await service.from('categories')
      .select('id,key_name,title');
    if (categoryError) databaseError(categoryError, 'Categories could not be verified.');
    const categoryFor = (value: string) => {
      const wanted = value.trim().toLowerCase();
      return (categories ?? []).find(row =>
        [row.id, row.key_name, row.title].some(candidate => String(candidate ?? '').trim().toLowerCase() === wanted),
      );
    };

    const prepared: Record<string, unknown>[] = [];
    const skipped: { sku: string; reason: string }[] = [...preparedInput.skipped];
    for (const candidate of preparedInput.rows) {
      const index = candidate.sourceIndex - 1;
      const values = candidate.values;
      const sku = values.sku;
      try {
        const category = categoryFor(values.category);
        if (!category) throw new AdminCatalogError(400, `Category "${values.category}" does not exist in the database.`);
        values.img = await storeImage(values.img, 'products', true);
        prepared.push({
          id: `prod_${crypto.randomUUID().replaceAll('-', '')}`,
          category_id: category.id,
          category_key: category.key_name,
          sku: values.sku,
          name: values.name,
          brand: values.brand,
          purchase_price: values.purchase_price,
          price: values.price,
          mrp: values.mrp,
          moq: values.moq,
          badge: values.badge,
          rating: values.rating,
          img: values.img || 'purifier.jpg',
          description: values.description,
          specs_json: values.specs_json,
          features_json: values.features_json,
          applications: values.applications,
          status: values.status,
          stock_quantity: values.stock_quantity,
          min_stock: values.min_stock,
          _source_index: index + 1,
        });
      } catch (error) {
        if (!(error instanceof AdminCatalogError)) throw error;
        skipped.push({ sku: sku || 'UNKNOWN', reason: `Row ${index + 1}: ${error.message}` });
      }
    }

    if (prepared.length === 0) {
      return { importedCount: 0, skippedCount: skipped.length, imported: [], skipped, replayed: false };
    }
    const fingerprintRows = prepared.map(({ id, _source_index, ...row }) => row);
    const requestHash = await requestFingerprint(adminUserId, fingerprintRows, skipped);
    const databaseRows = prepared.map(({ _source_index, ...row }) => row);
    const { data, error } = await service.rpc('ro_admin_bulk_import_products', {
      p_admin_user_id: adminUserId,
      p_request_hash: requestHash,
      p_products: databaseRows,
      p_initial_skipped: skipped,
    });
    if (error) databaseError(error, 'The product batch could not be saved. No database rows were committed.');
    if (!data || typeof data !== 'object') throw new AdminCatalogError(503, 'The product import response was invalid.');
    const result = data as Record<string, unknown>;
    return {
      ...result,
      imported: Array.isArray(result.imported) ? result.imported.map(row => productApi(row as Record<string, unknown>)) : [],
    };
  },
};

serve(createAdminCatalogHandler({ authenticate, repository }));
