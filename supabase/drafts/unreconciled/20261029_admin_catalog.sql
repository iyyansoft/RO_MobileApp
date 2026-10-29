-- Local draft only. Privileged product/category mutations are exposed through
-- the admin-catalog Edge Function, never direct browser table writes.
-- Review against the live schema and apply only after explicit approval.
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.products') IS NULL OR to_regclass('public.categories') IS NULL OR
     to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'Admin catalog draft requires existing products/categories and Supabase Auth';
  END IF;
END $$;

-- Preserve public category/catalog reads while keeping all mutations server-only.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.products, public.categories FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.ro_admin_create_category(
  p_admin_user_id uuid, p_id varchar, p_values jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE v_title text; v_key text; v_category public.categories%ROWTYPE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users
    WHERE id=p_admin_user_id AND email_confirmed_at IS NOT NULL
      AND coalesce(raw_app_meta_data->>'role','')='admin') THEN
    RAISE EXCEPTION 'Verified administrator required' USING ERRCODE='42501';
  END IF;
  IF coalesce(p_id,'')='' OR jsonb_typeof(p_values)<>'object' THEN RAISE EXCEPTION 'Category details are invalid'; END IF;
  v_title := btrim(coalesce(p_values->>'title',''));
  v_key := lower(btrim(coalesce(p_values->>'key_name','')));
  IF v_title='' OR char_length(v_title)>128 OR v_key !~ '^[a-z0-9][a-z0-9_-]{0,63}$' THEN
    RAISE EXCEPTION 'Category title or key is invalid';
  END IF;
  -- Serialize title/key checks even when older schema lacks a case-insensitive
  -- title index; the existing lower(key_name) unique index remains authoritative.
  PERFORM pg_advisory_xact_lock(hashtextextended('ro-admin-categories',0));
  IF EXISTS (SELECT 1 FROM public.categories
    WHERE lower(key_name)=v_key OR lower(title)=lower(v_title)) THEN
    RAISE EXCEPTION 'Category key or name already exists' USING ERRCODE='23505';
  END IF;
  INSERT INTO public.categories(id,key_name,title,description,badge_text,icon_color,image_url,display_order)
  VALUES(p_id,v_key,v_title,coalesce(p_values->>'description',''),
    coalesce(p_values->>'badge_text','⚡ B2B WHOLESALE'),coalesce(p_values->>'icon_color','#0F62FE'),
    nullif(p_values->>'image_url',''),coalesce((p_values->>'display_order')::integer,1))
  RETURNING * INTO v_category;
  RETURN to_jsonb(v_category);
END;
$$;

CREATE OR REPLACE FUNCTION public.ro_admin_update_category(
  p_admin_user_id uuid, p_category_id varchar, p_values jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_category public.categories%ROWTYPE;
  v_old_key text;
  v_title text;
  v_key text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users
    WHERE id=p_admin_user_id AND email_confirmed_at IS NOT NULL
      AND coalesce(raw_app_meta_data->>'role','')='admin') THEN
    RAISE EXCEPTION 'Verified administrator required' USING ERRCODE='42501';
  END IF;
  IF jsonb_typeof(p_values)<>'object' THEN RAISE EXCEPTION 'Category details are invalid'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('ro-admin-categories',0));
  SELECT * INTO v_category FROM public.categories WHERE id=p_category_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Category not found' USING ERRCODE='P0002'; END IF;
  v_old_key := v_category.key_name;
  v_title := btrim(coalesce(p_values->>'title',''));
  v_key := lower(btrim(coalesce(p_values->>'key_name','')));
  IF v_title='' OR char_length(v_title)>128 OR v_key !~ '^[a-z0-9][a-z0-9_-]{0,63}$' THEN
    RAISE EXCEPTION 'Category title or key is invalid';
  END IF;
  IF EXISTS (SELECT 1 FROM public.categories WHERE id<>v_category.id
    AND (lower(key_name)=v_key OR lower(title)=lower(v_title))) THEN
    RAISE EXCEPTION 'Category key or name already exists' USING ERRCODE='23505';
  END IF;
  UPDATE public.categories SET title=v_title,key_name=v_key,
    description=coalesce(p_values->>'description',''),
    badge_text=coalesce(p_values->>'badge_text','⚡ B2B WHOLESALE'),
    icon_color=coalesce(p_values->>'icon_color','#0F62FE'),
    image_url=nullif(p_values->>'image_url',''),
    display_order=coalesce((p_values->>'display_order')::integer,display_order)
  WHERE id=v_category.id RETURNING * INTO v_category;
  UPDATE public.products SET category_key=v_category.key_name
    WHERE category_id=v_category.id OR category_key=v_old_key;
  RETURN to_jsonb(v_category);
END;
$$;

CREATE OR REPLACE FUNCTION public.ro_admin_delete_category(
  p_admin_user_id uuid, p_category_id varchar
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_category public.categories%ROWTYPE;
  v_fallback public.categories%ROWTYPE;
  v_count integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users
    WHERE id=p_admin_user_id AND email_confirmed_at IS NOT NULL
      AND coalesce(raw_app_meta_data->>'role','')='admin') THEN
    RAISE EXCEPTION 'Verified administrator required' USING ERRCODE='42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('ro-admin-categories',0));
  SELECT * INTO v_category FROM public.categories WHERE id=p_category_id FOR UPDATE;
  IF NOT FOUND THEN
    SELECT * INTO v_category FROM public.categories WHERE key_name=p_category_id FOR UPDATE;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Category not found' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_fallback FROM public.categories WHERE lower(key_name)='spares' FOR UPDATE;
  IF NOT FOUND OR v_fallback.id=v_category.id THEN
    RAISE EXCEPTION 'A different Spares fallback category is required before deletion';
  END IF;
  UPDATE public.products SET category_id=v_fallback.id,category_key=v_fallback.key_name
    WHERE category_id=v_category.id OR category_key=v_category.key_name;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  DELETE FROM public.categories WHERE id=v_category.id;
  RETURN jsonb_build_object('message',format('Category deleted. (%s associated product(s) safely moved to Spares).',v_count),
    'reassignedCount',v_count,'categoryId',v_category.id);
END;
$$;

REVOKE ALL ON FUNCTION public.ro_admin_create_category(uuid, varchar, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ro_admin_update_category(uuid, varchar, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ro_admin_delete_category(uuid, varchar) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ro_admin_create_category(uuid, varchar, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.ro_admin_update_category(uuid, varchar, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.ro_admin_delete_category(uuid, varchar) TO service_role;

COMMIT;
