const express = require('express');
const cors = require('cors');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
const path = require('path');
const { pricingRules } = require('./pricing_rules');
const fs = require('fs');
const bcrypt = require('bcryptjs');
const { validGstin, createDealerToken, verifyDealerToken } = require('./checkout_service');
const { allocateDeliveryValues } = require('./shop_service');
const { createAdminAuth, adminTokenFrom } = require('./admin_auth');
const { releaseOrderStock, reReserveOrderStock } = require('./stock_service');
const { rewardSummary, requestRewardClaim, decideRewardClaim, reverseOrderReward, reinstateOrderReward, rewardLedgerReady } = require('./rewards');
const { purchaseMode, bulkQuantityProblem, modeConflict, bulkOrdersReady, bulkFields } = require('./bulk_orders');
const { rateLimit } = require('./rate_limit');
const { parseSpecifications, specificationLines, parseFeatures } = require('./product_info');
const { STORAGE_BUCKET, STORAGE_FOLDERS, CATEGORY_FOLDERS, categoryFolders, storageListRequest, listStorageFolders, listStorageImages, productImageProblem } = require('./storage_images');
const { requireDealerSession, DEALER_DATA_ROUTES } = require('./dealer_auth');
const { orderQuantityProblem, availability, minOrderQuantity, maxOrderQuantity, stockEnforced } = require('./order_rules');
const { ORDER_STATUSES, normalizeOrderStatus, normalizePaymentStatus, effectiveOrderStatus, orderStatusChangeError, paymentStatusChangeError } = require('./order_status');
require('dotenv').config();
const { createEmailSender, getEmailConfiguration } = require('./email_provider');

console.log('[EMAIL configuration]', JSON.stringify(getEmailConfiguration()));

const sendTransactionalEmail = createEmailSender({
  env: process.env,
  smtpTransportFactory: options => nodemailer.createTransport(options)
});

// Supabase PostgreSQL connection pool
const { pool, testConnection } = require('./db');

const app = express();
const PORT = process.env.PORT || 8080;
const isProduction = process.env.NODE_ENV === 'production';
const SESSION_SECRET = process.env.SESSION_SECRET || '';
if (isProduction) {
  const missingProductionConfig = [];
  if (SESSION_SECRET.length < 32) missingProductionConfig.push('SESSION_SECRET (32+ characters)');
  if (!process.env.SUPABASE_DB_URL) missingProductionConfig.push('SUPABASE_DB_URL');
  if (!process.env.SUPABASE_DB_SSL_CA && !process.env.SUPABASE_DB_SSL_CA_FILE) {
    missingProductionConfig.push('SUPABASE_DB_SSL_CA or SUPABASE_DB_SSL_CA_FILE');
  }
  if (!process.env.SUPABASE_URL) missingProductionConfig.push('SUPABASE_URL');
  if (!(process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY)) {
    missingProductionConfig.push('SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY)');
  }
  if (!process.env.SHOP_EMPLOYEE_SESSION_SECRET || process.env.SHOP_EMPLOYEE_SESSION_SECRET.length < 32) {
    missingProductionConfig.push('SHOP_EMPLOYEE_SESSION_SECRET (32+ characters)');
  }
  if (!process.env.ADMIN_EMAIL) missingProductionConfig.push('ADMIN_EMAIL');
  if (!process.env.ADMIN_PASSWORD || process.env.ADMIN_PASSWORD.length < 16) {
    missingProductionConfig.push('ADMIN_PASSWORD (16+ characters)');
  }
  if (missingProductionConfig.length) {
    throw new Error(`Missing required production configuration: ${missingProductionConfig.join(', ')}`);
  }
} else if (!SESSION_SECRET) {
  throw new Error('SESSION_SECRET must be configured before starting the backend.');
}

// Production-safe CORS configuration
const allowedOrigins = process.env.CORS_ORIGINS
  ? process.env.CORS_ORIGINS.split(',').map(o => o.trim())
  : [
      'https://romobileapp-production.up.railway.app',
      'http://localhost:8080',
      'http://127.0.0.1:8080'
    ];

app.use(cors({
  origin: function (origin, callback) {
    if (!origin) return callback(null, true);
    if (
      allowedOrigins.indexOf(origin) !== -1 ||
      process.env.NODE_ENV !== 'production' ||
      /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)
    ) {
      return callback(null, true);
    }
    return callback(null, false);
  },
  credentials: true
}));
// Behind Render's proxy the client address comes from X-Forwarded-For.
if (process.env.RENDER || process.env.TRUST_PROXY) app.set('trust proxy', 1);
// Request limits per client address: a general API cap, and a tight one for
// sign-in, one-time-code and password endpoints.
app.use('/api', rateLimit({ windowMs: 60 * 1000, max: Number(process.env.API_RATE_LIMIT_PER_MINUTE || 600), keyPrefix: 'api' }));
app.use([
  '/api/admin/login', '/api/auth/login', '/api/auth/send-otp', '/api/auth/verify-otp',
  '/api/auth/forgot-password', '/api/auth/reset-password', '/api/auth/signup',
  '/api/auth/google-signin', '/api/shop/auth/login',
], rateLimit({ windowMs: 15 * 60 * 1000, max: Number(process.env.AUTH_RATE_LIMIT_PER_15_MIN || 30), keyPrefix: 'auth', message: 'Too many sign-in attempts from this network. Please wait 15 minutes and try again.' }));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb', extended: true }));
// Customer data routes: only the signed-in dealer can read or change their
// own cart, orders, invoices, addresses, rewards and profile.
app.use(DEALER_DATA_ROUTES, requireDealerSession(SESSION_SECRET));

// Readiness endpoint used by Railway and deployment smoke tests. It exposes no
// database details and performs only a read-only query.
app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1 AS ok');
    return res.status(200).json({ status: 'ok' });
  } catch (_error) {
    return res.status(503).json({ status: 'unavailable' });
  }
});

// Ensure uploads directory exists & serve statically
const uploadsDir = path.join(__dirname, 'web_preview', 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}
app.use('/uploads', express.static(uploadsDir));
// Category/product images bundled with the app, served at /images/<filename>
app.use('/images', express.static(path.join(__dirname, 'assets', 'images'), { maxAge: '7d' }));
app.use(express.static(path.join(__dirname, 'web_preview')));

// Helper: Save uploaded base64 image file persistently
function saveUploadedFile(imageInput, prefix = 'prod') {
  if (!imageInput || typeof imageInput !== 'string') return '';
  const trimmed = imageInput.trim();
  if (!trimmed.startsWith('data:image/')) return trimmed;

  const match = trimmed.match(/^data:image\/([a-zA-Z0-9+\-+.]+);base64,(.+)$/);
  if (!match) return trimmed;

  let ext = match[1].toLowerCase();
  if (ext === 'jpeg') ext = 'jpg';
  const allowedExts = ['jpg', 'jpeg', 'png', 'webp'];
  if (!allowedExts.includes(ext)) {
    throw new Error('Unsupported image format. Allowed formats: JPG, JPEG, PNG, WEBP.');
  }

  const base64Data = match[2];
  const buffer = Buffer.from(base64Data, 'base64');
  const maxBytes = 5 * 1024 * 1024; // 5 MB
  if (buffer.length > maxBytes) {
    throw new Error('Image file size exceeds the 5 MB limit.');
  }

  const fileName = `${prefix}_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}.${ext}`;
  const filePath = path.join(uploadsDir, fileName);
  fs.writeFileSync(filePath, buffer);
  return `/uploads/${fileName}`;
}

// -----------------------------------------------------------------------------
// PRODUCT IMAGE STORAGE
// -----------------------------------------------------------------------------
// Images are kept permanently in the shared database (public.product_images,
// created by supabase/staging/006_product_images.sql) and served by every
// server from /api/product-images/<id>. Until that table exists they go to this
// server's uploads folder as before — which is local to one machine and wiped
// on each Render deploy. PRODUCT_IMAGE_STORE=disk|database overrides.
let productImageTableCheck = { available: false, checkedAt: 0 };
async function productImageStore() {
  const configured = String(process.env.PRODUCT_IMAGE_STORE || '').trim().toLowerCase();
  if (configured === 'disk' || configured === 'database') return configured;
  if (productImageTableCheck.available) return 'database';
  if (Date.now() - productImageTableCheck.checkedAt > 60 * 1000) {
    try {
      const [rows] = await pool.query("SELECT to_regclass('public.product_images') IS NOT NULL AS available");
      productImageTableCheck = { available: rows[0]?.available === true, checkedAt: Date.now() };
    } catch (_) {
      productImageTableCheck = { available: false, checkedAt: Date.now() };
    }
  }
  return productImageTableCheck.available ? 'database' : 'disk';
}
const PRODUCT_IMAGE_TYPES = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };

function decodeImageDataUrl(input) {
  const match = String(input).trim().match(/^data:image\/([a-zA-Z0-9+.-]+);base64,(.+)$/s);
  if (!match) throw new Error('Product image could not be read.');
  let ext = match[1].toLowerCase();
  if (ext === 'jpeg') ext = 'jpg';
  if (!PRODUCT_IMAGE_TYPES[ext]) throw new Error('Unsupported image format. Allowed formats: JPG, JPEG, PNG, WEBP.');
  const bytes = Buffer.from(match[2], 'base64');
  if (!bytes.length) throw new Error('Product image is empty.');
  if (bytes.length > 5 * 1024 * 1024) throw new Error('Image file size exceeds the 5 MB limit.');
  return { ext, bytes, contentType: PRODUCT_IMAGE_TYPES[ext] };
}

/** Saves a product/category image and returns the path to store. */
async function storeProductImage(imageInput, prefix = 'prod') {
  const raw = String(imageInput || '').trim();
  // The saved value is used as-is everywhere (app, web, share), so a broken one is refused, never stored.
  const problem = productImageProblem(raw);
  if (problem) throw new Error(problem);
  if (!raw.startsWith('data:image/')) return raw; // existing path or URL
  if ((await productImageStore()) !== 'database') return saveUploadedFile(raw, prefix);
  const { ext, bytes, contentType } = decodeImageDataUrl(raw);
  const id = `img_${Date.now()}_${crypto.randomBytes(6).toString('hex')}`;
  await pool.query(
    'INSERT INTO product_images (id, content_type, bytes) VALUES (?, ?, ?)',
    [id, contentType, bytes]
  );
  return `/api/product-images/${id}.${ext}`;
}

/**
 * Price rules shared by single, bulk and edit: purchase price may not be
 * negative, and MRP (when given) must be a number no lower than the dealer
 * price, because customers see MRP as the struck-through original price.
 */
function productPriceError({ purchasePrice, price, mrp }) {
  if (purchasePrice !== undefined && (isNaN(purchasePrice) || purchasePrice < 0)) {
    return 'Purchase price must be zero or more.';
  }
  if (mrp === undefined || mrp === null || String(mrp).trim() === '') return null;
  const cleanMrp = parseFloat(mrp);
  if (isNaN(cleanMrp) || cleanMrp <= 0) return 'MRP must be a valid amount.';
  // Compared only when a dealer price is set (0 = not set).
  if (price > 0 && cleanMrp < price) return 'MRP cannot be lower than the dealer price.';
  return null;
}

/**
 * One row of an Admin Excel / bulk product upload. Never invents a value:
 * stock must be entered (0 or more); rating, MOQ, brand, MRP, description,
 * specifications, features and applications stay empty when not given.
 * Existing SKUs are reported as 'duplicate' and are never updated.
 * Returns { status: 'ready'|'error'|'duplicate', errors, sku, name, image, product }.
 */
function validateBulkProductRow(raw, { resolveCategory, existingSkus, skusInUpload }) {
  const pick = (...keys) => { for (const k of keys) if (raw[k] !== undefined && raw[k] !== null) return raw[k]; return undefined; };
  const text = value => (isBlankField(value) ? '' : String(value).trim());
  const errors = [];
  const name = text(pick('name', 'product_name', 'productName', 'title', 'details', 'product_details'));
  const sku = text(pick('sku', 'sku_code')).toUpperCase();
  if (!name) errors.push('Product name is required.');
  if (!sku) errors.push('SKU is required.');
  else if (skusInUpload.has(sku)) errors.push(`SKU "${sku}" appears more than once in this upload.`);

  const rawPrice = pick('price', 'dealer_price', 'dealerPrice');
  const price = optionalAmount(rawPrice);
  if (isBlankField(rawPrice)) errors.push('Dealer price is required.');
  else if (isNaN(price) || price <= 0) errors.push('Dealer price must be greater than zero.');
  const purchasePrice = optionalAmount(pick('purchase_price', 'purchasePrice'));
  const rawMrp = pick('mrp');
  const priceError = productPriceError({ purchasePrice, price: isNaN(price) ? 0 : price, mrp: rawMrp });
  if (priceError) errors.push(priceError);

  const rawStock = pick('stock_quantity', 'stock');
  const stock = Number(text(rawStock));
  if (isBlankField(rawStock)) errors.push('Stock quantity is required (enter the counted stock, 0 or more).');
  else if (!Number.isSafeInteger(stock) || stock < 0 || stock > 2147483647) errors.push('Stock quantity must be a whole number, 0 or more.');
  const rawMinStock = pick('min_stock', 'minStock');
  const minStock = isBlankField(rawMinStock) ? 10 : Number(text(rawMinStock)); // low-stock alert threshold
  if (!Number.isSafeInteger(minStock) || minStock < 0) errors.push('Minimum stock alert must be a whole number, 0 or more.');

  const categoryInput = pick('category', 'category_key');
  const category = resolveCategory(categoryInput);
  if (!category) errors.push(isBlankField(categoryInput) ? 'Category is required.' : `Category "${text(categoryInput)}" does not exist.`);
  // Same rule as Add Product: Cabinet products need their own Cabinet Price.
  const cabinet = category ? cabinetPriceFor(isCabinetCategory(category.id, category.key), pick('cabinet_price', 'cabinetPrice')) : { value: null };
  if (cabinet.error) errors.push(cabinet.error);

  const parsedSpecs = parseSpecifications(pick('specs', 'specifications'));
  if (parsedSpecs.error) errors.push(parsedSpecs.error);
  const specs = parsedSpecs.value || {};
  const rawFeatures = pick('features', 'key_features');
  const features = Array.isArray(rawFeatures)
    ? rawFeatures.map(f => String(f).trim()).filter(Boolean)
    : text(rawFeatures).split(/\r?\n/).map(f => f.trim()).filter(Boolean);
  const moq = text(pick('moq', 'MOQ'));
  const rating = text(pick('rating'));
  const imageProblem = productImageProblem(text(pick('img', 'image')));
  if (imageProblem) errors.push(imageProblem);

  if (errors.length) return { status: 'error', errors, sku, name };
  if (existingSkus.has(sku)) {
    return { status: 'duplicate', errors: [`SKU "${sku}" already exists; the existing product is not changed.`], sku, name };
  }
  return {
    status: 'ready', errors: [], sku, name,
    image: text(pick('img', 'image')),
    product: {
      sku, name, category: category.key, category_id: category.id,
      brand: text(pick('brand')),
      purchase_price: purchasePrice, price, mrp: optionalAmount(rawMrp), cabinet_price: cabinet.value ?? null,
      stock_quantity: stock, min_stock: minStock,
      moq: moq ? (moq.startsWith('MOQ:') ? moq : `MOQ: ${moq}`) : null,
      badge: text(pick('badge')),
      rating: rating || null,
      desc: text(pick('desc', 'product_description', 'productDescription', 'description')),
      specs, features,
      applications: text(pick('applications')) || null,
      status: raw.status === 'inactive' ? 'inactive' : 'active',
    },
  };
}

/** An optional form field left empty (missing, null or only spaces). */
function isBlankField(value) {
  return value === undefined || value === null || String(value).trim() === '';
}

/**
 * Optional product money fields (Purchase Price, Dealer Price, MRP).
 * Blank -> `blankValue`; otherwise the number, or NaN when it is not a number
 * (callers reject NaN). The products table keeps these columns NOT NULL, so
 * "not set" is stored as 0, which the apps show as "Not set"/"Not available".
 */
function optionalAmount(value, blankValue = 0) {
  if (isBlankField(value)) return blankValue;
  if (typeof value !== 'number' && typeof value !== 'string') return NaN;
  const n = Number(String(value).trim());
  return Number.isFinite(n) ? n : NaN;
}

// --- Cabinet Price (products.cabinet_price, migration 009) -------------------
// Asked for, and required, only for products in the Cabinet category. Stored in
// its own column; Dealer Price, Purchase Price and MRP are never touched by it.
const CABINET_PRICE_REQUIRED = 'Cabinet Price is required for Cabinet products and must be greater than zero.';
const CABINET_PRICE_NO_COLUMN = 'Cabinet Price cannot be saved until the database update supabase/staging/009_product_cabinet_price.sql is applied. Nothing was saved.';

function isCabinetCategory(categoryId, categoryKey) {
  return String(categoryId || '').toUpperCase() === 'CAT_CAB' || String(categoryKey || '').toLowerCase() === 'cabinets';
}

let cabinetPriceColumnKnown = null;
/** True when products.cabinet_price exists (checked once, then remembered). */
async function hasCabinetPriceColumn() {
  if (cabinetPriceColumnKnown !== null) return cabinetPriceColumnKnown;
  try {
    const [rows] = await pool.query(
      `SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'cabinet_price' LIMIT 1`);
    cabinetPriceColumnKnown = Array.isArray(rows) && rows.length > 0;
    return cabinetPriceColumnKnown;
  } catch (_) {
    return false; // unknown: try again next time
  }
}

/** The Cabinet Price to save: null for other categories; a number > 0, or an error. */
function cabinetPriceFor(cabinet, raw, saved = null) {
  if (!cabinet) return { value: null };
  const value = optionalAmount(raw, saved);
  if (value === null || isNaN(value) || value <= 0) return { error: CABINET_PRICE_REQUIRED };
  return { value };
}

// Helper: Secure OTP Hash using SHA-256 HMAC
function hashOtp(email, otp) {
  return crypto
    .createHmac('sha256', SESSION_SECRET)
    .update(`${email.toLowerCase()}:${otp}`)
    .digest('hex');
}

// Verify Supabase PostgreSQL connection on startup
testConnection();

function logEmailFailure(stage, error) {
  console.error(`[EMAIL ${stage} failed]`, JSON.stringify({
    provider: error?.provider || 'unknown',
    code: error?.code || 'EMAIL_DELIVERY_FAILED',
    status: Number.isInteger(error?.status) ? error.status : null
  }));
}

// -----------------------------------------------------------------------------
// HELPER FUNCTIONS & UTILITIES
// -----------------------------------------------------------------------------

function fixEmailDomainTypo(emailStr) {
  if (!emailStr) return '';
  let clean = emailStr.trim().toLowerCase();
  clean = clean.replace(/@g(m|mi|ma|mai|maiil|mil|maill|aml|amail)\.com$/, '@gmail.com');
  clean = clean.replace(/@gma(l|ll|i)\.com$/, '@gmail.com');
  clean = clean.replace(/@gmai\.co$/, '@gmail.com');
  clean = clean.replace(/@yaho+\.com$/, '@yahoo.com');
  clean = clean.replace(/@yaho\.co$/, '@yahoo.com');
  clean = clean.replace(/@hotmial\.com$/, '@hotmail.com');
  clean = clean.replace(/@outlok\.com$/, '@outlook.com');
  return clean;
}

function isValidEmailAddress(emailStr) {
  if (!emailStr) return false;
  const clean = emailStr.trim().toLowerCase();
  const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
  if (!emailRegex.test(clean)) return false;

  const invalidDomainTypos = [
    'gmil.com', 'gmaill.com', 'gmal.com', 'gamil.com', 'gmai.com', 'gmall.com',
    'gmaill.co', 'gmai.co', 'gamel.com', 'gemail.com', 'gimail.com',
    'yaho.com', 'yahoo.co', 'ymail.co', 'hotmial.com', 'hotmai.com', 'outlok.com'
  ];

  const parts = clean.split('@');
  if (parts.length === 2 && invalidDomainTypos.includes(parts[1])) return false;
  return true;
}

// Reads city / state / pincode out of a typed address. Anything that is not
// in the text is left blank for the dealer to fill in — never guessed (it
// used to default to Salem/Chennai, Tamil Nadu, 600098).
function parseAddressString(rawAddress) {
  const clean = (rawAddress || '').trim();
  const pincodeMatch = clean.match(/\b\d{6}\b/);
  const lower = clean.toLowerCase();
  const knownCities = [
    ['chennai', 'Chennai', 'Tamil Nadu'], ['salem', 'Salem', 'Tamil Nadu'],
    ['coimbatore', 'Coimbatore', 'Tamil Nadu'], ['madurai', 'Madurai', 'Tamil Nadu'],
    ['trichy', 'Trichy', 'Tamil Nadu'], ['bengaluru', 'Bangalore', 'Karnataka'],
    ['bangalore', 'Bangalore', 'Karnataka'],
  ];
  const city = knownCities.find(([needle]) => lower.includes(needle));
  const typedState = ['tamil nadu', 'karnataka', 'kerala', 'andhra pradesh', 'telangana', 'puducherry']
    .find(state => lower.includes(state));
  return {
    street: clean,
    city: city ? city[1] : '',
    state: typedState ? typedState.replace(/\b\w/g, c => c.toUpperCase()) : (city ? city[2] : ''),
    pincode: pincodeMatch ? pincodeMatch[0] : ''
  };
}

function isDatabaseTrue(value) {
  return value === true || value === 1 || value === '1';
}

