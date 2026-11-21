// Reward points: one ledger (public.rewards_history) plus the dealer's
// running balance (public.users.reward_points). Every value is computed here,
// on the server, from stored order totals; nothing the app sends is trusted.
//
// Rules
//   * 2.5% of the eligible order amount: Rs 500 -> 12.50 pts, Rs 1,000 -> 25.
//     Points keep 2 decimals (exact paise maths, half-up on the 3rd decimal).
//   * 1 point = Rs 1 when redeemed.
//   * Credited once per order at checkout (unique index on the 'earned' row).
//   * Cancelled order -> its net points (and eligible amount) are reversed;
//     un-cancelled -> reinstated. Each order's net is either 0 or its credit.
//   * Free Claim unlocks when the CUMULATIVE eligible amount (all non-cancelled
//     orders) reaches Rs 1,00,000. Below that, claims are refused.
//   * A claim holds its points as 'pending'; the admin approves (final) or
//     rejects it (points go back to the balance).
//
// Ledger rows (rewards_history.entry_type):
//   earned      +points  +order amount   status credited
//   reversed    -points  -order amount   status reversed   (order cancelled)
//   reinstated  +points  +order amount   status credited   (cancel undone)
//   redeemed    points_redeemed = claim  status pending | approved | rejected
// so SUM(points_earned) = net points earned, SUM(order_amount) = eligible
// purchases, and balance = net earned - redeemed (pending + approved).
// Rows written before this change are 'earned' rows (5%, kept as they were).

const REWARD_RATE = 0.025;
const FREE_CLAIM_THRESHOLD = 100000;
const POINT_VALUE_INR = 1;
const ORDER_ENTRY_TYPES = ['earned', 'reversed', 'reinstated'];

const num = value => {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
};
/** Rounds to 2 decimals without binary drift (12.775 -> 12.78). */
const round2 = value => Math.round((num(value) + Number.EPSILON) * 100) / 100;

/** Points for an eligible amount: amount x 2.5%, exact to the paisa. */
function rewardPointsFor(amount) {
  const paise = Math.round(num(amount) * 100);
  if (paise <= 0) return 0;
  // paise x 0.025 = paise / 40 hundredths of a point (integer maths).
  return Math.round(paise / 40) / 100;
}

function rewardError(message, status = 400) {
  const error = new Error(message);
  error.status = status;
  return error;
}

// Until migration 010 is applied (today's live database), every function
// keeps the previous behaviour exactly, so deploying this code first changes
// nothing. Checked on each call (one cheap catalogue lookup), so applying the
// migration takes effect without a restart.
async function rewardLedgerReady(db) {
  const [rows] = await db.query(
    `SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'rewards_history' AND column_name = 'entry_type'
      LIMIT 1`
  );
  return rows.length > 0;
}
const notYetAvailable = () => rewardError('Free Claim is not available yet. Please try again later.', 503);

/** Credits an order's points once (a repeat call changes nothing). */
async function creditOrderReward(conn, { userId, orderId, amount }) {
  if (!(await rewardLedgerReady(conn))) {
    // Previous rule, unchanged until the migration: 5%, whole points.
    const legacy = Math.floor(num(amount) * 0.05);
    await conn.query('UPDATE users SET reward_points = reward_points + ? WHERE id = ?', [legacy, userId]);
    await conn.query('INSERT INTO rewards_history (user_id, order_id, order_amount, points_earned) VALUES (?, ?, ?, ?)', [userId, orderId, amount, legacy]);
    return legacy;
  }
  const points = rewardPointsFor(amount);
  const [inserted] = await conn.query(
    `INSERT INTO rewards_history (user_id, order_id, order_amount, points_earned, entry_type, status)
     VALUES (?, ?, ?, ?, 'earned', 'credited')
     ON CONFLICT (order_id) WHERE entry_type = 'earned' DO NOTHING
     RETURNING id`,
    [userId, orderId, round2(amount), points]
  );
  if (!inserted?.rows?.length) return 0; // already credited
  if (points > 0) await conn.query('UPDATE users SET reward_points = reward_points + ? WHERE id = ?', [points, userId]);
  return points;
}

async function orderRewardNet(conn, orderId) {
  const [rows] = await conn.query(
    `SELECT user_id,
            COALESCE(SUM(points_earned), 0) AS points,
            COALESCE(SUM(order_amount), 0) AS amount,
            COUNT(*) FILTER (WHERE entry_type = 'earned') AS earned_rows
       FROM rewards_history
      WHERE order_id = ? AND entry_type IN ('earned', 'reversed', 'reinstated')
      GROUP BY user_id`,
    [orderId]
  );
  return rows[0] || null;
}

