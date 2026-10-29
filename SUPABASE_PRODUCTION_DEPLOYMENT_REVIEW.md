# Existing Supabase project: production change review

**Target only:** `czegmfzntnfpwaxgczds` (`https://czegmfzntnfpwaxgczds.supabase.co`)
**State:** review packet, not executable approval-ready migrations. Nothing in this document has been run against the hosted project.

## Gate before production

The last read-only audit (`SUPABASE_READONLY_AUDIT.md`, 2026-10-28) found 15 public tables, with records in 11; RLS enabled but no public or Storage policies; broad grants; no Storage buckets; no deployed Edge Functions; and missing `users.auth_user_id`, `shop_order_assignments`, and `shop_delivery_items.delivery_confirmed`. The live project is data-bearing. These facts must be freshly rechecked read-only immediately before any production change. SQL in the current repository is not yet reconciled with that live schema, so there is no safe `supabase db push` or SQL-editor command to approve today.

**Do not run** the fresh baseline `supabase_migration.sql`, `supabase_data_import.sql`, the combined old auth/RLS bundle, or any file under `supabase/drafts/unreconciled/` directly against production. `supabase/migrations/` currently contains only a README; `supabase/staging/` files are test artifacts, not production migrations.

## Candidate SQL, dependency order, and impact to review

These are the exact existing candidate files. Before approval, each must be reconciled into a new numbered migration set using the fresh live catalog snapshot, then tested against a disposable local Supabase stack. Existing production records must remain untouched except for the explicitly described additive DDL and the narrowly approved data backfill below.

| Proposed order | Existing candidate | Intended change | Production impact / blocker |
|---|---|---|---|
| 1 | `supabase/staging/001_catalog_read.sql` | Restricted product/category read projection, grants, policies, view excluding purchase price | Changes grants/policies and creates a view. Must verify exact columns, view security mode, existing grants, and API payload compatibility. |
| 2 | `supabase/staging/002_dealer_profile_addresses.sql` | Add Auth identity link and owner-derived profile/address RPC/security | Adds column/FK/index/functions/policies. Current live `users.auth_user_id` is absent. A backfill/link of existing identities must not be automatic; it needs an independently verified mapping and explicit, reviewed row set. Pending dealer approval must remain intact. |
| 3 | `supabase/staging/003_dealer_cart.sql` | Dealer-owned cart policies and stock-bounded/idempotent cart RPC/ledger | Adds private ledger/functions/policies; depends on verified identity link and existing unique cart index. Must test retries/concurrent stock changes. |
| 4 | `supabase/staging/004_dealer_order_history.sql` | Owner-scoped order, item, reward reads and support-ticket operations | Adds/replaces policies/functions. Legacy email fallback requires verified auth-email semantics; do not expose unmatched legacy rows. |
| 5 | `supabase/staging/005_product_image_storage.sql` | Create `ro-product-images` bucket and read/upload rules | Creates bucket/policies; live audit found no buckets. Existing image URLs/files are not migrated by this SQL. Inventory image references and prove URL compatibility first. |
| 6 | `supabase/drafts/unreconciled/20261029_admin_catalog.sql` | Admin-only catalog/category RPCs and server-side catalog writes | Includes data-changing category operations: renames update product category keys; delete reassigns products to “Spares” and deletes the category row. Those operations are not part of installation; require separately approved per-operation semantics. |
| 7 | `supabase/drafts/unreconciled/20261030_admin_bulk_import.sql` | Import idempotency ledger and atomic admin bulk insert RPC | Adds ledger/function; future calls insert product rows. Must validate duplicate rules, category references, price/stock bounds, image handling, and rollback on partial invalid input. |
| 8 | `supabase/drafts/unreconciled/20261027_secure_checkout.sql` | Checkout/order/stock RPC and idempotency/inventory ledger | Mutates stock and creates orders; draft depends on absent shop assignment schema and has no coordinated writer/reservation strategy with active Express. Not eligible for approval yet. |
| 9 | `supabase/drafts/unreconciled/20261028_checkout_refund_reconciliation.sql` | Payment/refund reconciliation records/functions | Depends on checkout private objects. Provider settlement and ambiguous network failures are not proven by local tests. No production payment/refund operation may be simulated. |
| 10 | `supabase/drafts/unreconciled/20261031_shop_delivery.sql` and `20261028_admin_order_status.sql` | Employee linking/assignment, delivery confirmation, COD collection ledger, admin status | Adds employee/order assignment and delivery fields/tables. Existing orders are not assigned by the draft. COD confirmation changes payment status only on an explicit server-side collection action. Requires a verified employee-link/assignment workflow and no duplicate collection. |
| 11 | remaining admin/report/support/invoice functions | Replace only after each existing endpoint's behavior and required schema is verified | No complete deployed parity exists. Keep these routes in Express. |

The old `supabase/drafts/unreconciled/20261026_auth_rls_storage.sql` is **not** in the sequence: it overlaps stages 001/002/005, assumes a missing shop table, contains broad policy replacement, and includes a user-row update/linking operation. Do not execute it.

### Data and security effects to explicitly approve

