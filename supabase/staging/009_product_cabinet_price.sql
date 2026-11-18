-- Additive: a dedicated Cabinet Price for products in the Cabinet category.
--
-- Why: the Admin Add/Edit Product form asks for "Cabinet Price (₹)" when the
-- category is Cabinet. It is stored on its own and never replaces the Dealer
-- Price, Purchase Price or MRP.
--
-- Adds one nullable column. No existing row is changed (every product starts
-- with NULL = no Cabinet Price). Take a database backup first
-- (node scripts/backup_database.cjs).
-- Do not run on production until it has been reviewed and approved.
-- Rollback: ALTER TABLE public.products DROP COLUMN cabinet_price;

BEGIN;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS cabinet_price numeric(10,2) NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'products_cabinet_price_positive') THEN
    ALTER TABLE public.products
      ADD CONSTRAINT products_cabinet_price_positive CHECK (cabinet_price IS NULL OR cabinet_price > 0);
  END IF;
END $$;

COMMIT;
