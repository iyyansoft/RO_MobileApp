-- RO Wholesale Dealer App: MySQL-to-Supabase PostgreSQL schema
-- Generated from schema.sql, db.js runtime ALTER statements, and the tables
-- and columns referenced by server.js, order_checkout.js, and the JSON importer.
--
-- This creates schema only. It does not copy data, create users/roles, or
-- change MySQL. It enables Row Level Security with no client policies, so
-- anon/authenticated API roles have no table access until deliberate policies
-- are added. Run only in a new, empty Supabase project: IF NOT EXISTS does not
-- reconcile columns or constraints on tables that already exist.
-- Keep any service-role key or database owner credential on the server only.
-- Do not expose either credential in Flutter or browser code. If the backend
-- uses a non-owner database role, grant only required privileges and add
-- policies for that role before connecting the application.

BEGIN;

-- Keep email comparisons case-insensitive, like the source MySQL collation.
-- The length checks below retain each MySQL VARCHAR(191) limit.
-- citext does not reproduce every locale/accent rule of utf8mb4_unicode_ci;
-- audit non-ASCII email values before importing them.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA extensions;

-- MySQL DATETIME ON UPDATE CURRENT_TIMESTAMP behavior used by users and cart_items.
CREATE OR REPLACE FUNCTION public.ro_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS public.users (
  id varchar(64) PRIMARY KEY,
  email extensions.citext NOT NULL CHECK (char_length(email) <= 191),
  mobile varchar(20),
  name varchar(128) NOT NULL,
  password_hash varchar(255) NOT NULL,
  email_verified boolean NOT NULL DEFAULT true,
  gst_number varchar(15),
  business_name varchar(191),
  owner_name varchar(128),
  address text,
  status varchar(16) NOT NULL DEFAULT 'approved'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  is_approved boolean NOT NULL DEFAULT true,
  reward_points integer NOT NULL DEFAULT 0,
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
-- citext preserves case-insensitive email uniqueness and lookup behavior.
CREATE UNIQUE INDEX IF NOT EXISTS uk_users_email ON public.users (email);
CREATE UNIQUE INDEX IF NOT EXISTS uk_users_mobile ON public.users (mobile);
CREATE INDEX IF NOT EXISTS idx_users_status ON public.users (status);

CREATE TABLE IF NOT EXISTS public.user_addresses (
  id varchar(64) PRIMARY KEY,
  user_id varchar(64) NOT NULL,
  label varchar(64) NOT NULL DEFAULT 'Main Warehouse',
  business_name varchar(191),
  street text NOT NULL,
  city varchar(100) NOT NULL,
  state varchar(100) NOT NULL,
  pincode varchar(20) NOT NULL,
  phone varchar(20),
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  full_name varchar(191),
  door_no varchar(64),
  area varchar(191),
  district varchar(100),
  landmark varchar(191),
  address_type varchar(64) DEFAULT 'Office',
  gst_number varchar(64),
  CONSTRAINT fk_addresses_users FOREIGN KEY (user_id)
    REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_addresses_user_id ON public.user_addresses (user_id);

CREATE TABLE IF NOT EXISTS public.categories (
  id varchar(64) PRIMARY KEY,
  key_name varchar(64) NOT NULL,
  title varchar(128) NOT NULL,
  description text,
  badge_text varchar(64),
  icon_color varchar(32),
  image_url varchar(255),
  display_order integer NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS uk_categories_key ON public.categories (lower(key_name));

CREATE TABLE IF NOT EXISTS public.products (
  id varchar(64) PRIMARY KEY,
  category_id varchar(64),
  category_key varchar(64) NOT NULL,
  sku varchar(64) NOT NULL,
  name varchar(512) NOT NULL,
  brand varchar(255) NOT NULL,
  purchase_price numeric(10,2) NOT NULL DEFAULT 0.00,
  price numeric(10,2) NOT NULL,
  mrp numeric(10,2) NOT NULL,
  moq varchar(64),
  badge varchar(64),
  rating varchar(64),
  img text,
  description text,
  -- PostgreSQL json preserves the source JSON text representation more
  -- closely than jsonb, which normalizes object representation.
  specs_json json,
  features_json json,
  applications text,
  stock_quantity integer NOT NULL DEFAULT 50,
  min_stock integer NOT NULL DEFAULT 10,
  status varchar(32) NOT NULL DEFAULT 'active',
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_products_categories FOREIGN KEY (category_id)
    REFERENCES public.categories(id) ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS uk_products_sku ON public.products (lower(sku));
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products (category_key);
-- InnoDB creates an index for this FK when no suitable leading index exists.
CREATE INDEX IF NOT EXISTS idx_products_category_id ON public.products (category_id);

CREATE TABLE IF NOT EXISTS public.orders (
  order_id varchar(64) PRIMARY KEY,
  user_id varchar(64),
  user_email extensions.citext NOT NULL CHECK (char_length(user_email) <= 191),
  user_name varchar(128) NOT NULL,
  user_business varchar(191),
  subtotal numeric(10,2) NOT NULL DEFAULT 0.00,
  discount numeric(10,2) NOT NULL DEFAULT 0.00,
  gst numeric(10,2) NOT NULL DEFAULT 0.00,
  delivery_fee numeric(10,2) NOT NULL DEFAULT 0.00,
  grand_total numeric(10,2) NOT NULL DEFAULT 0.00,
  with_gst boolean NOT NULL DEFAULT true,
  payment_status varchar(32) NOT NULL DEFAULT 'pending',
  razorpay_payment_id varchar(100),
  payment_method varchar(100) NOT NULL DEFAULT 'UPI Direct QR Transfer',
  billing_address text,
  company_name varchar(191),
  gstin varchar(64),
  pan_number varchar(64),
  same_as_delivery boolean NOT NULL DEFAULT true,
  delivery_address text NOT NULL,
  delivery_note text,
  status varchar(100) NOT NULL DEFAULT 'Processing & Dispatched',
  invoice_number varchar(64) NOT NULL,
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uk_orders_invoice UNIQUE (invoice_number),
  CONSTRAINT fk_orders_users FOREIGN KEY (user_id)
    REFERENCES public.users(id) ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON public.orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_user_email ON public.orders (user_email);

CREATE TABLE IF NOT EXISTS public.order_items (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  order_id varchar(64) NOT NULL,
  product_id varchar(64),
  product_name varchar(512) NOT NULL,
  brand varchar(255),
  unit_price numeric(10,2) NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  moq varchar(64),
  img_src text,
  sku varchar(64),
  CONSTRAINT fk_order_items_orders FOREIGN KEY (order_id)
    REFERENCES public.orders(order_id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON public.order_items (order_id);

CREATE TABLE IF NOT EXISTS public.rewards_history (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  user_id varchar(64) NOT NULL,
  order_id varchar(64),
  order_amount numeric(10,2) NOT NULL,
  points_earned integer NOT NULL,
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_rewards_users FOREIGN KEY (user_id)
    REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_rewards_orders FOREIGN KEY (order_id)
    REFERENCES public.orders(order_id) ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_rewards_user_id ON public.rewards_history (user_id);
-- MySQL/InnoDB supplies an index for the order_id foreign key.
CREATE INDEX IF NOT EXISTS idx_rewards_history_order_id ON public.rewards_history (order_id);

CREATE TABLE IF NOT EXISTS public.otp_codes (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  email extensions.citext NOT NULL CHECK (char_length(email) <= 191),
  otp_code varchar(64) NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  expires_at timestamp without time zone NOT NULL,
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_otp_email_expires ON public.otp_codes (email, expires_at);

CREATE TABLE IF NOT EXISTS public.support_tickets (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  user_id varchar(64),
  user_email extensions.citext NOT NULL CHECK (char_length(user_email) <= 191),
  subject varchar(255) NOT NULL,
  message text NOT NULL,
  status varchar(50) NOT NULL DEFAULT 'Open',
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_tickets_users FOREIGN KEY (user_id)
    REFERENCES public.users(id) ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_tickets_user_email ON public.support_tickets (user_email);
-- MySQL/InnoDB supplies an index for the user_id foreign key.
CREATE INDEX IF NOT EXISTS idx_support_tickets_user_id ON public.support_tickets (user_id);

CREATE TABLE IF NOT EXISTS public.cart_items (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  user_id varchar(64) NOT NULL,
  product_id varchar(64) NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uk_user_product UNIQUE (user_id, product_id),
  CONSTRAINT fk_cart_users FOREIGN KEY (user_id)
    REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_cart_products FOREIGN KEY (product_id)
    REFERENCES public.products(id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_cart_user_id ON public.cart_items (user_id);
-- The unique index starts with user_id and cannot support product_id FK lookups.
CREATE INDEX IF NOT EXISTS idx_cart_items_product_id ON public.cart_items (product_id);

CREATE TABLE IF NOT EXISTS public.payment_sessions (
  id varchar(100) PRIMARY KEY,
  user_email extensions.citext NOT NULL CHECK (char_length(user_email) <= 191),
  amount bigint NOT NULL,
  payload_json text NOT NULL,
  payment_id varchar(100) UNIQUE,
  local_order_id varchar(100),
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Safe default for Supabase's exposed public schema: no anon/authenticated
-- policies are created here, so those roles cannot read or write these tables.
-- Add narrowly scoped policies only after the backend authentication model is
-- designed. A server-side Supabase service-role client bypasses RLS; keep its
-- key exclusively on the backend.
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rewards_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_sessions ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trg_users_updated_at ON public.users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION public.ro_set_updated_at();

DROP TRIGGER IF EXISTS trg_cart_items_updated_at ON public.cart_items;
CREATE TRIGGER trg_cart_items_updated_at
BEFORE UPDATE ON public.cart_items
FOR EACH ROW EXECUTE FUNCTION public.ro_set_updated_at();

COMMIT;