- Tightened grants/RLS can immediately make existing clients unable to read/write tables until their replacement client path is deployed. Keep current Express running, but verify it uses a trusted database role with appropriate RLS bypass/owner behavior.
- Adding policies changes exposure of existing records, although it should not rewrite them. Validate with anonymous, dealer A, dealer B, pending dealer, shop employee, and admin identities.
- `auth_user_id` backfill is a data mutation and is intentionally excluded from installation SQL until account ownership is proven. Never link by unverified email/mobile or auto-approve dealers.
- Catalog category rename/delete and bulk import, checkout, stock deduction/restock, payment status, COD collection, delivery confirmation, and refunds are business-data mutations. They are runtime operations, not migration steps; each requires separate integration tests and must not be invoked during schema deployment.
- Product Storage setup exposes product image objects for public reads by design; upload remains server-authorized. Confirm no private documents are put in that bucket.

## Exact staged deployment sequence after review and explicit approval

1. Run fresh read-only checks for project ref, schema columns/types/constraints/indexes, existing grants/RLS/policies, Storage buckets/policies, Auth providers/settings, functions, and migration history. Save a sanitized snapshot. Confirm the exact ref is `czegmfzntnfpwaxgczds`; abort on mismatch.
2. Create and verify a recoverable backup/snapshot using the provider's supported backup process. No migration proceeds until recovery is confirmed.
3. Reconcile the numbered SQL against the new live snapshot. Keep the resulting reviewed files in `supabase/migrations/`; do not include a data import, truncate, drop, broad user backfill, or fixture rows.
4. Apply one additive schema stage at a time to the existing project only after the exact file diff and impact are approved. The staged test harness is local only and is not proof of live compatibility.
5. Verify each stage using read-only schema checks and controlled Auth identities. Do not test by changing production products/orders or using customer data.
6. Configure Storage only after bucket/policy SQL review and image inventory. Upload a dedicated non-customer test image only if separately approved; remove it only through a separately reviewed cleanup.
7. Deploy Edge Functions in dependency order only after each function's schema is verified. Function directory names present locally: `admin-dealers`, `admin-dealer-approval`, `admin-dashboard-stats`, `admin-analytics`, `admin-catalog`, `admin-orders`, `admin-order-status`, `admin-shop-employees`, `admin-shop-enquiries`, `admin-shop-notifications`, `create-razorpay-order`, `place-cod-order`, `verify-razorpay-payment`, `cancel-order`, `shop-delivery`. Deployment command form (do not run without approval):

   ```powershell
   npx supabase functions deploy <function-name> --project-ref czegmfzntnfpwaxgczds
   ```

8. Configure only required server-side secrets via Supabase Dashboard/Secrets Manager after their owners approve. Never place service-role, Razorpay, database, or mail secrets in Flutter, browser build-time variables, Git, or this report. Email-dependent OTP/reset remain blocked until an approved sender is configured; Razorpay verification/refunds require sandbox tests before production credentials are considered.
9. Keep all client migration flags false. Run an approved smoke test per feature, compare responses with Express, then request a separate explicit approval to enable that feature's flag. Express stays available as rollback until parity is verified.
10. Only after essential paths pass against the deployed project, set a production Supabase URL and publishable key in the Flutter build environment, confirm no local/LAN/Express URLs remain in the release configuration, run Flutter tests/analyze, and build the release APK. Deploy Flutter Web Admin only after its Supabase login and all enabled admin paths pass browser tests. Hosting target/domain has not been confirmed and must be supplied/configured separately.

## Current test evidence and blockers

- Latest local Node suite: 150 tests total; 148 passed, 0 failed, 2 skipped (as reported by the last successful `npm test`).
- Latest disposable PostgreSQL migration harness: 1/1 passed. This exercises draft SQL logic with synthetic data, not Supabase Auth/Storage/Edge Runtime or the hosted schema.
- Shop-delivery Node handler suite: 5/5 passed in the previous run; local SQL harness includes delivery/RPC scenarios.
- Admin Catalog/Bulk Import Edge Function integration did not pass: a prior harness failed cleanup with HTTP 400; a fresh runtime could not start because a required Docker image pull stalled after registry/layer metadata, with no completed image or specific transport error. The pull was interrupted; no running app/container was stopped.
- Follow-up diagnosis found Docker Desktop proxy settings are present while the process shell has no proxy variables. The host can access registry manifests and the layer redirect endpoint, but `storage-api:v1.84.19` still stalls at layer download. The configured proxy endpoint is not reachable from a running disposable container on its advertised port; this strongly suggests a Docker proxy-path issue, but does not prove the Docker daemon used that same path for the failed request. No proxy setting was changed because applying a Docker Desktop networking change may restart the engine and interrupt existing containers.
- Supabase Edge Runtime/Deno type-check, Razorpay sandbox, SMTP delivery, Flutter/browser integration, and production schema compatibility remain unverified.
- Latest repository/API default still targets a local Express URL; Supabase migration flags remain disabled. A production APK or admin dashboard deployment now would not be a verified Supabase release.

## Approval boundary

This packet is for review only. No production SQL, data mutation, Storage/Auth setting, function deployment, feature flag, APK build, or dashboard publication is authorized by it. After local Edge Runtime tests and fresh read-only schema reconciliation, a new packet must include the exact final SQL contents and per-statement impact before asking for approval to apply any remote change.
