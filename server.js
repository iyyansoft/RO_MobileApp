const express = require('express');
const cors = require('cors');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
const path = require('path');
const bcrypt = require('bcryptjs');
require('dotenv').config();

// MySQL Database Connection Pool
const { pool, testConnection } = require('./db');

const app = express();
const PORT = process.env.PORT || 8080;
const SESSION_SECRET = process.env.SESSION_SECRET || 'RO_WHOLESALE_SECRET_KEY_2026';

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
    // Allow native Flutter mobile requests, Postman, or same-origin requests with no Origin header
    if (!origin) return callback(null, true);
    if (allowedOrigins.indexOf(origin) !== -1 || process.env.NODE_ENV !== 'production') {
      return callback(null, true);
    }
    return callback(null, false);
  },
  credentials: true
}));
app.use(express.json());

// Serve static frontend files from web_preview directory
app.use(express.static(path.join(__dirname, 'web_preview')));

// Helper: Secure OTP Hash using SHA-256 HMAC
function hashOtp(email, otp) {
  return crypto
    .createHmac('sha256', SESSION_SECRET)
    .update(`${email.toLowerCase()}:${otp}`)
    .digest('hex');
}

// -----------------------------------------------------------------------------
// REAL EMAIL TRANSPORTER INITIALIZATION
// -----------------------------------------------------------------------------
function createSmtpTransporter() {
  const host = process.env.SMTP_HOST || 'smtp.gmail.com';
  const port = parseInt(process.env.SMTP_PORT || '587');
  const secure = process.env.SMTP_SECURE === 'true';
  const user = (process.env.SMTP_USER || '').trim();
  const pass = (process.env.SMTP_PASS || '').replace(/\s+/g, '');

  if (user && pass) {
    console.log(`[SMTP SYSTEM] Initializing Pooled Gmail SMTP Transporter (${host}:${port}, secure=${secure}, user=${user})...`);
    return nodemailer.createTransport({
      pool: true,
      maxConnections: 5,
      maxMessages: 100,
      host: host,
      port: port,
      secure: secure,
      auth: { user, pass },
      tls: { rejectUnauthorized: false }
    });
  }

  console.log(`[SMTP SYSTEM] Defaulting to standard SMTP transport on ${host}:465...`);
  return nodemailer.createTransport({
    pool: true,
    maxConnections: 5,
    host: host,
    port: 465,
    secure: true,
    tls: { rejectUnauthorized: false }
  });
}

let primaryTransporter = createSmtpTransporter();

// Verify SMTP connection on startup
primaryTransporter.verify((err, success) => {
  if (err) {
    console.warn(`[SMTP VERIFICATION NOTICE] Primary SMTP server connection failed: ${err.message}`);
  } else {
    console.log(`[SMTP SYSTEM READY] Successfully connected to primary SMTP server!`);
  }
});

// Verify MySQL connection on startup
testConnection();

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

// Helper: Safely generate a unique 10-digit mobile number for OTP auto-registration
async function generateUniqueMobile(conn) {
  let attempts = 0;
  while (attempts < 10) {
    const candidate = `98${Math.floor(10000000 + Math.random() * 90000000)}`;
    const [rows] = await conn.query(`SELECT id FROM users WHERE mobile = ? LIMIT 1`, [candidate]);
    if (rows.length === 0) {
      return candidate;
    }
    attempts++;
  }
  return `9${Date.now().toString().slice(-9)}`;
}

// MySQL Helper: Lookup User by Email or Mobile Number
async function findUserByEmailOrMobile(identifier) {
  if (!identifier) return null;
  const cleanId = identifier.trim().toLowerCase();
  const cleanDigits = identifier.replace(/\D/g, '');

  const [rows] = await pool.query(
    `SELECT * FROM users WHERE email = ? OR (mobile IS NOT NULL AND mobile != '' AND mobile = ?) OR (mobile IS NOT NULL AND REPLACE(mobile, '-', '') = ?) LIMIT 1`,
    [cleanId, cleanId, cleanDigits]
  );
  if (rows.length === 0) return null;

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
    address: userRow.address || '',
    business: userRow.business_name || `${userRow.name} Aqua Wholesale`,
    owner: userRow.owner_name || userRow.name,
    status: userRow.status,
    isApproved: userRow.is_approved === 1 || userRow.status === 'approved',
    createdAt: userRow.created_at ? new Date(userRow.created_at).toISOString() : new Date().toISOString(),
    rewardPoints: userRow.reward_points || 0,
    addresses: addresses.map(a => ({
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
      isDefault: a.is_default === 1
    })),
    rewardsHistory: rewards.map(r => ({
      orderId: r.order_id,
      orderAmount: parseFloat(r.order_amount),
      pointsEarned: r.points_earned,
      date: r.created_at ? new Date(r.created_at).toISOString() : new Date().toISOString()
    }))
  };
}

