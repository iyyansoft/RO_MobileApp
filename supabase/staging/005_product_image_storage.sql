-- Staging-only, additive provision for the product/category image bucket.
-- This does not copy existing images, change product URLs, or grant client
-- write access. The admin-catalog Edge Function uploads with its server-only
-- service-role client; the public bucket is read-only by URL.
--
-- Stop if a bucket with this ID already exists with incompatible settings.
-- Do not run on production until this exact operation has been reviewed and
-- explicitly approved.

BEGIN;

DO $$
DECLARE
  v_bucket storage.buckets%ROWTYPE;
  v_expected_mime_types text[] := ARRAY['image/jpeg', 'image/png', 'image/webp']::text[];
  v_existing_mime_types text[];
  v_expected_sorted text[];
BEGIN
  SELECT *
  INTO v_bucket
  FROM storage.buckets
  WHERE id = 'ro-product-images'
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO storage.buckets (
      id,
      name,
      public,
      file_size_limit,
      allowed_mime_types
    ) VALUES (
      'ro-product-images',
      'ro-product-images',
      TRUE,
      5242880,
      v_expected_mime_types
    )
    ON CONFLICT (id) DO NOTHING;

    SELECT *
    INTO v_bucket
    FROM storage.buckets
    WHERE id = 'ro-product-images'
    FOR UPDATE;
  END IF;

  SELECT array_agg(mime_type ORDER BY mime_type)
  INTO v_existing_mime_types
  FROM unnest(v_bucket.allowed_mime_types) AS allowed(mime_type);

  SELECT array_agg(mime_type ORDER BY mime_type)
  INTO v_expected_sorted
  FROM unnest(v_expected_mime_types) AS expected(mime_type);

  IF v_bucket.id IS NULL
    OR v_bucket.name IS DISTINCT FROM 'ro-product-images'
    OR v_bucket.public IS DISTINCT FROM TRUE
    OR v_bucket.file_size_limit IS DISTINCT FROM 5242880
    OR v_existing_mime_types IS DISTINCT FROM v_expected_sorted
  THEN
    RAISE EXCEPTION 'Existing ro-product-images bucket configuration is incompatible; inspect it before continuing';
  END IF;
END;
$$;

COMMIT;
