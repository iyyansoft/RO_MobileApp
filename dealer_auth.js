// Customer (dealer) data must only be readable/changeable by that dealer.
//
// Before this guard, the cart identified the dealer by an `x-user-id` header
// or `userId` parameter, and /api/user/* by an `email` parameter, with no
// session check: anyone who knew a dealer's email or id could read their
// orders, invoices and addresses, change their profile, or edit their cart.
//
// Both customer apps already send the signed dealer token
// (`Authorization: Bearer ...`) on every request, so requiring it does not
// change their behaviour.
const { verifyDealerToken } = require('./checkout_service');

function present(value) {
  return value !== undefined && value !== null && String(value).trim() !== '';
}

function dealerTokenFrom(req) {
  const header = String(req.headers['authorization'] || '');
  if (header.startsWith('Bearer ')) return header.slice(7).trim();
  return String(req.headers['x-dealer-token'] || req.headers['x-user-token'] || '').trim();
}

/**
 * Middleware: a valid dealer session is required, and every email / user id
 * named in the request must be that dealer's own.
 */
function requireDealerSession(secret, verify = verifyDealerToken) {
  return function dealerSessionGuard(req, res, next) {
    const dealer = verify(dealerTokenFrom(req), secret);
    if (!dealer || !dealer.email) {
      return res.status(401).json({ success: false, error: 'Your session has expired. Please sign in again.' });
    }
    const ownEmail = String(dealer.email).trim().toLowerCase();
    const ownId = String(dealer.id || '');
    const emails = [req.query?.email, req.body?.email].filter(present).map(v => String(v).trim().toLowerCase());
    const ids = [req.headers['x-user-id'], req.query?.userId, req.body?.userId].filter(present).map(v => String(v).trim());
    if (emails.some(email => email !== ownEmail) || ids.some(id => id !== ownId)) {
      return res.status(403).json({ success: false, error: "This account cannot access another dealer's data." });
    }
    req.dealer = dealer;
    return next();
  };
}

/** Routes that read or change one dealer's own data. */
const DEALER_DATA_ROUTES = [
  '/api/cart',
  '/api/user/orders',
  '/api/user/gst-invoices',
  '/api/user/addresses',
  '/api/user/address',
  '/api/user/rewards',
  '/api/user/update-profile',
  '/api/user/change-password',
  '/api/user/support-ticket',
];

module.exports = { requireDealerSession, dealerTokenFrom, DEALER_DATA_ROUTES };