// -----------------------------------------------------------------------------
// REST API ENDPOINTS (MYSQL BACKED)
// -----------------------------------------------------------------------------

// 0. Auth Config Endpoint
app.get('/api/auth/config', (req, res) => {
  res.json({
    googleClientId: process.env.GOOGLE_CLIENT_ID || ''
  });
});

// 1. Send OTP Endpoint
app.post('/api/auth/send-otp', async (req, res) => {
  try {
    const { email } = req.body;
    let targetId = (email || '').trim().toLowerCase();

    if (!targetId) {
      return res.status(400).json({ success: false, error: 'Please enter a valid email address.' });
    }

    let cleanEmail = targetId;
    const cleanDigits = targetId.replace(/\D/g, '');
    if (cleanDigits && cleanDigits.length === 10 && !targetId.includes('@')) {
      const user = await findUserByEmailOrMobile(cleanDigits);
      if (user && user.email) {
        cleanEmail = user.email.toLowerCase();
      }
    }

    cleanEmail = fixEmailDomainTypo(cleanEmail);

    if (!isValidEmailAddress(cleanEmail)) {
      return res.status(400).json({ success: false, error: 'Please enter a valid email address.' });
    }

    const otpCode = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes expiry

    // Delete expired OTPs & insert new OTP into MySQL
    await pool.query(`DELETE FROM otp_codes WHERE expires_at < NOW()`);
    await pool.query(
      `INSERT INTO otp_codes (email, otp_code, expires_at) VALUES (?, ?, DATE_ADD(NOW(), INTERVAL 5 MINUTE))`,
      [cleanEmail, otpCode]
    );

    console.log(`🔑 [MYSQL OTP GENERATED] OTP Code for ${cleanEmail}: ${otpCode}`);

    // Send email via SMTP
    try {
      await primaryTransporter.sendMail({
        from: process.env.SMTP_FROM || '"RO Wholesale Security" <no-reply@ro-wholesale.com>',
        to: cleanEmail,
        subject: `Your RO Wholesale Security OTP: ${otpCode}`,
        text: `Your RO Wholesale Dealer Account verification code is: ${otpCode}. Valid for 5 minutes.`
      });
    } catch (e) {
      console.warn(`[SMTP DISPATCH NOTICE] ${e.message}`);
    }

    return res.status(200).json({
      success: true,
      message: `🎉 OTP sent successfully to ${cleanEmail}`,
      email: cleanEmail,
      otp: otpCode // Retained for instant testing
    });
  } catch (err) {
    console.error('[API ERROR] Failed to send-otp:', err);
    return res.status(500).json({ success: false, error: 'Server error sending OTP.' });
  }
});