const memoryOtps = new Map();
// PostgreSQL-backed lookup helper: Lookup User by Email or Mobile Number
async function findUserByEmailOrMobile(identifier) {
  if (!identifier) return null;
  const cleanId = identifier.trim().toLowerCase();
  const cleanDigits = identifier.replace(/\D/g, '');

  try {
    const [rows] = await pool.query(
      `SELECT * FROM users WHERE email = ? OR (mobile IS NOT NULL AND mobile != '' AND mobile = ?) OR (mobile IS NOT NULL AND REPLACE(mobile, '-', '') = ?) LIMIT 1`,
      [cleanId, cleanId, cleanDigits]
    );
    if (rows && rows.length > 0) {
      const userRow = rows[0];

      // Fetch User Addresses
      const [addresses] = await pool.query(
        `SELECT * FROM user_addresses WHERE user_id = ? ORDER BY is_default DESC, created_at ASC`,
        [userRow.id]
      );

      // Fetch Rewards History
      const [rewards] = await pool.query(
        `SELECT * FROM rewards_history WHERE user_id = ? ORDER BY created_at DESC`,
        [userRow.id]
      );

      return {
        id: userRow.id,
        name: userRow.name,
        mobile: userRow.mobile || '',
        email: userRow.email,
        passwordHash: userRow.password_hash,
        emailVerified: isDatabaseTrue(userRow.email_verified),
        address: userRow.address || '',
        business: userRow.business_name || '',
        gstNumber: userRow.gst_number || '',
        owner: userRow.owner_name || userRow.name,
        status: userRow.status,
        isApproved: isDatabaseTrue(userRow.is_approved) || userRow.status === 'approved',
        createdAt: userRow.created_at ? new Date(userRow.created_at).toISOString() : new Date().toISOString(),
        rewardPoints: Number(userRow.reward_points || 0),
        addresses: (addresses || []).map(a => ({
          id: a.id,
          fullName: userRow.name,
          phone: a.phone || userRow.mobile || '',
          businessName: a.business_name || userRow.business_name || '',
          street: a.street || '',
          area: '',
          city: a.city || '',
          state: a.state || '',
          pincode: a.pincode || '',
          addressType: 'Office',
          label: a.label || 'Main Warehouse',
          isDefault: isDatabaseTrue(a.is_default)
        })),
        rewardsHistory: (rewards || []).map(r => ({
          orderId: r.order_id,
          orderAmount: parseFloat(r.order_amount),
          pointsEarned: r.points_earned,
          date: r.created_at ? new Date(r.created_at).toISOString() : new Date().toISOString()
        }))
      };
    }
  } catch (dbErr) {
    // PostgreSQL is authoritative. Never substitute local JSON records.
    throw dbErr;
  }
  return null;
}

// Authentication always uses active PostgreSQL records.
async function findAuthUserByEmailOrMobile(identifier) {
  if (!identifier) return null;
  const cleanId = String(identifier).trim().toLowerCase();
  const cleanDigits = String(identifier).replace(/\D/g, '');
  const isEmail = cleanId.includes('@');
  if (!isEmail && !/^(?:91)?\d{10}$/.test(cleanDigits)) return null;
  const [rows] = await pool.query(
    isEmail
      ? 'SELECT * FROM users WHERE LOWER(email) = ? LIMIT 1'
      : `SELECT * FROM users
         WHERE mobile IS NOT NULL AND mobile != ''
           AND RIGHT(REGEXP_REPLACE(mobile, '[^0-9]', '', 'g'), 10) = RIGHT(?, 10)
         LIMIT 1`,
    [isEmail ? cleanId : cleanDigits]
  );
  if (!rows.length) return null;
  const userRow = rows[0];
  const [addresses] = await pool.query(
    'SELECT * FROM user_addresses WHERE user_id = ? ORDER BY is_default DESC, created_at ASC',
    [userRow.id]
  );
  const [rewards] = await pool.query(
    'SELECT * FROM rewards_history WHERE user_id = ? ORDER BY created_at DESC',
    [userRow.id]
  );
  return {
    id: userRow.id,
    name: userRow.name,
    mobile: userRow.mobile || '',
    email: userRow.email,
    passwordHash: userRow.password_hash,
    // Only an explicit PostgreSQL true represents a verified email.
    emailVerified: isDatabaseTrue(userRow.email_verified),
    address: userRow.address || '',
    business: userRow.business_name || '',
    gstNumber: userRow.gst_number || '',
    owner: userRow.owner_name || userRow.name,
    status: userRow.status,
    isApproved: isDatabaseTrue(userRow.is_approved) || userRow.status === 'approved',
    createdAt: userRow.created_at ? new Date(userRow.created_at).toISOString() : new Date().toISOString(),
    rewardPoints: Number(userRow.reward_points || 0),
    addresses: (addresses || []).map(a => ({
      id: a.id,
      fullName: userRow.name,
      phone: a.phone || userRow.mobile || '',
      businessName: a.business_name || userRow.business_name || '',
      street: a.street || '',
      area: '',
      city: a.city || '',
      state: a.state || '',
      pincode: a.pincode || '',
      addressType: 'Office',
      label: a.label || 'Main Warehouse',
      isDefault: isDatabaseTrue(a.is_default)
    })),
    rewardsHistory: (rewards || []).map(r => ({
      orderId: r.order_id,
      orderAmount: parseFloat(r.order_amount),
      pointsEarned: r.points_earned,
      date: r.created_at ? new Date(r.created_at).toISOString() : new Date().toISOString()
    }))
  };
}

// -----------------------------------------------------------------------------
// REST API ENDPOINTS
// -----------------------------------------------------------------------------

// 0. Auth Config Endpoint
app.get('/api/auth/config', (req, res) => {
  res.json({
    googleClientId: process.env.GOOGLE_CLIENT_ID || '',
    // Public deployment diagnostic only; enforcement remains server-side.
    dealerPasswordLogin: {
      requiresAdminApproval: false,
      requiresEmailVerification: false
    }
  });
});

// 1. Send OTP Endpoint
app.get('/api/auth/session', async (req, res) => {
  const identity = verifyDealerToken(String(req.headers.authorization || '').replace(/^Bearer /, ''), SESSION_SECRET);
  if (!identity) return res.status(401).json({success:false,error:'Please sign in again.'});
  let user;
  try { user = await findAuthUserByEmailOrMobile(identity.email); }
  catch (error) {
    console.error('[API ERROR] Session database lookup failed:', error.code || 'DB_ERROR');
    return res.status(503).json({ success: false, error: 'Account service is temporarily unavailable.' });
  }
  if (!user || user.id !== identity.id) return res.status(401).json({success:false,error:'This registered account is no longer active.'});
  if (user.status === 'rejected') return res.status(403).json({success:false,status:'rejected',isApproved:false,error:'This account is not approved for login.'});
  if (user.emailVerified !== true) {
    return res.status(403).json({success:false,error:'Verify your email before signing in.'});
  }
  return res.json({success:true,user:{id:user.id,name:user.name,email:user.email,mobile:user.mobile,address:user.address,business:user.business||'',gstNumber:user.gstNumber||'',status:user.status,isApproved:user.isApproved,token:String(req.headers.authorization).replace(/^Bearer /, '')}});
});

// Exchange a verified Supabase Auth JWT for the existing RO dealer API token.
// This bridge keeps the current profile/cart/checkout routes working while
// Flutter Auth is migrated; it validates the bearer with Supabase Auth and
// never accepts a client-supplied dealer ID or email as identity.
app.post('/api/auth/supabase/exchange', async (req, res) => {
  const authorization = String(req.headers.authorization || '');
  const accessToken = authorization.replace(/^Bearer\s+/i, '').trim();
  const supabaseUrl = String(process.env.SUPABASE_URL || '').replace(/\/+$/, '');
  const anonKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '';
  if (!supabaseUrl || !anonKey) {
    return res.status(503).json({ success: false, error: 'Supabase authentication bridge is not configured.' });
  }
  if (!accessToken) return res.status(401).json({ success: false, error: 'Please sign in again.' });
  try {
    const authResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}` },
      signal: AbortSignal.timeout(10000)
    });
    if (!authResponse.ok) return res.status(401).json({ success: false, error: 'Supabase session is invalid or expired.' });
    const authUser = await authResponse.json();
    const email = String(authUser.email || '').trim().toLowerCase();
    const verified = Boolean(authUser.email_confirmed_at || authUser.confirmed_at);
    if (!authUser.id || !email || !verified) {
      return res.status(403).json({ success: false, error: 'Verify your email before signing in.' });
    }
    const [rows] = await pool.query(
      'SELECT id, email, mobile, name, address, business_name, gst_number, status, is_approved FROM users WHERE auth_user_id = ? LIMIT 1',
      [String(authUser.id)]
    );
    const user = rows[0];
    if (!user || String(user.email).trim().toLowerCase() !== email) {
      return res.status(409).json({ success: false, error: 'Dealer profile is not linked. Sign in again after profile setup.' });
    }
    if (user.status === 'rejected') return res.status(403).json({ success: false, error: 'This account is not approved for login.' });
    const dealer = {
      id: String(user.id), email, mobile: user.mobile || '', name: user.name || '',
      address: user.address || '', business: user.business_name || '',
      gstNumber: user.gst_number || '', status: user.status || 'pending',
      isApproved: user.is_approved === true
    };
    const token = createDealerToken(dealer, SESSION_SECRET);
    return res.json({ success: true, token, user: { ...dealer, token } });
  } catch (error) {
    console.error('[API ERROR] Supabase dealer token exchange failed:', error.code || error.name || 'AUTH_BRIDGE_ERROR');
    return res.status(503).json({ success: false, error: 'Account service is temporarily unavailable.' });
  }
});
app.post('/api/auth/send-otp', async (req, res) => {
  try {
    const email = String(req.body.email || '').trim().toLowerCase();
    if (!isValidEmailAddress(email)) return res.status(400).json({ success: false, error: 'Enter a valid registered email address.' });
    // OTP delivery for signup/login must target an account in PostgreSQL.
    const [userRows] = await pool.query(
      'SELECT id, email, status FROM users WHERE LOWER(email) = LOWER(?) LIMIT 1',
      [email]
    );
    const user = userRows[0] || null;
    if (!user || user.email.toLowerCase() !== email) return res.status(404).json({ success: false, error: 'Email is not registered. Please sign up first.' });
    if (user.status === 'rejected') return res.status(403).json({ success: false, error: 'This account is not approved for login.' });
    const previous = memoryOtps.get(email);
    if (previous && Date.now() - previous.sentAt < 30000) return res.status(429).json({ success: false, error: 'Wait 30 seconds before requesting another code.' });
    const [recentCodes] = await pool.query("SELECT created_at > CURRENT_TIMESTAMP - INTERVAL '30 seconds' AS cooling_down FROM otp_codes WHERE email = ? ORDER BY created_at DESC LIMIT 1", [email]);
    if (recentCodes[0]?.cooling_down === true) {
      return res.status(429).json({ success: false, error: 'Wait 30 seconds before requesting another code.' });
    }
    const otp = crypto.randomInt(100000, 1000000).toString();
    let delivery;
    try {
      delivery = await sendTransactionalEmail({ to: user.email, subject: 'Your RO Wholesale email verification code', text: 'Your RO Wholesale email verification code is ' + otp + '. Valid for 5 minutes. Do not share this code.', html: '<div style="font-family:Arial;padding:24px;max-width:500px;color:#0F4C81"><h2>RO Wholesale</h2><p>Your email verification code:</p><strong style="font-size:32px;letter-spacing:6px">' + otp + '</strong><p>Valid for 5 minutes. Do not share this code.</p></div>' });
    } catch (mailError) {
      logEmailFailure('OTP delivery', mailError);
      return res.status(502).json({ success: false, error: 'Could not send the email code. Please try again.' });
    }
    if (!delivery?.accepted?.some(recipient => String(recipient).toLowerCase() === email)) {
      logEmailFailure('OTP recipient rejected', { provider: delivery?.provider, code: 'RECIPIENT_REJECTED' });
      return res.status(502).json({ success: false, error: 'The email server rejected delivery.' });
    }
    const record = { otp: hashOtp(email, otp), expiresAt: Date.now() + 300000, sentAt: Date.now(), attempts: 0 };
    try {
      // Replace the previous code in one atomic PostgreSQL statement.
      await pool.query("WITH removed AS (DELETE FROM otp_codes WHERE email = ?) INSERT INTO otp_codes (email, otp_code, expires_at, attempts) VALUES (?, ?, CURRENT_TIMESTAMP + INTERVAL '5 minutes', 0)", [email, email, record.otp]);
    } catch (error) {
      console.error('[OTP persistence failed]', error.code || 'DB_ERROR');
      return res.status(503).json({ success: false, error: 'The code could not be saved. Request a new email code.' });
    }
    memoryOtps.set(email, record);
    return res.json({ success: true, email, message: 'OTP sent to your registered email.' });
  } catch (error) {
    console.error('[API ERROR] OTP account lookup failed:', error.code || 'DB_ERROR');
    return res.status(503).json({ success: false, error: 'Email verification is temporarily unavailable. Please try again.' });
  }
});

// 2. Verify OTP Endpoint
app.post('/api/auth/verify-otp', async (req, res) => {
  try {
    const email = String(req.body.email || '').trim().toLowerCase(), otp = String(req.body.otp || '').trim();
    if (!isValidEmailAddress(email) || !/^\d{6}$/.test(otp)) return res.status(400).json({ success: false, error: 'Enter your email and complete six-digit code.' });
    const user = await findAuthUserByEmailOrMobile(email);
    if (!user) return res.status(404).json({ success: false, error: 'Email is not registered. Please sign up.' });
    if (user.status === 'rejected') return res.status(403).json({ success: false, error: 'This account is not approved for login.' });
    // PostgreSQL is authoritative, including after a Render restart or when
    // another instance has already consumed the code or counted an attempt.
    const [rows] = await pool.query('SELECT otp_code, attempts, expires_at > CURRENT_TIMESTAMP AS unexpired FROM otp_codes WHERE email = ? ORDER BY created_at DESC LIMIT 1', [email]);
    const record = rows[0] ? { otp: rows[0].otp_code, unexpired: rows[0].unexpired === true, attempts: rows[0].attempts || 0 } : null;
    const actual = hashOtp(email, otp);
    const valid = record && record.unexpired && record.attempts < 5 && record.otp.length === actual.length && crypto.timingSafeEqual(Buffer.from(record.otp), Buffer.from(actual));
    if (!valid) {
      if (record) await pool.query('UPDATE otp_codes SET attempts = attempts + 1 WHERE email = ? AND otp_code = ?', [email, record.otp]);
      return res.status(400).json({ success: false, error: 'Code is invalid, expired, or has too many attempts. Request a new code.' });
    }
    const [verified] = await pool.query(
      `WITH consumed AS (
        DELETE FROM otp_codes WHERE email = ? AND otp_code = ?
          AND expires_at > CURRENT_TIMESTAMP AND attempts < 5 RETURNING email
      ) UPDATE users SET email_verified = TRUE WHERE id = ?
        AND EXISTS (SELECT 1 FROM consumed)`,
      [email, actual, user.id]
    );
    if (!verified.affectedRows) return res.status(400).json({ success: false, error: 'Code is invalid, expired, or has already been used.' });
    user.emailVerified = true;
    memoryOtps.delete(email);
    if (user.status === 'rejected') return res.status(403).json({ success: false, error: 'This account is not approved for login.' });
    const token = createDealerToken(user, SESSION_SECRET);
    return res.json({ success: true, token, user: { id: user.id, name: user.name, email: user.email, mobile: user.mobile, address: user.address, business: user.business || '', gstNumber: user.gstNumber || '', status: user.status || 'approved', isApproved: user.isApproved, addresses: user.addresses || [], token } });
  } catch (error) {
    console.error('[API ERROR] OTP verification database operation failed:', error.code || 'DB_ERROR');
    return res.status(503).json({ success: false, error: 'Email verification is temporarily unavailable. Please try again.' });
  }
});

// Password recovery uses the same delivered, hashed, expiring email OTP records.
app.post('/api/auth/forgot-password', async (req, res) => {
  try {
    const email = String(req.body.email || '').trim().toLowerCase();
    if (!isValidEmailAddress(email)) return res.status(400).json({ success: false, error: 'Enter a valid email address.' });
    const user = await findUserByEmailOrMobile(email);
    if (!user || user.email.toLowerCase() !== email) return res.status(404).json({ success: false, error: 'Email is not registered. Please sign up first.' });
    if (user.status === 'rejected') return res.status(403).json({ success: false, error: 'This account is not approved for login.' });
    const previous = memoryOtps.get(email);
    if (previous && Date.now() - previous.sentAt < 30000) return res.status(429).json({ success: false, error: 'Wait 30 seconds before requesting another code.' });
    const otp = crypto.randomInt(100000, 1000000).toString();
    let delivery;
    try {
      delivery = await sendTransactionalEmail({
        to: user.email,
        subject: 'Reset your RO Wholesale password',
        text: `Your RO Wholesale password reset code is ${otp}. Valid for 5 minutes. Do not share this code.`,
        html: `<div style="font-family:Arial;padding:24px;max-width:500px;color:#0F4C81"><h2>RO Wholesale</h2><p>Your password reset verification code:</p><strong style="font-size:32px;letter-spacing:6px">${otp}</strong><p>Valid for 5 minutes. Do not share this code.</p></div>`
      });
    } catch (mailError) {
      logEmailFailure('password recovery delivery', mailError);
      return res.status(502).json({ success: false, error: 'Could not send the email code. Please try again.' });
    }
    if (!delivery?.accepted?.some(recipient => String(recipient).toLowerCase() === email)) {
      logEmailFailure('recovery recipient rejected', { provider: delivery?.provider, code: 'RECIPIENT_REJECTED' });
      return res.status(502).json({ success: false, error: 'The email server rejected delivery.' });
    }
    const record = { otp: hashOtp(email, otp), expiresAt: Date.now() + 300000, sentAt: Date.now(), attempts: 0 };
    memoryOtps.set(email, record);
    try {
      await pool.query('DELETE FROM otp_codes WHERE email = ?', [email]);
      await pool.query("INSERT INTO otp_codes (email, otp_code, expires_at, attempts) VALUES (?, ?, CURRENT_TIMESTAMP + INTERVAL '5 minutes', 0)", [email, record.otp]);
    } catch (_) { /* The sent code remains available to this live server process. */ }
    return res.json({ success: true, email, message: 'Password reset code sent to your registered email.' });
  } catch (_) { return res.status(500).json({ success: false, error: 'Could not request the password reset code.' }); }
});

app.post('/api/auth/reset-password', async (req, res) => {
  try {
    const email = String(req.body.email || '').trim().toLowerCase();
    const otp = String(req.body.otp || '').trim();
    const password = String(req.body.password || '');
    const confirmPassword = String(req.body.confirmPassword || '');
    if (!isValidEmailAddress(email) || !/^\d{6}$/.test(otp) || password.length < 8 || password !== confirmPassword) {
      return res.status(400).json({ success: false, error: 'Enter a valid email, six-digit code, and matching password (at least 8 characters).' });
    }
    const user = await findUserByEmailOrMobile(email);
    if (!user || user.email.toLowerCase() !== email) return res.status(404).json({ success: false, error: 'Account not found.' });
    let record = memoryOtps.get(email), fromMemory = Boolean(record);
    if (!record) {
      const [rows] = await pool.query('SELECT otp_code, expires_at, attempts FROM otp_codes WHERE email = ? ORDER BY created_at DESC LIMIT 1', [email]);
      if (rows.length) record = { otp: rows[0].otp_code, expiresAt: new Date(rows[0].expires_at).getTime(), attempts: rows[0].attempts || 0 };
    }
    const actual = hashOtp(email, otp);
    const valid = record && record.expiresAt > Date.now() && record.attempts < 5 && record.otp.length === actual.length && crypto.timingSafeEqual(Buffer.from(record.otp), Buffer.from(actual));
    if (!valid) {
      if (record) record.attempts++;
      try { await pool.query('UPDATE otp_codes SET attempts = attempts + 1 WHERE email = ?', [email]); } catch (_) {}
      return res.status(400).json({ success: false, error: 'Code is invalid, expired, or has too many attempts. Request a new code.' });
    }
    if (record) record.expiresAt = 0;
    try {
      const [removed] = await pool.query('DELETE FROM otp_codes WHERE email = ? AND otp_code = ?', [email, actual]);
      if (!fromMemory && !removed.affectedRows) return res.status(400).json({ success: false, error: 'This code has already been used.' });
    } catch (_) { if (!fromMemory) return res.status(503).json({ success: false, error: 'Could not verify the code. Try again.' }); }
    memoryOtps.delete(email);
    const passwordHash = await bcrypt.hash(password, 10);
    await pool.query('UPDATE users SET password_hash = ?, email_verified = TRUE WHERE email = ?', [passwordHash, email]);
    return res.json({ success: true, message: 'Password reset successfully.' });
  } catch (error) {
    console.error('[API ERROR] Password reset:', error.message);
    return res.status(503).json({ success: false, error: 'Password reset could not be saved. Please try again.' });
  }
});

// 3. Sign Up Endpoint (email verification is required before dealer access)
app.post('/api/auth/signup', async (req, res) => {
  let connection;
  try {
    const name = String(req.body.name || '').trim(), email = String(req.body.email || '').trim().toLowerCase(), address = String(req.body.address || '').trim();
    const mobile = String(req.body.mobile || '').trim(), password = String(req.body.password || ''), confirmPassword = String(req.body.confirmPassword || '');
    const company = String(req.body.companyName || req.body.businessName || '').trim(), gst = String(req.body.gstNumber || '').trim().toUpperCase();
    if (!name || !isValidEmailAddress(email) || password.length < 8 || password !== confirmPassword) return res.status(400).json({ success: false, error: 'Name, valid email, password (at least 8 characters) and matching confirmation are required.' });
    if (!/^\d{10}$/.test(mobile)) return res.status(400).json({ success: false, field: 'mobile', error: 'Enter a valid 10-digit mobile number.' });
    if (gst && !validGstin(gst)) return res.status(400).json({ success: false, error: 'Enter a valid GST number or leave it blank.' });
    // Registration uniqueness is authoritative in PostgreSQL.
    connection = await pool.getConnection();
    const [emailRows] = await connection.query(
      'SELECT id FROM users WHERE LOWER(email) = LOWER(?) LIMIT 1',
      [email]
    );
    if (emailRows.length) return res.status(409).json({ success: false, field: 'email', error: 'An account with this email already exists.' });
    const [mobileRows] = await connection.query(
      "SELECT id FROM users WHERE RIGHT(REGEXP_REPLACE(COALESCE(mobile, ''), '[^0-9]', '', 'g'), 10) = ? LIMIT 1",
      [mobile]
    );
    if (mobileRows.length) return res.status(409).json({ success: false, field: 'mobile', error: 'An account with this mobile number already exists.' });
    const id = 'DEALER_' + crypto.randomUUID(), hash = await bcrypt.hash(password, 10), parsed = parseAddressString(address), addressId = 'ADDR_' + crypto.randomUUID();
    await connection.beginTransaction();
    // Signup does not verify an email or grant an admin/employee role.
    // Approval fields remain admin-managed metadata, independent of login.
    await connection.query("INSERT INTO users (id, email, mobile, name, password_hash, email_verified, business_name, owner_name, address, gst_number, status, is_approved, reward_points) VALUES (?, ?, ?, ?, ?, TRUE, ?, ?, ?, ?, 'pending', FALSE, 0)", [id, email, mobile || null, name, hash, company, name, address || null, gst || null]);
    if (address) await connection.query("INSERT INTO user_addresses (id, user_id, label, business_name, street, city, state, pincode, phone, gst_number, is_default) VALUES (?, ?, 'Main address', ?, ?, ?, ?, ?, ?, ?, TRUE)", [addressId, id, company, address, parsed.city || '', parsed.state || '', parsed.pincode || '', mobile, gst]);
    await connection.commit();
    return res.json({ success: true, status: 'pending', isApproved: false, requiresEmailVerification: false, message: 'Account created. Sign in with your email and password.' });
  } catch (error) {
    if (connection) await connection.rollback().catch(() => {});
    if (error.code === 'ER_DUP_ENTRY') {
      const key = String(error.message || '').toLowerCase();
      if (key.includes('uk_users_mobile') || key.includes('users.mobile')) {
        return res.status(409).json({ success: false, field: 'mobile', error: 'An account with this mobile number already exists.' });
      }
      if (key.includes('uk_users_email') || key.includes('users.email')) {
        return res.status(409).json({ success: false, field: 'email', error: 'An account with this email already exists.' });
      }
      console.error('[API ERROR] Registration hit an unexpected unique constraint.');
      return res.status(503).json({ success: false, error: 'Registration could not be saved to database. Please try again.' });
    }
    console.error('[API ERROR] Registration database operation failed:', error.code || 'DB_ERROR');
    return res.status(503).json({ success: false, error: 'Registration could not be saved to database. Please try again.' });
  } finally { if (connection) connection.release(); }
});

// 4. Password Login Endpoint
app.post('/api/auth/login', async (req, res) => {
  try {
    const { identifier, email, mobile, password } = req.body;
    const loginTarget = identifier || email || mobile || '';
    const cleanId = (loginTarget || '').trim().toLowerCase();
    const cleanPassword = String(password || '');

    if (!cleanId || !cleanPassword) {
      return res.status(400).json({ success: false, error: 'Please enter your email/mobile and password.' });
    }

    let user = await findAuthUserByEmailOrMobile(cleanId);

    if (!user) {
      return res.status(400).json({
        success: false,
        error: 'Account not found. Please check your email/mobile or sign up.'
      });
    }

    if (!user.passwordHash) {
      return res.status(400).json({
        success: false,
        error: 'Invalid email/mobile or password.'
      });
    }

    let isMatch = false;
    try {
      isMatch = await bcrypt.compare(cleanPassword, user.passwordHash);
    } catch (bcryptErr) {
      console.error('[API ERROR] Password verification error:', bcryptErr.message);
      return res.status(500).json({
        success: false,
        error: 'Server error during password verification.'
      });
    }

    if (!isMatch) {
      return res.status(400).json({
        success: false,
        error: 'Invalid email/mobile or password.'
      });
    }

    if (user.status === 'rejected') {
      return res.status(403).json({
        success: false,
        status: 'rejected',
        isApproved: false,
        error: 'Your account application has been rejected.'
      });
    }

    // A verified dealer with a matching bcrypt password may sign in even when
    // status is pending / is_approved is false. Approval is admin metadata,
    // never a password-login prerequisite or a grant of admin/employee access.
    const token = createDealerToken(user, SESSION_SECRET);
    const userPayload = {
      id: user.id,
      name: user.name,
      email: user.email,
      mobile: user.mobile,
      address: user.address,
      business: user.business,
      gstNumber: user.gstNumber || '',
      status: user.status,
      isApproved: user.isApproved,
      addresses: user.addresses || [],
      token: token
    };

    console.log('[DEALER LOGIN]', JSON.stringify({
      outcome: 'authenticated', status: user.status, isApproved: user.isApproved
    }));

    return res.status(200).json({
      success: true,
      message: 'Login successful.',
      token: token,
      user: userPayload
    });
  } catch (err) {
    console.error('[API ERROR] Failed login:', err.code || 'AUTH_ERROR');
    return res.status(503).json({
      success: false,
      error: 'Sign in is temporarily unavailable. Please try again.'
    });
  }
});

// 5. Google Sign-In Endpoint
const { OAuth2Client } = require('google-auth-library');
const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID || '1088492040924-preview-dealer-portal.apps.googleusercontent.com');

async function verifyGoogleToken(credentialOrToken) {
  if (!credentialOrToken) throw new Error('No Google token provided.');

  const clientId = process.env.GOOGLE_CLIENT_ID;
  if (!clientId) throw new Error('Google sign-in is not configured.');
  // Signature, issuer, expiry and audience must be verified before login.
  // Decoding a JWT payload alone is never proof of identity.
  const ticket = await googleClient.verifyIdToken({ idToken: credentialOrToken, audience: clientId });
  const payload = ticket.getPayload();
  if (!payload?.sub || !payload.email || payload.email_verified !== true) {
    throw new Error('A verified Google email is required.');
  }
  return payload;
}

app.post('/api/auth/google-signin', async (req, res) => {
  try {
    const { credential, accessToken } = req.body;
    const tokenToVerify = credential || accessToken;
    if (!tokenToVerify) return res.status(400).json({ success: false, error: 'Missing Google credential.' });

    let googlePayload;
    try { googlePayload = await verifyGoogleToken(tokenToVerify); }
    catch (_) { return res.status(401).json({ success: false, error: 'Google credential is invalid or expired.' }); }
    const cleanEmail = (googlePayload.email || '').trim().toLowerCase();
    const name = googlePayload.name || cleanEmail.split('@')[0];

    if (!cleanEmail) return res.status(400).json({ success: false, error: 'Could not verify email from Google.' });

    let user = await findUserByEmailOrMobile(cleanEmail);

    if (user) {
      if (user.status === 'rejected') {
        return res.status(403).json({ success: false, status: 'rejected', isApproved: false, error: 'Account rejected.' });
      }
    } else {
      const userId = `DEALER_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
      // Only what Google provides; the dealer adds mobile, business and
      // address themselves. (A random "98xxxxxxxx" mobile used to be stored,
      // which could block the real owner of that number from registering.)
      const businessName = '';
      const googleMobile = null;

      const conn = await pool.getConnection();
      try {
        await conn.beginTransaction();
        await conn.query(
          `INSERT INTO users (id, email, mobile, name, password_hash, business_name, owner_name, address, status, is_approved, reward_points, email_verified)
           VALUES (?, ?, ?, ?, '', ?, ?, '', 'pending', FALSE, 0, TRUE)`,
          [userId, cleanEmail, googleMobile, name, businessName, name]
        );
        await conn.commit();
      } catch (error) {
        await conn.rollback().catch(() => {});
        throw error;
      } finally {
        conn.release();
      }
      user = await findUserByEmailOrMobile(cleanEmail);
      if (!user) throw new Error('Google dealer account was not saved to PostgreSQL.');
    }

    // A verified Google identity proves ownership of this registered email.
    if (user.emailVerified !== true) {
      await pool.query('UPDATE users SET email_verified = TRUE WHERE id = ?', [user.id]);
      user.emailVerified = true;
    }
    const token = createDealerToken(user, SESSION_SECRET);
    return res.status(200).json({
      success: true,
      message: 'Google Sign-In successful.',
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        mobile: user.mobile,
        address: user.address,
        business: user.business,
        status: user.status,
        isApproved: user.isApproved,
        addresses: user.addresses || [],
        token: token
      }
    });
  } catch (err) {
    console.error('[API ERROR] Google Sign-In failed:', err.message);
    return res.status(500).json({ success: false, error: 'Google authentication failed.' });
  }
});

