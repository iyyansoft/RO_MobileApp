'use strict';
// Read-only browsing of product pictures already uploaded to Supabase Storage
// (bucket ro-product-images). Used by the Admin "Choose from Supabase" picker.
//
// Listing a folder needs the service key (Storage has no public "list"
// permission), so it happens only here, on the server; the key is never sent to
// the browser. This module ONLY lists: it never uploads, renames, moves or
// deletes anything. Pictures are then used through their public URLs.

const STORAGE_BUCKET = 'ro-product-images';
// Folders that always exist (used when the bucket cannot be listed). The picker
// shows every top-level folder that actually exists in the bucket.
const STORAGE_FOLDERS = ['cabinets', 'pdf-catalog'];
// Preferred default folder per product category (category key_name): the first
// one that exists in the bucket is opened first. The admin can switch folders.
const CATEGORY_FOLDER_PREFERENCES = {
  cabinets: ['cabinets'],
  pumps: ['booster-pumps', 'pdf-catalog'],
  membranes: ['membrane', 'membranes', 'pdf-catalog'],
  systems: ['pdf-catalog'],
  filters: ['pdf-catalog'],
  pipes: ['pdf-catalog'],
  spares: ['pdf-catalog'],
};
const FOLDER_NAME = /^[A-Za-z0-9][A-Za-z0-9 _.-]{0,62}$/;
/** Default folder per category among the folders that exist. */
function categoryFolders(folders) {
  const out = {};
  for (const [category, prefs] of Object.entries(CATEGORY_FOLDER_PREFERENCES)) {
    const hit = prefs.find(f => folders.includes(f));
    if (hit) out[category] = hit;
  }
  return out;
}
const CATEGORY_FOLDERS = categoryFolders(STORAGE_FOLDERS);
const PAGE_SIZE = 100;
const IMAGE_FILE = /\.(jpe?g|png|webp|gif)$/i;

/** Public URL of an object: every path segment is encoded, so names with spaces or symbols work. */
function storagePublicUrl(supabaseUrl, objectPath) {
  const base = String(supabaseUrl || '').replace(/\/+$/, '');
  const encoded = String(objectPath).split('/').map(encodeURIComponent).join('/');
  return `${base}/storage/v1/object/public/${STORAGE_BUCKET}/${encoded}`;
}

/**
 * A product image value must be ONE thing: an absolute http(s) URL, a site path
 * (/api/product-images/..., /uploads/...), a bare file name (purifier.jpg), or an
 * uploaded data:image. Returns a message for anything else, e.g. two URLs run
 * together after pasting into the middle of an existing URL. Blank = no problem.
 */
