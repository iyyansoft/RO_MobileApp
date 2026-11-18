-- Additive: the order -> shop assignment table (same definition as in
-- shop_app_migration.sql, which was only partly applied to the live database:
-- the other four Shop App tables exist, this one does not).
--
-- Why: without it no order can be assigned to a shop. With one active shop the
-- Shop App falls back to showing every order; with two or more shops checkout
-- and Current Orders stop working.
--
-- Creates one table and one index. No existing row is changed.
-- Rollback: DROP TABLE public.shop_order_assignments;

BEGIN;

CREATE TABLE IF NOT EXISTS public.shop_order_assignments (
  order_id varchar(64) PRIMARY KEY REFERENCES public.orders(order_id) ON DELETE CASCADE,
  shop_name varchar(191) NOT NULL,
  assigned_by uuid REFERENCES public.shop_employees(id) ON DELETE SET NULL,
  assigned_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_shop_order_assignments_shop
  ON public.shop_order_assignments (lower(shop_name), assigned_at DESC);
-- No browser/mobile direct policies: all access goes through the server API.
ALTER TABLE public.shop_order_assignments ENABLE ROW LEVEL SECURITY;

COMMIT;