// -----------------------------------------------------------------------------
// ADMIN AUTHENTICATION & SECURITY SYSTEM
// -----------------------------------------------------------------------------
const ADMIN_EMAIL = (process.env.ADMIN_EMAIL || '').trim().toLowerCase();
const ADMIN_PASSWORD = (process.env.ADMIN_PASSWORD || '').trim();
if (!ADMIN_EMAIL || !ADMIN_PASSWORD) {
  throw new Error('ADMIN_EMAIL and ADMIN_PASSWORD must be configured before starting the backend.');
}
// Signed admin sessions (see admin_auth.js): valid across restarts and
// instances; changing ADMIN_PASSWORD signs every admin out.
const adminAuth = createAdminAuth({
  email: ADMIN_EMAIL,
  password: ADMIN_PASSWORD,
  secret: process.env.ADMIN_SESSION_SECRET || SESSION_SECRET,
});
const verifyAdminToken = token => adminAuth.verify(token);

// Admin Authentication Middleware
function requireAdminAuth(req, res, next) {
  const token = adminTokenFrom(req);
  if (token && verifyAdminToken(token)) {
    return next();
  }
  return res.status(401).json({ success: false, error: 'Unauthorized. Admin login required.' });
}

// Shop Employee routes use a separate role token and are installed only after
// the admin middleware is defined so employee provisioning stays admin-only.
const SHOP_EMPLOYEE_SECRET = process.env.SHOP_EMPLOYEE_SESSION_SECRET
  || SESSION_SECRET;
require('./shop_routes')(app, pool, SHOP_EMPLOYEE_SECRET, requireAdminAuth);

// Admin Login Endpoint
// 5 wrong attempts lock that email from that address (and that address
// overall) for 15 minutes. The response never says which part was wrong.
app.post('/api/admin/login', (req, res) => {
  try {
    const { email, password } = req.body || {};
    const cleanEmail = (email || '').trim().toLowerCase();
    const cleanPass = (password || '').trim();

    if (!cleanEmail || !cleanPass) {
      return res.status(400).json({ success: false, error: 'Please enter both admin email and password.' });
    }

    const clientKey = `ip:${req.ip || req.socket?.remoteAddress || 'unknown'}`;
    const accountKey = `${clientKey}:${cleanEmail}`;
    const lockedMs = Math.max(adminAuth.lockedFor(accountKey), adminAuth.lockedFor(clientKey));
    if (lockedMs > 0) {
      res.setHeader('Retry-After', String(Math.ceil(lockedMs / 1000)));
      return res.status(429).json({ success: false, error: `Too many failed sign-in attempts. Try again in ${Math.ceil(lockedMs / 60000)} minute(s).` });
    }

    if (adminAuth.checkPassword(cleanEmail, cleanPass)) {
      adminAuth.clearFailures(accountKey);
      adminAuth.clearFailures(clientKey);
      const adminToken = adminAuth.issue();
      console.log('🔐 [ADMIN LOGIN SUCCESS]');
      return res.status(200).json({
        success: true,
        message: 'Admin authentication successful.',
        token: adminToken,
        expiresInSeconds: Math.floor(adminAuth.ttlMs / 1000),
        admin: {
          email: ADMIN_EMAIL,
          name: 'System Administrator',
          role: 'super_admin'
        }
      });
    }

    const attempt = adminAuth.recordFailure(accountKey);
    adminAuth.recordFailure(clientKey);
    console.warn(`⚠️ [ADMIN LOGIN FAILED] attempt ${attempt.count}`);
    return res.status(401).json({
      success: false,
      error: 'Invalid admin email address or password.'
    });
  } catch (err) {
    console.error('[API ERROR] Admin login exception:', err.message);
    return res.status(500).json({ success: false, error: 'Server error during admin login.' });
  }
});

// Admin Verify Session Endpoint
app.get('/api/admin/session', (req, res) => {
  const token = adminTokenFrom(req);
  if (token && verifyAdminToken(token)) {
    return res.json({
      success: true,
      authenticated: true,
      admin: {
        email: ADMIN_EMAIL,
        name: 'System Administrator',
        role: 'super_admin'
      }
    });
  }
  return res.status(401).json({ success: false, authenticated: false, error: 'Admin session expired or invalid.' });
});

// Admin Logout Endpoint
app.post('/api/admin/logout', (req, res) => {
  const token = adminTokenFrom(req);
  if (token) {
    adminAuth.revoke(token);
  }
  return res.json({ success: true, message: 'Admin session logged out successfully.' });
});

// -----------------------------------------------------------------------------
// ADMIN PROTECTED ENDPOINTS
// -----------------------------------------------------------------------------

app.get('/api/admin/dealers', requireAdminAuth, async (req, res) => {
  try {
    const [rows] = await pool.query(`SELECT * FROM users ORDER BY created_at DESC`);
    const dealersList = rows.map(user => ({
      id: user.id,
      name: user.name || user.owner_name,
      email: user.email,
      mobile: user.mobile || '',
      address: user.address || '',
      business: user.business_name || '',
      status: user.status || 'approved',
      isApproved: isDatabaseTrue(user.is_approved) || user.status === 'approved',
      authMethod: 'Password/OTP',
      createdAt: user.created_at ? new Date(user.created_at).toISOString() : null
    }));
    return res.json({ success: true, count: dealersList.length, dealers: dealersList });
  } catch (err) {
    console.error('[API ERROR] Admin dealers:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Dealer data could not be loaded.' });
  }
});

app.post('/api/admin/set-status', requireAdminAuth, async (req, res) => {
  try {
    const { identifier, userId, email, status } = req.body || {};
    // The portal historically sent userId; keep it as an alias for older tabs.
    const target = identifier || userId || email;
    // Dealer ids are case-sensitive (DEALER_<uuid>); only the email is
    // compared case-insensitively. Lower-casing the id made the Admin Panel's
    // Approve / Reject / Reset buttons (which send the id) match no dealer.
    const rawId = typeof target === 'string' ? target.trim() : '';
    const cleanId = rawId.toLowerCase();
    const validStatuses = ['approved', 'pending', 'rejected'];
    const cleanStatus = typeof status === 'string' ? status.trim().toLowerCase() : '';

    if (!cleanId || !validStatuses.includes(cleanStatus)) {
      return res.status(400).json({ success: false, error: 'Invalid identifier or status.' });
    }

    const isApproved = cleanStatus === 'approved';
    const [updateResult] = await pool.query(
      `UPDATE users SET status = ?, is_approved = ? WHERE lower(email) = ? OR id = ? OR mobile = ?`,
      [cleanStatus, isApproved, cleanId, rawId, rawId]
    );
    if (!updateResult.affectedRows) {
      const [[existingDealer]] = await pool.query(
        'SELECT id FROM users WHERE lower(email) = ? OR id = ? OR mobile = ? LIMIT 1',
        [cleanId, rawId, rawId]
      );
      if (!existingDealer) return res.status(404).json({ success: false, error: 'Dealer not found.' });
    }

    return res.status(200).json({
      success: true,
      message: `Dealer status updated to ${cleanStatus}`,
      user: { email: cleanId, status: cleanStatus, isApproved: cleanStatus === 'approved' }
    });
  } catch (err) {
    // Database error details can contain personal data or connection details.
    console.error('[API ERROR] Admin set-status:', err.code || err.name);
    return res.status(503).json({ success: false, error: 'database is unavailable. Dealer status was not changed.' });
  }
});

// Admin Endpoint: Delete User
app.delete(['/api/admin/users/:id', '/api/admin/dealers/:id'], requireAdminAuth, async (req, res) => {
  try {
    const targetId = (req.params.id || '').trim();
    if (!targetId) {
      return res.status(400).json({ success: false, error: 'User ID is required for deletion.' });
    }

    const [result] = await pool.query(
      `DELETE FROM users WHERE id = ? OR email = ? OR mobile = ?`,
      [targetId, targetId, targetId]
    );

    if (result.affectedRows) {
      console.log(`🗑️ [ADMIN DELETE USER] Successfully deleted user: ${targetId}`);
      return res.status(200).json({ success: true, message: 'User deleted successfully.' });
    }
    return res.status(404).json({ success: false, error: 'User not found or already deleted.' });
  } catch (err) {
    console.error('[API ERROR] Delete user exception:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. User was not deleted.' });
  }
});

// -----------------------------------------------------------------------------
// USER PROFILE, ADDRESSES, REWARDS, INVOICES & SUPPORT ENDPOINTS
// -----------------------------------------------------------------------------

app.post('/api/user/update-profile', async (req, res) => {
  try {
    const { email, name, mobile, business, address } = req.body;
    const cleanEmail = (email || '').trim().toLowerCase();
    const cleanName = (name || '').trim();
    const cleanMobile = (mobile || '').replace(/\D/g, '');
    const cleanBusiness = (business || '').trim();
    const cleanAddress = (address || '').trim();

    if (!cleanEmail) return res.status(400).json({ success: false, error: 'Email required.' });
    if (!cleanName) return res.status(400).json({ success: false, error: 'Name required.' });
    if (!cleanMobile || cleanMobile.length !== 10) return res.status(400).json({ success: false, error: 'Valid 10-digit mobile required.' });

    await pool.query(
      `UPDATE users SET name = ?, owner_name = ?, mobile = ?, business_name = ?, address = ? WHERE email = ?`,
      // A blank business name stays blank (it used to become "<name> Aqua Wholesale").
      [cleanName, cleanName, cleanMobile, cleanBusiness, cleanAddress, cleanEmail]
    );

    const updatedUser = await findUserByEmailOrMobile(cleanEmail);
    return res.status(200).json({
      success: true,
      message: 'Profile updated successfully!',
      user: updatedUser
    });
  } catch (err) {
    console.error('[API ERROR] Update profile:', err);
    return res.status(500).json({ success: false, error: 'Server error updating profile.' });
  }
});

app.post('/api/user/change-password', async (req, res) => {
  try {
    const { email, currentPassword, newPassword } = req.body;
    const cleanEmail = (email || '').trim().toLowerCase();
    const cleanCurrentPass = (currentPassword || '').trim();
    const cleanNewPass = (newPassword || '').trim();

    if (!cleanEmail || !cleanCurrentPass || !cleanNewPass || cleanNewPass.length < 8) {
      return res.status(400).json({ success: false, error: 'Valid email, current password, and new password (min 8 chars) required.' });
    }

    const user = await findUserByEmailOrMobile(cleanEmail);
    if (!user || !user.passwordHash) {
      return res.status(404).json({ success: false, error: 'User account not found.' });
    }

    const isMatch = await bcrypt.compare(cleanCurrentPass, user.passwordHash);
    if (!isMatch) {
      return res.status(400).json({ success: false, error: 'Current password is incorrect.' });
    }

    const newHash = await bcrypt.hash(cleanNewPass, 10);

    await pool.query(`UPDATE users SET password_hash = ? WHERE email = ?`, [newHash, cleanEmail]);

    return res.status(200).json({ success: true, message: 'Password changed successfully!' });
  } catch (err) {
    console.error('[API ERROR] Change password:', err);
    return res.status(500).json({ success: false, error: 'Server error updating password.' });
  }
});

// Helper to normalize address objects for REST response
function normalizeAddressObj(a, userObj = {}) {
  return {
    id: a.id || a.address_id || `ADDR_${Date.now()}_${Math.floor(100 + Math.random() * 900)}`,
    fullName: a.full_name || a.fullName || userObj.name || userObj.owner || 'Recipient',
    phone: a.phone || a.mobile || userObj.mobile || '',
    doorNo: a.door_no || a.doorNo || '',
    street: a.street || '',
    area: a.area || '',
    city: a.city || '',
    district: a.district || a.city || '',
    state: a.state || '',
    pincode: a.pincode || '',
    landmark: a.landmark || '',
    addressType: a.address_type || a.addressType || a.label || 'Office',
    label: a.label || a.address_type || a.addressType || 'Office',
    businessName: a.business_name || a.businessName || userObj.business || '',
    gstNumber: a.gst_number || a.gstNumber || a.gstin || '',
    isDefault: isDatabaseTrue(a.is_default) || a.isDefault === true
  };
}

// 1. GET User Addresses
app.get('/api/user/addresses', async (req, res) => {
  try {
    const user = getDealerFromRequest(req);
    const emailQuery = (req.query.email || '').trim().toLowerCase();
    let targetUser = null;

    if (user && user.id) {
      targetUser = await findUserByEmailOrMobile(user.id);
    }
    if (!targetUser && emailQuery) {
      targetUser = await findUserByEmailOrMobile(emailQuery);
    }

    if (!targetUser) {
      return res.json({ success: true, addresses: [] });
    }

    let addresses = (targetUser.addresses || []).map(a => normalizeAddressObj(a, targetUser));

    // A dealer with no saved address but an address typed at signup gets that
    // address (only what they typed; blanks stay blank for them to complete).
    // Nothing is invented: before, a fake "No. 12, Wholesale Hub, Industrial
    // Estate, Chennai 600098" was created and saved as their default address.
    const signupAddress = String(targetUser.address || '').trim();
    if (addresses.length === 0 && signupAddress && signupAddress !== 'Wholesale Dealer Hub') {
      const parsed = parseAddressString(signupAddress);
      const defaultAddr = normalizeAddressObj({
        id: `ADDR_DEFAULT_${targetUser.id}`,
        full_name: targetUser.name || targetUser.owner || '',
        phone: targetUser.mobile || '',
        business_name: targetUser.business || '',
        street: parsed.street,
        city: parsed.city,
        district: parsed.city,
        state: parsed.state,
        pincode: parsed.pincode,
        address_type: 'Office',
        is_default: true
      }, targetUser);

      await pool.query(
        `INSERT INTO user_addresses (id, user_id, full_name, phone, business_name, door_no, street, area, city, district, state, pincode, address_type, label, is_default)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, TRUE)
         ON CONFLICT (id) DO NOTHING`,
        [defaultAddr.id, targetUser.id, defaultAddr.fullName, defaultAddr.phone, defaultAddr.businessName, '', defaultAddr.street, '', defaultAddr.city, defaultAddr.district, defaultAddr.state, defaultAddr.pincode, defaultAddr.addressType, defaultAddr.addressType]
      );

      addresses = [defaultAddr];
    }

    if (addresses.length > 0 && !addresses.some(a => a.isDefault)) {
      addresses[0].isDefault = true;
    }

    return res.json({ success: true, userId: targetUser.id, addresses });
  } catch (err) {
    console.error('[API ERROR] GET /api/user/addresses:', err.message);
    return res.status(500).json({ success: false, error: 'Server error retrieving addresses.' });
  }
});

