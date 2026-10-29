const express = require('express');
const cors = require('cors');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');
const bcrypt = require('bcryptjs');
const { validGstin, createDealerToken, verifyDealerToken } = require('./checkout_service');
const { allocateDeliveryValues } = require('./shop_service');
require('dotenv').config();
const { createEmailSender } = require('./email_provider');

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
    if (allowedOrigins.indexOf(origin) !== -1 || process.env.NODE_ENV !== 'production') {
      return callback(null, true);
    }
    return callback(null, false);
  },
  credentials: true
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb', extended: true }));

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

function parseAddressString(rawAddress) {
  const clean = (rawAddress || '').trim();
  const pincodeMatch = clean.match(/\b\d{6}\b/);
  const pincode = pincodeMatch ? pincodeMatch[0] : (clean.toLowerCase().includes('salem') ? '636001' : '600098');

  let city = 'Salem';
  const lower = clean.toLowerCase();
  if (lower.includes('chennai')) city = 'Chennai';
  else if (lower.includes('salem')) city = 'Salem';
  else if (lower.includes('coimbatore')) city = 'Coimbatore';
  else if (lower.includes('bangalore') || lower.includes('bengaluru')) city = 'Bangalore';
  else if (lower.includes('madurai')) city = 'Madurai';
  else if (lower.includes('trichy')) city = 'Trichy';

  return {
    street: clean,
    city: city,
    state: 'Tamil Nadu',
    pincode: pincode
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
        rewardPoints: userRow.reward_points || 0,
        addresses: (addresses || []).map(a => ({
          id: a.id,
          fullName: userRow.name,
          phone: a.phone || userRow.mobile || '',
          businessName: a.business_name || userRow.business_name || '',
          street: a.street || '',
          area: '',
          city: a.city || 'Chennai',
          state: a.state || 'Tamil Nadu',
          pincode: a.pincode || '600098',
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
  const [rows] = await pool.query(
    `SELECT * FROM users
     WHERE LOWER(email) = ?
        OR (mobile IS NOT NULL AND mobile != '' AND mobile = ?)
        OR (mobile IS NOT NULL AND RIGHT(REGEXP_REPLACE(mobile, '[^0-9]', '', 'g'), 10) = RIGHT(?, 10))
     LIMIT 1`,
    [cleanId, cleanId, cleanDigits]
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
    rewardPoints: userRow.reward_points || 0,
    addresses: (addresses || []).map(a => ({
      id: a.id,
      fullName: userRow.name,
      phone: a.phone || userRow.mobile || '',
      businessName: a.business_name || userRow.business_name || '',
      street: a.street || '',
      area: '',
      city: a.city || 'Chennai',
      state: a.state || 'Tamil Nadu',
      pincode: a.pincode || '600098',
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
    googleClientId: process.env.GOOGLE_CLIENT_ID || ''
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
  if (user.status !== 'approved' || user.isApproved !== true) {
    return res.status(403).json({success:false,status:user.status || 'pending',isApproved:false,error:'Your dealer account is awaiting admin approval.'});
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
    if (user.status !== 'approved' || !isDatabaseTrue(user.is_approved)) {
      return res.status(403).json({ success: false, status: user.status || 'pending', isApproved: false, error: 'Your dealer account is awaiting admin approval.' });
    }
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
    memoryOtps.set(email, record);
    try {
      await pool.query('DELETE FROM otp_codes WHERE email = ?', [email]);
      await pool.query("INSERT INTO otp_codes (email, otp_code, expires_at, attempts) VALUES (?, ?, CURRENT_TIMESTAMP + INTERVAL '5 minutes', 0)", [email, record.otp]);
    } catch (_) { /* Delivered codes remain valid in the active server if database is offline. */ }
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
    let record = memoryOtps.get(email), fromMemory = Boolean(record);
    if (!record) {
      try {
        const [rows] = await pool.query('SELECT otp_code, expires_at, attempts FROM otp_codes WHERE email = ? ORDER BY created_at DESC LIMIT 1', [email]);
        if (rows.length) record = { otp: rows[0].otp_code, expiresAt: new Date(rows[0].expires_at).getTime(), attempts: rows[0].attempts || 0 };
      } catch (_) {}
    }
    const actual = hashOtp(email, otp);
    const valid = record && record.expiresAt > Date.now() && record.attempts < 5 && record.otp.length === actual.length && crypto.timingSafeEqual(Buffer.from(record.otp), Buffer.from(actual));
    if (!valid) {
      if (record) record.attempts++;
      try { await pool.query('UPDATE otp_codes SET attempts = attempts + 1 WHERE email = ?', [email]); } catch (_) {}
      return res.status(400).json({ success: false, error: 'Code is invalid, expired, or has too many attempts. Request a new code.' });
    }
    try {
      await pool.query('UPDATE users SET email_verified = TRUE WHERE id = ?', [user.id]);
      user.emailVerified = true;
    } catch (_) {
      return res.status(503).json({ success: false, error: 'Email verification could not be saved. Please try again.' });
    }
    // Mark consumed before awaiting database so concurrent requests cannot reuse it.
    if (record) record.expiresAt = 0;
    try {
      const [removed] = await pool.query('DELETE FROM otp_codes WHERE email = ? AND otp_code = ?', [email, actual]);
      if (!fromMemory && !removed.affectedRows) return res.status(400).json({ success: false, error: 'This code has already been used.' });
    } catch (_) { if (!fromMemory) return res.status(503).json({ success: false, error: 'Could not verify the code. Try again.' }); }
    memoryOtps.delete(email);
    if (user.status === 'rejected') return res.status(403).json({ success: false, error: 'This account is not approved for login.' });
    if (user.status !== 'approved' || user.isApproved !== true) {
      return res.status(403).json({ success: false, status: user.status || 'pending', isApproved: false, error: 'Your dealer account is awaiting admin approval.' });
    }
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

// 3. Sign Up Endpoint (new dealers remain pending until admin approval)
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
    // Email/password registration remains unchanged, but account approval is
    // an explicit admin action. Never elevate a new dealer during signup.
    await connection.query("INSERT INTO users (id, email, mobile, name, password_hash, email_verified, business_name, owner_name, address, gst_number, status, is_approved, reward_points) VALUES (?, ?, ?, ?, ?, TRUE, ?, ?, ?, ?, 'pending', FALSE, 0)", [id, email, mobile || null, name, hash, company, name, address || null, gst || null]);
    if (address) await connection.query("INSERT INTO user_addresses (id, user_id, label, business_name, street, city, state, pincode, phone, gst_number, is_default) VALUES (?, ?, 'Main address', ?, ?, ?, ?, ?, ?, ?, TRUE)", [addressId, id, company, address, parsed.city || '', parsed.state || '', parsed.pincode || '', mobile, gst]);
    await connection.commit();
    return res.json({ success: true, status: 'pending', isApproved: false, message: 'Account created. Your dealer account is awaiting admin approval.' });
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

    if (user.emailVerified === false) {
      return res.status(403).json({ success: false, error: 'Verify your email with the OTP sent during signup before signing in.' });
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

    if (user.status !== 'approved' || user.isApproved !== true) {
      return res.status(403).json({
        success: false,
        status: user.status || 'pending',
        isApproved: false,
        error: 'Your dealer account is awaiting admin approval.'
      });
    }

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

    console.log(`🔑 [LOGIN SUCCESS] Logged in user: ${user.email}`);

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
  if (clientId) {
    try {
      const ticket = await googleClient.verifyIdToken({ idToken: credentialOrToken, audience: clientId });
      return ticket.getPayload();
    } catch (err) {}
  }

  try {
    const res = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${credentialOrToken}`);
    if (res.ok) {
      const payload = await res.json();
      if (payload.email) return payload;
    }
  } catch (err) {}

  try {
    const parts = credentialOrToken.split('.');
    if (parts.length === 3) {
      const payloadBuf = Buffer.from(parts[1], 'base64url');
      const payload = JSON.parse(payloadBuf.toString('utf-8'));
      if (payload.email) return payload;
    }
  } catch (err) {}

  throw new Error('Google OAuth token verification failed.');
}

app.post('/api/auth/google-signin', async (req, res) => {
  try {
    const { credential, accessToken } = req.body;
    const tokenToVerify = credential || accessToken;
    if (!tokenToVerify) return res.status(400).json({ success: false, error: 'Missing Google credential.' });

    const googlePayload = await verifyGoogleToken(tokenToVerify);
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
      const businessName = `${name} Aqua Wholesale`;
      const googleMobile = `98${Math.floor(10000000 + Math.random() * 90000000)}`;

      const conn = await pool.getConnection();
      try {
        await conn.beginTransaction();
        await conn.query(
          `INSERT INTO users (id, email, mobile, name, password_hash, business_name, owner_name, address, status, is_approved, reward_points)
           VALUES (?, ?, ?, ?, '', ?, ?, 'Wholesale Dealer Hub', 'pending', FALSE, 0)`,
          [userId, cleanEmail, googleMobile, name, businessName, name]
        );
        await conn.query(
          `INSERT INTO user_addresses (id, user_id, label, business_name, street, city, state, pincode, phone, is_default)
           VALUES (?, ?, 'Main Warehouse', ?, 'Wholesale Dealer Hub', 'Chennai', 'Tamil Nadu', '600098', ?, TRUE)`,
          [`ADDR_${Date.now()}`, userId, businessName, googleMobile]
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

    if (user.status !== 'approved' || user.isApproved !== true) {
      return res.status(403).json({
        success: false,
        status: user.status || 'pending',
        isApproved: false,
        error: 'Your dealer account is awaiting admin approval.'
      });
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
const activeAdminTokens = new Set();
const ADMIN_EMAIL = (process.env.ADMIN_EMAIL || '').trim().toLowerCase();
const ADMIN_PASSWORD = (process.env.ADMIN_PASSWORD || '').trim();
if (!ADMIN_EMAIL || !ADMIN_PASSWORD) {
  throw new Error('ADMIN_EMAIL and ADMIN_PASSWORD must be configured before starting the backend.');
}

// Admin Authentication Middleware
function requireAdminAuth(req, res, next) {
  const authHeader = req.headers['authorization'] || '';
  const tokenHeader = req.headers['x-admin-token'] || '';
  let token = '';

  if (authHeader.startsWith('Bearer ')) {
    token = authHeader.substring(7).trim();
  } else if (tokenHeader) {
    token = tokenHeader.trim();
  }

  if (token && activeAdminTokens.has(token)) {
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
app.post('/api/admin/login', (req, res) => {
  try {
    const { email, password } = req.body || {};
    const cleanEmail = (email || '').trim().toLowerCase();
    const cleanPass = (password || '').trim();

    if (!cleanEmail || !cleanPass) {
      return res.status(400).json({ success: false, error: 'Please enter both admin email and password.' });
    }

    if (cleanEmail === ADMIN_EMAIL && cleanPass === ADMIN_PASSWORD) {
      const adminToken = `RO_ADMIN_SECURE_${Date.now()}_${crypto.randomBytes(16).toString('hex')}`;
      activeAdminTokens.add(adminToken);
      console.log(`🔐 [ADMIN LOGIN SUCCESS] Admin logged in: ${cleanEmail}`);
      return res.status(200).json({
        success: true,
        message: 'Admin authentication successful.',
        token: adminToken,
        admin: {
          email: ADMIN_EMAIL,
          name: 'System Administrator',
          role: 'super_admin'
        }
      });
    }

    console.warn(`⚠️ [ADMIN LOGIN FAILED] Invalid credentials attempt for: ${cleanEmail}`);
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
  const authHeader = req.headers['authorization'] || '';
  const tokenHeader = req.headers['x-admin-token'] || '';
  let token = '';

  if (authHeader.startsWith('Bearer ')) {
    token = authHeader.substring(7).trim();
  } else if (tokenHeader) {
    token = tokenHeader.trim();
  }

  if (token && activeAdminTokens.has(token)) {
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
  const authHeader = req.headers['authorization'] || '';
  const tokenHeader = req.headers['x-admin-token'] || '';
  let token = '';

  if (authHeader.startsWith('Bearer ')) {
    token = authHeader.substring(7).trim();
  } else if (tokenHeader) {
    token = tokenHeader.trim();
  }

  if (token) {
    activeAdminTokens.delete(token);
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
    const { identifier, email, status } = req.body;
    const cleanId = (identifier || email || '').trim().toLowerCase();
    const validStatuses = ['approved', 'pending', 'rejected'];
    const cleanStatus = (status || '').toLowerCase();

    if (!cleanId || !validStatuses.includes(cleanStatus)) {
      return res.status(400).json({ success: false, error: 'Invalid identifier or status.' });
    }

    const isApproved = cleanStatus === 'approved';
    const [updateResult] = await pool.query(
      `UPDATE users SET status = ?, is_approved = ? WHERE email = ? OR id = ? OR mobile = ?`,
      [cleanStatus, isApproved, cleanId, cleanId, cleanId]
    );
    if (!updateResult.affectedRows) {
      const [[existingDealer]] = await pool.query(
        'SELECT id FROM users WHERE email = ? OR id = ? OR mobile = ? LIMIT 1',
        [cleanId, cleanId, cleanId]
      );
      if (!existingDealer) return res.status(404).json({ success: false, error: 'Dealer not found.' });
    }

    return res.status(200).json({
      success: true,
      message: `Dealer status updated to ${cleanStatus}`,
      user: { email: cleanId, status: cleanStatus, isApproved: cleanStatus === 'approved' }
    });
  } catch (err) {
    console.error('[API ERROR] Admin set-status:', err);
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
      [cleanName, cleanName, cleanMobile, cleanBusiness || `${cleanName} Aqua Wholesale`, cleanAddress, cleanEmail]
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
    city: a.city || 'Chennai',
    district: a.district || a.city || 'Chennai',
    state: a.state || 'Tamil Nadu',
    pincode: a.pincode || '600098',
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

    // If targetUser has 0 saved addresses but has a signup address/email, auto-seed a default address card for the user!
    if (addresses.length === 0 && (targetUser.address || targetUser.email)) {
      const defaultAddr = normalizeAddressObj({
        id: `ADDR_DEFAULT_${targetUser.id || Date.now()}`,
        full_name: targetUser.name || targetUser.owner || 'Recipient',
        phone: targetUser.mobile || '',
        business_name: targetUser.business || `${targetUser.name} Aqua Wholesale`,
        door_no: 'No. 12',
        street: targetUser.address || 'Wholesale Hub',
        area: 'Industrial Estate',
        city: 'Chennai',
        district: 'Chennai',
        state: 'Tamil Nadu',
        pincode: '600098',
        address_type: 'Office',
        is_default: true
      }, targetUser);

      await pool.query(
        `INSERT INTO user_addresses (id, user_id, full_name, phone, business_name, door_no, street, area, city, district, state, pincode, address_type, label, is_default)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, TRUE)
         ON CONFLICT (id) DO UPDATE SET is_default = TRUE`,
        [defaultAddr.id, targetUser.id, defaultAddr.fullName, defaultAddr.phone, defaultAddr.businessName, defaultAddr.doorNo, defaultAddr.street, defaultAddr.area, defaultAddr.city, defaultAddr.district, defaultAddr.state, defaultAddr.pincode, defaultAddr.addressType, defaultAddr.addressType]
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
    moq: row.moq || 'MOQ: 1 Units',
    imgSrc: row.img || row.imgSrc || 'purifier.jpg',
    sku: row.sku || `SKU-${(row.product_id || row.id).toString().toUpperCase()}`,
    quantity: parseInt(row.quantity, 10) || 1
  };
}

// 1. GET User Cart
app.get('/api/cart', async (req, res) => {
  try {
    const user = getDealerFromRequest(req);
    const userId = user ? user.id : '';

    if (!userId) {
      return res.json({ success: true, items: [] });
    }

    const [rows] = await pool.query(
      `SELECT ci.id as cart_item_id, ci.quantity, ci.product_id,
              p.name, p.brand, p.price, p.mrp, p.moq, p.badge, p.rating, p.img, p.category_key, p.sku
       FROM cart_items ci
       LEFT JOIN products p ON ci.product_id = p.id
       WHERE ci.user_id = ?
       ORDER BY ci.id ASC`,
      [userId]
    );
    return res.json({ success: true, userId, items: rows.map(formatCartItemRow) });
  } catch (err) {
    console.error('[API ERROR] GET /api/cart:', err.message);
    return res.status(500).json({ success: false, error: 'Server error retrieving cart.' });
  }
});

// 2. ADD Item to User Cart
app.post('/api/cart/add', async (req, res) => {
  try {
    const { productId, quantity = 1 } = req.body || {};
    const user = getDealerFromRequest(req);
    const userId = user ? user.id : '';

    if (!userId || !productId) {
      return res.status(400).json({ success: false, error: 'User ID and Product ID required.' });
    }

    const qty = parseInt(quantity, 10) || 1;

    await pool.query(
      `INSERT INTO cart_items (user_id, product_id, quantity)
       VALUES (?, ?, ?)
       ON CONFLICT (user_id, product_id) DO UPDATE SET quantity = cart_items.quantity + EXCLUDED.quantity`,
      [userId, productId, qty]
    );
    const [rows] = await pool.query(
      `SELECT ci.id as cart_item_id, ci.quantity, ci.product_id,
              p.name, p.brand, p.price, p.mrp, p.moq, p.badge, p.rating, p.img, p.category_key, p.sku
       FROM cart_items ci
       LEFT JOIN products p ON ci.product_id = p.id
       WHERE ci.user_id = ?
       ORDER BY ci.id ASC`,
      [userId]
    );
    return res.json({ success: true, message: 'Item added to cart.', items: rows.map(formatCartItemRow) });
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
    if (qty <= 0) await pool.query(`DELETE FROM cart_items WHERE user_id = ? AND product_id = ?`, [userId, productId]);
    else await pool.query(`UPDATE cart_items SET quantity = ? WHERE user_id = ? AND product_id = ?`, [qty, userId, productId]);
    const [rows] = await pool.query(
      `SELECT ci.id as cart_item_id, ci.quantity, ci.product_id,
              p.name, p.brand, p.price, p.mrp, p.moq, p.badge, p.rating, p.img, p.category_key, p.sku
       FROM cart_items ci
       LEFT JOIN products p ON ci.product_id = p.id
       WHERE ci.user_id = ?
       ORDER BY ci.id ASC`,
      [userId]
    );
    return res.json({ success: true, message: 'Cart item updated.', items: rows.map(formatCartItemRow) });
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
    const [rows] = await pool.query(
      `SELECT ci.id as cart_item_id, ci.quantity, ci.product_id,
              p.name, p.brand, p.price, p.mrp, p.moq, p.badge, p.rating, p.img, p.category_key, p.sku
       FROM cart_items ci
       LEFT JOIN products p ON ci.product_id = p.id
       WHERE ci.user_id = ?
       ORDER BY ci.id ASC`,
      [userId]
    );
    return res.json({ success: true, message: 'Item removed from cart.', items: rows.map(formatCartItemRow) });
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
    for (const o of orderRows) {
      const [itemRows] = await pool.query(`SELECT * FROM order_items WHERE order_id = ?`, [o.order_id]);
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
              sku: i.sku || i.product_id || ''
            })),
            subtotal: parseFloat(o.subtotal),
            discount: parseFloat(o.discount),
            gst: parseFloat(o.gst),
            deliveryFee: parseFloat(o.delivery_fee),
            grandTotal: parseFloat(o.grand_total),
            paymentMethod: o.payment_method,
            deliveryAddress: o.delivery_address,
            billingAddress: o.billing_address || o.delivery_address,
            sameAsDelivery: isDatabaseTrue(o.same_as_delivery),
            companyName: o.company_name || o.user_business || '',
            gstin: o.gstin || '',
            panNumber: o.pan_number || '',
            deliveryNote: o.delivery_note || '',
            status: o.status,
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

app.get('/api/user/rewards', async (req, res) => {
  try {
    const email = (req.query.email || '').trim().toLowerCase();
    if (!email) return res.status(400).json({ success: false, error: 'Email required.' });

    const user = await findUserByEmailOrMobile(email);
    if (!user) return res.status(404).json({ success: false, error: 'User account not found.' });

    const historyRows = user.rewardsHistory || [];
    const totalPointsEarned = historyRows.reduce((sum, h) => sum + (h.pointsEarned || 0), 0);

    return res.status(200).json({
      success: true,
      totalPoints: user.rewardPoints || 0,
      totalPointsEarned: totalPointsEarned,
      history: historyRows
    });
  } catch (err) {
    console.error('[API ERROR] Fetch rewards:', err);
    return res.status(500).json({ success: false, error: 'Server error fetching rewards.' });
  }
});

app.get('/api/user/gst-invoices', async (req, res) => {
  try {
    const email = (req.query.email || '').trim().toLowerCase();
    if (!email) return res.status(400).json({ success: false, error: 'Email required.' });

    const [invoiceRows] = await pool.query(
      `SELECT order_id, grand_total, gst, invoice_number, created_at FROM orders WHERE user_email = ? AND with_gst = TRUE ORDER BY created_at DESC`,
      [email]
    );
    const orders = invoiceRows.map(o => ({
      orderId: o.order_id,
      grandTotal: parseFloat(o.grand_total),
      gst: parseFloat(o.gst),
      invoiceNumber: o.invoice_number,
      createdAt: o.created_at
    }));

    const creditLimit = 250000;
    const totalSpent = orders.reduce((sum, o) => sum + parseFloat(o.grandTotal || 0), 0);
    const availableCredit = Math.max(0, creditLimit - (totalSpent % creditLimit));

    const invoices = orders.map(o => ({
      invoiceNumber: o.invoiceNumber,
      orderId: o.orderId,
      date: o.createdAt ? new Date(o.createdAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'Sep 18, 2026',
      amount: parseFloat(o.grandTotal),
      gstAmount: parseFloat(o.gst),
      itemsSummary: 'RO Water Equipment'
    }));

    return res.status(200).json({
      success: true,
      creditLimit: creditLimit,
      availableCredit: availableCredit,
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
    const ticketId = `TKT-2026-${result.insertId}`;

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
app.get('/api/products', async (req, res) => {
  try {
    // Dealer-facing catalog reads deliberately exclude purchase_price at the
    // query layer. Admin product routes use their separately protected query.
    const [rows] = await pool.query(`SELECT id, category_key, brand, name, price, mrp, moq, badge, rating, img, sku, description, specs_json, features_json, applications, stock_quantity, min_stock, status FROM products WHERE status != 'inactive' ORDER BY category_key, name`);
    const products = rows.map(p => ({
          id: p.id,
          category: p.category_key,
          brand: p.brand,
          name: p.name,
          price: parseFloat(p.price),
          dealer_price: parseFloat(p.price),
          mrp: parseFloat(p.mrp),
          moq: p.moq,
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
    return res.json({ success: true, count: products.length, products });
  } catch (err) {
    console.error('[API ERROR] Get products:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Product data could not be loaded.' });
  }
});

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
          moq: p.moq,
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
    const cleanPrice = parseFloat(price || 0);
    const cleanPurchasePrice = parseFloat(purchase_price !== undefined ? purchase_price : (purchasePrice !== undefined ? purchasePrice : 0));
    const cleanStock = Number(req.body.stock_quantity ?? req.body.stock ?? 50);
    const cleanMinStock = Number(req.body.min_stock ?? req.body.minStock ?? 10);
    if (![cleanStock, cleanMinStock].every(value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647) ||
        [req.body.stock_quantity, req.body.stock, req.body.min_stock, req.body.minStock].some(value => value !== undefined && (!['number', 'string'].includes(typeof value) || (typeof value === 'string' && !value.trim())))) {
      return res.status(400).json({ success: false, error: 'Stock quantity and minimum stock must be nonnegative integers.' });
    }

    if (!cleanName) return res.status(400).json({ success: false, error: 'Product name is required.' });
    if (!cleanSku) return res.status(400).json({ success: false, error: 'Product SKU is required.' });
    if (isNaN(cleanPrice) || cleanPrice <= 0) return res.status(400).json({ success: false, error: 'Valid dealer price is required.' });

    let categoryId;
    try {
      const [categoryRows] = await pool.query(
        `SELECT id FROM categories WHERE LOWER(id) = ? OR LOWER(key_name) = ? OR LOWER(title) = ? LIMIT 1`,
        [cleanCat, cleanCat, cleanCat]
      );
      if (!categoryRows.length) return res.status(400).json({ success: false, error: 'Select an existing product category.' });
      categoryId = categoryRows[0].id;
    } catch (dbErr) {
      return res.status(503).json({ success: false, error: 'database is unavailable. No product was saved.' });
    }

    // Check duplicate SKU
    const [duplicateRows] = await pool.query('SELECT sku FROM products WHERE UPPER(sku) = ? LIMIT 1', [cleanSku]);
    if (duplicateRows.length) {
      return res.status(400).json({ success: false, error: `Product SKU "${cleanSku}" already exists. Please use a unique SKU.` });
    }

    let cleanSpecs = {};
    if (specs && typeof specs === 'object') {
      cleanSpecs = specs;
    } else if (typeof specs === 'string' && specs.trim()) {
      try {
        cleanSpecs = JSON.parse(specs.trim());
      } catch (e) {
        cleanSpecs = { "Specification": specs.trim() };
      }
    }

    let cleanFeatures = [];
    if (Array.isArray(features)) {
      cleanFeatures = features.map(f => String(f).trim()).filter(Boolean);
    } else if (typeof features === 'string' && features.trim()) {
      cleanFeatures = features.split(/[\n,]+/).map(f => f.trim()).filter(Boolean);
    }

    const rawImg = (img || image || '').trim();
    let cleanImg = 'purifier.jpg';
    if (rawImg) {
      try {
        cleanImg = saveUploadedFile(rawImg);
      } catch (imgErr) {
        return res.status(400).json({ success: false, error: imgErr.message || 'Product image could not be saved.' });
      }
    }

    const cleanDesc = (desc || short_desc || full_desc || '').trim();
    const cleanBrand = (brand || 'RO Wholesale').trim();
    const cleanApps = (applications || 'Commercial & Domestic Water Plants').trim();

    const prodId = `prod_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}`;
    const newProd = {
      id: prodId,
      sku: cleanSku,
      name: cleanName,
      category: cleanCat,
      category_id: categoryId,
      brand: cleanBrand,
      purchase_price: cleanPurchasePrice,
      purchasePrice: cleanPurchasePrice,
      price: cleanPrice,
      stock_quantity: cleanStock,
      min_stock: cleanMinStock,
      mrp: parseFloat(mrp || cleanPrice * 1.25),
      moq: moq ? (moq.toString().startsWith('MOQ:') ? moq : `MOQ: ${moq}`) : 'MOQ: 1 Unit',
      badge: String(badge || '').trim(),
      rating: String(rating || '★★★★★ (5.0)').trim(),
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
        `INSERT INTO products (id, category_id, category_key, sku, name, brand, purchase_price, price, mrp, moq, badge, rating, img, description, specs_json, features_json, applications, status, stock_quantity, min_stock)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          newProd.id, newProd.category_id, newProd.category, newProd.sku, newProd.name, newProd.brand,
          newProd.purchase_price, newProd.price, newProd.mrp, newProd.moq, newProd.badge, newProd.rating,
          newProd.img, newProd.desc, JSON.stringify(newProd.specs), JSON.stringify(newProd.features),
          newProd.applications, newProd.status, newProd.stock_quantity, newProd.min_stock
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

    const validToImport = [];
    const skippedSKUs = [];

    for (const raw of rawProducts) {
      const cleanName = (raw.name || raw.product_name || raw.productName || raw.title || raw.details || raw.product_details || '').trim();
      const cleanSku = (raw.sku || raw.sku_code || '').trim().toUpperCase();
      const cleanBrand = (raw.brand || 'RO Wholesale').trim();
      const cleanPurchasePrice = parseFloat(raw.purchase_price !== undefined ? raw.purchase_price : (raw.purchasePrice !== undefined ? raw.purchasePrice : 0));
      const cleanPrice = parseFloat(raw.price !== undefined ? raw.price : (raw.dealer_price !== undefined ? raw.dealer_price : (raw.dealerPrice !== undefined ? raw.dealerPrice : 0)));
      const cleanMrp = parseFloat(raw.mrp !== undefined ? raw.mrp : (cleanPrice * 1.25));
      const cleanStock = Number(raw.stock_quantity ?? raw.stock ?? 50);
      const cleanMinStock = Number(raw.min_stock ?? raw.minStock ?? 10);
      if (![cleanStock, cleanMinStock].every(value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647) ||
          [raw.stock_quantity, raw.stock, raw.min_stock, raw.minStock].some(value => value !== undefined && (!['number', 'string'].includes(typeof value) || (typeof value === 'string' && !value.trim())))) {
        skippedSKUs.push({ sku: cleanSku || 'UNKNOWN', reason: 'Stock quantity and minimum stock must be nonnegative integers.' });
        continue;
      }

      if (!cleanName || !cleanSku || isNaN(cleanPrice) || cleanPrice <= 0) {
        skippedSKUs.push({ sku: cleanSku || 'UNKNOWN', reason: 'Missing required fields (Product Details, SKU, or Dealer Price)' });
        continue;
      }

      if (existingSkus.has(cleanSku)) {
        skippedSKUs.push({ sku: cleanSku, reason: `Duplicate SKU "${cleanSku}" already exists in database` });
        continue;
      }

      const catObj = resolveCategory(raw.category || raw.category_key);
      if (!catObj) {
        skippedSKUs.push({ sku: cleanSku || 'UNKNOWN', reason: `Category "${raw.category || raw.category_key || ''}" does not exist in database.` });
        continue;
      }
      existingSkus.add(cleanSku);
      const prodId = `prod_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}`;

      const rawImg = (raw.img || raw.image || '').trim();
      let cleanImg = 'purifier.jpg';
      if (rawImg) {
        try {
          cleanImg = saveUploadedFile(rawImg);
        } catch (imgErr) {
          skippedSKUs.push({ sku: cleanSku, reason: `Image could not be saved: ${imgErr.message}` });
          existingSkus.delete(cleanSku);
          continue;
        }
      }

      const newProd = {
        id: prodId,
        sku: cleanSku,
        name: cleanName,
        category: catObj.key,
        category_id: catObj.id,
        brand: cleanBrand,
        purchase_price: cleanPurchasePrice,
        purchasePrice: cleanPurchasePrice,
        price: cleanPrice,
        mrp: cleanMrp,
        stock_quantity: cleanStock,
        min_stock: cleanMinStock,
        moq: raw.moq ? (raw.moq.toString().startsWith('MOQ:') ? raw.moq : `MOQ: ${raw.moq}`) : 'MOQ: 1 Unit',
        badge: String(raw.badge || '').trim(),
        rating: String(raw.rating || '★★★★★ (5.0)').trim(),
        img: cleanImg,
        desc: (raw.desc || raw.product_description || raw.productDescription || raw.description || '').trim(),
        specs: raw.specs || {},
        features: Array.isArray(raw.features) ? raw.features : [],
        applications: (raw.applications || 'Commercial & Domestic Water Plants').trim(),
        status: raw.status === 'inactive' ? 'inactive' : 'active',
        createdAt: new Date().toISOString()
      };

      validToImport.push(newProd);
    }

    if (validToImport.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'No valid products to import. All rows were either duplicates or missing required fields.',
        skipped: skippedSKUs
      });
    }

    // Save only new SKU values. The unique constraint handles duplicates
    // that race the preflight lookup without modifying the existing product.
    const dbErrors = [];

    for (const p of validToImport) {
      try {
        const [insertResult] = await pool.query(
          `INSERT INTO products (id, category_id, category_key, sku, name, brand, purchase_price, price, mrp, moq, badge, rating, img, description, specs_json, features_json, applications, status, stock_quantity, min_stock)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            p.id, p.category_id, p.category, p.sku, p.name, p.brand,
            p.purchase_price, p.price, p.mrp, p.moq, p.badge, p.rating,
            p.img, p.desc, JSON.stringify(p.specs), JSON.stringify(p.features),
            p.applications, p.status, p.stock_quantity, p.min_stock
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
            : 'database could not save this product.'
        });
      }
    }

    // Mirror only confirmed database writes, so failed rows can be retried safely.
    const persistedProducts = validToImport.filter(p => !dbErrors.some(e => e.sku === p.sku));
    const totalSkipped = [...skippedSKUs, ...dbErrors];

    return res.status(201).json({
      success: true,
      message: `🎉 ${validToImport.length - dbErrors.length} products imported successfully!`,
      importedCount: validToImport.length - dbErrors.length,
      skippedCount: totalSkipped.length,
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
    const cleanPrice = parseFloat(price || 0);

    if (!cleanName) return res.status(400).json({ success: false, error: 'Product name is required.' });
    if (!cleanSku) return res.status(400).json({ success: false, error: 'Product SKU is required.' });
    if (isNaN(cleanPrice) || cleanPrice <= 0) return res.status(400).json({ success: false, error: 'Valid dealer price is required.' });

    const [databaseProducts] = await pool.query('SELECT * FROM products WHERE id = ? OR sku = ? LIMIT 1', [targetId, targetId]);
    const databaseProduct = databaseProducts[0];
    if (!databaseProduct) return res.status(404).json({ success: false, error: 'Product not found.' });
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
    const cleanStock = Number(req.body.stock_quantity ?? req.body.stock ?? existing.stock_quantity ?? existing.stock ?? 50);
    const cleanMinStock = Number(req.body.min_stock ?? req.body.minStock ?? existing.min_stock ?? existing.minStock ?? 10);
    if (![cleanStock, cleanMinStock].every(value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647) ||
        [req.body.stock_quantity, req.body.stock, req.body.min_stock, req.body.minStock].some(value => value !== undefined && (!['number', 'string'].includes(typeof value) || (typeof value === 'string' && !value.trim())))) {
      return res.status(400).json({ success: false, error: 'Stock quantity and minimum stock must be nonnegative integers.' });
    }

    let cleanSpecs = existing.specs || {};
    if (specs && typeof specs === 'object') {
      cleanSpecs = specs;
    } else if (typeof specs === 'string' && specs.trim()) {
      try {
        cleanSpecs = JSON.parse(specs.trim());
      } catch (e) {
        cleanSpecs = { "Specification": specs.trim() };
      }
    }

    let cleanFeatures = existing.features || [];
    if (Array.isArray(features)) {
      cleanFeatures = features.map(f => String(f).trim()).filter(Boolean);
    } else if (typeof features === 'string' && features.trim()) {
      cleanFeatures = features.split(/[\n,]+/).map(f => f.trim()).filter(Boolean);
    }

    const rawPP = purchase_price !== undefined ? purchase_price : purchasePrice;
    const cleanPurchasePrice = rawPP !== undefined ? parseFloat(rawPP || 0) : parseFloat(existing.purchase_price || existing.purchasePrice || 0);

    let cleanImg = existing.img || 'purifier.jpg';
    const rawImg = img !== undefined ? img : image;
    if (rawImg !== undefined) {
      if (rawImg === null || !String(rawImg).trim()) {
        cleanImg = '';
      } else {
        try { cleanImg = saveUploadedFile(String(rawImg).trim()); }
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
      brand: (brand || existing.brand || 'RO Wholesale').trim(),
      purchase_price: cleanPurchasePrice,
      purchasePrice: cleanPurchasePrice,
      price: cleanPrice,
      mrp: parseFloat(mrp || cleanPrice * 1.25),
      moq: moq ? (moq.toString().startsWith('MOQ:') ? moq : `MOQ: ${moq}`) : (existing.moq || 'MOQ: 1 Unit'),
      badge: String(badge !== undefined ? badge : existing.badge || '').trim(),
      rating: String(rating !== undefined ? rating : existing.rating || '★★★★★ (5.0)').trim(),
      img: cleanImg,
      desc: (desc || short_desc || full_desc || existing.desc || '').trim(),
      specs: cleanSpecs,
      features: cleanFeatures,
      applications: (applications !== undefined ? applications : existing.applications || '').trim(),
      status: status === 'inactive' ? 'inactive' : 'active'
    };

    await pool.query(
      `UPDATE products SET category_id = ?, category_key = ?, sku = ?, name = ?, brand = ?, purchase_price = ?, price = ?, mrp = ?, moq = ?, badge = ?, rating = ?, img = ?, description = ?, specs_json = ?, features_json = ?, applications = ?, status = ?, stock_quantity = ?, min_stock = ? WHERE id = ?`,
      [
        updatedProd.category_id, updatedProd.category, updatedProd.sku, updatedProd.name, updatedProd.brand,
        updatedProd.purchase_price, updatedProd.price, updatedProd.mrp, updatedProd.moq, updatedProd.badge, updatedProd.rating,
        updatedProd.img, updatedProd.desc, JSON.stringify(updatedProd.specs), JSON.stringify(updatedProd.features),
        updatedProd.applications, updatedProd.status, updatedProd.stock_quantity, updatedProd.min_stock, databaseProduct.id
      ]
    );
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
    const [result] = await pool.query(`DELETE FROM products WHERE id = ? OR sku = ?`, [targetId, targetId]);
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
    return res.json({ success: true, count: rows.length, categories: rows });
  } catch (err) {
    console.error('[API ERROR] Get categories:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Category data could not be loaded.' });
  }
});

app.get('/api/admin/categories', requireAdminAuth, async (req, res) => {
  try {
    const [rows] = await pool.query(`SELECT * FROM categories ORDER BY display_order ASC`);
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
      if (rawImg) processedImage = saveUploadedFile(rawImg, 'cat');
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
        processedImage = rawImg ? saveUploadedFile(rawImg, 'cat') : '';
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
            originalOrderStatus: o.status || 'Processing',
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
              imgSrc: i.img_src
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

app.put('/api/admin/orders/:id/status', requireAdminAuth, async (req, res) => {
  try {
    const orderId = req.params.id;
    const { status } = req.body;
    const cleanStatus = String(status || 'Processing').trim();
    if (!cleanStatus) return res.status(400).json({ success: false, error: 'Order status is required.' });
    const [shopDeliveryRows] = await pool.query('SELECT COUNT(*)::int AS delivery_rows FROM shop_delivery_items WHERE order_id = ?', [orderId]);
    if (Number(shopDeliveryRows[0]?.delivery_rows || 0) > 0) {
      return res.status(409).json({ success: false, error: 'Delivery has been submitted by the Shop App. Its status is synchronized from the saved delivery quantities.' });
    }
    if (cleanStatus.toLowerCase() === 'delivered') {
      const [deliveryRows] = await pool.query(`SELECT COALESCE(SUM(oi.quantity), 0)::int AS ordered_quantity,
          COALESCE(SUM(COALESCE(d.delivered_quantity, CASE WHEN d.delivered THEN oi.quantity ELSE 0 END)), 0)::int AS delivered_quantity
        FROM order_items oi LEFT JOIN shop_delivery_items d ON d.order_item_id = oi.id
        WHERE oi.order_id = ?`, [orderId]);
      if (Number(deliveryRows[0]?.ordered_quantity || 0) !== Number(deliveryRows[0]?.delivered_quantity || 0)) {
        return res.status(409).json({ success: false, error: 'An order can be marked Delivered only after every ordered unit is recorded as delivered in the Shop App.' });
      }
    }
    const [updateResult] = await pool.query(`UPDATE orders SET status = ? WHERE order_id = ?`, [cleanStatus, orderId]);
    if (!updateResult.affectedRows) {
      const [[existing]] = await pool.query('SELECT order_id FROM orders WHERE order_id = ? LIMIT 1', [orderId]);
      if (!existing) return res.status(404).json({ success: false, error: 'Order not found.' });
    }
    return res.json({
      success: true,
      message: `Order #${orderId} status updated to "${cleanStatus}".`
    });
  } catch (err) {
    console.error('[API ERROR] Update order status:', err);
    return res.status(503).json({ success: false, error: 'database is unavailable. Order status was not changed.' });
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
  res.sendFile(path.join(__dirname, 'web_preview', 'admin.html'));
});

// Serve SPA Fallback (Never intercept /api routes)
app.get('*', (req, res) => {
  if (req.path.startsWith('/api')) {
    return res.status(404).json({ success: false, error: 'API endpoint not found.' });
  }
  res.sendFile(path.join(__dirname, 'web_preview', 'index.html'));
});

const server = app.listen(PORT, '0.0.0.0', () => {
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