// 2. Verify OTP Endpoint
app.post('/api/auth/verify-otp', async (req, res) => {
  try {
    const { email, otp } = req.body;
    const cleanEmail = (email || '').trim().toLowerCase();
    const cleanOtp = (otp || '').trim();

    if (!cleanEmail || !cleanOtp || cleanOtp.length !== 6) {
      return res.status(400).json({ success: false, error: '⚠️ Please enter full 6-digit OTP code.' });
    }

    // Query OTP from MySQL otp_codes table
    const [rows] = await pool.query(
      `SELECT * FROM otp_codes WHERE email = ? AND otp_code = ? AND expires_at > NOW() ORDER BY created_at DESC LIMIT 1`,
      [cleanEmail, cleanOtp]
    );

    if (rows.length === 0) {
      return res.status(400).json({ success: false, error: 'OTP invalid or expired. Please request a new OTP.' });
    }

    // Delete verified OTP code
    await pool.query(`DELETE FROM otp_codes WHERE email = ?`, [cleanEmail]);

    // Check if user exists in MySQL
    let existingUser = await findUserByEmailOrMobile(cleanEmail);
    if (!existingUser) {
      const newUserId = `DEALER_OTP_${Date.now()}`;
      const defaultName = cleanEmail.split('@')[0];
      
      const conn = await pool.getConnection();
      try {
        await conn.beginTransaction();
        const autoMobile = await generateUniqueMobile(conn);
        await conn.query(
          `INSERT INTO users (id, email, mobile, name, password_hash, business_name, owner_name, address, status, is_approved, reward_points)
           VALUES (?, ?, ?, ?, '', ?, ?, 'Wholesale Dealer Hub', 'approved', 1, 0)`,
          [newUserId, cleanEmail, autoMobile, defaultName, `${defaultName} Enterprises`, defaultName]
        );
        await conn.query(
          `INSERT INTO user_addresses (id, user_id, label, business_name, street, city, state, pincode, phone, is_default)
           VALUES (?, ?, 'Main Warehouse', ?, 'Wholesale Dealer Hub', 'Chennai', 'Tamil Nadu', '600098', ?, 1)`,
          [`ADDR_${Date.now()}`, newUserId, `${defaultName} Enterprises`, autoMobile]
        );
        await conn.commit();
      } catch (e) {
        await conn.rollback();
        throw e;
      } finally {
        conn.release();
      }

      existingUser = await findUserByEmailOrMobile(cleanEmail);
    }

    if (existingUser.status === 'rejected') {
      return res.status(403).json({
        success: false,
        status: 'rejected',
        isApproved: false,
        error: 'Your account application has been rejected.'
      });
    }

    const token = `RO_B2B_JWT_${Date.now()}_${crypto.randomBytes(8).toString('hex')}`;
    const userPayload = {
      id: existingUser.id,
      name: existingUser.name,
      email: existingUser.email,
      mobile: existingUser.mobile,
      address: existingUser.address,
      business: existingUser.business,
      status: existingUser.status,
      isApproved: true,
      token: token
    };

    return res.status(200).json({
      success: true,
      message: '🎉 Welcome back! Login successful.',
      user: userPayload
    });
  } catch (err) {
    console.error('[API ERROR] Failed to verify-otp:', err);
    return res.status(500).json({ success: false, error: '❌ Internal server error verifying OTP.' });
  }
});

