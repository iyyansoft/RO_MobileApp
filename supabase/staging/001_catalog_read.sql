-- Local-only staging migration: public, read-only catalog access for the existing live
-- Supabase products/categories tables. Do not execute against production.
--
-- This is deliberately outside supabase/migrations because the older pending
-- migrations have not yet been reconciled to the audited live schema (notably
-- shop_order_assignments is absent). This file is a one-time staging migration;
-- do not replay it or put it in the production CLI migration chain without review.
-- Project-target identity is not encoded here; independently verify staging
-- before execution. This SQL alone cannot prove which Supabase project it reaches.
--
-- Scope: anon/authenticated can read active products and categories only.
-- Purchase cost, admin writes, shop data, and all other business tables are
-- outside this migration. Express remains the active fallback.
BEGIN;

DO $$
DECLARE
  v_missing text[];
  v_version integer;
BEGIN
  IF to_regclass('public.products') IS NULL OR to_regclass('public.categories') IS NULL THEN
    RAISE EXCEPTION 'Existing public products and categories tables are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') OR
     NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    RAISE EXCEPTION 'Supabase anon/authenticated roles are required';
  END IF;

  v_version := current_setting('server_version_num')::integer;
  IF v_version < 150000 THEN
    RAISE EXCEPTION 'Catalog migration requires PostgreSQL 15+ security-invoker views';
  END IF;

  SELECT array_agg(required.column_name ORDER BY required.column_name)
    INTO v_missing
  FROM (VALUES
    ('products','id'), ('products','category_id'), ('products','category_key'),
    ('products','sku'), ('products','name'), ('products','brand'),
    ('products','price'), ('products','mrp'), ('products','moq'),
    ('products','badge'), ('products','rating'), ('products','img'),
    ('products','description'), ('products','specs_json'),
    ('products','features_json'), ('products','applications'),
    ('products','stock_quantity'),
    ('products','status'), ('products','created_at'),
    ('categories','id'), ('categories','key_name'), ('categories','title'),
    ('categories','description'), ('categories','badge_text'),
    ('categories','icon_color'), ('categories','image_url'),
    ('categories','display_order')
  ) AS required(table_name, column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns AS c
    WHERE c.table_schema = 'public'
      AND c.table_name = required.table_name
      AND c.column_name = required.column_name
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Existing catalog schema is incompatible; missing columns: %',
      array_to_string(v_missing, ', ');
  END IF;

  -- Permissive policies are ORed together. Fail closed on any unreviewed rule;
  -- existing matching policies are accepted so this draft can be replayed.
  IF EXISTS (
    SELECT 1 FROM pg_policies AS p
    WHERE p.schemaname = 'public' AND p.tablename IN ('products','categories')
      AND NOT (
        (p.tablename = 'products' AND p.policyname = 'ro_products_active_read'
          AND p.cmd = 'SELECT' AND p.permissive = 'PERMISSIVE'
          AND cardinality(p.roles) = 2
          AND p.roles @> ARRAY['anon','authenticated']::name[]
          AND replace(replace(replace(coalesce(p.qual,''), '::character varying',''), '::text',''), ' ','')
              = '(status<>''inactive'')'
          AND p.with_check IS NULL)
        OR
        (p.tablename = 'categories' AND p.policyname = 'ro_categories_read'
          AND p.cmd = 'SELECT' AND p.permissive = 'PERMISSIVE'
          AND cardinality(p.roles) = 2
          AND p.roles @> ARRAY['anon','authenticated']::name[]
          AND p.qual = 'true' AND p.with_check IS NULL)
      )
  ) THEN
    RAISE EXCEPTION 'Unreviewed or incompatible catalog RLS policy exists; reconcile it before continuing';
  END IF;
END;
$$;

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

-- Remove the audited broad table grants. Re-grant only the public catalog
-- columns; purchase_price remains inaccessible to client roles.
REVOKE ALL PRIVILEGES ON TABLE public.products, public.categories
  FROM PUBLIC, anon, authenticated;
DO $$
DECLARE
  v_table text;
  v_columns text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['products','categories'] LOOP
    SELECT string_agg(format('%I', column_name), ', ' ORDER BY ordinal_position)
      INTO v_columns
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = v_table;
    IF v_columns IS NOT NULL THEN
      EXECUTE format(
        'REVOKE ALL PRIVILEGES (%s) ON TABLE public.%I FROM PUBLIC, anon, authenticated',
        v_columns, v_table
      );
    END IF;
  END LOOP;
END;
$$;
GRANT SELECT (
  id, category_id, category_key, sku, name, brand, price, mrp, moq, badge,
  rating, img, description, specs_json, features_json, applications,
  stock_quantity, status, created_at
) ON TABLE public.products TO anon, authenticated;
GRANT SELECT (
  id, key_name, title, description, badge_text, icon_color, image_url,
  display_order
) ON TABLE public.categories TO anon, authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='products'
      AND policyname='ro_products_active_read'
  ) THEN
    CREATE POLICY ro_products_active_read ON public.products
      FOR SELECT TO anon, authenticated USING (status <> 'inactive');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='categories'
      AND policyname='ro_categories_read'
  ) THEN
    CREATE POLICY ro_categories_read ON public.categories
      FOR SELECT TO anon, authenticated USING (true);
  END IF;
END;
$$;

-- security_invoker keeps both the product and category RLS policies in force.
-- This view is the only product projection used by the opt-in dealer client.
CREATE OR REPLACE VIEW public.catalog_products
WITH (security_invoker = true)
AS
SELECT p.id, p.category_id, p.category_key, c.title AS category_name,
       p.sku, p.name, p.brand, p.price, p.price AS dealer_price, p.mrp,
       p.moq, p.badge, p.rating, p.img, p.description,
       p.description AS "desc", p.specs_json AS specs,
       p.features_json AS features, p.applications, p.stock_quantity,
       p.status, p.created_at
FROM public.products AS p
LEFT JOIN public.categories AS c ON c.id = p.category_id
WHERE p.status <> 'inactive';

REVOKE ALL PRIVILEGES ON TABLE public.catalog_products
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.catalog_products TO anon, authenticated;

-- DDL may be applied over a direct PostgreSQL connection; explicitly refresh
-- PostgREST's schema cache so the newly-created view is immediately routable.
NOTIFY pgrst, 'reload schema';

COMMIT;