// 2. SAVE / UPDATE User Address
app.post('/api/user/addresses/save', async (req, res) => {
  try {
    const {
      email, id, fullName, phone, doorNo, street, area, city, district, state, pincode, landmark, addressType, businessName, gstNumber, isDefault
    } = req.body || {};

    const reqUser = getDealerFromRequest(req);
    const cleanEmail = (email || '').trim().toLowerCase();
    let targetUser = null;

    if (reqUser && reqUser.id) {
      targetUser = await findUserByEmailOrMobile(reqUser.id);
    }
    if (!targetUser && cleanEmail) {
      targetUser = await findUserByEmailOrMobile(cleanEmail);
    }

    if (!targetUser) {
      return res.status(400).json({ success: false, error: 'User account not found. Please log in.' });
    }

    const cleanFullName = (fullName || targetUser.name || '').trim();
    const cleanPhone = (phone || targetUser.mobile || '').replace(/\D/g, '');
    const cleanDoorNo = (doorNo || '').trim();
    const cleanStreet = (street || '').trim();
    const cleanArea = (area || '').trim();
    const cleanCity = (city || '').trim();
    const cleanDistrict = (district || cleanCity || '').trim();
    const cleanState = (state || 'Tamil Nadu').trim();
    const cleanPincode = (pincode || '').replace(/\D/g, '');

    if (!cleanFullName) return res.status(400).json({ success: false, error: 'Full name is required.' });
    if (!cleanPhone || cleanPhone.length !== 10) return res.status(400).json({ success: false, error: 'Mobile number must be exactly 10 digits.' });
    if (!cleanStreet) return res.status(400).json({ success: false, error: 'Street address is required.' });
    if (!cleanCity) return res.status(400).json({ success: false, error: 'City is required.' });
    if (!cleanState) return res.status(400).json({ success: false, error: 'State is required.' });
    if (!cleanPincode || cleanPincode.length !== 6) return res.status(400).json({ success: false, error: 'PIN code must be exactly 6 digits.' });

    const addrId = id || `ADDR_${Date.now()}_${Math.floor(100 + Math.random() * 900)}`;
    let existingAddr = (targetUser.addresses || []).find(a => a.id === addrId);
    let shouldBeDefault = isDefault === true || isDefault === 'true' || isDefault === 1;
    if (id && isDefault === undefined && existingAddr) {
      shouldBeDefault = existingAddr.isDefault === 1 || existingAddr.isDefault === true;
    }

    const savedAddrObj = {
      id: addrId,
      user_id: targetUser.id,
      fullName: cleanFullName,
      phone: cleanPhone,
      doorNo: cleanDoorNo,
      street: cleanStreet,
      area: cleanArea,
      city: cleanCity,
      district: cleanDistrict,
      state: cleanState,
      pincode: cleanPincode,
      landmark: (landmark || '').trim(),
      addressType: (addressType || 'Office').trim(),
      label: (addressType || 'Office').trim(),
      businessName: (businessName || targetUser.business || '').trim(),
      gstNumber: (gstNumber || '').trim().toUpperCase(),
      isDefault: shouldBeDefault
    };

    if (shouldBeDefault) {
      await pool.query(`UPDATE user_addresses SET is_default = FALSE WHERE user_id = ?`, [targetUser.id]);
    }
    await pool.query(
        `INSERT INTO user_addresses (id, user_id, label, full_name, phone, business_name, door_no, street, area, city, district, state, pincode, landmark, address_type, gst_number, is_default)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (id) DO UPDATE SET
           full_name = EXCLUDED.full_name,
           phone = EXCLUDED.phone,
           business_name = EXCLUDED.business_name,
           door_no = EXCLUDED.door_no,
           street = EXCLUDED.street,
           area = EXCLUDED.area,
           city = EXCLUDED.city,
           district = EXCLUDED.district,
           state = EXCLUDED.state,
           pincode = EXCLUDED.pincode,
           landmark = EXCLUDED.landmark,
           address_type = EXCLUDED.address_type,
           label = EXCLUDED.label,
           gst_number = EXCLUDED.gst_number,
           is_default = EXCLUDED.is_default`,
        [
          savedAddrObj.id, targetUser.id, savedAddrObj.label, savedAddrObj.fullName, savedAddrObj.phone,
          savedAddrObj.businessName, savedAddrObj.doorNo, savedAddrObj.street, savedAddrObj.area,
          savedAddrObj.city, savedAddrObj.district, savedAddrObj.state, savedAddrObj.pincode,
          savedAddrObj.landmark, savedAddrObj.addressType, savedAddrObj.gstNumber, Boolean(savedAddrObj.isDefault)
        ]
    );

    const updatedUser = await findUserByEmailOrMobile(targetUser.email);
    return res.status(200).json({
      success: true,
      message: 'Address saved successfully!',
      addresses: (updatedUser.addresses || []).map(a => normalizeAddressObj(a, updatedUser))
    });
  } catch (err) {
    console.error('[API ERROR] POST /api/user/addresses/save:', err.message);
    return res.status(500).json({ success: false, error: 'Server error saving address.' });
  }
});

// 3. SET DEFAULT User Address
app.post('/api/user/addresses/set-default', async (req, res) => {
  try {
    const email = req.body?.email;
    const addressId = req.body?.addressId || req.body?.address_id;
    const reqUser = getDealerFromRequest(req);
    let targetUser = null;

    if (reqUser && reqUser.id) {
      targetUser = await findUserByEmailOrMobile(reqUser.id);
    }
    if (!targetUser && email) {
      targetUser = await findUserByEmailOrMobile(email);
    }

    if (!targetUser || !addressId) {
      return res.status(400).json({ success: false, error: 'User email and addressId required.' });
    }

    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      const [addressRows] = await connection.query('SELECT id FROM user_addresses WHERE user_id = ? AND id = ? FOR UPDATE', [targetUser.id, addressId]);
      if (!addressRows.length) {
        await connection.rollback();
        return res.status(404).json({ success: false, error: 'Address not found.' });
      }
      await connection.query(`UPDATE user_addresses SET is_default = FALSE WHERE user_id = ?`, [targetUser.id]);
      await connection.query(`UPDATE user_addresses SET is_default = TRUE WHERE user_id = ? AND id = ?`, [targetUser.id, addressId]);
      await connection.commit();
    } catch (error) {
      await connection.rollback().catch(() => {});
      throw error;
    } finally {
      connection.release();
    }

    const updatedUser = await findUserByEmailOrMobile(targetUser.email);
    return res.json({ success: true, message: 'Default address updated.', addresses: (updatedUser.addresses || []).map(a => normalizeAddressObj(a, updatedUser)) });
  } catch (err) {
    console.error('[API ERROR] set-default address:', err);
    return res.status(500).json({ success: false, error: 'Server error setting default address.' });
  }
});

// 4. DELETE User Address
app.post('/api/user/addresses/delete', async (req, res) => {
  try {
    const { email, addressId } = req.body || {};
    const reqUser = getDealerFromRequest(req);
    let targetUser = null;

    if (reqUser && reqUser.id) {
      targetUser = await findUserByEmailOrMobile(reqUser.id);
    }
    if (!targetUser && email) {
      targetUser = await findUserByEmailOrMobile(email);
    }

    if (!targetUser || !addressId) {
      return res.status(400).json({ success: false, error: 'User email and addressId required.' });
    }

    await pool.query(`DELETE FROM user_addresses WHERE user_id = ? AND id = ?`, [targetUser.id, addressId]);
    const [remaining] = await pool.query(`SELECT id FROM user_addresses WHERE user_id = ? ORDER BY created_at ASC`, [targetUser.id]);
    if (remaining.length > 0) {
      await pool.query(`UPDATE user_addresses SET is_default = TRUE WHERE user_id = ? AND id = ?`, [targetUser.id, remaining[0].id]);
    }

    const updatedUser = await findUserByEmailOrMobile(targetUser.email);
    return res.json({ success: true, message: 'Address deleted successfully.', addresses: (updatedUser.addresses || []).map(a => normalizeAddressObj(a, updatedUser)) });
  } catch (err) {
    console.error('[API ERROR] delete address:', err);
    return res.status(500).json({ success: false, error: 'Server error deleting address.' });
  }
});

// -----------------------------------------------------------------------------
// USER-SPECIFIC PERSISTENT SHOPPING CART SYSTEM
// -----------------------------------------------------------------------------
function getDealerFromRequest(req) {
  const authHeader = req.headers['authorization'] || '';
  const tokenHeader = req.headers['x-dealer-token'] || req.headers['x-user-token'] || '';
  const headerUserId = req.headers['x-user-id'] || req.query.userId || req.body?.userId || '';

  if (headerUserId) {
    return { id: headerUserId };
  }
  return null;
}

function formatCartItemRow(row) {
  const priceNum = typeof row.price === 'number' ? row.price : parseFloat(row.price) || 0;
  return {
    id: row.product_id || row.id,
    product_id: row.product_id || row.id,
    name: row.name,
    brand: row.brand || 'AQUACLEAN',
    price: `₹${priceNum.toLocaleString('en-IN')}`,
    numericPrice: priceNum,
    mrp: Number(row.mrp) || 0,
    category: row.category_key || row.category || '',
    badge: row.badge || '',
    moq: row.moq || '',
    max_order_quantity: maxOrderQuantity({ id: row.product_id || row.id, moq: row.moq }),
    stock_enforced: stockEnforced(),
    stock_quantity: row.stock_quantity == null ? null : Number(row.stock_quantity),
    status: row.status || 'active',
    imgSrc: row.img || row.imgSrc || 'purifier.jpg',
    sku: row.sku || `SKU-${(row.product_id || row.id).toString().toUpperCase()}`,
    quantity: parseInt(row.quantity, 10) || 1,
    // 'normal' (Dealer Price) or 'bulk' (bulk_price per piece, bulk_orders.js).
    purchase_mode: row.purchase_mode || 'normal',
    ...bulkFields(row)
  };
}

/** The dealer's cart lines (with purchase mode and bulk offer once migration 011 is in). */
async function loadCartRows(userId) {
  const bulk = await bulkOrdersReady(pool);
  const [rows] = await pool.query(
    `SELECT ci.id as cart_item_id, ci.quantity, ci.product_id,${bulk ? ' ci.purchase_mode, p.bulk_price, p.bulk_min_qty, p.bulk_step, p.bulk_pack_label,' : ''}
            p.name, p.brand, p.price, p.mrp, p.moq, p.badge, p.rating, p.img, p.category_key, p.sku, p.stock_quantity, p.status
     FROM cart_items ci
     LEFT JOIN products p ON ci.product_id = p.id
     WHERE ci.user_id = ?
     ORDER BY ci.id ASC`,
    [userId]
  );
  return rows.map(formatCartItemRow);
}

/** Existing cart line for a product: { quantity, mode } or null. */
async function cartLine(userId, productId) {
  const bulk = await bulkOrdersReady(pool);
  const [rows] = await pool.query(`SELECT quantity${bulk ? ', purchase_mode' : ''} FROM cart_items WHERE user_id = ? AND product_id = ?`, [userId, productId]);
  return rows[0] ? { quantity: Number(rows[0].quantity || 0), mode: rows[0].purchase_mode || 'normal' } : null;
}

/** Bulk rule check for a cart line (needs the product's bulk offer). */
async function bulkCartProblem(productId, quantity, options) {
  if (!(await bulkOrdersReady(pool))) return { status: 503, code: 'BULK_NOT_READY', error: 'Bulk Orders are not available yet.' };
  const [rows] = await pool.query('SELECT id, name, stock_quantity, status, bulk_price, bulk_min_qty, bulk_step, bulk_pack_label FROM products WHERE id = ? LIMIT 1', [productId]);
  const product = rows[0];
  if (!product || String(product.status || 'active').toLowerCase() === 'inactive') {
    return { status: 404, code: 'PRODUCT_UNAVAILABLE', error: 'This product is no longer available.' };
  }
  return bulkQuantityProblem(product, quantity, options);
}

// 1. GET User Cart
app.get('/api/cart', async (req, res) => {
  try {
    const user = getDealerFromRequest(req);
    const userId = user ? user.id : '';

    if (!userId) {
      return res.json({ success: true, items: [] });
    }

    const rows = await loadCartRows(userId);
    return res.json({ success: true, userId, items: rows });
  } catch (err) {
    console.error('[API ERROR] GET /api/cart:', err.message);
    return res.status(500).json({ success: false, error: 'Server error retrieving cart.' });
  }
});

// Cart rule (checkout applies the same rule again, see order_rules.js): a line
// holds at least 1 and at most the product's maximum (the PDF quantity for the
// PDF catalogue) and the stock. Lowering or removing a line is always allowed.
async function cartQuantityProblem(productId, wantedTotal, options) {
  const [rows] = await pool.query('SELECT id, name, stock_quantity, status, moq FROM products WHERE id = ? LIMIT 1', [productId]);
  const product = rows[0];
  if (!product || String(product.status || 'active').toLowerCase() === 'inactive') {
    return { status: 404, code: 'PRODUCT_UNAVAILABLE', error: 'This product is no longer available.' };
  }
  return orderQuantityProblem(product, wantedTotal, options);
}

// 2. ADD Item to User Cart
app.post('/api/cart/add', async (req, res) => {
  try {
    const { productId, quantity = 1 } = req.body || {};
    const user = getDealerFromRequest(req);
    const userId = user ? user.id : '';

    if (!userId || !productId) {
      return res.status(400).json({ success: false, error: 'User ID and Product ID required.' });
    }

    const mode = purchaseMode(req.body?.purchaseMode ?? req.body?.purchase_mode);
    if (!mode) return res.status(400).json({ success: false, error: 'Unknown purchase mode.' });
    const qty = parseInt(quantity, 10) || 1;
    if (qty < 1) return res.status(400).json({ success: false, error: 'Quantity must be at least 1.' });
    const existing = await cartLine(userId, productId);
    // A product is in the cart normally OR in bulk; never converted silently.
    if (existing && existing.mode !== mode) {
      const [[p]] = await pool.query('SELECT name FROM products WHERE id = ? LIMIT 1', [productId]);
      const conflict = modeConflict(p || {}, existing.mode, mode);
      return res.status(conflict.status).json({ success: false, error: conflict.error, code: conflict.code });
    }
    const wanted = Number(existing?.quantity || 0) + qty;
    const stockProblem = mode === 'bulk'
      ? await bulkCartProblem(productId, wanted)
      : await cartQuantityProblem(productId, wanted);
    if (stockProblem) return res.status(stockProblem.status).json({ success: false, error: stockProblem.error, code: stockProblem.code, max: stockProblem.max, min: stockProblem.min, step: stockProblem.step });

    if (mode === 'bulk') {
      await pool.query(
        `INSERT INTO cart_items (user_id, product_id, quantity, purchase_mode)
         VALUES (?, ?, ?, 'bulk')
         ON CONFLICT (user_id, product_id) DO UPDATE SET quantity = cart_items.quantity + EXCLUDED.quantity`,
        [userId, productId, qty]
      );
    } else {
      await pool.query(
        `INSERT INTO cart_items (user_id, product_id, quantity)
         VALUES (?, ?, ?)
         ON CONFLICT (user_id, product_id) DO UPDATE SET quantity = cart_items.quantity + EXCLUDED.quantity`,
        [userId, productId, qty]
      );
    }
    const rows = await loadCartRows(userId);
    return res.json({ success: true, message: 'Item added to cart.', items: rows });
  } catch (err) {
    console.error('[API ERROR] POST /api/cart/add:', err.message);
    return res.status(500).json({ success: false, error: 'Server error adding item to cart.' });
  }
});

// 3. UPDATE Item Quantity in User Cart
app.put('/api/cart/update', async (req, res) => {
  try {
    const { productId, quantity } = req.body || {};
    const user = getDealerFromRequest(req);
    const userId = user ? user.id : '';

    if (!userId || !productId) {
      return res.status(400).json({ success: false, error: 'User ID and Product ID required.' });
    }

    const qty = parseInt(quantity, 10);

    if (!Number.isFinite(qty)) return res.status(400).json({ success: false, error: 'Valid quantity is required.' });
    if (qty > 0) {
      const existing = await cartLine(userId, productId);
      const current = Number(existing?.quantity || 0);
      // The line keeps its own mode (bulk lines: minimum + whole steps).
      const stockProblem = existing?.mode === 'bulk'
        ? await bulkCartProblem(productId, qty, { checkStock: qty > current })
        // Growing a line is fully checked; lowering only has to stay at or above
        // the MOQ (to go below it, remove the line), so a dealer can always lower.
        : qty > current
          ? await cartQuantityProblem(productId, qty)
          : await cartQuantityProblem(productId, qty, { checkMax: false });
      if (stockProblem) return res.status(stockProblem.status).json({ success: false, error: stockProblem.error, code: stockProblem.code, max: stockProblem.max, min: stockProblem.min, step: stockProblem.step });
    }
    if (qty <= 0) await pool.query(`DELETE FROM cart_items WHERE user_id = ? AND product_id = ?`, [userId, productId]);
    else await pool.query(`UPDATE cart_items SET quantity = ? WHERE user_id = ? AND product_id = ?`, [qty, userId, productId]);
    const rows = await loadCartRows(userId);
    return res.json({ success: true, message: 'Cart item updated.', items: rows });
  } catch (err) {
    console.error('[API ERROR] PUT /api/cart/update:', err.message);
    return res.status(500).json({ success: false, error: 'Server error updating cart.' });
  }
});

// 4. REMOVE Item from User Cart
app.delete('/api/cart/remove', async (req, res) => {
  try {
    const productId = req.body?.productId || req.query.productId;
    const user = getDealerFromRequest(req);
    const userId = user ? user.id : '';

    if (!userId || !productId) {
      return res.status(400).json({ success: false, error: 'User ID and Product ID required.' });
    }

    await pool.query(`DELETE FROM cart_items WHERE user_id = ? AND product_id = ?`, [userId, productId]);
    const rows = await loadCartRows(userId);
    return res.json({ success: true, message: 'Item removed from cart.', items: rows });
  } catch (err) {
    console.error('[API ERROR] DELETE /api/cart/remove:', err.message);
    return res.status(500).json({ success: false, error: 'Server error removing cart item.' });
  }
});

// 5. CLEAR User Cart
app.delete('/api/cart/clear', async (req, res) => {
  try {
    const user = getDealerFromRequest(req);
    const userId = user ? user.id : '';

    if (!userId) {
      return res.json({ success: true, message: 'Cart cleared.', items: [] });
    }

    await pool.query(`DELETE FROM cart_items WHERE user_id = ?`, [userId]);

    return res.json({ success: true, message: 'User cart cleared.', items: [] });
  } catch (err) {
    console.error('[API ERROR] DELETE /api/cart/clear:', err.message);
    return res.status(500).json({ success: false, error: 'Server error clearing cart.' });
  }
});

app.delete('/api/user/address', async (req, res) => {
  try {
    const { email, addressId } = req.body;
    const cleanEmail = (email || '').trim().toLowerCase();
    if (!cleanEmail || !addressId) return res.status(400).json({ success: false, error: 'Email and addressId required.' });

    const [userRows] = await pool.query(`SELECT id FROM users WHERE email = ?`, [cleanEmail]);
    if (userRows && userRows.length > 0) {
      await pool.query(`DELETE FROM user_addresses WHERE id = ? AND user_id = ?`, [addressId, userRows[0].id]);
    }

    const updatedUser = await findUserByEmailOrMobile(cleanEmail);
    return res.status(200).json({
      success: true,
      message: 'Address deleted successfully!',
      user: updatedUser
    });
  } catch (err) {
    console.error('[API ERROR] Delete address:', err);
    return res.status(500).json({ success: false, error: 'Server error deleting address.' });
  }
});

// -----------------------------------------------------------------------------
// ORDERS & CHECKOUT ENDPOINTS
// -----------------------------------------------------------------------------

app.get('/api/user/orders', async (req, res) => {
  try {
    const email = (req.query.email || '').trim().toLowerCase();
    if (!email) return res.status(400).json({ success: false, error: 'Email parameter required.' });
    const [orderRows] = await pool.query(
      `SELECT * FROM orders WHERE user_email = ? ORDER BY created_at DESC`,
      [email]
    );
    const formattedOrders = [];
    // Supplied units per order, so the customer sees the same order status as
    // the Admin Panel and the Shop App (Cancelled > supplied quantities > stored).
    const [supplyMeta] = await pool.query(`SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'shop_delivery_items' AND column_name = 'delivery_confirmed'
    ) AS available`);
    const confirmedColumn = supplyMeta[0]?.available === true ? 'COALESCE(d.delivery_confirmed, FALSE)' : 'COALESCE(d.delivered, FALSE)';
    for (const o of orderRows) {
      const [itemRows] = await pool.query(`SELECT oi.*, CASE WHEN ${confirmedColumn} THEN COALESCE(d.delivered_quantity, 0) ELSE 0 END AS supplied_quantity
        FROM order_items oi LEFT JOIN shop_delivery_items d ON d.order_item_id = oi.id WHERE oi.order_id = ? ORDER BY oi.id`, [o.order_id]);
      const suppliedQuantity = itemRows.reduce((sum, i) => sum + Number(i.supplied_quantity || 0), 0);
      const orderedQuantity = itemRows.reduce((sum, i) => sum + Number(i.quantity || 0), 0);
      formattedOrders.push({
            orderId: o.order_id,
            userEmail: o.user_email,
            userName: o.user_name,
            userBusiness: o.user_business,
            items: (itemRows || []).map(i => ({
              id: i.product_id,
              name: i.product_name,
              brand: i.brand || 'RO Wholesale',
              price: `₹${parseFloat(i.unit_price).toLocaleString('en-IN')}`,
              numericPrice: parseFloat(i.unit_price),
              quantity: i.quantity,
              moq: i.moq || '',
              imgSrc: i.img_src || '',
              sku: i.sku || i.product_id || '',
              // 'bulk' lines were priced per piece at the bulk rate (migration 011).
              purchaseMode: i.purchase_mode || 'normal',
              bulkPackLabel: i.bulk_pack_label || null
            })),
            subtotal: parseFloat(o.subtotal),
            discount: parseFloat(o.discount),
            gst: parseFloat(o.gst),
            deliveryFee: parseFloat(o.delivery_fee),
            grandTotal: parseFloat(o.grand_total),
            withGst: isDatabaseTrue(o.with_gst),
            paymentMethod: o.payment_method,
            deliveryAddress: o.delivery_address,
            billingAddress: o.billing_address || o.delivery_address,
            sameAsDelivery: isDatabaseTrue(o.same_as_delivery),
            companyName: o.company_name || o.user_business || '',
            gstin: o.gstin || '',
            panNumber: o.pan_number || '',
            deliveryNote: o.delivery_note || '',
            status: effectiveOrderStatus(o.status, suppliedQuantity, orderedQuantity),
            paymentStatus: o.payment_status || 'pending',
            suppliedQuantity,
            orderedQuantity,
            invoiceNumber: o.invoice_number,
            createdAt: o.created_at ? new Date(o.created_at).toISOString() : new Date().toISOString()
      });
    }
    return res.status(200).json({ success: true, count: formattedOrders.length, orders: formattedOrders });
  } catch (err) {
    console.error('[API ERROR] Fetch orders:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Order data could not be loaded.' });
  }
});

require('./order_checkout')(app, pool, SESSION_SECRET, findUserByEmailOrMobile);

// -----------------------------------------------------------------------------
// REWARDS, GST INVOICES & SUPPORT DESK
// -----------------------------------------------------------------------------

// Points, Free Claim eligibility and history: all computed on the server.
app.get('/api/user/rewards', async (req, res) => {
  try {
    const email = (req.query.email || '').trim().toLowerCase();
    if (!email) return res.status(400).json({ success: false, error: 'Email required.' });

    const user = await findUserByEmailOrMobile(email);
    if (!user) return res.status(404).json({ success: false, error: 'User account not found.' });

    return res.status(200).json({ success: true, ...(await rewardSummary(pool, user.id)) });
  } catch (err) {
    console.error('[API ERROR] Fetch rewards:', err.code || err.name);
    return res.status(500).json({ success: false, error: 'Server error fetching rewards.' });
  }
});

