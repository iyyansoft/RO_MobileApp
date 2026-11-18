// Admin sessions and login protection.
//
// Sessions are signed, expiring tokens (no server memory), so they survive
// backend restarts, redeploys and multiple instances. The signing key is
// derived from the session secret AND the admin password, so changing
// ADMIN_PASSWORD signs every existing admin out.
const crypto = require('crypto');

const DEFAULT_TTL_MS = 12 * 60 * 60 * 1000; // 12 hours
const TOKEN_PREFIX = 'roadm1';

function safeEqual(a, b) {
  const left = Buffer.from(String(a));
  const right = Buffer.from(String(b));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function createAdminAuth({
  email,
  password,
  secret,
  ttlMs = DEFAULT_TTL_MS,
  maxFailures = 5,
  lockMs = 15 * 60 * 1000,
  now = () => Date.now(),
} = {}) {
  if (!email || !password || !secret) throw new Error('Admin email, password and session secret are required.');
  const adminEmail = String(email).trim().toLowerCase();
  const signingKey = crypto.createHmac('sha256', String(secret)).update(`admin-session:${adminEmail}:${password}`).digest();
  const revoked = new Map(); // jti -> exp (until the token would expire anyway)
  const failures = new Map(); // key -> { count, windowStart, lockedUntil }

  const sign = payload => crypto.createHmac('sha256', signingKey).update(payload).digest('base64url');

  function issue() {
    const iat = now();
    const payload = Buffer.from(JSON.stringify({
      sub: 'admin', email: adminEmail, iat, exp: iat + ttlMs, jti: crypto.randomBytes(12).toString('hex'),
    })).toString('base64url');
    return `${TOKEN_PREFIX}.${payload}.${sign(payload)}`;
  }

  function verify(token) {
    const parts = String(token || '').split('.');
    if (parts.length !== 3 || parts[0] !== TOKEN_PREFIX) return null;
    if (!safeEqual(sign(parts[1]), parts[2])) return null;
    let claims;
    try { claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')); } catch (_) { return null; }
    if (claims.sub !== 'admin' || claims.email !== adminEmail) return null;
    if (!Number.isFinite(claims.exp) || claims.exp <= now()) return null;
    if (revoked.has(claims.jti)) return null;
    return claims;
  }

  function revoke(token) {
    const claims = verify(token);
    if (!claims) return false;
    revoked.set(claims.jti, claims.exp);
    for (const [jti, exp] of revoked) if (exp <= now()) revoked.delete(jti);
    return true;
  }

  const checkPassword = (candidateEmail, candidatePassword) =>
    safeEqual(String(candidateEmail || '').trim().toLowerCase(), adminEmail)
    & safeEqual(String(candidatePassword || ''), password);

  function lockedFor(key) {
    const entry = failures.get(key);
    if (!entry || entry.lockedUntil <= now()) return 0;
    return entry.lockedUntil - now();
  }

  function recordFailure(key) {
    const current = failures.get(key);
    const entry = current && current.windowStart > now() - lockMs
      ? current
      : { count: 0, windowStart: now(), lockedUntil: 0 };
    entry.count += 1;
    if (entry.count >= maxFailures) entry.lockedUntil = now() + lockMs;
    failures.set(key, entry);
    return entry;
  }

  const clearFailures = key => failures.delete(key);

  return { issue, verify, revoke, checkPassword, lockedFor, recordFailure, clearFailures, ttlMs };
}

/** Bearer token or x-admin-token header value. */
function adminTokenFrom(req) {
  const authHeader = String(req.headers['authorization'] || '');
  if (authHeader.startsWith('Bearer ')) return authHeader.substring(7).trim();
  return String(req.headers['x-admin-token'] || '').trim();
}

module.exports = { createAdminAuth, adminTokenFrom, DEFAULT_TTL_MS };