// 3. Sign Up Endpoint (Instant Approved Registration)
app.post('/api/auth/signup', async (req, res) => {
  try {
    const { name, mobile, email, password, confirmPassword, address } = req.body;
    
    const cleanName = (name || '').trim();
    const cleanMobile = (mobile || '').replace(/\D/g, '');
    const cleanEmail = (email || '').trim().toLowerCase();
    const cleanPassword = (password || '').trim();
    const cleanConfirmPassword = (confirmPassword || '').trim();
    const cleanAddress = (address || '').trim();

    if (!cleanName) return res.status(400).json({ success: false, error: 'Please enter your name' });
    if (!cleanMobile || cleanMobile.length !== 10) return res.status(400).json({ success: false, error: 'Please enter a valid 10-digit mobile number' });
    if (!cleanEmail || !isValidEmailAddress(cleanEmail)) return res.status(400).json({ success: false, error: 'Please enter a valid email address' });
    if (!cleanPassword || cleanPassword.length < 8) return res.status(400).json({ success: false, error: 'Password must contain at least 8 characters' });
    if (cleanPassword !== cleanConfirmPassword) return res.status(400).json({ success: false, error: 'Passwords do not match' });
    if (!cleanAddress) return res.status(400).json({ success: false, error: 'Please enter your address' });

    // Check duplicate email or mobile in MySQL
    const [existingEmail] = await pool.query(`SELECT id FROM users WHERE email = ?`, [cleanEmail]);
    if (existingEmail.length > 0) {
      return res.status(400).json({ success: false, error: 'An account with this email already exists.' });
    }

    const [existingMobile] = await pool.query(`SELECT id FROM users WHERE mobile = ?`, [cleanMobile]);
    if (existingMobile.length > 0) {
      return res.status(400).json({ success: false, error: 'An account with this mobile number already exists.' });
    }

    const passwordHash = await bcrypt.hash(cleanPassword, 10);
    const parsedAddr = parseAddressString(cleanAddress);
    const userId = `DEALER_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
    const businessName = `${cleanName} Aqua Wholesale`;

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      await conn.query(
        `INSERT INTO users (id, email, mobile, name, password_hash, business_name, owner_name, address, status, is_approved, reward_points)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'approved', 1, 0)`,
        [userId, cleanEmail, cleanMobile, cleanName, passwordHash, businessName, cleanName, cleanAddress]
      );

      await conn.query(
        `INSERT INTO user_addresses (id, user_id, label, business_name, street, city, state, pincode, phone, is_default)
         VALUES (?, ?, 'Main Warehouse & Hub', ?, ?, ?, ?, ?, ?, 1)`,
        [`ADDR_SIGNUP_${Date.now()}`, userId, businessName, cleanAddress, parsedAddr.city, parsedAddr.state, parsedAddr.pincode, cleanMobile]
      );

      await conn.commit();
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }

    console.log(`👤 [MYSQL SIGNUP SUCCESS] Created dealer account for ${cleanEmail}`);

    return res.status(200).json({
      success: true,
      status: 'approved',
      isApproved: true,
      message: 'Your account has been created successfully! You can now log in.'
    });
  } catch (err) {
    console.error('[API ERROR] Failed signup:', err);
    return res.status(500).json({ success: false, error: 'Server error during signup.' });
  }
});

// 4. Password Login Endpoint
app.post('/api/auth/login', async (req, res) => {
  try {
    const { identifier, email, mobile, password } = req.body;
    const loginTarget = identifier || email || mobile || '';
    const cleanId = (loginTarget || '').trim().toLowerCase();
    const cleanPassword = (password || '').trim();

    if (!cleanId || !cleanPassword) {
      return res.status(400).json({ success: false, error: 'Please enter your email/mobile and password.' });
    }

    const user = await findUserByEmailOrMobile(cleanId);
    if (!user || !user.passwordHash) {
      return res.status(400).json({ success: false, error: 'Invalid email/mobile or password.' });
    }

    const isMatch = await bcrypt.compare(cleanPassword, user.passwordHash);
    if (!isMatch) {
      return res.status(400).json({ success: false, error: 'Invalid email/mobile or password.' });
    }

    if (user.status === 'rejected') {
      return res.status(403).json({
        success: false,
        status: 'rejected',
        isApproved: false,
        error: 'Your account application has been rejected.'
      });
    }

    const token = `RO_B2B_JWT_${Date.now()}_${crypto.randomBytes(8).toString('hex')}`;
    const userPayload = {
      id: user.id,
      name: user.name,
      email: user.email,
      mobile: user.mobile,
      address: user.address,
      business: user.business,
      status: 'approved',
      isApproved: true,
      token: token
    };

    console.log(`🔑 [MYSQL LOGIN SUCCESS] Logged in user: ${user.email}`);

    return res.status(200).json({
      success: true,
      message: 'Login successful.',
      token: token,
      user: userPayload
    });
  } catch (err) {
    console.error('[API ERROR] Failed login:', err);
    return res.status(500).json({ success: false, error: 'Server error during login.' });
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
    let isNewUser = false;

    if (user) {
      if (user.status === 'rejected') {
        return res.status(403).json({ success: false, status: 'rejected', isApproved: false, error: 'Account rejected.' });
      }
    } else {
      isNewUser = true;
      const userId = `DEALER_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
      const businessName = `${name} Aqua Wholesale`;

      const conn = await pool.getConnection();
      try {
        await conn.beginTransaction();
        const googleMobile = `98${Math.floor(10000000 + Math.random() * 90000000)}`;
        await conn.query(
          `INSERT INTO users (id, email, mobile, name, password_hash, business_name, owner_name, address, status, is_approved, reward_points)
           VALUES (?, ?, ?, ?, '', ?, ?, 'Wholesale Dealer Hub', 'approved', 1, 0)`,
          [userId, cleanEmail, googleMobile, name, businessName, name]
        );
        await conn.query(
          `INSERT INTO user_addresses (id, user_id, label, business_name, street, city, state, pincode, phone, is_default)
           VALUES (?, ?, 'Main Warehouse', ?, 'Wholesale Dealer Hub', 'Chennai', 'Tamil Nadu', '600098', ?, 1)`,
          [`ADDR_${Date.now()}`, userId, businessName, googleMobile]
        );
        await conn.commit();
      } catch (e) {
        await conn.rollback();
        throw e;
      } finally {
        conn.release();
      }

      user = await findUserByEmailOrMobile(cleanEmail);
    }

    const token = `RO_B2B_JWT_GOOGLE_${Date.now()}_${crypto.randomBytes(8).toString('hex')}`;
    return res.status(200).json({
      success: true,
      isNewUser: isNewUser,
      message: isNewUser ? `🎉 Welcome ${name}!` : `🎉 Welcome back ${name}!`,
      user: { ...user, token }
    });
  } catch (err) {
    console.error('[API ERROR] Failed google-signin:', err);
    return res.status(401).json({ success: false, error: err.message });
  }
});

// -----------------------------------------------------------------------------
// ADMIN ENDPOINTS (MYSQL BACKED)
// -----------------------------------------------------------------------------