// Free Claim request. Only the points value is read from the request; the
// dealer comes from the session, and eligibility + balance are checked here.
app.post('/api/user/rewards/claim', async (req, res) => {
  let conn;
  try {
    const user = await findUserByEmailOrMobile(String(req.dealer?.email || '').trim().toLowerCase());
    if (!user) return res.status(404).json({ success: false, error: 'User account not found.' });
    conn = await pool.getConnection();
    await conn.beginTransaction();
    const claim = await requestRewardClaim(conn, user.id, req.body?.points);
    await conn.commit();
    return res.json({ success: true, claim, message: `Claim for ${claim.points} points sent. You will be notified once it is approved.` });
  } catch (err) {
    if (conn) await conn.rollback().catch(() => {});
    if (err.status) return res.status(err.status).json({ success: false, error: err.message });
    console.error('[API ERROR] Reward claim:', err.code || err.name);
    return res.status(503).json({ success: false, error: 'Could not send the claim. Please try again.' });
  } finally {
    conn?.release();
  }
});

app.get('/api/user/gst-invoices', async (req, res) => {
  try {
    const email = (req.query.email || '').trim().toLowerCase();
    if (!email) return res.status(400).json({ success: false, error: 'Email required.' });

    // Item names come from the order itself (was a fixed "RO Water Equipment").
    const [invoiceRows] = await pool.query(
      `SELECT o.order_id, o.grand_total, o.gst, o.invoice_number, o.created_at,
              (SELECT string_agg(oi.product_name || ' × ' || oi.quantity, ', ' ORDER BY oi.id)
                 FROM order_items oi WHERE oi.order_id = o.order_id) AS items_summary
         FROM orders o WHERE o.user_email = ? AND o.with_gst = TRUE ORDER BY o.created_at DESC`,
      [email]
    );
    const invoices = invoiceRows.map(o => ({
      invoiceNumber: o.invoice_number,
      orderId: o.order_id,
      // No invented fallback date: an order without one shows no date.
      date: o.created_at ? new Date(o.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : null,
      createdAt: o.created_at ? new Date(o.created_at).toISOString() : null,
      amount: parseFloat(o.grand_total),
      gstAmount: parseFloat(o.gst),
      itemsSummary: o.items_summary || ''
    }));

    // Credit: the limit is a business setting (DEALER_CREDIT_LIMIT); without
    // it no limit is shown. Outstanding = this dealer's orders that are not
    // cancelled and not fully paid (all orders, with or without GST).
    const configuredLimit = Number(process.env.DEALER_CREDIT_LIMIT);
    const creditLimit = Number.isFinite(configuredLimit) && configuredLimit > 0 ? configuredLimit : null;
    const [[outstandingRow]] = await pool.query(
      `SELECT COALESCE(SUM(grand_total), 0) AS outstanding FROM orders
        WHERE user_email = ? AND lower(COALESCE(status, '')) <> 'cancelled'
          AND lower(COALESCE(payment_status, '')) <> 'paid'`,
      [email]
    );
    const outstanding = Number(outstandingRow?.outstanding || 0);

    return res.status(200).json({
      success: true,
      creditLimit,
      outstandingAmount: outstanding,
      availableCredit: creditLimit == null ? null : Math.max(0, creditLimit - outstanding),
      invoices: invoices
    });
  } catch (err) {
    console.error('[API ERROR] GST Invoices:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Invoice data could not be loaded.' });
  }
});

app.post('/api/user/support-ticket', async (req, res) => {
  try {
    const { email, name, subject, category, message } = req.body;
    const cleanEmail = (email || '').trim().toLowerCase();
    const cleanMessage = (message || '').trim();

    if (!cleanEmail || !cleanMessage) return res.status(400).json({ success: false, error: 'Email and message required.' });

    const [userRows] = await pool.query(`SELECT id FROM users WHERE email = ?`, [cleanEmail]);
    const userId = userRows.length > 0 ? userRows[0].id : null;
    const [result] = await pool.query(
      `INSERT INTO support_tickets (user_id, user_email, subject, message) VALUES (?, ?, ?, ?) RETURNING id`,
      [userId, cleanEmail, subject || category || 'Dealer Query', cleanMessage]
    );
    if (!result || !result.insertId) throw new Error('Support ticket insert returned no ID.');
    // Year the ticket was raised (India time), not a fixed year.
    const ticketYear = new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', year: 'numeric' }).format(new Date());
    const ticketId = `TKT-${ticketYear}-${result.insertId}`;

    return res.status(200).json({
      success: true,
      ticketId: ticketId,
      message: `🎉 Support Ticket #${ticketId} created successfully! Our B2B Support Desk will contact you within 15 minutes.`
    });
  } catch (err) {
    console.error('[API ERROR] Support ticket:', err);
    return res.status(500).json({ success: false, error: 'Server error submitting ticket.' });
  }
});

// -----------------------------------------------------------------------------
// PRODUCT CATALOG ENDPOINTS
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// PRODUCT ENDPOINTS (PUBLIC & ADMIN)
// -----------------------------------------------------------------------------

// Customer Endpoint: Get active products
// Public, read-only pricing rules (discount %, GST %, delivery charge and the
// free-delivery threshold). The app shows cart and checkout totals with these;
// orders are always re-priced on the server (see checkout_service.js).
app.get('/api/pricing-rules', (req, res) => {
  try {
    return res.json({ success: true, rules: pricingRules() });
  } catch (err) {
    console.error('[API ERROR] Pricing rules:', err.message);
    return res.status(500).json({ success: false, error: 'Pricing rules are not configured correctly.' });
  }
});

app.get('/api/products', async (req, res) => {
  try {
    // Dealer-facing catalog reads deliberately exclude purchase_price at the
    // query layer. Admin product routes use their separately protected query.
    // A NULL status is shown as "active" in the admin panel, so it must be
    // visible here too (`status != 'inactive'` alone silently drops NULLs).
    // Cabinet Price comes from its own column (migration 009); it is selected
    // only once that column exists, so the catalog keeps working before it.
    const withCabinetPrice = await hasCabinetPriceColumn();
    // Bulk Orders offer (migration 011), selected once those columns exist.
    const withBulk = await bulkOrdersReady(pool);
    const [rows] = await pool.query(`SELECT id, category_key, category_id, brand, name, price, mrp,${withCabinetPrice ? ' cabinet_price,' : ''}${withBulk ? ' bulk_price, bulk_min_qty, bulk_step, bulk_pack_label,' : ''} moq, badge, rating, img, sku, description, specs_json, features_json, applications, stock_quantity, min_stock, status, created_at, (SELECT c.title FROM categories c WHERE c.id = products.category_id OR c.key_name = products.category_key ORDER BY (c.id = products.category_id) DESC LIMIT 1) AS category_name FROM products WHERE COALESCE(status, 'active') <> 'inactive' ORDER BY category_key, name`);
    const products = rows.map(p => ({
          id: p.id,
          category: p.category_key,
          category_id: p.category_id || null,
          category_name: p.category_name || null,
          created_at: p.created_at ? new Date(p.created_at).toISOString() : null,
          brand: p.brand,
          name: p.name,
          price: parseFloat(p.price),
          dealer_price: parseFloat(p.price),
          mrp: parseFloat(p.mrp),
          // Cabinet products only; null when not set (never Dealer Price or MRP).
          cabinet_price: isCabinetCategory(p.category_id, p.category_key) && p.cabinet_price != null && Number(p.cabinet_price) > 0
            ? Number(p.cabinet_price) : null,
          // Bulk Orders only (bulk_orders.js); null = not sold in bulk. Never
          // replaces the Dealer Price or MRP above.
          ...bulkFields(p),
          moq: p.moq,
          // Same rule as cart and checkout (order_rules.js).
          min_order_quantity: minOrderQuantity(p),
          max_order_quantity: maxOrderQuantity(p),
          stock_enforced: stockEnforced(),
          availability: availability(p),
          badge: p.badge,
          rating: p.rating,
          img: p.img,
          sku: p.sku,
          desc: p.description,
          specs: typeof p.specs_json === 'string' ? JSON.parse(p.specs_json || '{}') : (p.specs_json || {}),
          features: typeof p.features_json === 'string' ? JSON.parse(p.features_json || '[]') : (p.features_json || []),
          applications: p.applications,
          stock_quantity: p.stock_quantity == null ? null : Number(p.stock_quantity),
          min_stock: p.min_stock == null ? null : Number(p.min_stock),
          status: p.status || 'active'
    }));
    // Admin edits must show up on the next read; never serve a cached catalog.
    res.set('Cache-Control', 'no-store');
    return res.json({ success: true, count: products.length, products });
  } catch (err) {
    console.error('[API ERROR] Get products:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Product data could not be loaded.' });
  }
});

// Product images kept in the shared database (PRODUCT_IMAGE_STORE=database).
app.get('/api/product-images/:file', async (req, res) => {
  const id = String(req.params.file || '').replace(/\.[a-z0-9]+$/i, '');
  if (!/^img_[0-9]+_[0-9a-f]+$/.test(id)) return res.status(404).end();
  try {
    const [rows] = await pool.query('SELECT content_type, bytes FROM product_images WHERE id = ? LIMIT 1', [id]);
    if (!rows.length) return res.status(404).end();
    res.set('Content-Type', rows[0].content_type || 'application/octet-stream');
    // Each upload gets a new id, so the bytes behind a URL never change.
    res.set('Cache-Control', 'public, max-age=31536000, immutable');
    // Always send binary (some drivers return a Uint8Array, not a Buffer).
    return res.send(Buffer.from(rows[0].bytes));
  } catch (err) {
    console.error('[API ERROR] Product image:', err.message);
    return res.status(404).end();
  }
});

// -----------------------------------------------------------------------------
// PUBLIC PRODUCT SHARE PAGE (WhatsApp / social link previews)
// -----------------------------------------------------------------------------
// Shared links must show MRP only. This route never selects price,
// dealer_price or purchase_price, so they cannot reach the page, its Open
// Graph tags or any preview built from it.
const escapeShareHtml = value => String(value ?? '')
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

function shareRupees(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return '';
  return '₹' + n.toLocaleString('en-IN', { maximumFractionDigits: 2 });
}

function requestOrigin(req) {
  // A fixed public address (e.g. https://ro-mobileapp.onrender.com) keeps
  // shared pages and preview images off localhost/internal host names.
  const configured = String(process.env.PUBLIC_BASE_URL || '').trim().replace(/\/+$/, '');
  if (configured) return configured;
  const proto = String(req.get('x-forwarded-proto') || req.protocol || 'http').split(',')[0].trim();
  const host = String(req.get('x-forwarded-host') || req.get('host') || '').split(',')[0].trim();
  return `${proto}://${host}`;
}

function storefrontUrl(req) {
  const configured = String(process.env.STOREFRONT_URL || '').trim().replace(/\/+$/, '');
  if (configured) return configured;
  // A public share address is configured: never link to a local storefront.
  if (String(process.env.PUBLIC_BASE_URL || '').trim()) return '';
  const host = String(req.get('x-forwarded-host') || req.get('host') || '');
  // Local development: the Flutter web app is served on port 8080.
  if (/^(localhost|127\.0\.0\.1)(:\d+)?$/i.test(host)) return `http://${host.split(':')[0]}:8080`;
  return '';
}

function absoluteImageUrl(img, origin) {
  const clean = String(img || '').trim() || 'purifier.jpg';
  if (/^https?:\/\//i.test(clean)) return clean;
  return origin + (clean.startsWith('/') ? clean : '/' + clean);
}

/** Width/height of a JPEG or PNG from its header, or null. */
function imageDimensions(buffer) {
  if (!buffer || buffer.length < 24) return null;
  if (buffer.readUInt32BE(0) === 0x89504E47) {
    return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20), type: 'image/png' };
  }
  if (buffer[0] === 0xFF && buffer[1] === 0xD8) {
    let i = 2;
    while (i + 9 < buffer.length) {
      if (buffer[i] !== 0xFF) { i++; continue; }
      const marker = buffer[i + 1];
      if (marker >= 0xC0 && marker <= 0xCF && ![0xC4, 0xC8, 0xCC].includes(marker)) {
        return { width: buffer.readUInt16BE(i + 7), height: buffer.readUInt16BE(i + 5), type: 'image/jpeg' };
      }
      i += 2 + buffer.readUInt16BE(i + 2);
    }
  }
  return null;
}

/**
 * Image for link previews. Bundled photos use the 800px JPEG copies in
 * web_preview/share-images (WhatsApp skips large preview images); uploaded
 * files on this server report their real size and type.
 */
let catalogImageMap = null;
function loadCatalogImageMap() {
  if (!catalogImageMap) {
    try {
      catalogImageMap = JSON.parse(fs.readFileSync(path.join(__dirname, 'web_preview', 'share-images', 'catalog-image-map.json'), 'utf8'));
    } catch (err) {
      console.error('[SHARE PAGE] catalog-image-map.json unavailable:', err.message);
      catalogImageMap = { placeholders: [], bySku: {}, byCategoryText: [], defaultTile: null };
    }
  }
  return catalogImageMap;
}

/**
 * The picture the customer app shows for this product. Uploaded images are
 * used as they are. Products whose stored image is a shared placeholder
 * (purifier.jpg, cat_filter.jpg, ...) are shown in the app as their own tile
 * of the catalog sprite (ProductModel.displayImageUrl); the share page uses
 * the same tile so WhatsApp shows the same product picture.
 */
