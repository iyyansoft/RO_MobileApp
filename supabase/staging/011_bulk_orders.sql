-- Bulk Orders: a second purchase mode on the same product records.
--
-- What changes (additive; no existing value is modified):
--   products     bulk_price (per piece), bulk_min_qty, bulk_step, bulk_pack_label.
--                All NULL = the product is not offered in Bulk Orders.
--                Dealer Price (price), MRP and Cabinet Price are untouched.
--   cart_items   purchase_mode 'normal' | 'bulk' (existing rows: 'normal').
--                Still one line per (dealer, product): a product is in the
--                cart either normally or in bulk; the server refuses mixing
--                (never converts one into the other).
--   order_items  purchase_mode (existing rows: 'normal') and bulk_pack_label,
--                so orders and invoices show which lines were bulk.
--
-- Bulk prices are filled separately from the supplier PDFs
-- (scripts/extract_bulk_pricing.cjs), only after review and approval.
-- Take a database backup first (node scripts/backup_database.cjs).
-- Do not run on production until it has been reviewed and approved.
--
-- Rollback (only while no bulk cart lines / bulk orders exist):
--   ALTER TABLE public.order_items DROP COLUMN purchase_mode, DROP COLUMN bulk_pack_label;
--   ALTER TABLE public.cart_items DROP COLUMN purchase_mode;
--   ALTER TABLE public.products DROP COLUMN bulk_price, DROP COLUMN bulk_min_qty,
--     DROP COLUMN bulk_step, DROP COLUMN bulk_pack_label;

BEGIN;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS bulk_price numeric(10,2) NULL,
  ADD COLUMN IF NOT EXISTS bulk_min_qty integer NULL,
  ADD COLUMN IF NOT EXISTS bulk_step integer NULL,
  ADD COLUMN IF NOT EXISTS bulk_pack_label varchar(32) NULL;

ALTER TABLE public.cart_items
  ADD COLUMN IF NOT EXISTS purchase_mode varchar(8) NOT NULL DEFAULT 'normal';

ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS purchase_mode varchar(8) NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS bulk_pack_label varchar(32) NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'products_bulk_pricing_check') THEN
    -- All four set (a valid bulk offer) or all NULL; quantities are whole
    -- steps from the minimum.
    ALTER TABLE public.products ADD CONSTRAINT products_bulk_pricing_check CHECK (
      (bulk_price IS NULL AND bulk_min_qty IS NULL AND bulk_step IS NULL AND bulk_pack_label IS NULL)
      OR (bulk_price > 0 AND bulk_min_qty >= 1 AND bulk_step >= 1 AND bulk_min_qty % bulk_step = 0
          AND bulk_pack_label IS NOT NULL)
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'cart_items_purchase_mode_check') THEN
    ALTER TABLE public.cart_items ADD CONSTRAINT cart_items_purchase_mode_check
      CHECK (purchase_mode IN ('normal', 'bulk'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'order_items_purchase_mode_check') THEN
    ALTER TABLE public.order_items ADD CONSTRAINT order_items_purchase_mode_check
      CHECK (purchase_mode IN ('normal', 'bulk'));
  END IF;
END $$;

COMMIT;
