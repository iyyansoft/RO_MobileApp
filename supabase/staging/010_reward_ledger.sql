-- Reward points v2: 2.5% with decimals, one credit per order, reversal on
-- cancellation, and Free Claim redemption requests. Reuses the existing
-- tables (public.rewards_history + public.users.reward_points); no new table.
--
-- What changes
--   * users.reward_points and rewards_history.points_earned become
--     numeric(12,2) (12.50 points must be storable). Existing whole-number
--     values convert exactly (3558 -> 3558.00); no balance changes.
--   * rewards_history gains entry_type / status / points_redeemed / note /
--     decided_at. Every existing row becomes entry_type 'earned', status
--     'credited', points_redeemed 0, i.e. exactly what it already was.
--   * A partial unique index allows only ONE 'earned' row per order, so an
--     order can never be credited twice.
--
-- Preflight: aborts (changing nothing) if any order already has two reward
-- rows, or if balances do not match the ledger.
-- Take a database backup first (node scripts/backup_database.cjs).
-- Do not run on production until it has been reviewed and approved.
--
-- Rollback (only while no decimal points / claims exist):
--   DROP INDEX IF EXISTS public.ux_rewards_history_order_earned;
--   ALTER TABLE public.rewards_history DROP COLUMN entry_type, DROP COLUMN status,
--     DROP COLUMN points_redeemed, DROP COLUMN note, DROP COLUMN decided_at;
--   ALTER TABLE public.rewards_history ALTER COLUMN points_earned TYPE integer;
--   ALTER TABLE public.users ALTER COLUMN reward_points TYPE integer;

BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT order_id FROM public.rewards_history
     WHERE order_id IS NOT NULL GROUP BY order_id HAVING COUNT(*) > 1
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'rewards_history' AND column_name = 'entry_type'
  ) THEN
    RAISE EXCEPTION 'An order has more than one reward row; resolve it before this migration.';
  END IF;
END $$;

ALTER TABLE public.users
  ALTER COLUMN reward_points TYPE numeric(12,2) USING reward_points::numeric(12,2),
  ALTER COLUMN reward_points SET DEFAULT 0;

ALTER TABLE public.rewards_history
  ALTER COLUMN points_earned TYPE numeric(12,2) USING points_earned::numeric(12,2),
  ALTER COLUMN order_amount TYPE numeric(12,2) USING order_amount::numeric(12,2),
  ADD COLUMN IF NOT EXISTS points_redeemed numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS entry_type varchar(16) NOT NULL DEFAULT 'earned',
  ADD COLUMN IF NOT EXISTS status varchar(16) NOT NULL DEFAULT 'credited',
  ADD COLUMN IF NOT EXISTS note varchar(255) NULL,
  ADD COLUMN IF NOT EXISTS decided_at timestamp without time zone NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rewards_history_entry_type_check') THEN
    ALTER TABLE public.rewards_history ADD CONSTRAINT rewards_history_entry_type_check
      CHECK (entry_type IN ('earned', 'reversed', 'reinstated', 'redeemed'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rewards_history_status_check') THEN
    ALTER TABLE public.rewards_history ADD CONSTRAINT rewards_history_status_check
      CHECK (status IN ('credited', 'reversed', 'pending', 'approved', 'rejected'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rewards_history_redeemed_check') THEN
    ALTER TABLE public.rewards_history ADD CONSTRAINT rewards_history_redeemed_check
      CHECK (points_redeemed >= 0 AND (entry_type <> 'redeemed' OR (points_redeemed > 0 AND points_earned = 0)));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS ux_rewards_history_order_earned
  ON public.rewards_history (order_id) WHERE entry_type = 'earned';
CREATE INDEX IF NOT EXISTS idx_rewards_history_pending_claims
  ON public.rewards_history (created_at) WHERE entry_type = 'redeemed' AND status = 'pending';

-- Dealers who read their own ledger directly (Supabase path, still behind a
-- disabled feature flag) may see the new columns too.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    GRANT SELECT (points_redeemed, entry_type, status, note, decided_at)
      ON public.rewards_history TO authenticated;
  END IF;
END $$;

-- Postflight: every balance still equals its ledger.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.users u
     WHERE u.reward_points <> COALESCE((
       SELECT SUM(r.points_earned) - SUM(CASE WHEN r.status IN ('pending', 'approved') THEN r.points_redeemed ELSE 0 END)
         FROM public.rewards_history r WHERE r.user_id = u.id), 0)
  ) THEN
    RAISE EXCEPTION 'A reward balance does not match its ledger; migration rolled back.';
  END IF;
END $$;

COMMIT;