function productShareImagePath(product) {
  const img = String(product.img || '').trim();
  const name = img.split(/[?#]/)[0].split('/').pop().toLowerCase();
  const map = loadCatalogImageMap();
  // A full web address saved by the admin is always used as-is (same rule as the app).
  if (/^https?:\/\//i.test(img)) return img;
  if (img && !map.placeholders.includes(name)) return img;
  let tile = map.bySku[String(product.sku || '').toUpperCase()];
  if (tile === undefined) {
    const categoryText = `${product.category_key || ''} ${product.category_title || ''}`.toLowerCase();
    const rule = map.byCategoryText.find(r => r.contains.some(word => categoryText.includes(word)));
    tile = rule ? rule.tile : map.defaultTile;
  }
  if (Number.isInteger(tile) && fs.existsSync(path.join(__dirname, 'web_preview', 'share-images', `catalog-${tile}.jpg`))) {
    return `/share-images/catalog-${tile}.jpg`;
  }
  return img || 'purifier.jpg';
}

function sharePreviewImage(img, origin) {
  const clean = String(img || '').trim() || 'purifier.jpg';
  let file = null;
  let urlPath = null;
  if (/^\/share-images\/[A-Za-z0-9_.-]+$/.test(clean)) {
    file = path.join(__dirname, 'web_preview', clean.slice(1));
  } else if (/^[A-Za-z0-9_.-]+$/.test(clean)) {
    const preview = path.join(__dirname, 'web_preview', 'share-images', clean);
    if (fs.existsSync(preview)) { file = preview; urlPath = `/share-images/${clean}`; }
    else { file = path.join(__dirname, 'web_preview', clean); }
  } else if (/^\/?uploads\/[A-Za-z0-9_.-]+$/.test(clean)) {
    file = path.join(uploadsDir, path.basename(clean));
  }
  let meta = null;
  try { if (file && fs.existsSync(file)) meta = imageDimensions(fs.readFileSync(file)); } catch (_) { meta = null; }
  const url = absoluteImageUrl(urlPath || clean, origin);
  const type = meta?.type
    || (/\.png(\?|$)/i.test(url) ? 'image/png' : /\.webp(\?|$)/i.test(url) ? 'image/webp' : 'image/jpeg');
  return { url, type, width: meta?.width || null, height: meta?.height || null };
}

// The product's own picture as an image file, for attaching to WhatsApp
// through the Web Share API / share sheet. Same picture as og:image and the
// app (see productShareImagePath). Public: it contains no price information.
app.get('/share/products/:id/image', async (req, res) => {
  let product;
  try {
    const [rows] = await pool.query(
      `SELECT p.id, p.sku, p.img, p.status, p.category_key,
              COALESCE(c.title, p.category_key) AS category_title
         FROM products p
         LEFT JOIN categories c ON c.id = p.category_id OR c.key_name = p.category_key
        WHERE p.id = ? LIMIT 1`,
      [req.params.id]
    );
    product = rows[0];
  } catch (err) {
    console.error('[SHARE IMAGE] Lookup failed:', err.message);
    return res.status(503).json({ success: false, error: 'Product image is temporarily unavailable.' });
  }
  if (!product || String(product.status || 'active').toLowerCase() === 'inactive') {
    return res.status(404).json({ success: false, error: 'Product not found.' });
  }

  const imagePath = productShareImagePath(product);
  const safeName = String(product.sku || product.id).replace(/[^A-Za-z0-9_-]+/g, '-') || 'product';
  res.set('Cache-Control', 'public, max-age=300');
  // Lets the web app read the bytes when it is hosted on another origin.
  res.set('Access-Control-Allow-Origin', '*');

  const sendBytes = (bytes, type) => {
    const ext = type === 'image/png' ? 'png' : type === 'image/webp' ? 'webp' : 'jpg';
    res.set('Content-Type', type);
    res.set('Content-Disposition', `inline; filename="${safeName}.${ext}"`);
    return res.send(Buffer.from(bytes));
  };

  try {
    const dbImage = imagePath.match(/^\/api\/product-images\/(img_[0-9]+_[0-9a-f]+)/);
    if (dbImage) {
      const [rows] = await pool.query('SELECT content_type, bytes FROM product_images WHERE id = ? LIMIT 1', [dbImage[1]]);
      if (!rows.length) return res.status(404).json({ success: false, error: 'Product image not found.' });
      return sendBytes(rows[0].bytes, rows[0].content_type);
    }
    let file = null;
    if (/^\/share-images\/[A-Za-z0-9_.-]+$/.test(imagePath)) file = path.join(__dirname, 'web_preview', imagePath.slice(1));
    else if (/^\/?uploads\/[A-Za-z0-9_.-]+$/.test(imagePath)) file = path.join(uploadsDir, path.basename(imagePath));
    else if (/^\/?[A-Za-z0-9_.-]+$/.test(imagePath)) file = path.join(__dirname, 'web_preview', path.basename(imagePath));
    if (file && fs.existsSync(file)) {
      const bytes = fs.readFileSync(file);
      const meta = imageDimensions(bytes);
      const type = meta?.type || (/\.webp$/i.test(file) ? 'image/webp' : /\.png$/i.test(file) ? 'image/png' : 'image/jpeg');
      return sendBytes(bytes, type);
    }
    if (/^https?:\/\//i.test(imagePath)) return res.redirect(302, imagePath);
    // A site-relative picture on this server (e.g. a local sandbox picture).
    if (/^\/[A-Za-z0-9_./-]+$/.test(imagePath) && !imagePath.includes('..')) return res.redirect(302, imagePath);
    return res.status(404).json({ success: false, error: 'Product image not found.' });
  } catch (err) {
    console.error('[SHARE IMAGE] Read failed:', err.message);
    return res.status(500).json({ success: false, error: 'Product image could not be read.' });
  }
});

app.get(['/share/products/:id', '/share/products/:id/'], async (req, res) => {
  res.set('Cache-Control', 'public, max-age=300');
  let product;
  try {
    const [rows] = await pool.query(
      `SELECT p.id, p.name, p.sku, p.brand, p.mrp, p.img, p.description, p.status, p.category_key,
              COALESCE(c.title, p.category_key) AS category_title
         FROM products p
         LEFT JOIN categories c ON c.id = p.category_id OR c.key_name = p.category_key
        WHERE p.id = ? LIMIT 1`,
      [req.params.id]
    );
    product = rows[0];
  } catch (err) {
    console.error('[SHARE PAGE] Lookup failed:', err.message);
    return res.status(503).type('html').send('<!doctype html><title>Unavailable</title><p>Product details are temporarily unavailable.</p>');
  }
  if (!product || String(product.status || 'active').toLowerCase() === 'inactive') {
    return res.status(404).type('html').send('<!doctype html><meta name="robots" content="noindex"><title>Product not found</title><p>This product is no longer available.</p>');
  }

  const origin = requestOrigin(req);
  const pageUrl = `${origin}/share/products/${encodeURIComponent(product.id)}`;
  const preview = sharePreviewImage(productShareImagePath(product), origin);
  const imageUrl = preview.url;
  const mrp = shareRupees(product.mrp);
  const store = storefrontUrl(req);
  const storeLink = store ? `${store}/#/products/${encodeURIComponent(product.id)}` : '';
  const description = String(product.description || '').trim();
  const summary = [
    mrp && `MRP ${mrp}`,
    product.brand && `Brand: ${product.brand}`,
    product.category_title && `Category: ${product.category_title}`,
    product.sku && `SKU: ${product.sku}`,
  ].filter(Boolean).join(' · ');
  const ogDescription = [summary, description].filter(Boolean).join(' — ').slice(0, 280);
  const e = escapeShareHtml;

  res.type('html').send(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${e(product.name)} | RO Wholesale</title>
<meta name="description" content="${e(ogDescription)}">
<link rel="canonical" href="${e(pageUrl)}">
<meta property="og:type" content="product">
<meta property="og:site_name" content="RO Wholesale">
<meta property="og:title" content="${e(product.name)}${mrp ? ` — MRP ${e(mrp)}` : ''}">
<meta property="og:description" content="${e(ogDescription)}">
<meta property="og:url" content="${e(pageUrl)}">
<meta property="og:image" content="${e(imageUrl)}">
<meta property="og:image:secure_url" content="${e(imageUrl)}">
<meta property="og:image:type" content="${preview.type}">
${preview.width && preview.height ? `<meta property="og:image:width" content="${preview.width}">
<meta property="og:image:height" content="${preview.height}">` : ''}
<meta property="og:image:alt" content="${e(product.name)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${e(product.name)}">
<meta name="twitter:description" content="${e(ogDescription)}">
<meta name="twitter:image" content="${e(imageUrl)}">
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; background: #EEF5FB; color: #0F172A; }
  main { max-width: 560px; margin: 0 auto; padding: 24px 16px 40px; }
  .card { background: #fff; border-radius: 20px; box-shadow: 0 12px 32px rgba(15, 76, 129, .12); overflow: hidden; }
  .photo { background: linear-gradient(180deg, #F3F8FD, #fff); display: flex; justify-content: center; padding: 24px; }
  .photo img { width: 100%; max-height: 340px; object-fit: contain; }
  .body { padding: 20px 22px 24px; }
  .brand { color: #0F62FE; font-weight: 800; font-size: 12px; letter-spacing: .08em; text-transform: uppercase; }
  h1 { font-size: 22px; line-height: 1.25; margin: 6px 0 12px; }
  .mrp { font-size: 26px; font-weight: 800; margin: 0 0 4px; }
  .mrp small { font-size: 13px; color: #64748B; font-weight: 700; margin-right: 6px; }
  dl { display: grid; grid-template-columns: auto 1fr; gap: 6px 14px; margin: 16px 0; font-size: 14px; }
  dt { color: #64748B; } dd { margin: 0; font-weight: 600; word-break: break-word; }
  p.desc { color: #334155; line-height: 1.55; white-space: pre-line; }
  a.cta { display: block; text-align: center; background: #0F62FE; color: #fff; font-weight: 700; text-decoration: none; padding: 14px; border-radius: 12px; margin-top: 18px; }
  footer { text-align: center; color: #64748B; font-size: 12px; margin-top: 18px; }
</style>
</head>
<body>
<main>
  <article class="card">
    <div class="photo"><img src="${e(imageUrl)}" alt="${e(product.name)}" onerror="this.onerror=null;this.src='${e(origin)}/purifier.jpg'"></div>
    <div class="body">
      ${product.brand ? `<div class="brand">${e(product.brand)}</div>` : ''}
      <h1>${e(product.name)}</h1>
      ${mrp ? `<p class="mrp"><small>MRP</small>${e(mrp)}</p>` : ''}
      <dl>
        ${product.sku ? `<dt>SKU</dt><dd>${e(product.sku)}</dd>` : ''}
        ${product.category_title ? `<dt>Category</dt><dd>${e(product.category_title)}</dd>` : ''}
        ${product.brand ? `<dt>Brand</dt><dd>${e(product.brand)}</dd>` : ''}
      </dl>
      ${description ? `<p class="desc">${e(description)}</p>` : ''}
      ${storeLink ? `<a class="cta" href="${e(storeLink)}">View product in store</a>` : ''}
    </div>
  </article>
  <footer>RO Wholesale · Dealer prices are available after signing in.</footer>
</main>
</body>
</html>`);
});

// Admin: browse pictures already uploaded to Supabase Storage (read-only listing;
// the service key stays on the server). The chosen picture is saved as its public URL.
const storageBrowseConfig = () => ({
  supabaseUrl: String(process.env.SUPABASE_URL || '').trim(),
  serviceKey: String(process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim(),
});
// Folders are read from the bucket (so newly created ones appear); cached briefly.
let storageFolderCache = { at: 0, folders: null };
async function storageFoldersNow({ supabaseUrl, serviceKey }) {
  if (storageFolderCache.folders && Date.now() - storageFolderCache.at < 60000) return storageFolderCache.folders;
  const found = await listStorageFolders({ supabaseUrl, serviceKey });
  storageFolderCache = { at: Date.now(), folders: found.length ? found : STORAGE_FOLDERS };
  return storageFolderCache.folders;
}
app.get('/api/admin/storage-folders', requireAdminAuth, async (req, res) => {
  const { supabaseUrl, serviceKey } = storageBrowseConfig();
  if (!supabaseUrl || !serviceKey) return res.json({ success: true, configured: false, bucket: STORAGE_BUCKET, folders: STORAGE_FOLDERS, categoryFolders: CATEGORY_FOLDERS });
  try {
    const folders = await storageFoldersNow({ supabaseUrl, serviceKey });
    res.json({ success: true, configured: true, bucket: STORAGE_BUCKET, folders, categoryFolders: categoryFolders(folders) });
  } catch (error) {
    console.error('Storage folder list failed:', error.status || '', error.message);
    res.status(502).json({ success: false, error: 'Could not load folders from Supabase Storage. Please try again.' });
  }
});
app.get('/api/admin/storage-images', requireAdminAuth, async (req, res) => {
  const { supabaseUrl, serviceKey } = storageBrowseConfig();
  if (!supabaseUrl || !serviceKey) {
    return res.status(503).json({ success: false, configured: false, error: 'Choosing pictures from Supabase is not set up on this server (Supabase Storage key missing). Use Image URL or Upload Image.' });
  }
  try {
    const request = storageListRequest(req.query, await storageFoldersNow({ supabaseUrl, serviceKey }));
    if (request.error) return res.status(400).json({ success: false, error: request.error });
    const page = await listStorageImages({ supabaseUrl, serviceKey, ...request });
    res.json({ success: true, bucket: STORAGE_BUCKET, folder: request.folder, search: request.search, ...page });
  } catch (error) {
    console.error('Storage image list failed:', error.status || '', error.message);
    res.status(502).json({ success: false, error: 'Could not load pictures from Supabase Storage. Please try again.' });
  }
});

// Admin edit conflicts (optimistic concurrency, no schema change): a product's
// version is a hash of its saved row. The Admin Panel sends the version it
// loaded as `If-Match`; if the row has changed since, the write is refused
// with 409 and nothing is saved. Requests without If-Match work as before.
function productVersion(row) {
  const norm = v => (v == null ? null
    : v instanceof Date ? v.toISOString()
      : typeof v === 'object' && !Buffer.isBuffer(v) ? v
        : String(v));
  const pairs = Object.keys(row).sort().map(k => [k, norm(row[k])]);
  return crypto.createHash('sha256').update(JSON.stringify(pairs)).digest('hex').slice(0, 32);
}
function expectedProductVersion(req) {
  const raw = String(req.get('if-match') || '').trim().replace(/^W\//, '').replace(/^"|"$/g, '');
  return /^[0-9a-f]{32}$/.test(raw) ? raw : null;
}
const PRODUCT_CONFLICT_ERROR = 'This product was changed by someone else after you opened it. Your changes were not saved. Reload the product and enter your changes again.';
/** Runs `write(conn)` only while the locked row still has `version`; false = conflict (nothing written). */
async function writeIfProductUnchanged(lockSql, lockParams, version, write) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [rows] = await conn.query(lockSql, lockParams);
    if (!rows[0] || productVersion(rows[0]) !== version) { await conn.rollback(); return false; }
    await write(conn);
    await conn.commit();
    return true;
  } catch (error) {
    await conn.rollback().catch(() => {});
    throw error;
  } finally {
    conn.release();
  }
}

// Admin Endpoint: Get all products (active + inactive)
app.get('/api/admin/products', requireAdminAuth, async (req, res) => {
  try {
    const [rows] = await pool.query(`SELECT * FROM products ORDER BY created_at DESC`);
    const products = rows.map(p => ({
          id: p.id,
          category: p.category_key,
          brand: p.brand,
          name: p.name,
          purchase_price: parseFloat(p.purchase_price || 0),
          purchasePrice: parseFloat(p.purchase_price || 0),
          price: parseFloat(p.price),
          mrp: parseFloat(p.mrp),
          // Cabinet products only; null when not set (or before migration 009).
          cabinet_price: p.cabinet_price == null ? null : Number(p.cabinet_price),
          moq: p.moq,
          // Same rule as cart and checkout (order_rules.js).
          min_order_quantity: minOrderQuantity(p),
          max_order_quantity: maxOrderQuantity(p),
          stock_enforced: stockEnforced(),
          availability: availability(p),
          badge: p.badge,
          rating: p.rating,
          img: p.img,
          sku: p.sku,
          desc: p.description,
          specs: typeof p.specs_json === 'string' ? JSON.parse(p.specs_json || '{}') : (p.specs_json || {}),
          features: typeof p.features_json === 'string' ? JSON.parse(p.features_json || '[]') : (p.features_json || []),
          applications: p.applications,
          stock_quantity: p.stock_quantity == null ? null : Number(p.stock_quantity),
          min_stock: p.min_stock == null ? null : Number(p.min_stock),
          status: p.status || 'active',
          // Sent back as If-Match when editing or deleting (409 if changed since).
          version: productVersion(p)
    }));
    return res.json({ success: true, count: products.length, products });
  } catch (err) {
    console.error('[API ERROR] Admin products:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Product data could not be loaded.' });
  }
});

// Admin Endpoint: Add New Product
app.post('/api/admin/products', requireAdminAuth, async (req, res) => {
  try {
    const { name, sku, category, brand, purchase_price, purchasePrice, price, mrp, moq, badge, rating, img, image, desc, short_desc, full_desc, specs, features, applications, status } = req.body;

    const cleanName = (name || '').trim();
    const cleanSku = (sku || '').trim().toUpperCase();
    const cleanCat = (category || 'spares').trim().toLowerCase();
    // Brand, Purchase Price, Dealer Price and MRP are optional: blank = not set.
    const cleanPrice = optionalAmount(price);
    const cleanPurchasePrice = optionalAmount(purchase_price !== undefined ? purchase_price : purchasePrice);
    // Stock is never assumed: the admin must enter the counted quantity (0 or more).
    if (isBlankField(req.body.stock_quantity ?? req.body.stock)) {
      return res.status(400).json({ success: false, error: 'Stock quantity is required (enter the counted stock, 0 or more).' });
    }
    const cleanStock = Number(req.body.stock_quantity ?? req.body.stock);
    const cleanMinStock = Number(req.body.min_stock ?? req.body.minStock ?? 10);
    if (![cleanStock, cleanMinStock].every(value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647) ||
        [req.body.stock_quantity, req.body.stock, req.body.min_stock, req.body.minStock].some(value => value !== undefined && (!['number', 'string'].includes(typeof value) || (typeof value === 'string' && !value.trim())))) {
      return res.status(400).json({ success: false, error: 'Stock quantity and minimum stock must be nonnegative integers.' });
    }

    if (!cleanName) return res.status(400).json({ success: false, error: 'Product name is required.' });
    if (!cleanSku) return res.status(400).json({ success: false, error: 'Product SKU is required.' });
    if (!isBlankField(price) && (isNaN(cleanPrice) || cleanPrice <= 0)) return res.status(400).json({ success: false, error: 'Dealer price must be greater than zero.' });
    const priceError = productPriceError({ purchasePrice: cleanPurchasePrice, price: cleanPrice, mrp });
    if (priceError) return res.status(400).json({ success: false, error: priceError });

    let categoryId;
    let categoryKey;
    try {
      const [categoryRows] = await pool.query(
        `SELECT id, key_name FROM categories WHERE LOWER(id) = ? OR LOWER(key_name) = ? OR LOWER(title) = ? LIMIT 1`,
        [cleanCat, cleanCat, cleanCat]
      );
      if (!categoryRows.length) return res.status(400).json({ success: false, error: 'Select an existing product category.' });
      categoryId = categoryRows[0].id;
      // Store the category's own key (as bulk import does), not the text the
      // client sent, so the product lists under the right customer category.
      categoryKey = categoryRows[0].key_name || cleanCat;
    } catch (dbErr) {
      return res.status(503).json({ success: false, error: 'database is unavailable. No product was saved.' });
    }
    const cabinetPrice = cabinetPriceFor(isCabinetCategory(categoryId, categoryKey), req.body.cabinet_price ?? req.body.cabinetPrice);
    if (cabinetPrice.error) return res.status(400).json({ success: false, error: cabinetPrice.error });
    const withCabinetColumn = await hasCabinetPriceColumn();
    if (cabinetPrice.value !== null && !withCabinetColumn) return res.status(503).json({ success: false, error: CABINET_PRICE_NO_COLUMN });

    // Check duplicate SKU
    const [duplicateRows] = await pool.query('SELECT sku FROM products WHERE UPPER(sku) = ? LIMIT 1', [cleanSku]);
    if (duplicateRows.length) {
      return res.status(400).json({ success: false, error: `Product SKU "${cleanSku}" already exists. Please use a unique SKU.` });
    }

    // One "Name: Value" per line (or JSON); each line is its own specification.
    const parsedSpecs = parseSpecifications(specs);
    if (parsedSpecs.error) return res.status(400).json({ success: false, error: parsedSpecs.error });
    const cleanSpecs = parsedSpecs.value;

    let cleanFeatures = [];
    if (Array.isArray(features)) {
      cleanFeatures = features.map(f => String(f).trim()).filter(Boolean);
    } else if (typeof features === 'string' && features.trim()) {
      cleanFeatures = features.split(/\r?\n/).map(f => f.trim()).filter(Boolean); // one per line (commas allowed)
    }

    const rawImg = (img || image || '').trim();
    let cleanImg = 'purifier.jpg';
    if (rawImg) {
      try {
        cleanImg = await storeProductImage(rawImg);
      } catch (imgErr) {
        console.error('[PRODUCT IMAGE] Save failed:', imgErr.message);
        return res.status(400).json({ success: false, error: imgErr.message || 'Product image could not be saved.' });
      }
    }

    const cleanDesc = (desc || short_desc || full_desc || '').trim();
    const cleanBrand = String(brand ?? '').trim(); // blank = not set (column is NOT NULL)
    // Blank = not set; never a made-up default text.
    const cleanApps = isBlankField(applications) ? null : String(applications).trim();

    const prodId = `prod_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}`;
    const newProd = {
      id: prodId,
      sku: cleanSku,
      name: cleanName,
      category: categoryKey,
      category_id: categoryId,
      brand: cleanBrand,
      purchase_price: cleanPurchasePrice,
      purchasePrice: cleanPurchasePrice,
      price: cleanPrice,
      stock_quantity: cleanStock,
      min_stock: cleanMinStock,
      // Blank MRP = not available (0); never estimated from the dealer price.
      mrp: optionalAmount(mrp),
      cabinet_price: cabinetPrice.value,
      // Blank MOQ / rating stay unset ("MOQ not set", no stars); never invented.
      moq: isBlankField(moq) ? null : (moq.toString().startsWith('MOQ:') ? String(moq).trim() : `MOQ: ${String(moq).trim()}`),
      badge: String(badge || '').trim(),
      rating: isBlankField(rating) ? null : String(rating).trim(),
      img: cleanImg,
      desc: cleanDesc,
      specs: cleanSpecs,
      features: cleanFeatures,
      applications: cleanApps,
      status: status === 'inactive' ? 'inactive' : 'active',
      createdAt: new Date().toISOString()
    };

    // Persist to database first; never report success from the JSON fallback.
    try {
      await pool.query(
        `INSERT INTO products (id, category_id, category_key, sku, name, brand, purchase_price, price, mrp, moq, badge, rating, img, description, specs_json, features_json, applications, status, stock_quantity, min_stock${withCabinetColumn ? ', cabinet_price' : ''})
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?${withCabinetColumn ? ', ?' : ''})`,
        [
          newProd.id, newProd.category_id, newProd.category, newProd.sku, newProd.name, newProd.brand,
          newProd.purchase_price, newProd.price, newProd.mrp, newProd.moq, newProd.badge, newProd.rating,
          newProd.img, newProd.desc, JSON.stringify(newProd.specs), JSON.stringify(newProd.features),
          newProd.applications, newProd.status, newProd.stock_quantity, newProd.min_stock,
          ...(withCabinetColumn ? [newProd.cabinet_price] : [])
        ]
      );
    } catch (dbErr) {
      if (dbErr.code === 'ER_DUP_ENTRY') return res.status(409).json({ success: false, error: `Product SKU "${cleanSku}" already exists.` });
      console.error('[DATABASE PRODUCT INSERT FAILED]', dbErr.message);
      return res.status(503).json({ success: false, error: 'database is unavailable. No product was saved.' });
    }

    return res.status(201).json({
      success: true,
      message: `🎉 Product "${cleanName}" created successfully!`,
      product: newProd
    });
  } catch (err) {
    console.error('[API ERROR] Add product:', err);
    return res.status(500).json({ success: false, error: 'Server error creating product.' });
  }
});

// Admin Endpoint: Bulk Import Products
app.post('/api/admin/products/bulk', requireAdminAuth, async (req, res) => {
  try {
    const rawProducts = Array.isArray(req.body.products) ? req.body.products : [];
    if (rawProducts.length === 0) {
      return res.status(400).json({ success: false, error: 'No product rows provided for bulk import.' });
    }

    const existingSkus = new Set();

    try {
      const [rows] = await pool.query('SELECT UPPER(sku) as sku FROM products');
      rows.forEach(r => { if (r.sku) existingSkus.add(r.sku.toUpperCase()); });
    } catch(e) {
      return res.status(503).json({ success: false, error: 'database is unavailable. No products were saved. Check the database connection and try again.' });
    }

    // Load database categories for dynamic resolution
    let databaseCategories;
    try {
      const [cRows] = await pool.query('SELECT id, key_name, title FROM categories');
      databaseCategories = cRows;
    } catch(e) {
      return res.status(503).json({ success: false, error: 'database is unavailable. No products were saved.' });
    }

    const resolveCategory = (inputCat) => {
      if (!inputCat) return null;
      const clean = String(inputCat).trim().toLowerCase();

      for (const r of databaseCategories) {
        if ((r.id || '').toLowerCase() === clean) return { id: r.id, key: r.key_name || 'spares', title: r.title };
        if ((r.key_name || '').toLowerCase() === clean) return { id: r.id, key: r.key_name || 'spares', title: r.title };
        if ((r.title || '').toLowerCase() === clean) return { id: r.id, key: r.key_name || 'spares', title: r.title };
      }

      return null;
    };

    // dryRun: validate every row and report, save nothing (no images either).
    const dryRun = req.body.dryRun === true;
    const validToImport = [];
    const skippedSKUs = [];
    const rowResults = [];
    const skusInUpload = new Set();

    for (let index = 0; index < rawProducts.length; index++) {
      const raw = rawProducts[index] && typeof rawProducts[index] === 'object' ? rawProducts[index] : {};
      const rowNumber = Number.isSafeInteger(Number(raw.row)) && Number(raw.row) > 0 ? Number(raw.row) : index + 1;
      const v = validateBulkProductRow(raw, { resolveCategory, existingSkus, skusInUpload });
      const result = { row: rowNumber, sku: v.sku || '', name: v.name || '', status: v.status, errors: v.errors };
      if (v.status !== 'ready') {
        skippedSKUs.push({ row: rowNumber, sku: v.sku || 'UNKNOWN', reason: v.errors.join(' ') });
        rowResults.push(result);
        continue;
      }
      skusInUpload.add(v.sku);
      let cleanImg = 'purifier.jpg'; // placeholder name: the app shows its built-in picture
      if (v.image) {
        if (dryRun) result.image = 'will be saved';
        else {
          try {
            cleanImg = await storeProductImage(v.image);
          } catch (imgErr) {
            const reason = `Image could not be saved: ${imgErr.message}`;
            skippedSKUs.push({ row: rowNumber, sku: v.sku, reason });
            rowResults.push({ ...result, status: 'error', errors: [reason] });
            skusInUpload.delete(v.sku);
            continue;
          }
        }
      }
      result.values = { ...v.product, img: v.image ? (dryRun ? '(uploaded image)' : cleanImg) : null };
      rowResults.push(result);
      validToImport.push({
        id: `prod_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}_${index}`,
        ...v.product,
        purchasePrice: v.product.purchase_price,
        img: cleanImg,
        createdAt: new Date().toISOString()
      });
    }

    const summary = {
      total: rawProducts.length,
      ready: rowResults.filter(r => r.status === 'ready').length,
      errors: rowResults.filter(r => r.status === 'error').length,
      duplicates: rowResults.filter(r => r.status === 'duplicate').length,
    };
    if (dryRun) {
      return res.json({ success: true, dryRun: true, summary, rows: rowResults, skipped: skippedSKUs });
    }

    if (validToImport.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'No valid products to import. All rows were either duplicates or missing required fields.',
        summary,
        rows: rowResults,
        skipped: skippedSKUs
      });
    }

    // Save only new SKU values. The unique constraint handles duplicates
    // that race the preflight lookup without modifying the existing product.
    const dbErrors = [];
    const withCabinetColumn = await hasCabinetPriceColumn();

    for (const p of validToImport) {
      try {
        if (p.cabinet_price !== null && !withCabinetColumn) throw Object.assign(new Error(CABINET_PRICE_NO_COLUMN), { code: 'NO_CABINET_COLUMN' });
        const [insertResult] = await pool.query(
          `INSERT INTO products (id, category_id, category_key, sku, name, brand, purchase_price, price, mrp, moq, badge, rating, img, description, specs_json, features_json, applications, status, stock_quantity, min_stock${withCabinetColumn ? ', cabinet_price' : ''})
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?${withCabinetColumn ? ', ?' : ''})`,
          [
            p.id, p.category_id, p.category, p.sku, p.name, p.brand,
            p.purchase_price, p.price, p.mrp, p.moq, p.badge, p.rating,
            p.img, p.desc, JSON.stringify(p.specs), JSON.stringify(p.features),
            p.applications, p.status, p.stock_quantity, p.min_stock,
            ...(withCabinetColumn ? [p.cabinet_price] : [])
          ]
        );
        if (insertResult.affectedRows !== 1) {
          dbErrors.push({ sku: p.sku, reason: `Duplicate SKU "${p.sku}" already exists in database` });
        }
      } catch (dbErr) {
        console.error(`❌ [DATABASE PRODUCT INSERT FAILED] SKU "${p.sku}":`, dbErr.message);
        dbErrors.push({
          sku: p.sku,
          reason: dbErr.code === 'ER_DUP_ENTRY'
            ? `Duplicate SKU "${p.sku}" already exists in database`
            : dbErr.code === 'NO_CABINET_COLUMN' ? dbErr.message : 'database could not save this product.'
        });
      }
    }

    // Mirror only confirmed database writes, so failed rows can be retried safely.
    const persistedProducts = validToImport.filter(p => !dbErrors.some(e => e.sku === p.sku));
    const totalSkipped = [...skippedSKUs, ...dbErrors];
    for (const e of dbErrors) {
      const r = rowResults.find(x => x.sku === e.sku && x.status === 'ready');
      if (r) { r.status = 'error'; r.errors = [e.reason]; delete r.values; }
    }
    rowResults.filter(r => r.status === 'ready').forEach(r => { r.status = 'imported'; });

    return res.status(201).json({
      success: true,
      message: `🎉 ${validToImport.length - dbErrors.length} products imported successfully!`,
      importedCount: validToImport.length - dbErrors.length,
      skippedCount: totalSkipped.length,
      summary: { ...summary, imported: persistedProducts.length },
      rows: rowResults,
      imported: persistedProducts,
      skipped: totalSkipped
    });
  } catch (err) {
    console.error('[API ERROR] Bulk import products:', err);
    return res.status(500).json({ success: false, error: `Server Error (Status 500): ${err.message}` });
  }
});

// Admin Endpoint: Edit Product
app.put('/api/admin/products/:id', requireAdminAuth, async (req, res) => {
  try {
    const targetId = req.params.id;
    const { name, sku, category, brand, purchase_price, purchasePrice, price, mrp, moq, badge, rating, img, image, desc, short_desc, full_desc, specs, features, applications, status } = req.body;

    const cleanName = (name || '').trim();
    const cleanSku = (sku || '').trim().toUpperCase();
    const cleanCat = (category || 'spares').trim().toLowerCase();

    if (!cleanName) return res.status(400).json({ success: false, error: 'Product name is required.' });
    if (!cleanSku) return res.status(400).json({ success: false, error: 'Product SKU is required.' });

    const [databaseProducts] = await pool.query('SELECT * FROM products WHERE id = ? OR sku = ? LIMIT 1', [targetId, targetId]);
    const databaseProduct = databaseProducts[0];
    if (!databaseProduct) return res.status(404).json({ success: false, error: 'Product not found.' });
    const wantedVersion = expectedProductVersion(req);
    if (wantedVersion && productVersion(databaseProduct) !== wantedVersion) {
      return res.status(409).json({ success: false, conflict: true, error: PRODUCT_CONFLICT_ERROR });
    }
    // Optional money fields: a value is validated; blank keeps the saved value.
    const cleanPrice = optionalAmount(price, Number(databaseProduct.price || 0));
    if (!isBlankField(price) && (isNaN(cleanPrice) || cleanPrice <= 0)) return res.status(400).json({ success: false, error: 'Dealer price must be greater than zero.' });
    const rawPP = purchase_price !== undefined ? purchase_price : purchasePrice;
    const cleanPurchasePrice = optionalAmount(rawPP, Number(databaseProduct.purchase_price || 0));
    const editPriceError = productPriceError({ purchasePrice: cleanPurchasePrice, price: cleanPrice, mrp });
    if (editPriceError) return res.status(400).json({ success: false, error: editPriceError });
    // Check duplicate SKU using the authoritative database catalog.
    const [duplicateRows] = await pool.query('SELECT id FROM products WHERE UPPER(sku) = ? AND id <> ? LIMIT 1', [cleanSku, databaseProduct.id]);
    if (duplicateRows.length) {
      return res.status(400).json({ success: false, error: `Product SKU "${cleanSku}" is already used by another product.` });
    }

    const parseDbJson = (value, fallback) => {
      if (value && typeof value === 'object') return value;
      try { return value ? JSON.parse(value) : fallback; } catch (_) { return fallback; }
    };
    const existing = {
      id: databaseProduct.id,
      sku: databaseProduct.sku,
      name: databaseProduct.name,
      category: databaseProduct.category_key,
      brand: databaseProduct.brand,
      purchase_price: databaseProduct.purchase_price,
      price: databaseProduct.price,
      mrp: databaseProduct.mrp,
      moq: databaseProduct.moq,
      badge: databaseProduct.badge,
      rating: databaseProduct.rating,
      img: databaseProduct.img,
      desc: databaseProduct.description,
      specs: parseDbJson(databaseProduct.specs_json, {}),
      features: parseDbJson(databaseProduct.features_json, []),
      applications: databaseProduct.applications,
      status: databaseProduct.status,
      stock_quantity: databaseProduct.stock_quantity,
      min_stock: databaseProduct.min_stock
    };
    const [categoryRows] = await pool.query(
      'SELECT id, key_name FROM categories WHERE LOWER(id) = ? OR LOWER(key_name) = ? OR LOWER(title) = ? LIMIT 1',
      [cleanCat, cleanCat, cleanCat]
    );
    if (!categoryRows.length) return res.status(400).json({ success: false, error: 'Select an existing product category.' });
    const categoryRow = categoryRows[0];
    // Cabinet Price: required for Cabinet (blank keeps the saved one); moving the
    // product to another category clears it.
    const savedCabinetPrice = databaseProduct.cabinet_price == null ? null : Number(databaseProduct.cabinet_price);
    const cabinetPrice = cabinetPriceFor(isCabinetCategory(categoryRow.id, categoryRow.key_name), req.body.cabinet_price ?? req.body.cabinetPrice, savedCabinetPrice);
    if (cabinetPrice.error) return res.status(400).json({ success: false, error: cabinetPrice.error });
    const withCabinetColumn = await hasCabinetPriceColumn();
    if (cabinetPrice.value !== null && !withCabinetColumn) return res.status(503).json({ success: false, error: CABINET_PRICE_NO_COLUMN });
    const cleanStock = Number(req.body.stock_quantity ?? req.body.stock ?? existing.stock_quantity ?? existing.stock ?? 50);
    const cleanMinStock = Number(req.body.min_stock ?? req.body.minStock ?? existing.min_stock ?? existing.minStock ?? 10);
    if (![cleanStock, cleanMinStock].every(value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647) ||
        [req.body.stock_quantity, req.body.stock, req.body.min_stock, req.body.minStock].some(value => value !== undefined && (!['number', 'string'].includes(typeof value) || (typeof value === 'string' && !value.trim())))) {
      return res.status(400).json({ success: false, error: 'Stock quantity and minimum stock must be nonnegative integers.' });
    }

    // Not sent (or a blank string) keeps the saved specifications; an object
    // (the Admin form) or "Name: Value" lines replace them, one entry per line.
    let cleanSpecs = existing.specs || {};
    if (specs !== undefined && specs !== null && !(typeof specs === 'string' && !specs.trim())) {
      const parsedSpecs = parseSpecifications(specs);
      if (parsedSpecs.error) return res.status(400).json({ success: false, error: parsedSpecs.error });
      cleanSpecs = parsedSpecs.value;
    }

    let cleanFeatures = existing.features || [];
    if (Array.isArray(features)) {
      cleanFeatures = features.map(f => String(f).trim()).filter(Boolean);
    } else if (typeof features === 'string' && features.trim()) {
      cleanFeatures = features.split(/\r?\n/).map(f => f.trim()).filter(Boolean); // one per line (commas allowed)
    }

    let cleanImg = existing.img || 'purifier.jpg';
    const rawImg = img !== undefined ? img : image;
    if (rawImg !== undefined) {
      if (rawImg === null || !String(rawImg).trim()) {
        cleanImg = '';
      } else {
        try { cleanImg = await storeProductImage(String(rawImg).trim()); }
        catch (imgErr) { return res.status(400).json({ success: false, error: imgErr.message || 'Product image could not be saved.' }); }
      }
    }
    const updatedProd = {
      ...existing,
      stock_quantity: cleanStock,
      min_stock: cleanMinStock,
      name: cleanName,
      sku: cleanSku,
      category: categoryRow.key_name,
      category_id: categoryRow.id,
      // Optional: blank keeps the saved brand (never a made-up one).
      brand: String(isBlankField(brand) ? (existing.brand || '') : brand).trim(),
      purchase_price: cleanPurchasePrice,
      purchasePrice: cleanPurchasePrice,
      price: cleanPrice,
      // A blank MRP keeps the saved value (0 = not available); never estimated.
      mrp: (mrp !== undefined && mrp !== null && String(mrp).trim() !== '' && !isNaN(parseFloat(mrp)))
        ? parseFloat(mrp)
        : Number(existing.mrp || 0),
      // A blank MOQ field keeps the saved value, including "not set" (never 1).
      // An unchanged MOQ is saved exactly as it was (no "MOQ: " prefix added).
      moq: moq
        ? (String(moq).trim() === String(existing.moq ?? '').trim() || moq.toString().startsWith('MOQ:') ? moq : `MOQ: ${moq}`)
        : (existing.moq || null),
      badge: String(badge !== undefined ? badge : existing.badge || '').trim(),
      // Editing never invents a rating: no rating sent keeps the saved one,
      // including none.
      rating: rating !== undefined && rating !== null && String(rating).trim() !== ''
        ? String(rating).trim()
        : (existing.rating ?? null),
      img: cleanImg,
      // A description that is sent (even empty) replaces the saved one, so an
      // admin can also clear it; not sent keeps the saved description.
      desc: (desc !== undefined && desc !== null ? String(desc) : (short_desc || full_desc || existing.desc || '')).trim(),
      specs: cleanSpecs,
      features: cleanFeatures,
      applications: (applications !== undefined ? applications : existing.applications || '').trim(),
      status: status === 'inactive' ? 'inactive' : 'active',
      cabinet_price: cabinetPrice.value
    };
    // A field that was never set and comes back empty from the form stays unset
    // (NULL), so an edit such as a stock update changes only what was changed.
    const isEmptyValue = v => v == null || (typeof v === 'string' && !v.trim())
      || (Array.isArray(v) ? v.length === 0 : typeof v === 'object' && Object.keys(v).length === 0);
    for (const [field, column] of [['badge', 'badge'], ['desc', 'description'], ['applications', 'applications'], ['specs', 'specs_json'], ['features', 'features_json']]) {
      if (databaseProduct[column] == null && isEmptyValue(updatedProd[field])) updatedProd[field] = null;
    }

    const updateSql = `UPDATE products SET category_id = ?, category_key = ?, sku = ?, name = ?, brand = ?, purchase_price = ?, price = ?, mrp = ?, moq = ?, badge = ?, rating = ?, img = ?, description = ?, specs_json = ?, features_json = ?, applications = ?, status = ?, stock_quantity = ?, min_stock = ?${withCabinetColumn ? ', cabinet_price = ?' : ''} WHERE id = ?`;
    const updateParams = [
        updatedProd.category_id, updatedProd.category, updatedProd.sku, updatedProd.name, updatedProd.brand,
        updatedProd.purchase_price, updatedProd.price, updatedProd.mrp, updatedProd.moq, updatedProd.badge, updatedProd.rating,
        updatedProd.img, updatedProd.desc,
        updatedProd.specs == null ? null : JSON.stringify(updatedProd.specs),
        updatedProd.features == null ? null : JSON.stringify(updatedProd.features),
        updatedProd.applications, updatedProd.status, updatedProd.stock_quantity, updatedProd.min_stock,
        ...(withCabinetColumn ? [updatedProd.cabinet_price] : []),
        databaseProduct.id
    ];
    if (wantedVersion) {
      // Re-checked under a row lock, so two admins can never overwrite each other.
      const written = await writeIfProductUnchanged('SELECT * FROM products WHERE id = ? FOR UPDATE', [databaseProduct.id], wantedVersion,
        conn => conn.query(updateSql, updateParams));
      if (!written) return res.status(409).json({ success: false, conflict: true, error: PRODUCT_CONFLICT_ERROR });
    } else {
      await pool.query(updateSql, updateParams);
    }
    return res.status(200).json({
      success: true,
      message: `🎉 Product "${cleanName}" updated successfully!`,
      product: updatedProd
    });
  } catch (err) {
    console.error('[API ERROR] Edit product:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Product was not updated.' });
  }
});

// Admin Endpoint: Delete Product
app.delete('/api/admin/products/:id', requireAdminAuth, async (req, res) => {
  try {
    const targetId = req.params.id;
    const wantedVersion = expectedProductVersion(req);
    let result;
    if (wantedVersion) {
      const [found] = await pool.query('SELECT id FROM products WHERE id = ? OR sku = ? LIMIT 1', [targetId, targetId]);
      if (!found.length) return res.status(404).json({ success: false, error: 'Product not found.' });
      const written = await writeIfProductUnchanged('SELECT * FROM products WHERE id = ? FOR UPDATE', [found[0].id], wantedVersion,
        async conn => { [result] = await conn.query('DELETE FROM products WHERE id = ?', [found[0].id]); });
      if (!written) return res.status(409).json({ success: false, conflict: true, error: 'This product was changed by someone else after you opened the list. It was not deleted. Reload and check it first.' });
    } else {
      [result] = await pool.query(`DELETE FROM products WHERE id = ? OR sku = ?`, [targetId, targetId]);
    }
    if (!result.affectedRows) return res.status(404).json({ success: false, error: 'Product not found.' });
    return res.status(200).json({
      success: true,
      message: 'Product deleted successfully!'
    });
  } catch (err) {
    console.error('[API ERROR] Delete product:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Product was not deleted.' });
  }
});

// -----------------------------------------------------------------------------
// CATEGORY ENDPOINTS (PUBLIC & ADMIN)
// -----------------------------------------------------------------------------

app.get('/api/categories', async (req, res) => {
  try {
    const [rows] = await pool.query(`SELECT * FROM categories ORDER BY display_order ASC`);
    res.set('Cache-Control', 'no-store');
    return res.json({ success: true, count: rows.length, categories: rows });
  } catch (err) {
    console.error('[API ERROR] Get categories:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Category data could not be loaded.' });
  }
});

app.get('/api/admin/categories', requireAdminAuth, async (req, res) => {
  try {
    const [rows] = await pool.query(`SELECT * FROM categories ORDER BY display_order ASC`);
    res.set('Cache-Control', 'no-store');
    return res.json({ success: true, count: rows.length, categories: rows });
  } catch (err) {
    console.error('[API ERROR] Admin categories:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Category data could not be loaded.' });
  }
});

app.post('/api/admin/categories', requireAdminAuth, async (req, res) => {
  try {
    const { title, name, key_name, key, description, badge_text, icon_color, image_url, image, img, display_order } = req.body;

    const catTitle = (title || name || '').trim();
    const catKey = (key_name || key || '').trim().toLowerCase().replace(/\s+/g, '_');

    if (!catTitle) return res.status(400).json({ success: false, error: 'Category title/name is required.' });
    if (!catKey) return res.status(400).json({ success: false, error: 'Category key is required.' });

    let categoryCount;
    try {
      const [[duplicate]] = await pool.query('SELECT id FROM categories WHERE LOWER(key_name) = ? OR LOWER(title) = ? LIMIT 1', [catKey, catTitle.toLowerCase()]);
      if (duplicate) return res.status(409).json({ success: false, error: 'Category key or name already exists.' });
      const [[countRow]] = await pool.query('SELECT COUNT(*) AS count FROM categories');
      categoryCount = Number(countRow.count || 0);
    } catch (dbErr) {
      return res.status(503).json({ success: false, error: 'database is unavailable. No category was saved.' });
    }

    let processedImage = 'cat_spares.jpg';
    try {
      const rawImg = image_url || image || img;
      if (rawImg) processedImage = await storeProductImage(rawImg, 'cat');
    } catch (imgErr) {
      return res.status(400).json({ success: false, error: imgErr.message });
    }

    const catId = `CAT_${Date.now()}`;
    const newCat = {
      id: catId,
      key_name: catKey,
      key: catKey,
      title: catTitle,
      badge_text: (badge_text || '⚡ B2B WHOLESALE').trim(),
      icon_color: (icon_color || '#0F62FE').trim(),
      image_url: processedImage,
      display_order: parseInt(display_order || categoryCount + 1, 10),
      description: (description || '').trim()
    };

    try {
      await pool.query(
        `INSERT INTO categories (id, key_name, title, description, badge_text, icon_color, image_url, display_order)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [newCat.id, newCat.key_name, newCat.title, newCat.description, newCat.badge_text, newCat.icon_color, newCat.image_url, newCat.display_order]
      );
    } catch (dbErr) {
      if (dbErr.code === 'ER_DUP_ENTRY') return res.status(409).json({ success: false, error: 'That category key already exists.' });
      console.error('[DATABASE CATEGORY INSERT FAILED]', dbErr.message);
      return res.status(503).json({ success: false, error: 'database is unavailable. No category was saved.' });
    }

    return res.status(201).json({
      success: true,
      message: `🎉 Category "${catTitle}" created successfully!`,
      category: newCat
    });
  } catch (err) {
    console.error('[API ERROR] Add category:', err);
    return res.status(500).json({ success: false, error: 'Server error creating category.' });
  }
});

app.put('/api/admin/categories/:id', requireAdminAuth, async (req, res) => {
  try {
    const targetId = req.params.id;
    const { title, name, key_name, key, description, badge_text, icon_color, image_url, image, img, display_order } = req.body;

    const catTitle = (title || name || '').trim();
    const catKey = (key_name || key || '').trim().toLowerCase().replace(/\s+/g, '_');

    if (!catTitle) return res.status(400).json({ success: false, error: 'Category title/name is required.' });

    const [categoryRows] = await pool.query(`SELECT * FROM categories WHERE id = ? OR key_name = ? LIMIT 1`, [targetId, targetId]);
    const existing = categoryRows[0] || null;
    if (!existing) return res.status(404).json({ success: false, error: 'Category not found.' });

    let processedImage = existing.image_url;
    const rawImg = image_url !== undefined ? image_url : (image !== undefined ? image : img);
    if (rawImg !== undefined) {
      try {
        processedImage = rawImg ? await storeProductImage(rawImg, 'cat') : '';
      } catch (imgErr) {
        return res.status(400).json({ success: false, error: imgErr.message });
      }
    }

    const updatedCat = {
      ...existing,
      title: catTitle,
      key_name: catKey || existing.key_name,
      key: catKey || existing.key,
      badge_text: badge_text !== undefined ? badge_text : existing.badge_text,
      icon_color: icon_color !== undefined ? icon_color : existing.icon_color,
      image_url: processedImage,
      display_order: parseInt(display_order !== undefined ? display_order : existing.display_order, 10),
      description: description !== undefined ? description : existing.description
    };

    const previousKey = existing.key_name || existing.key || targetId;
    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      await connection.query(
        `UPDATE categories SET title = ?, key_name = ?, description = ?, badge_text = ?, icon_color = ?, image_url = ?, display_order = ? WHERE id = ? OR key_name = ?`,
        [updatedCat.title, updatedCat.key_name, updatedCat.description, updatedCat.badge_text, updatedCat.icon_color, updatedCat.image_url, updatedCat.display_order, targetId, targetId]
      );
      await connection.query(
        `UPDATE products SET category_key = ? WHERE category_id = ? OR category_key = ?`,
        [updatedCat.key_name, existing.id || targetId, previousKey]
      );
      await connection.commit();
    } catch (dbErr) {
      await connection.rollback();
      if (dbErr.code === 'ER_DUP_ENTRY') return res.status(409).json({ success: false, error: 'That category key already exists.' });
      console.error('[DATABASE CATEGORY UPDATE FAILED]', dbErr.message);
      return res.status(503).json({ success: false, error: 'database is unavailable. Category was not changed.' });
    } finally {
      connection.release();
    }

    return res.status(200).json({
      success: true,
      message: `🎉 Category "${catTitle}" updated successfully!`,
      category: updatedCat
    });
  } catch (err) {
    console.error('[API ERROR] Edit category:', err);
    return res.status(500).json({ success: false, error: 'Server error updating category.' });
  }
});

app.delete('/api/admin/categories/:id', requireAdminAuth, async (req, res) => {
  try {
    const targetId = req.params.id;
    let dbCategory;
    try {
      const [rows] = await pool.query(`SELECT id, key_name, title FROM categories WHERE id = ? OR key_name = ? LIMIT 1`, [targetId, targetId]);
      dbCategory = rows[0];
    } catch (dbErr) {
      return res.status(503).json({ success: false, error: 'database is unavailable. Category was not deleted.' });
    }
    if (!dbCategory) return res.status(404).json({ success: false, error: 'Category not found.' });
    const targetKey = dbCategory.key_name;

    let reassignedCount = 0;
    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      const [updated] = await connection.query(
        `UPDATE products SET category_key = 'spares', category_id = (SELECT id FROM categories WHERE key_name = 'spares' LIMIT 1) WHERE category_key = ? OR category_id = ?`,
        [targetKey, dbCategory.id]
      );
      reassignedCount = updated.affectedRows || 0;
      await connection.query(`DELETE FROM categories WHERE id = ?`, [dbCategory.id]);
      await connection.commit();
    } catch (dbErr) {
      await connection.rollback();
      console.error('[DATABASE CATEGORY DELETE FAILED]', dbErr.message);
      return res.status(503).json({ success: false, error: 'database could not delete this category. No category was removed.' });
    } finally {
      connection.release();
    }

    return res.status(200).json({
      success: true,
      message: `Category deleted. (${reassignedCount} associated product(s) safely moved to Spares).`
    });
  } catch (err) {
    console.error('[API ERROR] Delete category:', err);
    return res.status(500).json({ success: false, error: 'Server error deleting category.' });
  }
});

// -----------------------------------------------------------------------------
// ADMIN ORDERS & DASHBOARD STATS ENDPOINTS
// -----------------------------------------------------------------------------

app.get('/api/admin/orders', requireAdminAuth, async (req, res) => {
  try {
    const [assignmentMetadata] = await pool.query("SELECT to_regclass('public.shop_order_assignments') IS NOT NULL AS available");
    const assignmentTableAvailable = assignmentMetadata[0]?.available === true;
    const [deliveryMetadata] = await pool.query(`SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'shop_delivery_items'
        AND column_name = 'delivery_confirmed'
    ) AS available`);
    const hasDeliveryConfirmation = deliveryMetadata[0]?.available === true;
    const deliveryConfirmedColumn = hasDeliveryConfirmation ? 'd.delivery_confirmed' : 'd.delivered';
    const [activeShops] = await pool.query(`SELECT DISTINCT shop_name FROM shop_employees
      WHERE active = TRUE AND shop_name IS NOT NULL AND btrim(shop_name) <> '' ORDER BY shop_name`);
    const uniqueShops = [...new Map(activeShops.map(row => [String(row.shop_name).toLowerCase(), row.shop_name])).values()];
    const singleShopFallback = uniqueShops.length === 1 ? uniqueShops[0] : '';
    const [rows] = await pool.query(`SELECT * FROM orders ORDER BY created_at DESC`);
    const formatted = [];
    for (const o of rows) {
      const [items] = await pool.query(`SELECT oi.*, d.order_item_id AS shop_delivery_record_id, d.delivered AS shop_delivered,
          ${deliveryConfirmedColumn} AS shop_delivery_confirmed,
          d.delivered_quantity AS shop_delivered_quantity,
          d.undelivered_quantity AS shop_undelivered_quantity,
          d.refund_status AS shop_refund_status, d.delivered_at AS shop_delivered_at,
          d.recorded_by AS shop_recorded_by, se.full_name AS shop_recorded_by_name,
          se.employee_id AS shop_recorded_by_employee_id
        FROM order_items oi LEFT JOIN shop_delivery_items d ON d.order_item_id = oi.id
        LEFT JOIN shop_employees se ON se.id = d.recorded_by
        WHERE oi.order_id = ? ORDER BY oi.id`, [o.order_id]);
      const allocation = allocateDeliveryValues(items.map(i => ({
        unit_price: i.unit_price,
        quantity: i.quantity,
        deliveredQuantity: i.shop_delivery_confirmed ? (i.shop_delivered_quantity ?? 0) : 0,
      })), o).allocated;
      const assignmentRows = assignmentTableAvailable
        ? (await pool.query('SELECT shop_name FROM shop_order_assignments WHERE order_id = ?', [o.order_id]))[0]
        : [];
      const orderDeliveredValue = allocation.reduce((sum, line) => sum + line.deliveredValue, 0);
      const orderRefundAmount = allocation.reduce((sum, line) => sum + line.refundValue, 0);
      const originalOrderValue = allocation.reduce((sum, line) => sum + line.allocatedValue, 0);
      const deliveredQuantity = allocation.reduce((sum, line) => sum + line.deliveredQuantity, 0);
      const orderedQuantity = allocation.reduce((sum, line) => sum + Number(line.quantity || 0), 0);
      const deliveryStatus = deliveredQuantity <= 0 ? 'Pending'
        : deliveredQuantity >= orderedQuantity ? 'Delivered' : 'Partially Delivered';
      const cashCollected = ['cod', 'cash on delivery'].includes(String(o.payment_method || '').trim().toLowerCase())
        && String(o.payment_status || '').trim().toLowerCase() === 'paid';
      const confirmedDeliveryRows = items.filter(i => i.shop_delivery_confirmed && i.shop_delivered_at);
      formatted.push({
            orderId: o.order_id,
            userEmail: o.user_email,
            userName: o.user_name,
            userBusiness: o.user_business,
            orderDate: o.created_at ? new Date(o.created_at).toISOString() : null,
            dueDate: null,
            items: (items || []).map(i => ({
              id: i.product_id,
              orderItemId: String(i.id),
              name: i.product_name,
              brand: i.brand || 'RO Wholesale',
              price: `₹${parseFloat(i.unit_price).toLocaleString('en-IN')}`,
              numericPrice: parseFloat(i.unit_price),
              dealerPrice: parseFloat(i.unit_price),
              purchaseMode: i.purchase_mode || 'normal',
              bulkPackLabel: i.bulk_pack_label || null,
              quantity: i.quantity,
              orderedQuantity: Number(i.quantity),
              actualDeliveredQuantity: i.shop_delivery_confirmed ? Number(i.shop_delivered_quantity ?? 0) : 0,
              submittedDeliveryQuantity: Number(i.shop_delivered_quantity ?? 0),
              deliveryConfirmed: i.shop_delivery_confirmed === true,
              deliveryStatus: !i.shop_delivery_confirmed || Number(i.shop_delivered_quantity ?? 0) <= 0
                ? 'Pending'
                : Number(i.shop_delivered_quantity) >= Number(i.quantity)
                  ? 'Delivered'
                  : 'Partially Delivered',
              deliveredAt: i.shop_delivery_confirmed ? i.shop_delivered_at : null,
              deliveredBy: i.shop_delivery_confirmed ? (i.shop_recorded_by_name || i.shop_recorded_by_employee_id || null) : null,
              deliveredByEmployeeId: i.shop_delivery_confirmed ? (i.shop_recorded_by_employee_id || null) : null,
              undeliveredQuantity: Number(i.quantity) - (i.shop_delivery_confirmed ? Number(i.shop_delivered_quantity ?? 0) : 0),
              deliveredValue: allocation[items.indexOf(i)]?.deliveredValue || 0,
              refundAmount: allocation[items.indexOf(i)]?.refundValue || 0,
              refundStatus: i.shop_refund_status || 'not_required',
              imgSrc: i.img_src || ''
            })),
            subtotal: parseFloat(o.subtotal || 0),
            discount: parseFloat(o.discount || 0),
            gst: parseFloat(o.gst || 0),
            deliveryFee: parseFloat(o.delivery_fee || 0),
            grandTotal: parseFloat(o.grand_total || 0),
            paymentMethod: o.payment_method || 'Cash on Delivery',
            paymentStatus: o.payment_status || 'pending',
            cashCollected,
            cashCollectedAt: cashCollected
              ? confirmedDeliveryRows.reduce((latest, item) => !latest || new Date(item.shop_delivered_at) > new Date(latest) ? item.shop_delivered_at : latest, null)
              : null,
            cashCollectedBy: cashCollected
              ? [...new Set(items.filter(i => i.shop_delivery_confirmed).map(i => i.shop_recorded_by_name || i.shop_recorded_by_employee_id).filter(Boolean))].join(', ') || null
              : null,
            deliveryAddress: o.delivery_address || '',
            deliveryNote: o.delivery_note || '',
            status: deliveryStatus,
            orderStatus: effectiveOrderStatus(o.status, deliveredQuantity, orderedQuantity),
            originalOrderStatus: effectiveOrderStatus(o.status, deliveredQuantity, orderedQuantity),
            deliveryStatus,
            shopDeliveryStarted: items.some(i => i.shop_delivery_record_id != null),
            deliveredQuantity,
            undeliveredQuantity: Math.max(0, orderedQuantity - deliveredQuantity),
            deliveredValue: orderDeliveredValue,
            originalOrderValue,
            refundAmount: orderRefundAmount,
            deliveredAt: items
              .filter(i => i.shop_delivery_confirmed && i.shop_delivered_at)
              .reduce((latest, item) => !latest || new Date(item.shop_delivered_at) > new Date(latest) ? item.shop_delivered_at : latest, null),
            deliveredBy: [...new Set(items
              .filter(i => i.shop_delivery_confirmed)
              .map(i => i.shop_recorded_by_name || i.shop_recorded_by_employee_id)
              .filter(Boolean))].join(', ') || null,
            shopName: assignmentRows[0]?.shop_name || singleShopFallback,
            invoiceNumber: o.invoice_number,
            createdAt: o.created_at ? new Date(o.created_at).toISOString() : new Date().toISOString()
      });
    }
    return res.json({ success: true, count: formatted.length, orders: formatted });
  } catch (err) {
    console.error('[API ERROR] Fetch admin orders:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Order data could not be loaded.' });
  }
});

// Admin Endpoint: Analytics & Revenue Intelligence
app.get('/api/admin/analytics', requireAdminAuth, async (req, res) => {
  try {
    const period = (req.query.period || 'daily').toLowerCase();

    // Fetch orders & items
    const [rows] = await pool.query(`SELECT * FROM orders ORDER BY created_at DESC`);
    const ordersList = [];
    for (const o of rows) {
      const [items] = await pool.query(`SELECT * FROM order_items WHERE order_id = ?`, [o.order_id]);
      ordersList.push({
            orderId: o.order_id,
            userEmail: o.user_email,
            userName: o.user_name,
            items: (items || []).map(i => ({
              id: i.product_id,
              name: i.product_name,
              brand: i.brand,
              numericPrice: parseFloat(i.unit_price),
              quantity: i.quantity,
              imgSrc: i.img_src,
              purchaseMode: i.purchase_mode || 'normal',
              bulkPackLabel: i.bulk_pack_label || null
            })),
            grandTotal: parseFloat(o.grand_total || 0),
            status: o.status || 'Processing',
            createdAt: o.created_at ? new Date(o.created_at).toISOString() : new Date().toISOString()
      });
    }

    // Filter non-cancelled orders for paid revenue calculation
    const validOrders = ordersList.filter(o => (o.status || '').toLowerCase() !== 'cancelled');

    // Revenue totals
    const now = new Date();
    const todayStr = now.toISOString().split('T')[0];
    const currentMonth = now.getMonth();
    const currentYear = now.getFullYear();

    let todayRevenue = 0;
    let monthRevenue = 0;
    let totalRevenue = 0;

    validOrders.forEach(o => {
      const oDate = new Date(o.createdAt);
      const amount = parseFloat(o.grandTotal || 0);
      totalRevenue += amount;

      if (oDate.toISOString().split('T')[0] === todayStr) {
        todayRevenue += amount;
      }
      if (oDate.getMonth() === currentMonth && oDate.getFullYear() === currentYear) {
        monthRevenue += amount;
      }
    });

    const totalOrdersCount = ordersList.length;
    const avgOrderValue = validOrders.length > 0 ? Math.round(totalRevenue / validOrders.length) : 0;

    // Build Chart Trends based on period
    let labels = [];
    let revenueData = [];
    let orderCountData = [];

    if (period === 'daily') {
      // Last 7 Days
      for (let i = 6; i >= 0; i--) {
        const d = new Date();
        d.setDate(d.getDate() - i);
        const dateStr = d.toISOString().split('T')[0];
        const labelStr = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        labels.push(labelStr);

        let dayRev = 0;
        let dayCount = 0;
        validOrders.forEach(o => {
          if (new Date(o.createdAt).toISOString().split('T')[0] === dateStr) {
            dayRev += parseFloat(o.grandTotal || 0);
            dayCount++;
          }
        });
        revenueData.push(dayRev);
        orderCountData.push(dayCount);
      }
    } else if (period === 'weekly') {
      // Last 4 Weeks
      for (let i = 3; i >= 0; i--) {
        labels.push(`Week ${4 - i}`);
        let weekRev = 0;
        let weekCount = 0;
        const nowMs = Date.now();
        const startMs = nowMs - (i + 1) * 7 * 24 * 60 * 60 * 1000;
        const endMs = nowMs - i * 7 * 24 * 60 * 60 * 1000;

        validOrders.forEach(o => {
          const t = new Date(o.createdAt).getTime();
          if (t >= startMs && t < endMs) {
            weekRev += parseFloat(o.grandTotal || 0);
            weekCount++;
          }
        });
        revenueData.push(weekRev);
        orderCountData.push(weekCount);
      }
    } else if (period === 'monthly') {
      // Last 6 Months
      for (let i = 5; i >= 0; i--) {
        const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
        const m = d.getMonth();
        const y = d.getFullYear();
        labels.push(d.toLocaleDateString('en-US', { month: 'short', year: '2-digit' }));

        let mRev = 0;
        let mCount = 0;
        validOrders.forEach(o => {
          const od = new Date(o.createdAt);
          if (od.getMonth() === m && od.getFullYear() === y) {
            mRev += parseFloat(o.grandTotal || 0);
            mCount++;
          }
        });
        revenueData.push(mRev);
        orderCountData.push(mCount);
      }
    } else { // yearly
      for (let i = 2; i >= 0; i--) {
        const y = currentYear - i;
        labels.push(String(y));
        let yRev = 0;
        let yCount = 0;
        validOrders.forEach(o => {
          if (new Date(o.createdAt).getFullYear() === y) {
            yRev += parseFloat(o.grandTotal || 0);
            yCount++;
          }
        });
        revenueData.push(yRev);
        orderCountData.push(yCount);
      }
    }

    // Calculate Top Selling Products
    const productSalesMap = {};
    validOrders.forEach(o => {
      (o.items || []).forEach(item => {
        const pId = item.id || item.sku || item.name;
        if (!productSalesMap[pId]) {
          productSalesMap[pId] = {
            id: pId,
            name: item.name,
            category: item.category || item.brand || 'RO Spares',
            img: item.imgSrc || item.img || 'purifier.jpg',
            unitsSold: 0,
            totalRevenue: 0
          };
        }
        const qty = parseInt(item.quantity || 1, 10);
        const price = item.numericPrice || parseFloat(String(item.price || '0').replace(/[^0-9.]/g, '')) || 0;
        productSalesMap[pId].unitsSold += qty;
        productSalesMap[pId].totalRevenue += price * qty;
      });
    });

    const topProducts = Object.values(productSalesMap)
      .sort((a, b) => b.unitsSold - a.unitsSold)
      .slice(0, 5);

    // Fetch Low Stock Products
    const [pRows] = await pool.query(`SELECT * FROM products ORDER BY stock_quantity ASC`);
    const allProds = pRows.map(p => ({
          id: p.id,
          sku: p.sku,
          name: p.name,
          category: p.category_key,
          img: p.img,
          stock: parseInt(p.stock_quantity ?? 50, 10),
          minStock: parseInt(p.min_stock ?? 10, 10)
    }));

    const lowStock = allProds
      .filter(p => p.stock <= p.minStock)
      .sort((a, b) => a.stock - b.stock);

    return res.json({
      success: true,
      revenue: {
        todayRevenue,
        monthRevenue,
        totalRevenue,
        totalOrders: totalOrdersCount,
        avgOrderValue
      },
      chart: {
        labels,
        revenueData,
        orderCountData
      },
      topProducts,
      lowStock
    });
  } catch (err) {
    console.error('[API ERROR] Analytics endpoint error:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Analytics could not be generated.' });
  }
});

// Supplied vs ordered units for an order (only Shop App-confirmed supplies count).
async function orderSupplyTotals(queryable, orderId) {
  const [confirmationMeta] = await queryable.query(`SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'shop_delivery_items' AND column_name = 'delivery_confirmed'
  ) AS available`);
  const confirmed = confirmationMeta[0]?.available === true ? 'COALESCE(d.delivery_confirmed, FALSE)' : 'COALESCE(d.delivered, FALSE)';
  const [rows] = await queryable.query(`SELECT COALESCE(SUM(oi.quantity), 0)::int AS ordered_quantity,
      COALESCE(SUM(CASE WHEN ${confirmed} THEN COALESCE(d.delivered_quantity, 0) ELSE 0 END), 0)::int AS delivered_quantity
    FROM order_items oi LEFT JOIN shop_delivery_items d ON d.order_item_id = oi.id
    WHERE oi.order_id = ?`, [orderId]);
  return { ordered: Number(rows[0]?.ordered_quantity || 0), delivered: Number(rows[0]?.delivered_quantity || 0) };
}

// Admin: order status (Pending, Processing & Dispatched, Partially Delivered,
// Delivered, Cancelled). Must agree with the quantities supplied in the Shop
// App; never changes the payment status. Cancelling returns the unsupplied
// units to stock; re-opening a cancelled order takes them again.
app.put('/api/admin/orders/:id/status', requireAdminAuth, async (req, res) => {
  let conn;
  try {
    const orderId = req.params.id;
    const status = normalizeOrderStatus(req.body.status);
    if (!status) return res.status(400).json({ success: false, error: `Choose one of: ${ORDER_STATUSES.join(', ')}.` });
    conn = await pool.getConnection();
    await conn.beginTransaction();
    const [[existing]] = await conn.query('SELECT order_id, status FROM orders WHERE order_id = ? LIMIT 1 FOR UPDATE', [orderId]);
    if (!existing) { await conn.rollback(); return res.status(404).json({ success: false, error: 'Order not found.' }); }
    const supply = await orderSupplyTotals(conn, orderId);
    const problem = orderStatusChangeError(status, supply.delivered, supply.ordered);
    if (problem) {
      await conn.rollback();
      return res.status(409).json({ success: false, error: problem, deliveredQuantity: supply.delivered, orderedQuantity: supply.ordered });
    }
    const wasCancelled = normalizeOrderStatus(existing.status) === 'Cancelled';
    let stock = null;
    if (status === 'Cancelled' && !wasCancelled) stock = await releaseOrderStock(conn, orderId);
    if (status !== 'Cancelled' && wasCancelled) stock = await reReserveOrderStock(conn, orderId);
    // Reward points follow the order: cancelled -> reversed, restored -> reinstated.
    if (status === 'Cancelled' && !wasCancelled) await reverseOrderReward(conn, orderId);
    if (status !== 'Cancelled' && wasCancelled) await reinstateOrderReward(conn, orderId);
    await conn.query('UPDATE orders SET status = ? WHERE order_id = ?', [status, orderId]);
    await conn.commit();
    return res.json({
      success: true,
      status,
      stockReturned: stock?.released?.reduce((sum, line) => sum + line.units, 0) || 0,
      message: `Order #${orderId} status updated to "${status}".`
    });
  } catch (err) {
    if (conn) await conn.rollback().catch(() => {});
    if (err.status) return res.status(err.status).json({ success: false, error: err.message });
    console.error('[API ERROR] Update order status:', err.code || err.name);
    return res.status(503).json({ success: false, error: 'database is unavailable. Order status was not changed.' });
  } finally {
    conn?.release();
  }
});

// Admin: payment status, kept separate from the order status. Cash on
// Delivery stays DUE_ON_DELIVERY until someone records the money.
app.put('/api/admin/orders/:id/payment-status', requireAdminAuth, async (req, res) => {
  try {
    const orderId = req.params.id;
    const paymentStatus = normalizePaymentStatus(req.body.paymentStatus);
    const [[order]] = await pool.query('SELECT order_id, payment_method, payment_status FROM orders WHERE order_id = ? LIMIT 1', [orderId]);
    if (!order) return res.status(404).json({ success: false, error: 'Order not found.' });
    const problem = paymentStatusChangeError(order.payment_method, order.payment_status, paymentStatus);
    if (problem) return res.status(paymentStatus ? 409 : 400).json({ success: false, error: problem });
    await pool.query('UPDATE orders SET payment_status = ? WHERE order_id = ?', [paymentStatus, orderId]);
    return res.json({
      success: true,
      paymentStatus,
      message: `Order #${orderId} payment status updated to "${paymentStatus.toUpperCase()}".`
    });
  } catch (err) {
    console.error('[API ERROR] Update payment status:', err.code || err.name);
    return res.status(503).json({ success: false, error: 'database is unavailable. Payment status was not changed.' });
  }
});

// Admin: Free Claim requests (pending first).
app.get('/api/admin/reward-claims', requireAdminAuth, async (req, res) => {
  try {
    if (!(await rewardLedgerReady(pool))) return res.json({ success: true, claims: [], ledgerReady: false });
    const [rows] = await pool.query(
      `SELECT r.id, r.user_id, r.points_redeemed, r.status, r.created_at, r.decided_at,
              u.name, u.email, u.business_name, u.reward_points
         FROM rewards_history r JOIN users u ON u.id = r.user_id
        WHERE r.entry_type = 'redeemed'
        ORDER BY (r.status = 'pending') DESC, r.created_at DESC
        LIMIT 500`);
    return res.json({
      success: true,
      claims: rows.map(r => ({
        id: Number(r.id),
        userId: r.user_id,
        name: r.name,
        email: r.email,
        business: r.business_name || '',
        points: Number(r.points_redeemed),
        value: Number(r.points_redeemed),
        balance: Number(r.reward_points),
        status: r.status,
        createdAt: r.created_at ? new Date(r.created_at).toISOString() : null,
        decidedAt: r.decided_at ? new Date(r.decided_at).toISOString() : null,
      })),
    });
  } catch (err) {
    console.error('[API ERROR] Reward claims:', err.code || err.name);
    return res.status(503).json({ success: false, error: 'database is unavailable.' });
  }
});

app.put('/api/admin/reward-claims/:id', requireAdminAuth, async (req, res) => {
  let conn;
  try {
    const id = Number.parseInt(req.params.id, 10);
    if (!Number.isSafeInteger(id) || id <= 0) return res.status(400).json({ success: false, error: 'Invalid claim.' });
    conn = await pool.getConnection();
    await conn.beginTransaction();
    const claim = await decideRewardClaim(conn, id, req.body?.status);
    await conn.commit();
    return res.json({ success: true, claim, message: `Claim ${claim.status}.` });
  } catch (err) {
    if (conn) await conn.rollback().catch(() => {});
    if (err.status) return res.status(err.status).json({ success: false, error: err.message });
    console.error('[API ERROR] Decide reward claim:', err.code || err.name);
    return res.status(503).json({ success: false, error: 'database is unavailable. The claim was not changed.' });
  } finally {
    conn?.release();
  }
});

app.get('/api/admin/dashboard-stats', requireAdminAuth, async (req, res) => {
  try {
    const [[userStats]] = await pool.query(`
      SELECT COUNT(*) AS totalUsers,
        SUM(CASE WHEN LOWER(status) = 'pending' THEN 1 ELSE 0 END) AS pendingUsers,
        SUM(CASE WHEN LOWER(status) = 'approved' THEN 1 ELSE 0 END) AS approvedUsers,
        SUM(CASE WHEN LOWER(status) = 'rejected' THEN 1 ELSE 0 END) AS rejectedUsers
      FROM users`);
    const [[productStats]] = await pool.query(`
      SELECT COUNT(*) AS totalProducts,
        SUM(CASE WHEN LOWER(COALESCE(status, 'active')) = 'inactive' THEN 0 ELSE 1 END) AS activeProducts,
        SUM(CASE WHEN LOWER(COALESCE(status, 'active')) = 'inactive' THEN 1 ELSE 0 END) AS inactiveProducts
      FROM products`);
    const [[categoryStats]] = await pool.query('SELECT COUNT(*) AS totalCategories FROM categories');
    const [[orderStats]] = await pool.query('SELECT COUNT(*) AS totalOrders, COALESCE(SUM(grand_total), 0) AS totalRevenue FROM orders');
    const stats = Object.fromEntries(
      Object.entries({ ...userStats, ...productStats, ...categoryStats, ...orderStats })
        .map(([key, value]) => [key, Number(value || 0)])
    );

    return res.json({
      success: true,
      stats
    });
  } catch (err) {
    console.error('[API ERROR] Dashboard stats:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Dashboard statistics could not be loaded.' });
  }
});

// Serve Admin Dashboard / Login Page
app.get(['/admin', '/admin/', '/admin/login', '/admin/dashboard', '/admin/*'], (req, res) => {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
  // The local sandbox sets ADMIN_ENV_LABEL=local-test so its Admin Panel shows
  // "LOCAL TEST COPY" (never Production). Render does not set it.
  if (process.env.ADMIN_ENV_LABEL === 'local-test') {
    const html = fs.readFileSync(path.join(__dirname, 'web_preview', 'admin.html'), 'utf8');
    return res.type('html').send(html.replace('<head>', '<head>\n<script>window.__ADMIN_ENV = { mode: "local-test" };</script>'));
  }
  res.sendFile(path.join(__dirname, 'web_preview', 'admin.html'));
});

// Serve SPA Fallback (Never intercept /api routes)
app.get('*', (req, res) => {
  if (req.path.startsWith('/api')) {
    return res.status(404).json({ success: false, error: 'API endpoint not found.' });
  }
  res.sendFile(path.join(__dirname, 'web_preview', 'index.html'));
});

// RO_LISTEN_HOST=127.0.0.1 keeps a local copy reachable only from this computer.
// Never set on Render, so production keeps listening on all interfaces.
const server = app.listen(PORT, process.env.RO_LISTEN_HOST || '0.0.0.0', () => {
  console.log(`===================================================`);
  console.log(`🚀 RO Wholesale B2B Backend Server Running on Port ${PORT}`);
  console.log(`🌐 Dealer Portal Live Web: http://127.0.0.1:${PORT}/`);
  console.log(`===================================================`);
});

// Close the listener and database pool cleanly when the backend is restarted.
let shutdownStarted = false;
const shutdown = (signal) => {
  if (shutdownStarted) return;
  shutdownStarted = true;
  console.log(`[SERVER] ${signal} received; closing HTTP listener and database pool.`);
  const timeout = setTimeout(() => {
    console.error('[SERVER] Graceful shutdown timed out; exiting.');
    process.exit(1);
  }, 10000);
  timeout.unref();
  server.close(async (error) => {
    if (error) console.error('[SERVER] Listener close failed:', error.code || error.name);
    try {
      await pool.end();
      process.exitCode = error ? 1 : 0;
    } catch (poolError) {
      console.error('[SERVER] Database pool close failed:', poolError.code || poolError.name);
      process.exitCode = 1;
    }
    clearTimeout(timeout);
  });
};
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

module.exports = { app, server };
