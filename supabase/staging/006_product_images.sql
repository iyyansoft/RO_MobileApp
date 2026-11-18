-- Additive: shared storage for admin-uploaded product images.
--
-- Why: server.js saved product images to its own uploads folder, which only
-- exists on the machine that received the upload (an image added through the
-- local admin is missing on Render, and Render's disk is reset on deploy).
-- With this table and PRODUCT_IMAGE_STORE=database, every server stores and
-- serves the same image from /api/product-images/<id>.
--
-- Creates one new table only. No existing table or row is changed.
-- Do not run on production until it has been reviewed and approved.
-- Rollback: DROP TABLE public.product_images;  (then unset PRODUCT_IMAGE_STORE)

BEGIN;

CREATE TABLE IF NOT EXISTS public.product_images (
  id           text PRIMARY KEY,
  content_type text NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp')),
  bytes        bytea NOT NULL CHECK (octet_length(bytes) BETWEEN 1 AND 5242880),
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Only the backend (database owner) reads and writes this table. Images are
-- served publicly through the API, never directly from PostgREST.
ALTER TABLE public.product_images ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.product_images FROM PUBLIC;
DO $$
BEGIN
  -- Supabase API roles (absent in plain PostgreSQL test databases).
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON TABLE public.product_images FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'REVOKE ALL ON TABLE public.product_images FROM authenticated';
  END IF;
END $$;

COMMIT;
