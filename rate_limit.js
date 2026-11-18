// Small fixed-window rate limiter (no extra dependency). Counts are kept per
// server instance; that is enough to blunt password guessing and request
// floods on the login, code and API endpoints.
function rateLimit({ windowMs, max, keyPrefix = 'rl', message = 'Too many requests. Please wait and try again.', now = () => Date.now() }) {
  const hits = new Map();
  let lastSweep = now();
  return function rateLimitMiddleware(req, res, next) {
    const t = now();
    if (t - lastSweep > windowMs) {
      for (const [key, entry] of hits) if (entry.reset <= t) hits.delete(key);
      lastSweep = t;
    }
    const key = `${keyPrefix}:${req.ip || req.socket?.remoteAddress || 'unknown'}`;
    let entry = hits.get(key);
    if (!entry || entry.reset <= t) {
      entry = { count: 0, reset: t + windowMs };
      hits.set(key, entry);
    }
    entry.count += 1;
    const remaining = Math.max(0, max - entry.count);
    if (typeof res.setHeader === 'function') {
      res.setHeader('RateLimit-Limit', String(max));
      res.setHeader('RateLimit-Remaining', String(remaining));
      res.setHeader('RateLimit-Reset', String(Math.ceil((entry.reset - t) / 1000)));
    }
    if (entry.count > max) {
      if (typeof res.setHeader === 'function') res.setHeader('Retry-After', String(Math.ceil((entry.reset - t) / 1000)));
      return res.status(429).json({ success: false, error: message });
    }
    return next();
  };
}

module.exports = { rateLimit };