app.get('/api/admin/dealers', async (req, res) => {
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
      isApproved: user.is_approved === 1 || user.status === 'approved',
      authMethod: 'Password/OTP',
      createdAt: user.created_at ? new Date(user.created_at).toISOString() : new Date().toISOString()
    }));

    return res.json({ success: true, count: dealersList.length, dealers: dealersList });
  } catch (err) {
    console.error('[API ERROR] Admin dealers:', err);
    return res.status(500).json({ success: false, error: 'Server error fetching dealers.' });
  }
});

app.post('/api/admin/set-status', async (req, res) => {
  try {
    const { identifier, email, status } = req.body;
    const cleanId = (identifier || email || '').trim().toLowerCase();
    const validStatuses = ['approved', 'pending', 'rejected'];
    const cleanStatus = (status || '').toLowerCase();

    if (!cleanId || !validStatuses.includes(cleanStatus)) {
      return res.status(400).json({ success: false, error: 'Invalid identifier or status.' });
    }

    const isApproved = (cleanStatus === 'approved') ? 1 : 0;
    const [result] = await pool.query(
      `UPDATE users SET status = ?, is_approved = ? WHERE email = ? OR id = ? OR mobile = ?`,
      [cleanStatus, isApproved, cleanId, cleanId, cleanId]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, error: 'Dealer user not found.' });
    }

    return res.status(200).json({
      success: true,
      message: `Dealer status updated to ${cleanStatus}`,
      user: { email: cleanId, status: cleanStatus, isApproved: isApproved === 1 }
    });
  } catch (err) {
    console.error('[API ERROR] Admin set-status:', err);
    return res.status(500).json({ success: false, error: 'Server error updating status.' });
  }
});

// -----------------------------------------------------------------------------
// USER PROFILE, ADDRESSES, REWARDS, INVOICES & SUPPORT ENDPOINTS (MYSQL BACKED)
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

    const [result] = await pool.query(
      `UPDATE users SET name = ?, owner_name = ?, mobile = ?, business_name = ?, address = ? WHERE email = ?`,
      [cleanName, cleanName, cleanMobile, cleanBusiness || `${cleanName} Aqua Wholesale`, cleanAddress, cleanEmail]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, error: 'User account not found.' });
    }

    const updatedUser = await findUserByEmailOrMobile(cleanEmail);
    return res.status(200).json({
      success: true,
      message: 'Profile updated successfully!',
      user: {
        id: updatedUser.id,
        name: updatedUser.name,
        email: updatedUser.email,
        mobile: updatedUser.mobile,
        address: updatedUser.address,
        business: updatedUser.business,
        status: updatedUser.status,
        isApproved: true,
        token: `RO_B2B_JWT_${Date.now()}`
      }
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

    const [rows] = await pool.query(`SELECT password_hash FROM users WHERE email = ?`, [cleanEmail]);
    if (rows.length === 0) return res.status(404).json({ success: false, error: 'User not found.' });

    const currentHash = rows[0].password_hash;
    if (currentHash) {
      const isMatch = await bcrypt.compare(cleanCurrentPass, currentHash);
      if (!isMatch) return res.status(400).json({ success: false, error: 'Current password is incorrect.' });
    }

    const newHash = await bcrypt.hash(cleanNewPass, 10);
    await pool.query(`UPDATE users SET password_hash = ? WHERE email = ?`, [newHash, cleanEmail]);

    return res.status(200).json({ success: true, message: 'Password changed successfully!' });
  } catch (err) {
    console.error('[API ERROR] Change password:', err);
    return res.status(500).json({ success: false, error: 'Server error updating password.' });
  }
});

app.get('/api/user/addresses', async (req, res) => {
  try {
    const email = (req.query.email || '').trim().toLowerCase();
    if (!email) return res.status(400).json({ success: false, error: 'Email parameter required.' });

    const user = await findUserByEmailOrMobile(email);
    if (!user) return res.status(404).json({ success: false, error: 'User not found.' });

    return res.status(200).json({ success: true, addresses: user.addresses });
  } catch (err) {
    console.error('[API ERROR] Fetch addresses:', err);
    return res.status(500).json({ success: false, error: 'Server error fetching addresses.' });
  }
});