/** Order cancelled: takes back whatever that order still has credited. */
async function reverseOrderReward(conn, orderId) {
  if (!(await rewardLedgerReady(conn))) return 0;
  const net = await orderRewardNet(conn, orderId);
  if (!net) return 0;
  const points = round2(net.points);
  const amount = round2(net.amount);
  if (points <= 0 && amount <= 0) return 0;
  await conn.query(
    `INSERT INTO rewards_history (user_id, order_id, order_amount, points_earned, entry_type, status, note)
     VALUES (?, ?, ?, ?, 'reversed', 'reversed', 'Order cancelled')`,
    [net.user_id, orderId, -amount, -points]
  );
  if (points !== 0) await conn.query('UPDATE users SET reward_points = reward_points - ? WHERE id = ?', [points, net.user_id]);
  return points;
}

/** Cancellation undone: gives back the order's original credit, once. */
async function reinstateOrderReward(conn, orderId) {
  if (!(await rewardLedgerReady(conn))) return 0;
  const net = await orderRewardNet(conn, orderId);
  if (!net || Number(net.earned_rows) === 0) return 0;
  if (round2(net.points) !== 0 || round2(net.amount) !== 0) return 0; // still credited
  const [[earned]] = await conn.query(
    `SELECT order_amount, points_earned FROM rewards_history
      WHERE order_id = ? AND entry_type = 'earned' LIMIT 1`,
    [orderId]
  );
  const points = round2(earned.points_earned);
  await conn.query(
    `INSERT INTO rewards_history (user_id, order_id, order_amount, points_earned, entry_type, status, note)
     VALUES (?, ?, ?, ?, 'reinstated', 'credited', 'Order cancellation undone')`,
    [net.user_id, orderId, round2(earned.order_amount), points]
  );
  if (points !== 0) await conn.query('UPDATE users SET reward_points = reward_points + ? WHERE id = ?', [points, net.user_id]);
  return points;
}

/** Points, eligibility and history for one dealer. */
async function rewardSummary(db, userId) {
  const [[user]] = await db.query('SELECT reward_points FROM users WHERE id = ? LIMIT 1', [userId]);
  const ready = await rewardLedgerReady(db);
  const [rows] = await db.query(
    `SELECT r.id, r.order_id, r.order_amount, r.points_earned,
            ${ready ? 'r.points_redeemed, r.entry_type, r.status, r.note, r.decided_at,' : ''}
            r.created_at,
            o.created_at AS order_date, o.status AS order_status
       FROM rewards_history r
       LEFT JOIN orders o ON o.order_id = r.order_id
      WHERE r.user_id = ?
      ORDER BY r.created_at DESC, r.id DESC`,
    [userId]
  );
  for (const row of rows) { // rows written before migration 010
    row.entry_type = row.entry_type || 'earned';
    row.status = row.status || 'credited';
  }
  let earned = 0; let eligible = 0; let redeemed = 0; let pending = 0;
  const reversedOrders = new Set();
  for (const row of rows) {
    if (ORDER_ENTRY_TYPES.includes(row.entry_type)) {
      earned += num(row.points_earned);
      eligible += num(row.order_amount);
    } else if (row.entry_type === 'redeemed') {
      if (row.status === 'pending') pending += num(row.points_redeemed);
      if (row.status === 'approved') redeemed += num(row.points_redeemed);
    }
  }
  // Net per order decides whether an 'earned' row is still active.
  const netByOrder = new Map();
  for (const row of rows) {
    if (!row.order_id || !ORDER_ENTRY_TYPES.includes(row.entry_type)) continue;
    netByOrder.set(row.order_id, num(netByOrder.get(row.order_id)) + num(row.points_earned));
  }
  for (const [orderId, net] of netByOrder) if (round2(net) === 0) reversedOrders.add(orderId);

  const iso = value => (value ? new Date(value).toISOString() : null);
  const history = rows.map(row => {
    const type = row.entry_type || 'earned';
    const isOrder = ORDER_ENTRY_TYPES.includes(type);
    let status = row.status || 'credited';
    if (type === 'earned' && reversedOrders.has(row.order_id)) status = 'reversed';
    return {
      id: Number(row.id),
      type,
      orderId: row.order_id || null,
      orderDate: iso(row.order_date) || (isOrder ? iso(row.created_at) : null),
      orderAmount: round2(row.order_amount),
      pointsEarned: isOrder ? round2(row.points_earned) : 0,
      pointsRedeemed: round2(row.points_redeemed),
      status,
      note: row.note || null,
      date: iso(row.created_at),
      createdAt: iso(row.created_at),
      decidedAt: iso(row.decided_at),
    };
  });
  const balance = round2(user ? user.reward_points : 0);
  eligible = round2(eligible);
  const unlocked = eligible >= FREE_CLAIM_THRESHOLD;
  return {
    totalPoints: balance,
    availablePoints: balance,
    availableValue: round2(balance * POINT_VALUE_INR),
    totalPointsEarned: round2(earned),
    totalPointsRedeemed: round2(redeemed),
    pendingRedemption: round2(pending),
    eligiblePurchaseAmount: eligible,
    freeClaimThreshold: FREE_CLAIM_THRESHOLD,
    remainingForFreeClaim: round2(Math.max(0, FREE_CLAIM_THRESHOLD - eligible)),
    freeClaimProgress: Math.min(1, Math.max(0, eligible / FREE_CLAIM_THRESHOLD)),
    freeClaimUnlocked: unlocked,
    canClaim: ready && unlocked && balance > 0,
    rewardRatePercent: REWARD_RATE * 100,
    pointValueInr: POINT_VALUE_INR,
    history,
  };
}