function productImageProblem(value) {
  const text = String(value ?? '').trim();
  if (!text || /^data:image\//i.test(text)) return null;
  const joined = 'The image URL looks like two addresses joined together. Clear the field, paste the full URL once, and save again.';
  if (/\s/.test(text)) return 'The image URL must not contain spaces or line breaks (use %20 for spaces).';
  const schemes = text.match(/https?:\/\//gi) || [];
  if (/^https?:\/\//i.test(text)) {
    if (schemes.length > 1) return joined;
    try {
      const url = new URL(text);
      if (!url.hostname || !url.hostname.includes('.') && url.hostname !== 'localhost') return 'The image URL is not a valid web address.';
    } catch (_) { return 'The image URL is not a valid web address.'; }
    return null;
  }
  if (schemes.length || /^[a-z][a-z0-9+.-]*:/i.test(text)) return 'The image must start with https:// (or be a site path such as /api/product-images/...).';
  return null;
}

/** Checks the request against the folders that exist; returns { folder, search, offset } or { error }. */
function storageListRequest(query = {}, folders = STORAGE_FOLDERS) {
  const folder = String(query.folder ?? '').trim();
  if (!FOLDER_NAME.test(folder) || !folders.includes(folder)) return { error: `Unknown folder. Choose one of: ${folders.join(', ')}.` };
  const search = String(query.search ?? '').trim().slice(0, 100);
  const offset = query.offset === undefined || query.offset === '' ? 0 : Number(query.offset);
  if (!Number.isInteger(offset) || offset < 0 || offset > 100000) return { error: 'Invalid page offset.' };
  return { folder, search, offset };
}

/** Top-level folders that exist in the bucket (read-only list of the bucket root). */
async function listStorageFolders({ supabaseUrl, serviceKey, fetchImpl = fetch }) {
  const base = String(supabaseUrl || '').replace(/\/+$/, '');
  const folders = [];
  for (let offset = 0; offset < 2000; offset += PAGE_SIZE) {
    const entries = await listPage({ base, serviceKey, prefix: '', offset, fetchImpl });
    folders.push(...entries.filter(e => e && !e.id && FOLDER_NAME.test(e.name || '')).map(e => e.name));
    if (entries.length < PAGE_SIZE) break;
  }
  return folders.sort((a, b) => a.localeCompare(b));
}

async function listPage({ base, serviceKey, folder, prefix, offset, fetchImpl }) {
  const response = await fetchImpl(`${base}/storage/v1/object/list/${STORAGE_BUCKET}`, {
    method: 'POST',
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefix: prefix ?? `${folder}/`, limit: PAGE_SIZE, offset, sortBy: { column: 'name', order: 'asc' } }),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) {
    const error = new Error(`Storage list failed (HTTP ${response.status})`);
    error.status = response.status;
    throw error;
  }
  const entries = await response.json();
  if (!Array.isArray(entries)) throw new Error('Unexpected Storage response');
  return entries;
}

const toImage = (base, folder) => e => ({
  name: e.name,
  path: `${folder}/${e.name}`,
  url: storagePublicUrl(base, `${folder}/${e.name}`),
  size: Number(e.metadata?.size) || null,
  type: e.metadata?.mimetype || null,
  updatedAt: e.updated_at || null,
});
const isImage = e => e && e.id && e.name && IMAGE_FILE.test(e.name); // files only (folders have no id), pictures only
const MAX_SEARCH_SCAN = 5000;

/**
 * Lists one page (100) of pictures in an allowed folder.
 * Without a search: one Storage page at `offset`. With a search: the folder is
 * scanned page by page (Storage's own search only matches the start of a name)
 * and names CONTAINING the text (any case) are returned, 100 at a time.
 * Returns { images: [{ name, path, url, size, type, updatedAt }], offset, nextOffset, hasMore }.
 */
async function listStorageImages({ supabaseUrl, serviceKey, folder, search = '', offset = 0, fetchImpl = fetch }) {
  if (!FOLDER_NAME.test(String(folder || ''))) throw new Error('Unknown folder');
  const base = String(supabaseUrl || '').replace(/\/+$/, '');
  const needle = String(search || '').trim().toLowerCase();
  if (!needle) {
    const entries = await listPage({ base, serviceKey, folder, offset, fetchImpl });
    // A full page means there may be more (entries counts folders too).
    return { images: entries.filter(isImage).map(toImage(base, folder)), offset, nextOffset: offset + entries.length, hasMore: entries.length === PAGE_SIZE };
  }
  const matches = [];
  for (let at = 0; at < MAX_SEARCH_SCAN; at += PAGE_SIZE) {
    const entries = await listPage({ base, serviceKey, folder, offset: at, fetchImpl });
    matches.push(...entries.filter(e => isImage(e) && e.name.toLowerCase().includes(needle)));
    if (entries.length < PAGE_SIZE) break;
  }
  const page = matches.slice(offset, offset + PAGE_SIZE);
  return { images: page.map(toImage(base, folder)), offset, nextOffset: offset + page.length, hasMore: offset + PAGE_SIZE < matches.length };
}

module.exports = { STORAGE_BUCKET, STORAGE_FOLDERS, CATEGORY_FOLDERS, PAGE_SIZE, categoryFolders, storagePublicUrl, storageListRequest, listStorageFolders, listStorageImages, productImageProblem };