app.post('/api/user/addresses/save', async (req, res) => {
  try {
    const { email, id, fullName, phone, businessName, street, city, state, pincode, label, isDefault } = req.body;
    const cleanEmail = (email || '').trim().toLowerCase();
    if (!cleanEmail) return res.status(400).json({ success: false, error: 'Email required.' });

    const [userRows] = await pool.query(`SELECT id, mobile, business_name FROM users WHERE email = ?`, [cleanEmail]);
    if (userRows.length === 0) return res.status(404).json({ success: false, error: 'User not found.' });

    const userId = userRows[0].id;
    const addrId = id || `ADDR_${Date.now()}_${Math.floor(Math.random()*1000)}`;
    const isDef = !!isDefault;

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      if (isDef) {
        await conn.query(`UPDATE user_addresses SET is_default = 0 WHERE user_id = ?`, [userId]);
      }

      await conn.query(
        `INSERT INTO user_addresses (id, user_id, label, business_name, street, city, state, pincode, phone, is_default)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
         label=VALUES(label), business_name=VALUES(business_name), street=VALUES(street), city=VALUES(city),
         state=VALUES(state), pincode=VALUES(pincode), phone=VALUES(phone), is_default=VALUES(is_default)`,
        [
          addrId, userId, (label || 'Main Warehouse').trim(),
          (businessName || userRows[0].business_name || '').trim(),
          (street || '').trim(), (city || 'Chennai').trim(),
          (state || 'Tamil Nadu').trim(), (pincode || '600098').trim(),
          (phone || userRows[0].mobile || '').trim(), isDef ? 1 : 0
        ]
      );

      await conn.commit();
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }

    const updatedUser = await findUserByEmailOrMobile(cleanEmail);
    return res.status(200).json({
      success: true,
      message: 'Delivery address saved successfully!',
      addresses: updatedUser.addresses
    });
  } catch (err) {
    console.error('[API ERROR] Save address:', err);
    return res.status(500).json({ success: false, error: 'Server error saving address.' });
  }
});

app.post('/api/user/addresses/delete', async (req, res) => {
  try {
    const { email, addressId } = req.body;
    const cleanEmail = (email || '').trim().toLowerCase();
    if (!cleanEmail || !addressId) return res.status(400).json({ success: false, error: 'Email and Address ID required.' });

    const [userRows] = await pool.query(`SELECT id FROM users WHERE email = ?`, [cleanEmail]);
    if (userRows.length === 0) return res.status(404).json({ success: false, error: 'User not found.' });

    await pool.query(`DELETE FROM user_addresses WHERE id = ? AND user_id = ?`, [addressId, userRows[0].id]);

    const updatedUser = await findUserByEmailOrMobile(cleanEmail);
    return res.status(200).json({
      success: true,
      message: 'Address deleted successfully.',
      addresses: updatedUser.addresses
    });
  } catch (err) {
    console.error('[API ERROR] Delete address:', err);
    return res.status(500).json({ success: false, error: 'Server error deleting address.' });
  }
});

app.post('/api/user/addresses/set-default', async (req, res) => {
  try {
    const { email, addressId } = req.body;
    const cleanEmail = (email || '').trim().toLowerCase();
    if (!cleanEmail || !addressId) return res.status(400).json({ success: false, error: 'Email and Address ID required.' });

    const [userRows] = await pool.query(`SELECT id FROM users WHERE email = ?`, [cleanEmail]);
    if (userRows.length === 0) return res.status(404).json({ success: false, error: 'User not found.' });

    const userId = userRows[0].id;
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      await conn.query(`UPDATE user_addresses SET is_default = 0 WHERE user_id = ?`, [userId]);
      await conn.query(`UPDATE user_addresses SET is_default = 1 WHERE id = ? AND user_id = ?`, [addressId, userId]);
      await conn.commit();
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }

    const updatedUser = await findUserByEmailOrMobile(cleanEmail);
    return res.status(200).json({
      success: true,
      message: 'Default delivery address updated.',
      addresses: updatedUser.addresses
    });
  } catch (err) {
    console.error('[API ERROR] Set default address:', err);
    return res.status(500).json({ success: false, error: 'Server error setting default address.' });
  }
});

// -----------------------------------------------------------------------------
// ORDERS & CHECKOUT ENDPOINTS (MYSQL BACKED WITH TRANSACTIONS)
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
      const [itemRows] = await pool.query(
        `SELECT * FROM order_items WHERE order_id = ?`,
        [o.order_id]
      );
      formattedOrders.push({
        orderId: o.order_id,
        userEmail: o.user_email,
        userName: o.user_name,
        userBusiness: o.user_business,
        items: itemRows.map(i => ({
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
        deliveryNote: o.delivery_note || '',
        status: o.status,
        invoiceNumber: o.invoice_number,
        createdAt: o.created_at ? new Date(o.created_at).toISOString() : new Date().toISOString()
      });
    }

    return res.status(200).json({
      success: true,
      count: formattedOrders.length,
      orders: formattedOrders
    });
  } catch (err) {
    console.error('[API ERROR] Fetch orders:', err);
    return res.status(500).json({ success: false, error: 'Server error fetching orders.' });
  }
});