/** Dealer asks to redeem points. Server checks eligibility and balance. */
async function requestRewardClaim(conn, userId, requested) {
  if (!(await rewardLedgerReady(conn))) throw notYetAvailable();
  const raw = typeof requested === 'string' ? requested.trim() : requested;
  const points = Number(raw);
  if (!Number.isFinite(points) || points <= 0) throw rewardError('Enter the number of points to claim.');
  if (Math.abs(points * 100 - Math.round(points * 100)) > 1e-6) {
    throw rewardError('Points can have at most 2 decimals.');
  }
  const amount = round2(points);
  const [[user]] = await conn.query('SELECT id, reward_points FROM users WHERE id = ? FOR UPDATE', [userId]);
  if (!user) throw rewardError('User account not found.', 404);
  const [[totals]] = await conn.query(
    `SELECT COALESCE(SUM(order_amount), 0) AS eligible FROM rewards_history
      WHERE user_id = ? AND entry_type IN ('earned', 'reversed', 'reinstated')`,
    [userId]
  );
  const eligible = round2(totals.eligible);
  if (eligible < FREE_CLAIM_THRESHOLD) {
    throw rewardError(`Free Claim unlocks after ₹${FREE_CLAIM_THRESHOLD.toLocaleString('en-IN')} of purchases. ₹${round2(FREE_CLAIM_THRESHOLD - eligible).toLocaleString('en-IN')} to go.`, 403);
  }
  const balance = round2(user.reward_points);
  if (amount > balance) throw rewardError(`You have ${balance} points available.`, 409);
  const [inserted] = await conn.query(
    `INSERT INTO rewards_history (user_id, order_id, order_amount, points_earned, points_redeemed, entry_type, status, note)
     VALUES (?, NULL, 0, 0, ?, 'redeemed', 'pending', 'Free Claim request')
     RETURNING id`,
    [userId, amount]
  );
  const row = inserted.rows[0];
  await conn.query('UPDATE users SET reward_points = reward_points - ? WHERE id = ?', [amount, userId]);
  return { id: Number(row.id), points: amount, value: round2(amount * POINT_VALUE_INR), status: 'pending', balance: round2(balance - amount) };
}

/** Admin approves or rejects a pending claim (rejected = points returned). */
async function decideRewardClaim(conn, claimId, decision) {
  if (!(await rewardLedgerReady(conn))) throw notYetAvailable();
  const status = String(decision || '').trim().toLowerCase();
  if (!['approved', 'rejected'].includes(status)) throw rewardError('Choose approved or rejected.');
  const [[claim]] = await conn.query(
    `SELECT id, user_id, points_redeemed, status FROM rewards_history
      WHERE id = ? AND entry_type = 'redeemed' FOR UPDATE`,
    [claimId]
  );
  if (!claim) throw rewardError('Claim not found.', 404);
  if (claim.status !== 'pending') throw rewardError(`This claim is already ${claim.status}.`, 409);
  await conn.query('UPDATE rewards_history SET status = ?, decided_at = CURRENT_TIMESTAMP WHERE id = ?', [status, claimId]);
  if (status === 'rejected') {
    await conn.query('UPDATE users SET reward_points = reward_points + ? WHERE id = ?', [round2(claim.points_redeemed), claim.user_id]);
  }
  return { id: Number(claim.id), status, points: round2(claim.points_redeemed) };
}

module.exports = {
  REWARD_RATE,
  FREE_CLAIM_THRESHOLD,
  POINT_VALUE_INR,
  rewardPointsFor,
  rewardLedgerReady,
  creditOrderReward,
  reverseOrderReward,
  reinstateOrderReward,
  rewardSummary,
  requestRewardClaim,
  decideRewardClaim,
};
