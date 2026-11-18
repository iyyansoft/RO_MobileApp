-- Additive: stock ledger + "stock never negative" guard.
--
-- Why: placing an order never reduced products.stock_quantity, so the same
-- units could be sold repeatedly. Every stock change made by an order is now
-- recorded here, so it can be reversed exactly once (cancellation / short
-- supply) and never for orders placed before this table existed (their stock
-- was never taken, so returning it would inflate stock).
--
-- Creates one table and one CHECK constraint. No existing row is changed.
-- The constraint is NOT VALID: it applies to every future change without
-- scanning or rejecting existing rows.
-- Rollback: ALTER TABLE public.products DROP CONSTRAINT IF EXISTS ck_products_stock_nonnegative;
--           DROP TABLE public.stock_movements;

BEGIN;

CREATE TABLE IF NOT EXISTS public.stock_movements (
  id              bigserial PRIMARY KEY,
  product_id      varchar(64) NOT NULL,
  order_id        varchar(64) REFERENCES public.orders(order_id) ON DELETE CASCADE,
  order_item_id   bigint,
  quantity_change integer NOT NULL CHECK (quantity_change <> 0),
  reason          varchar(32) NOT NULL
                  CHECK (reason IN ('order_placed', 'order_cancelled', 'order_reopened')),
  stock_after     integer,
  created_at      timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_stock_movements_order ON public.stock_movements (order_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON public.stock_movements (product_id, created_at DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ck_products_stock_nonnegative' AND conrelid = 'public.products'::regclass
  ) THEN
    ALTER TABLE public.products
      ADD CONSTRAINT ck_products_stock_nonnegative CHECK (stock_quantity >= 0) NOT VALID;
  END IF;
END $$;

-- Backend-only table (same policy as the other server tables).
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.stock_movements FROM PUBLIC;
DO $$
BEGIN
  -- Supabase API roles (absent in plain PostgreSQL test databases).
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON TABLE public.stock_movements FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'REVOKE ALL ON TABLE public.stock_movements FROM authenticated';
  END IF;
END $$;

COMMIT;
