# Supabase Read-Only Audit

**Project:** `czegmfzntnfpwaxgczds`  
**Audit date:** 2026-10-28  
**Scope:** Read-only live schema, grants, RLS, Storage and Edge Function inventory, compared with local migration drafts.

## Safety and verification scope

PostgreSQL catalog inspection was performed in a read-only transaction and rolled back. The Supabase CLI function inventory was also read-only. No migration SQL was executed; no data or schema was modified; no functions were deployed; no feature flags were enabled; and no APK was built. The audit did not inspect or report personal record contents, credentials, tokens, or password hashes.

## Live project findings

- PostgreSQL version: 17.11.
- The `public` schema contains 15 tables: `cart_items`, `categories`, `order_items`, `orders`, `otp_codes`, `payment_sessions`, `products`, `rewards_history`, `shop_admin_notifications`, `shop_delivery_items`, `shop_employees`, `shop_product_enquiries`, `support_tickets`, `user_addresses`, and `users`.
- Some of these tables contain data. This is a data-bearing project, not an empty migration target.
- RLS is enabled on all 15 public tables. No public-table RLS policies were found. `FORCE ROW LEVEL SECURITY` is disabled on these tables.
- The `storage.objects` relation has RLS enabled, no policies, and FORCE disabled. No Storage buckets were found.
- No views were found in `public`. The only public function found was `ro_set_updated_at()`.
- The Supabase CLI reported no deployed Edge Functions.
- Existing primary/foreign keys, unique/check constraints, and indexes were inventoried. The cart has a unique `(user_id, product_id)` index. Identity columns use `BY DEFAULT` identity generation with owned sequences.
- Effective grants are broad: `anon`, `authenticated`, and `service_role` have table-level privileges across the public tables. Client roles also have grants on sensitive columns, including purchase-price, password-hash, OTP, payment, and status fields. RLS currently has no policies, which normally denies API-role row access, but the broad grants must be corrected as policies are introduced. Table owners and privileged/BYPASSRLS roles require separate handling.

## Fresh read-only recheck (2026-10-28)

- The guarded database audit connected and confirmed that the configured database belongs to project `czegmfzntnfpwaxgczds`. Catalog queries ran inside `BEGIN READ ONLY` and were rolled back.
- The same 15 public tables were found. RLS is enabled on each; no public or Storage policies were found. `storage.objects` has RLS enabled, and the Storage bucket list is empty.
- Existence-only checks found rows in 11 tables: `cart_items`, `categories`, `order_items`, `orders`, `products`, `rewards_history`, `shop_admin_notifications`, `shop_delivery_items`, `shop_employees`, `user_addresses`, and `users`. The other four tables had no rows. No record contents, identifiers, emails, or password hashes were selected.
- Read-only `GET /auth/v1/settings` returned HTTP 200 for the verified existing project. Signup is enabled, email auto-confirm is disabled (email confirmation is required), and email is the only enabled external provider. This does not verify SMTP delivery or OTP arrival.
- The direct Supabase CLI executable is unavailable. A read-only `npx supabase functions list` attempt did not return before interruption, so deployed Edge Function status is not freshly verified; the earlier CLI inventory reported none.
- No migration, data write, Storage configuration, Auth setting, deployment, or feature-flag operation was issued.

## Notable schema differences and migration dependencies

- `users.auth_user_id` is absent; the identity-linking stage must add and constrain it only after a verified account-linking design is ready.
- `shop_order_assignments` is absent. Checkout/shop drafts that reference it cannot be applied as-is.
- `shop_delivery_items.delivery_confirmed` is absent; the shop delivery draft depends on this field or an explicitly reconciled alternative.
- The live core monetary columns inspected use `numeric(10,2)`. The staging plan’s description of unbounded numeric monetary fields is inconsistent and should be reconciled against exact live columns before migration.
- The catalog view drafts disagree on `security_invoker`; choose and test one safe definition before creating the view.
- Staging migration 004 includes an email-based fallback for legacy records. It must be proven to enforce verified ownership or removed before exposure through RLS/RPC.
- The product image draft expects a Storage bucket, but no bucket currently exists and existing local/external image references have not been migrated.
- `supabase/migrations` has no runnable versioned migrations. Drafts are under `supabase/staging` and `supabase/drafts/unreconciled`.
- Root `supabase_migration.sql` is a fresh-schema baseline, not a safe upgrade for this populated project. `supabase_data_import.sql` has empty-table guards and must not be used against the current data-bearing project.
- The endpoint inventory still classifies the 66 Express routes as Express-backed. Local drafts/pilots are not deployed or verified replacements.