app.post('/api/user/orders/create', async (req, res) => {
  try {
    const { email, items, subtotal, discount, gst, deliveryFee, grandTotal, paymentMethod, deliveryAddress, deliveryNote } = req.body;
    const cleanEmail = (email || '').trim().toLowerCase();

    if (!cleanEmail || !items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ success: false, error: 'Valid user email and cart items required.' });
    }

    const [userRows] = await pool.query(`SELECT id, name, business_name, reward_points FROM users WHERE email = ?`, [cleanEmail]);
    const user = userRows.length > 0 ? userRows[0] : null;

    const orderId = `RO-ORD-${Date.now().toString().slice(-6)}-${Math.floor(100 + Math.random() * 900)}`;
    const invoiceNumber = `INV-2026-${Math.floor(1000 + Math.random() * 9000)}`;
    const pointsEarned = Math.floor((grandTotal || 0) / 100) * 5;
    let totalRewardPoints = user ? user.reward_points : 0;

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      // 1. Insert Order Header
      await conn.query(
        `INSERT INTO orders 
         (order_id, user_id, user_email, user_name, user_business, subtotal, discount, gst, delivery_fee, grand_total, payment_method, delivery_address, delivery_note, status, invoice_number)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Processing & Dispatched', ?)`,
        [
          orderId, user ? user.id : null, cleanEmail,
          user ? user.name : cleanEmail.split('@')[0],
          user ? user.business_name : 'Aqua Wholesale',
          subtotal || 0, discount || 0, gst || 0, deliveryFee || 0, grandTotal || 0,
          paymentMethod || 'UPI Direct QR Transfer',
          deliveryAddress || 'Wholesale Dealer Hub',
          deliveryNote || '', invoiceNumber
        ]
      );

      // 2. Insert Order Line Items
      for (const item of items) {
        const unitPrice = item.numericPrice || parseFloat((item.price || '0').toString().replace(/[^\d.]/g, '')) || 0;
        await conn.query(
          `INSERT INTO order_items (order_id, product_id, product_name, brand, unit_price, quantity, moq, img_src, sku)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            orderId, item.id || item.sku || null, item.name || 'RO Equipment',
            item.brand || 'RO Wholesale', unitPrice, item.quantity || 1,
            item.moq || '', item.imgSrc || item.img || '', item.sku || item.id || ''
          ]
        );
      }

      // 3. Update Rewards if user exists
      if (user && pointsEarned > 0) {
        await conn.query(`UPDATE users SET reward_points = reward_points + ? WHERE id = ?`, [pointsEarned, user.id]);
        await conn.query(
          `INSERT INTO rewards_history (user_id, order_id, order_amount, points_earned) VALUES (?, ?, ?, ?)`,
          [user.id, orderId, grandTotal || 0, pointsEarned]
        );
        totalRewardPoints += pointsEarned;
      }

      await conn.commit();
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }

    const responseOrder = {
      orderId: orderId,
      userEmail: cleanEmail,
      userName: user ? user.name : cleanEmail.split('@')[0],
      userBusiness: user ? user.business_name : 'Aqua Wholesale',
      items: items,
      subtotal: subtotal || 0,
      discount: discount || 0,
      gst: gst || 0,
      deliveryFee: deliveryFee || 0,
      grandTotal: grandTotal || 0,
      paymentMethod: paymentMethod || 'UPI Direct QR Transfer',
      deliveryAddress: deliveryAddress || 'Wholesale Dealer Hub',
      deliveryNote: deliveryNote || '',
      status: 'Processing & Dispatched',
      invoiceNumber: invoiceNumber,
      createdAt: new Date().toISOString()
    };

    console.log(`📦 [MYSQL ORDER SUCCESS] Created order ${orderId} for ${cleanEmail}`);

    return res.status(200).json({
      success: true,
      message: `🎉 Order placed successfully! B2B GST Invoice Generated.`,
      order: responseOrder,
      pointsEarned: pointsEarned,
      totalRewardPoints: totalRewardPoints
    });
  } catch (err) {
    console.error('[API ERROR] Create order:', err);
    return res.status(500).json({ success: false, error: 'Server error creating order.' });
  }
});

// -----------------------------------------------------------------------------
// REWARDS, GST INVOICES & SUPPORT DESK (MYSQL BACKED)
// -----------------------------------------------------------------------------

app.get('/api/user/rewards', async (req, res) => {
  try {
    const email = (req.query.email || '').trim().toLowerCase();
    if (!email) return res.status(400).json({ success: false, error: 'Email required.' });

    const [userRows] = await pool.query(`SELECT id, reward_points FROM users WHERE email = ?`, [email]);
    if (userRows.length === 0) return res.status(404).json({ success: false, error: 'User account not found.' });

    const userId = userRows[0].id;
    const totalPoints = userRows[0].reward_points || 0;

    const [historyRows] = await pool.query(
      `SELECT order_id as orderId, order_amount as orderAmount, points_earned as pointsEarned, created_at as date FROM rewards_history WHERE user_id = ? ORDER BY created_at DESC`,
      [userId]
    );

    const totalPointsEarned = historyRows.reduce((sum, h) => sum + (h.pointsEarned || 0), 0);

    return res.status(200).json({
      success: true,
      totalPoints: totalPoints,
      totalPointsEarned: totalPointsEarned,
      history: historyRows.map(h => ({
        orderId: h.orderId,
        orderAmount: parseFloat(h.orderAmount),
        pointsEarned: h.pointsEarned,
        date: h.date ? new Date(h.date).toISOString() : new Date().toISOString()
      }))
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

    const [orders] = await pool.query(
      `SELECT order_id, grand_total, gst, invoice_number, created_at FROM orders WHERE user_email = ? ORDER BY created_at DESC`,
      [email]
    );

    const creditLimit = 250000;
    const totalSpent = orders.reduce((sum, o) => sum + parseFloat(o.grand_total || 0), 0);
    const availableCredit = Math.max(0, creditLimit - (totalSpent % creditLimit));

    const invoices = orders.map(o => ({
      invoiceNumber: o.invoice_number,
      orderId: o.order_id,
      date: o.created_at ? new Date(o.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'Sep 18, 2026',
      amount: parseFloat(o.grand_total),
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
    return res.status(500).json({ success: false, error: 'Server error fetching GST invoices.' });
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
      `INSERT INTO support_tickets (user_id, user_email, subject, message) VALUES (?, ?, ?, ?)`,
      [userId, cleanEmail, subject || category || 'Dealer Query', cleanMessage]
    );

    const ticketId = `TKT-2026-${result.insertId || Math.floor(100000 + Math.random() * 900000)}`;
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
// PRODUCT CATALOG ENDPOINTS (MYSQL BACKED)
// -----------------------------------------------------------------------------

app.get('/api/products', async (req, res) => {
  try {
    const [rows] = await pool.query(`SELECT * FROM products ORDER BY category_key, name`);
    const products = rows.map(p => ({
      id: p.id,
      category: p.category_key,
      brand: p.brand,
      name: p.name,
      price: parseFloat(p.price),
      mrp: parseFloat(p.mrp),
      moq: p.moq,
      badge: p.badge,
      rating: p.rating,
      img: p.img,
      sku: p.sku,
      desc: p.description,
      specs: p.specs_json,
      features: p.features_json,
      applications: p.applications
    }));
    return res.json({ success: true, count: products.length, products: products });
  } catch (err) {
    console.error('[API ERROR] Get products:', err);
    return res.status(500).json({ success: false, error: 'Server error fetching products.' });
  }
});

app.get('/api/categories', async (req, res) => {
  try {
    const [rows] = await pool.query(`SELECT * FROM categories ORDER BY display_order ASC`);
    return res.json({ success: true, count: rows.length, categories: rows });
  } catch (err) {
    console.error('[API ERROR] Get categories:', err);
    return res.status(500).json({ success: false, error: 'Server error fetching categories.' });
  }
});

// Serve Admin Dashboard Page
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'web_preview', 'admin.html'));
});

// Serve SPA Fallback (Never intercept /api routes)
app.get('*', (req, res) => {
  if (req.path.startsWith('/api')) {
    return res.status(404).json({ success: false, error: 'API endpoint not found.' });
  }
  res.sendFile(path.join(__dirname, 'web_preview', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`===================================================`);
  console.log(`🚀 RO Wholesale B2B Backend Server (MySQL Backed) Running on Port ${PORT}`);
  console.log(`🌐 Dealer Portal Live Web: http://127.0.0.1:${PORT}/`);
  console.log(`===================================================`);
});