## Prioritized migration blockers

1. **Privilege and RLS design:** No policies exist, while table and sensitive-column grants are broad. Define least-privilege grants and dealer/admin policies, then test both allowed access and cross-dealer denial with real JWT roles before enabling any client path.
2. **Safe rollout target:** Only the existing project is authorized. It contains live data and must never be used for synthetic write tests. Use the disposable local Supabase stack for integration tests; request explicit approval with exact SQL/impact before any production migration.
3. **Identity linking and dealer approval:** `users.auth_user_id` is missing. A verified ownership/linking process and pending/unapproved dealer enforcement are required; email OTP delivery is not configured, so email-dependent tests are blocked.
4. **Shop/order schema gap:** `shop_order_assignments` and `shop_delivery_items.delivery_confirmed` are missing, blocking the current shop/checkout drafts. Reconcile design and dependencies before testing delivery migration.
5. **Draft inconsistencies:** Resolve numeric type and catalog view `security_invoker` mismatches, and repair the stage 004 legacy email fallback. Validate SQL ordering and idempotency in staging.
6. **Storage and image migration:** No bucket or object policies exist. Define public/private image rules, upload authorization, limits, and a non-destructive migration plan for existing image URLs/files.
7. **Privileged features remain Express-only:** Checkout, stock mutation, Razorpay verification/refunds, admin writes, shop delivery, invoices and reports have no deployed Edge Functions. Keep Express as fallback until replacements pass integration/security tests.
8. **No deployed function or end-to-end evidence:** The live project has zero Edge Functions; PostgreSQL/RLS, Edge Runtime, Flutter/browser, email, and Razorpay sandbox integration remain unverified.

## Safest existing-project recommendation

Do not create or use another hosted project. Use the repository's disposable local Supabase stack with synthetic fixtures for SQL, Auth API, PostgREST, Storage, and RLS tests. Never use the current data-bearing project for test writes. For production rollout, capture a verified backup and metadata snapshot, review each additive SQL/settings change and its impact, and obtain explicit approval before applying it.

1. Finish disposable-local tests in dependency order: catalog and Storage reads, Auth/profile/address, cart, then order-history/rewards/support. Use synthetic fixtures and reset only the isolated local test stack.
2. Before a production rollout, capture a verified backup and metadata snapshot, inspect current policies/grants/functions, and present exact additive SQL/settings changes plus rollback for approval.
3. Test grants and RLS using `anon`, dealer A, dealer B, pending dealer, and authorized admin JWTs. Include negative cross-dealer tests and checks that clients cannot read or change purchase price, stock, order totals, payment status, or admin roles.
4. Keep all feature flags disabled and Express active until each route passes local SQL/API/Auth/Flutter tests and an approved production verification window. Payment tests require Razorpay sandbox credentials; email-dependent tests require a working provider.
5. Keep all feature flags disabled and Express active until each route passes database, function, Flutter/browser, and security tests. Production deployment requires a separate reviewed change and explicit approval.

## Current completion status

This document records a read-only metadata and Auth-settings audit. It does not certify migration readiness or production security. No live changes were made. The catalog and dealer profile/address paths have since passed the disposable local Supabase Auth/PostgREST/RLS/Storage test using synthetic fixtures. The next safe action is to continue local coverage for cart and order-history/rewards/support, then present exact additive changes for approval before changing the existing project. No separate hosted staging project is in scope.
