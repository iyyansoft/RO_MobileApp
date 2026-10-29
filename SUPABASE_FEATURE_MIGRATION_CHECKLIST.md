# Supabase feature migration checklist

Scope: existing Supabase project only. This checklist records repository status as of 2026-10-28. The Express source contains 66 concrete API method/path routes across 65 registration declarations; the dealer deletion aliases are tracked as separate paths in `MIGRATION_ENDPOINT_INVENTORY.md`. “Prepared” means code/SQL exists locally but has not been applied or proven against the live app. Migration flags remain disabled. Email-dependent work is deferred.

## Feature status and expected behavior

| Feature | Current implementation/status | Supabase target and acceptance behavior |
|---|---|---|
| Dealer signup | Express default; Supabase Auth adapter is opt-in; local Express signup now creates pending accounts | Auth creates an unverified identity; profile is linked only after verified Auth; new dealer remains pending/unapproved until admin approval; duplicate email/mobile reports correctly |
| Password login/session | Express default; Supabase password path and token-exchange bridge are opt-in | Supabase Auth owns password/session; profile approval is checked; retained server operations validate the Auth JWT during transition |
| Email OTP / password reset | Express + SMTP/Nodemailer | **Deferred:** Resend is suspended and SMTP is not configured; no success may be reported unless an authorized provider confirms delivery |
| Google sign-in | Express Google OAuth path found | Supabase Auth Google provider after OAuth client/redirect setup; otherwise retain Express path |
| Dealer approval | Express admin route today; local profile sync does not approve | Pending/rejected/approved status is server-controlled; only verified admin action changes approval; never permit self-approval |
| Dealer profile | Express default; local Supabase profile read/edit path prepared behind `USE_SUPABASE_DEALER_DATA=false` | Auth user reads only its linked profile; client updates only name/mobile/business/address fields, never role, approval, rewards, password hash, or link ID |
| Saved addresses | Supabase repository/RPC prepared behind the same disabled-by-default flag; Express fallback retained | Dealer can list/save/set-default/delete only own addresses; RPC derives owner and serializes default changes |
| Cart | Express default; stages 001–004 execute and test against disposable local PostgreSQL fixtures; Supabase repository remains behind a disabled flag | Dealer sees/mutates own cart only; add/update RPC validates active product/current stock; add retries reuse a persisted key and private ledger; Supabase project integration remains unverified |
| Product/category read | Express default; catalog provider and safe view verified against an isolated local Supabase stack; `USE_SUPABASE_CATALOG=false` | Public catalog/category reads; product view excludes purchase price; RLS/grants deny client writes |
| Product/category administration | Local Supabase catalog CRUD adapter and Edge Function draft added behind `USE_SUPABASE_ADMIN_CATALOG=false`; Express remains default and fallback | `admin-catalog` requires verified Supabase Auth plus trusted `app_metadata.role=admin`; catalog writes use server validation/service role; category mutations use service-only RPC drafts; product delete deactivates |
| Image uploads | New function path uploads accepted image data URLs to planned `ro-product-images` bucket; existing Express storage remains default | Image size/MIME/signature checks and admin Edge Function authorization are local only. Bucket setup, Storage policy verification, existing object inventory/migration, and URL length compatibility remain open |
| Bulk Excel/CSV products | Local Supabase batch-import path prepared behind `USE_SUPABASE_ADMIN_BULK_IMPORT=false`; Express remains default | Server validates fields/categories/images and duplicates; one service-only RPC transaction commits accepted rows and an idempotency result. Identical retries replay the saved result; database failures roll back the full batch |
| Checkout/order creation | Express transaction remains default and authoritative | Local Edge Function + service-only RPC draft remains behind `USE_SUPABASE_CHECKOUT=false`; it validates approved Auth-linked dealers, prices/totals, stock, rewards, shop assignment and idempotency. Inventory is deducted under row locks in the final order transaction and recorded in a private idempotent movement ledger. It is **not reserved** while Razorpay payment is in flight; the feature remains blocked until reservation/expiry and Express-writer coordination are designed and concurrency-tested |
| COD | Express order creation; payment remains pending until real collection | Local Supabase path stores `due_on_delivery`; it never records cash as collected. A local authenticated cancellation function restores stock once for an undelivered COD order only when a checkout deduction ledger exists. Shop delivery remains Express and must record actual collection. No SQL was applied |
| Razorpay | Express creates gateway order and verifies/captures payment | Local Edge Function draft holds key usage server-side, validates HMAC and provider payment ID/order/amount/currency/status, captures authorized payment, then calls the atomic order/stock RPC. A new local-only reconciliation migration now records definitive post-capture business rejections, checks the provider for an existing refund before issuing one, claims at most one refund POST, and records pending/refunded/manual-review states. This does not resolve ambiguous network failures or guarantee provider refund settlement; admin reconciliation and Razorpay sandbox tests remain required |
| Order history/details | Supabase repository/RLS locally tested against synthetic PostgreSQL fixtures; checkout writes remain Express | Dealer reads only owned orders/items; legacy email fallback only for rows with null user ID; admin sees full records through authorized server path; Supabase project verification remains open |
| Delivery/shop operations | Express custom employee sessions and routes | Server-side Edge Functions validate employee and assigned shop; transactional item quantities/status/adjustments; partial delivery stays partial; admin reads persisted records. Shortage restock must wait until confirmed refund/adjustment and must use the checkout inventory ledger |
| Rewards | Supabase read adapter/RLS locally tested against synthetic PostgreSQL fixtures; writes occur in Express checkout | Dealer history is read-only; rewards ledger and balance updates only inside trusted order transaction; remote RLS remains unverified |
| Support tickets | Supabase create RPC/read locally tested against synthetic PostgreSQL fixtures | RPC derives verified dealer identity and status; no client-chosen owner/status; admin inbox remains admin-only; remote authorization remains unverified |
| GST invoices | Invoice summary metadata has a local Supabase owner-scoped read path; PDF generation and the legacy fixed credit-limit calculation remain Express | Preserve order data ownership; keep document rendering trusted/server-side; identify a data-backed credit policy before retiring the endpoint; no separate invoice table exists in live schema |
| Admin dashboard/analytics/orders/shop enquiries | Flutter Web login and admin APIs use Express by default. Local pilots exist for dealer listing/status, dashboard stats, analytics, catalog CRUD/import, read-only Admin Orders and Shop Enquiries, and order status; each has a separate default-off flag | Supabase Auth admin identity plus verified `app_metadata` role; Edge Functions/RPC provide aggregate and management operations; no client role flags. No pilot is deployed or browser-tested |
| Payments/invoice status | Existing Express/admin operations | Payment status changes only after verified gateway event or real COD collection; invoice status must not be inferred from delivery |
| Notifications | SMTP-backed Express features | Email deferred; in-app notification rows can move after admin/employee authorization and RLS/Edge Function tests |

## Existing live schema audit and staged local rollout (2026-10-27)

- [x] Read-only catalog audit confirmed all 11 core tables and four existing shop tables. `public.shop_order_assignments` is absent, although the older broad RLS draft requires it and therefore cannot be run against the audited schema as-is.
- [x] The live schema has no `catalog_products` view, no public-table RLS policies, and no Storage buckets/policies. RLS is enabled on the audited public tables, while `anon` and `authenticated` currently have broad table grants; the policies are presently the effective row-access barrier.
- [x] Existing PostgreSQL backend role is non-superuser and has `BYPASSRLS`, so retaining Express as the fallback remains compatible with client-grant tightening.
- [x] Added a standalone, local-only catalog-read stage at `supabase/staging/001_catalog_read.sql`. It verifies the existing columns and PostgreSQL 15+ before granting only read access to public catalog columns, creates active-product/category policies, and exposes a `security_invoker` product view that omits `purchase_price`.
- [x] Local Supabase integration verified `001_catalog_read.sql` plus `005_product_image_storage.sql` through PostgreSQL, PostgREST, Auth, and Storage: anonymous and authenticated dealer catalog/category reads succeeded; inactive products were hidden; `purchase_price` reads and client table writes were denied; public image GET succeeded while anonymous/dealer uploads were denied. This used synthetic rows and a temporary local stack only; it does not verify the existing hosted Supabase project or live data.
- [x] Added `npm run test:supabase-catalog-local` and `scripts/test-supabase-catalog-local.ps1`, which hard-check loopback URLs and dedicated ports, reset only the disposable local Supabase database, and run the real API/RLS/Storage test with runtime-only local credentials. The test refuses remote targets and existing catalog tables.
- [x] Added `NOTIFY pgrst, 'reload schema'` to the catalog stage and a bounded PostgREST cache-refresh wait in the integration test. The first local run caught stale schema cache (`PGRST205`); the rerun passed after this fix.
- [x] Updated the opt-in Flutter catalog client to request explicit projections from the view and category table. `USE_SUPABASE_CATALOG` remains false by default; Express remains the default.
- [ ] Do not add this stage to the production migration chain until earlier unapplied migrations are reconciled against the live schema. Do not run it against production without review and explicit approval.
- [ ] Validate on an isolated hosted staging clone that `security_invoker` behavior, column grants, RLS, production PostgREST/Auth/Storage configuration, image URL compatibility, and Flutter response parsing match the contract.
- [ ] Broader cleanup remains: revoke excessive grants on sensitive tables, safely link existing dealers to Auth, migrate Storage objects, and reconcile numeric precision drift without narrowing populated values.

### Local Admin Shop Enquiries read pilot (2026-10-28)

The Admin Web `GET /api/admin/shop/enquiries` route now has a local-only `admin-shop-enquiries` Edge Function alternative. It uses the existing `shop_product_enquiries` and `shop_employees` tables, explicit field allowlists, the legacy 500-row limit, and a verified Supabase Auth identity with trusted `app_metadata.role=admin`. `USE_SUPABASE_ADMIN_SHOP_ENQUIRIES` defaults to false; Express remains the active path. No schema or data changes are required for this pilot. Handler, query-projection, bound, and Flutter route mapping tests pass locally. Live function deployment, real Auth authorization, and browser rendering remain unverified.

### Local Admin Shop Notifications read pilot (2026-10-28)

The Admin Web `GET /api/admin/shop/notifications` inbox now has a local-only `admin-shop-notifications` Edge Function alternative. It reads only the existing `shop_admin_notifications` fields and maps employee ID/name from `shop_employees`, preserves the Express 250-row limit and response keys, and requires a verified Supabase Auth user whose trusted `app_metadata.role` is `admin`. `USE_SUPABASE_ADMIN_SHOP_NOTIFICATIONS` defaults to false. Express remains the active path, and the refund-recording endpoint remains Express. No SQL/schema/data change is included. Local handler, explicit-query projection, bounds, error sanitization, authorization, and Flutter route-mapping tests cover the pilot; live Supabase Auth, PostgREST schema compatibility, deployment, and browser behavior remain unverified.

Validation on 2026-10-28: the complete Node suite passed 132 tests, failed 0, and skipped the opt-in PostgreSQL harness test; the disposable local PostgreSQL harness separately passed 1/1. The focused notifications handler suite passed 5/5. The new Dart route test was formatted but Flutter test/analysis commands stalled with no output and were interrupted; existing Dart analyzer hangs remain unresolved. Deno is not installed/discoverable in this terminal, so the new Edge Function did not receive a Deno type check in this session.

### Local Admin Shop Employees read pilot (2026-10-28)

The Admin Web `GET /api/admin/shop/employees` read now has an `admin-shop-employees` Edge Function alternative. It returns the existing UI fields (`id`, `employee_id`, `shop_name`, `full_name`, `active`, `created_at`), paginates instead of silently truncating at PostgREST's page cap, and never selects `password_hash`. It requires a verified Supabase Auth identity with trusted `app_metadata.role=admin`; `USE_SUPABASE_ADMIN_SHOP_EMPLOYEES` defaults to false. Employee login, provisioning, and activation remain Express because they need a secure credential/auth migration. This pilot adds no SQL or data changes and has not been deployed or browser-tested.

Validation after the employees and dealer-approval display fixes: `npm test` passed 138 tests, failed 0, skipped 1 (the opt-in PostgreSQL test, also run separately and passed 1/1). Focused registration, employee, and notification handler tests passed 11/11. Flutter test/analysis remains stalled in this Windows checkout; Deno is not available for checking the Edge Function entrypoint. No production functions or database objects have changed.

### Dealer approval display safety fix (2026-10-28)

The successful signup client state and legacy registration-submitted screen now both show a new dealer as pending administrator approval. This corrects a misleading UI state only; it does not approve the database account, alter authentication, or change the existing approval endpoint. A source-contract test guards against reintroducing the incorrect approved state/message.

### Live schema differences requiring migration planning

- Missing live object: `shop_order_assignments`; the local broad auth/RLS migration checks this table as mandatory. Shop order assignment migrations must not be attempted until its actual workflow and existing `shop_delivery_items` relationships are reconciled.
- Missing local-pilot objects: `checkout_sessions`, `checkout_inventory_movements`, `checkout_refund_reconciliations`, and `admin_bulk_import_requests`. These are unapplied drafts, not production objects.
- Missing live view: `catalog_products`. The narrow draft supplies it locally but is intentionally outside `supabase/migrations` to avoid the unreconciled migration chain being auto-applied in order.
- Live `user_addresses` has additional address fields compared with the original base schema draft. Preserve them; do not replace the table.
- Several live monetary columns are unbounded `numeric` where the MySQL source used `DECIMAL(10,2)` and the base migration draft declared bounded numeric. Audit actual values before proposing a constraint/type correction; do not narrow existing data blindly.
- No production row contents were queried. Object names, column names/types, constraints, grants, RLS/policies, views/functions, role attributes, and identity metadata were inspected read-only.

## Security and database checklist

- [x] Read-only live metadata audit completed; no application rows inspected.
- [x] Live schema contains the 11 core tables plus 4 existing shop tables; no shadow business tables are proposed. `shop_order_assignments` is absent.
- [x] Live RLS is enabled on all 15 public tables and `storage.objects`; no policies were found.
- [x] 2026-10-28 read-only check verified the configured database belongs to the existing project. Existence-only queries found rows in 11 of 15 public tables, including users, products, categories, carts, orders/items, addresses, rewards, and shop delivery/admin tables. No row contents were read; this is production data and not a staging target.
- [ ] Edge Function deployment inventory is unverified. No local Supabase CLI access-token file was found; no deployment was attempted.
- [x] Live `anon` and `authenticated` grants are broad on the 15 public tables; local migration draft revokes these for core and shop tables before granting narrowly scoped access.
- [x] Public dealer catalog response and query no longer include purchase price; admin product API remains separately protected.
- [x] Reconciled the absent `shop_order_assignments` dependency out of the automatic migration path: legacy SQL moved to `supabase/drafts/unreconciled/`, ordered staged drafts added under `supabase/staging/`.
- [ ] Parse/apply the staged SQL on an independently identified Supabase staging project and confirm exact grants/policies before any production review.
- [ ] Add/link `users.auth_user_id`; safely reconcile existing accounts without changing passwords or approvals.
- [ ] Decide and implement employee identity/session migration; current shop employees use employee ID/password hashes, not Supabase Auth identities.
- [ ] Create secure admin-role provisioning/revocation procedure; never accept role from user-editable metadata.
- [ ] Reconcile missing live `shop_delivery_items.delivery_confirmed` column with the existing additive shop migration before delivery-function parity work.
- [x] Prepared local-only `supabase/staging/005_product_image_storage.sql`; it creates only a missing exact `ro-product-images` public-read bucket (5 MiB, JPG/PNG/WEBP), accepts a compatible rerun, and aborts on conflicting settings. It creates no client write policy and changes no image URL.
- [ ] Apply stage 005 only to independently verified staging; test server-authorized upload, public download, size/MIME validation, and rejected anonymous writes.
- [ ] Inventory and migrate existing image files/URLs only after every object is verified.
- [ ] Add least-privilege policies/RPC/Edge Functions for all operations; verify no service-role key is in client assets/builds.

## Test plan before enabling any flag or cutting over

1. Run SQL syntax checks and apply the migration only to an isolated staging project after approval; compare schema, grants, RLS, policies, constraints, and sequences before/after.
2. Use separate anonymous, dealer A, dealer B, pending dealer, approved dealer, admin, and employee sessions. Prove every cross-owner read/write fails.
3. Test signup/profile linking for existing and new users, pending status, duplicate email/mobile, expired/revoked session, and no approval escalation. Email delivery tests wait for provider setup.
4. Test catalog response/view does not expose purchase price; admin can still read/edit the value; inactive products are hidden from dealer clients.
5. Test address default concurrency, cart stock boundaries/concurrency, and direct table-write denials.
6. Test order creation using server/database prices, stock races, GST/discount/delivery calculations, duplicate idempotency key, COD pending state, failed Razorpay verification, valid signature, replayed webhook, and one-time reward application.
7. Test dealer order/reward/ticket ownership, assigned-shop order visibility, partial/full/zero delivery, duplicate delivery submit, refund adjustment approvals, COD cash collection evidence, and admin synchronization after reload.
8. Test product/category CRUD, image upload size/MIME/path authorization, duplicate-SKU/invalid-row bulk import, rollback on batch failure, and persisted URLs.
9. Test invoice output parity, GST details, order ownership, PDF rendering, admin dashboard aggregates, and role denial.
10. Run Node tests, Flutter tests/analyzer, and emulator/browser end-to-end tests. Enable one feature flag only after its isolated test suite passes; keep Express rollback path until production parity is verified.

### Isolated local catalog API/RLS/Storage verification (2026-10-28)

- [x] Applied staged SQL 001 and 005 only to the disposable local Supabase stack, using synthetic catalog rows matching the audited table columns.
- [x] Verified PostgREST schema-cache refresh, anonymous category and catalog reads, authenticated dealer catalog reads, inactive-product filtering, and omission/denial of `purchase_price`.
- [x] Verified anonymous and dealer base-table writes fail, public product-image reads work, anonymous/dealer Storage uploads fail, and the local service role can provision and clean up test fixtures.
- [x] The Flutter catalog providers were tested against the same local API as anonymous and authenticated users. Product/category fields and the public Storage URL mapped correctly, category ID/name matching returned the expected products, and Flutter downloaded and decoded the test PNG.
- [x] The Supabase provider now explicitly sorts products by category key/name and categories by display order ascending, matching the existing Express endpoints. The integration test caught Supabase Dart's descending default and this parity issue was corrected.
- [x] `npm run test:supabase-catalog-local`: local Node/PostgREST/Auth/Storage test passed 1/1 and Flutter client integration test passed 1/1. Targeted `dart analyze` on the provider and integration test reported no issues. `npm test`: passed 143, failed 0, skipped 2; the two opt-in integration tests passed 1/1 each when run separately (catalog API/RLS/Storage and the existing staging PostgreSQL harness).
- [ ] Hosted staging and production integration remain unverified. The production catalog flag stays off, Express remains the active fallback, and neither SQL nor functions were applied/deployed remotely.

### Isolated local PostgreSQL verification: dealer profile and saved addresses (2026-10-28)

- [x] Extended `test/supabase_staging_postgres_test.cjs` to exercise stage 002 under the `authenticated` database role with synthetic Auth identities and dealer rows. The disposable PostgreSQL harness passed after checking verified identity linkage, pending approval preservation, owner-only profile/address reads, restricted profile updates, address create/update, default-address replacement/selection, owner-only delete, foreign-owner ID collision rejection, and anonymous RPC/table denial.
- [x] Re-ran the combined local staging SQL harness; migrations 001–004 and the profile/address/cart/history policy checks passed 1/1. The harness uses temporary Docker PostgreSQL with a minimal Auth stub, not Supabase Auth, PostgREST, live Storage, hosted staging, or production.
- [x] Confirmed this checkout's local Supabase link metadata identifies the existing production project `czegmfzntnfpwaxgczds`; no separate staging project reference or URL was found. No remote command was run. This cannot establish whether a hosted staging project exists outside this workspace.
- [ ] Hosted staging verification remains required for Auth JWT-to-RLS claims, actual RPC exposure through PostgREST, profile/address Flutter integration, and concurrency behavior. `USE_SUPABASE_DEALER_DATA` remains false; Express remains the default/fallback.

## Admin product/category pilot status (2026-10-27)

- [x] Audited existing Flutter Web product/category forms, `AdminRepository`, and Express product/category endpoints before adding the adapter.
- [x] Added `supabase/functions/admin-catalog` for product/category reads, create/update, product soft-deactivation, and safe category reassignment/deletion. The function uses `auth.getUser()` and checks verified email plus `app_metadata.role=admin` before service-role access.
- [x] Added local-only `20261029_admin_catalog.sql` RPC/grant draft; it does not create business tables and has not been executed.
- [x] Added `USE_SUPABASE_ADMIN_CATALOG`, default false. Flutter Web keeps Express login/session and all noncatalog routes. Catalog CRUD routes use Supabase only with a verified Supabase Auth admin session. Mutation errors are not replayed through Express because the Supabase outcome may be uncertain.
- [x] Added Node tests for handler authentication/authorization, CRUD dispatch, input validation, request limits, image data URL checks, and sanitized server errors, plus Flutter route-mapping tests.
- [x] Audited Express `POST /api/admin/products/bulk`: it prechecks SKUs/categories and inserts rows individually, so a database failure can leave a partial batch.
- [x] Added Edge bulk import action with server-side normalization/validation for fields, data types, price/stock bounds, category references, images, and duplicate rows/SKUs.
- [x] Added default-off `USE_SUPABASE_ADMIN_BULK_IMPORT`; Flutter sends the existing `products/bulk` request to the Edge Function only when this flag and a verified Supabase admin session are active. Express remains the default fallback.
- [x] Added local-only `20261030_admin_bulk_import.sql`: one RPC transaction persists imported products and a per-admin content fingerprint response ledger; identical retries are idempotent and unexpected SQL errors roll back the batch.
- [x] Extended the Admin Web preview validation and tests for duplicate headers, SKU format, price/stock limits, and MOQ aliases. Replay responses avoid claiming a second import.
- [x] `npm test`: 71/71 Node tests passed; `node --check` passed for the shared Edge handler; `dart analyze` passed for the admin route mapper; Dart formatting check passed.
- [ ] Flutter route/config tests were attempted but the Flutter test runner produced no output and did not complete during the run; rerun them in a healthy Flutter tool environment.
- [ ] Reconcile and execute SQL only on approved isolated staging; only a disposable local PostgreSQL fixture was used here.
- [ ] Provision a trusted Supabase Auth admin identity, configure the Storage bucket/policies, deploy the function, and run browser/PostgreSQL integration tests. None were performed here.
- [ ] Verify product/category field and image URL parity, duplicate behavior, category delete/reassignment, and admin role revocation in staging before enabling the flag.
- [ ] Test transaction rollback, concurrent duplicate insertion, and same-batch replay against Supabase PostgreSQL staging; the local harness does not verify Supabase role/Auth behavior.
- [ ] Define a cleanup process for content-addressed images uploaded before a batch SQL failure; Storage uploads cannot participate in the PostgreSQL transaction.
- [ ] Add Supabase PostgreSQL integration coverage for admin-import advisory-lock idempotency, duplicate SKU races against the expression index, request-ledger replay, and transaction rollback. The cart retry/stock behavior has local PostgreSQL coverage only.
- [ ] Confirm `categories.image_url` can store the actual Storage public URL length. The local schema draft currently uses `varchar(255)`; if the project URL/bucket path exceeds this bound, prepare and review a separate compatible local DDL adjustment before any real upload.

## Current release gate

No Supabase SQL has been applied and no Edge Function has been deployed. Local checkout and admin-catalog Edge Function sources exist, and all migration flags remain disabled. Email-dependent features remain on Express. The app is not ready for backend cutover.

## Local Admin Order Status stage (2026-10-28)

- [x] Added the `admin-order-status` Edge Function and Flutter Web adapter for `PUT /api/admin/orders/:id/status`, gated by `USE_SUPABASE_ADMIN_ORDER_STATUS=false`.
- [x] Added an additive local SQL draft that creates only the restricted RPC function; it creates no table and does not change rows when installed. The RPC checks trusted verified-admin app metadata, locks the order and items, refuses to mark incomplete orders Delivered, and refuses to override a saved Shop delivery.
- [x] Added handler, repository, Flutter routing/config, and local PostgreSQL authorization/state tests. The function and SQL remain local and un-deployed.
- [ ] Verify the schema, grants, Auth role claim, concurrent Shop delivery interaction, and response/error behavior against an isolated Supabase staging project before enabling the flag.
- [ ] The app still relies on the Express API for the Supabase Auth token-exchange bridge and most unported features. No route is considered retired.

## Current 66-route disposition

- [x] `MIGRATION_ENDPOINT_INVENTORY.md` now lists the 66 concrete route paths individually. All 66 remain registered in Express; local Supabase alternatives are pilots only and remain disabled.
- [ ] Supabase Auth signup/login/OTP and account linking: local opt-in adapter plus profile-linking SQL draft; email delivery, remote Auth configuration, approval parity, token/session behavior, and staging tests remain open. The adapter still exchanges the Supabase session through Express for the legacy API token.
- [ ] Public product/category reads, dealer-owned profile/address/cart/history/rewards/support reads, checkout, selected admin reads/CRUD/import, and admin order-status have local alternatives. Each remains unverified against the live or isolated Supabase project.
- [ ] Razorpay, cancellation/refunds, stock mutation, Shop delivery, invoices/PDF, reports, and several admin/shop APIs remain Express-only or draft-only. Preserve Express until each replacement passes Auth, PostgreSQL, Edge Runtime, and client integration tests.

## Local validation update (2026-10-28)

- [x] Expanded the disposable PostgreSQL fixture to verify linking a verified legacy dealer without changing pending approval, creating a new dealer as pending even when untrusted user metadata says `role=admin`, rejecting unverified identities, and denying direct self-approval updates.
- [x] Disposable PostgreSQL harness passed 1/1 after the new Auth/RLS scenarios and Admin Order Status RPC checks. It uses loopback Docker plus synthetic data only; it is not a Supabase staging integration test.
- [x] Deno 2.9.8 previously checked the 11 existing Edge Function entrypoints; the added `admin-shop-enquiries` function also passes `deno check --no-config --no-lock`. The full set of 12 local entrypoints has therefore type-checked. No function was deployed.
- [x] Full Node suite after the release guard: 127 passed, 0 failed, 1 local-PostgreSQL test skipped by default. Focused enquiry/inventory tests pass 15/15; the release guard passes and the PowerShell build script parses.
- [x] The disposable PostgreSQL harness passed 1/1 in this turn using the isolated loopback container and synthetic fixtures. It validates dealer isolation, stock bounds, and safe retries; it is not a Supabase staging integration test.
- [x] A read-only Supabase metadata/existence audit verified the configured project target; it found live data as recorded above. No business row values were read, and no SQL was executed.
- [ ] Supabase CLI 2.122.0 is available through `npx`, but no local CLI access token exists. Function deployment listing could not be verified; no project deployment, SQL execution, or production configuration changes were performed.
- [ ] Still required: positively identify isolated staging, compare its schema/grants/RLS to these drafts, validate Edge Functions against Supabase Auth/PostgREST and browser flows, and configure email delivery before claiming OTP delivery parity.
- [x] Earlier Flutter commands had startup delay while IDE Dart processes were present; no process/cache was terminated. The latest full Flutter tests and targeted changed-file analysis now complete. Full analysis reports informational lints only; see the latest verification block below.
- [ ] `npx --yes supabase --version` returned `2.122.0`, but `npx supabase functions serve --help` produced no output and was stopped after 30 seconds. No local Edge Function runtime was started. Use the CLI version command as confirmed tooling availability; runtime serving still needs diagnosis.

## Current locally implemented dealer-data stage

- Catalog read, dealer profile read/edit, saved-address operations, cart, order/reward reads, and support-ticket submission have local Supabase client/RPC paths and ordered staging SQL. The relevant flags remain disabled; none of these paths is considered cut over or production-verified.
- Cart stage now checks the required existing columns, valid non-partial unique `(user_id, product_id)` index, and absence of pre-existing cart RPC names before proceeding. It aborts if cart RLS policies already exist, preserves active-product/stock locking, and its write RPCs return `void` rather than exposing a full cart row.
- Latest Node/PostgreSQL/Flutter results are recorded in the dated verification block at the end of this file. The local harness uses synthetic records and a minimal Storage metadata fixture; it does not verify real Supabase Auth, Storage service, Edge Runtime, or browser behavior.
- Next step: positively identify an isolated staging project, then review/apply stages 001–005 there and run Auth/RLS, Storage, browser, and API integration tests. Checkout writes remain Express until payment/inventory coordination is tested.
- The local Express fallback no longer auto-approves new password or Google registrations, and it blocks app sessions for pending dealers. Existing rows and the running service were not changed; verify the updated source after the normal service restart and test admin approval.

## Local admin dealer-approval stage (2026-10-27)

- [x] Mapped the existing Admin Web `POST /api/admin/set-status` call to a local Supabase Edge Function adapter.
- [x] The function verifies the bearer through Supabase Auth, requires a confirmed email and server-controlled `app_metadata.role=admin`, and accepts only `approved`, `pending`, or `rejected`.
- [x] The database adapter resolves email, exact dealer ID, or a 10-digit mobile to one unique existing `users` row; it rejects missing/ambiguous identifiers and updates only `status` plus `is_approved`.

## Latest local verification and Storage preparation (2026-10-28)

- [x] Repeated the guarded, read-only inventory against the configured existing Supabase project. It matched project `czegmfzntnfpwaxgczds`, found 15 public tables (RLS enabled on each), rows in 11 tables, zero public/Storage policies, no Storage buckets, and one public function (`ro_set_updated_at()`). Only metadata and row-existence booleans were read.
- [x] Extended `scripts/inspect-supabase-schema-readonly.cjs` to include bucket settings and `storage.objects` RLS/policies; added `test/supabase_schema_audit_test.cjs`.
- [x] Added `supabase/staging/005_product_image_storage.sql`. It inserts only a missing `ro-product-images` bucket with public read, a 5 MiB size limit, and JPG/PNG/WEBP MIME restrictions. A matching existing bucket is a no-op; mismatched settings raise an exception. It does not add client-write policies or alter image URLs/objects.
- [x] Added a disposable-PostgreSQL Storage metadata fixture and idempotency assertions. This synthetic test does not substitute for Supabase Storage/Edge Function testing.
- [x] Corrected the bulk-template test to compare the `Product Description` column actually used by the template. This changed only a stale test expectation; importer behavior was already correct.
- [ ] Supabase Auth/provider settings, deployed Edge Function inventory, admin role provisioning, browser integration, image object migration, OTP email, Razorpay, and all live app flows remain unverified. No remote SQL or function deployment occurred.
- [ ] Before any remote SQL/function operation, present the exact reviewed operation and impact and obtain approval. Supabase CLI deployment access still needs an authenticated local CLI session; do not paste access tokens into chat.
- [x] Added the independently default-off `USE_SUPABASE_ADMIN_DEALER_APPROVAL` flag. Without it, or without an authorized Supabase admin session, the existing Express route remains the active path. Failed Supabase operations are not replayed via Express.
- [x] No SQL/schema change is required for this pilot; no database was contacted and the function was not deployed.
- [ ] Provision and verify trusted Supabase admin `app_metadata` through an operator-controlled process, including revocation.
- [ ] Run the Edge Function against an isolated Supabase staging target and verify `users` column/data behavior, missing/ambiguous identifiers, and role denial.
- [ ] Verify the approval queue, status update, session blocking for pending/rejected dealers, and post-approval login in the browser/mobile flow.
- [ ] Keep the flag disabled and Express active until those integration checks pass.

## Local admin dealer-directory stage (2026-10-27)

- [x] Audited the existing `GET /api/admin/dealers` response and implemented a separate read-only `admin-dealers` Edge Function using the existing `public.users` table.
- [x] The function authenticates each request through Supabase Auth, requires confirmed email plus trusted `app_metadata.role=admin`, and uses a server-only service client after authorization.
- [x] The query selects only the fields used by the existing dashboard response; password hashes, Auth link IDs, GST values, and reward balances are excluded. Reads page through 500-row ranges rather than silently truncating at the PostgREST default.
- [x] Added the isolated default-off `USE_SUPABASE_ADMIN_DEALERS` flag and route mapping for only the dealer-list GET. Express remains the default for this and all other admin APIs.
- [x] Added tests for trusted role enforcement, method restrictions, safe projection, response mapping, pagination, and sanitized database failures.
- [ ] Verify live `users` column compatibility, Supabase Auth app metadata, Edge Runtime, list parity, and browser rendering on an identified isolated staging project. The function is not deployed and the flag remains off.
- [ ] Add search/status pagination parity only if the existing UI's full-list behavior requires it after staging performance review.

## Local admin dashboard-statistics stage (2026-10-27)

- [x] Audited Express `GET /api/admin/dashboard-stats`; the existing response contains status counts for dealers/products, category/order counts, and total `orders.grand_total` revenue.
- [x] Added `admin-dashboard-stats`, which validates confirmed Supabase Auth plus trusted `app_metadata.role=admin` before any table query.
- [x] The function reads only `users.status`, `products.status`, `categories.id`, and `orders.grand_total`, paginates in 500-row pages, and fails closed when a table exceeds the 50,000-row processing limit.
- [x] Preserved the existing `{success, stats}` payload keys and lower-case status counting semantics; database errors are sanitized.
- [x] Added a separate `USE_SUPABASE_ADMIN_STATS` flag, false by default, and routed only the dashboard-stats GET through Supabase when an authorized Supabase admin session exists.
- [ ] Compare exact counts/revenue against Express on an isolated staging dataset, check high-volume latency and currency precision, and verify the Admin Web overview after reload. This local function has not been deployed or live-tested.

## Checkout implementation status (2026-10-27)

- [x] Local-only checkout SQL draft includes locked stock revalidation/deduction, private inventory movement ledger, and owner-authorized COD cancellation/restock RPC in `supabase/drafts/unreconciled/20261027_secure_checkout.sql`.
- [x] Local Edge Function source added for COD, Razorpay order creation/verification, and COD order cancellation; secrets are referenced only through Edge Function environment variables.
- [x] Flutter checkout repository path added behind `USE_SUPABASE_CHECKOUT`, which defaults to false and additionally requires Supabase Auth session.
- [x] Node tests cover server-derived pricing/totals, invalid/unapproved/stock-limited requests, payment provider status/identity/amount validation, auth gates, idempotency guards, and cancellation/ledger SQL safeguards.
- [ ] Review/apply schema only after explicit approval; no live SQL was run.
- [ ] Deploy/configure Edge Functions and run Supabase staging authorization and transaction tests.
- [ ] Test Razorpay test-mode create/capture/replay/recovery end to end; no payment test was performed.
- [ ] Parse/apply only in approved isolated staging and run real transaction/concurrency tests; no PostgreSQL parser or local Supabase CLI is available here.
- [ ] Integrate the Express fallback with the same inventory ledger or isolate it as the only active writer before enabling the Supabase checkout flag.
- [x] Add a local-only, service-role-protected reconciliation ledger and guarded full-refund path for captured payments rejected by definitive order-finalization business rules; tests cover allow-listed failures, provider match checks, and no-blind-retry structure.
- [ ] Exercise refund recovery against Razorpay test mode and PostgreSQL staging, including timeout after provider acceptance, concurrent retries, provider-pending status, and manual reconciliation. No SQL was run and no payment was sent.
- [ ] Coordinate checkout stock reservations/expiry with the still-active Express inventory writer before enabling checkout; current stock deduction is atomic at final order commit but a paid order can still fail if stock changes during payment.
- [ ] Migrate shop delivery/refund operations as one authorized transaction so confirmed shortage quantities restore stock once, refunds/adjustments are persisted, and original order values remain immutable. Shop operations remain on Express; the Supabase checkout flag stays disabled.
- [ ] Verify the existing shop assignment and reward semantics against actual staging records before enabling the flag.

## Local checkout lifecycle review (2026-10-27)

- [x] `npm test`: 59/59 passed, including 8 focused Supabase checkout tests.
- [x] `node --check` for the shared checkout rules and targeted `git diff --check` passed.
- [x] Dart formatter applied to the touched Supabase checkout repository.
- [ ] Flutter analyzer did not complete in this environment (no diagnostics were returned before interruption).
- [ ] PostgreSQL parsing/transaction tests, Edge Runtime tests, Razorpay sandbox tests, and real Supabase integration were not run. No SQL was executed and no Edge Function was deployed.

## Local captured-payment recovery review (2026-10-27)

- [x] Added `supabase/drafts/unreconciled/20261028_checkout_refund_reconciliation.sql` as a separate, unapplied draft. It creates a private reconciliation ledger with unique payment identity and a state claim before any refund request.
- [x] `verify-razorpay-payment` now recovers only allow-listed definitive database business rejections; it checks Razorpay's existing refunds before the one-time refund POST and records submitted, refunded, or needs-review outcomes.
- [x] Tests cover definitive vs ambiguous failures, provider payment/amount/currency matching, service-role-only grants, and ordering of provider lookup, DB claim, and POST.
- [ ] No PostgreSQL/Edge Runtime/Razorpay test was available. A crash after claiming but before the provider request intentionally fails closed into manual reconciliation rather than risk a duplicate refund.
- [ ] This compensates a subset of captured-payment failures; it is not an automatic refund platform. Provider-pending refunds need admin monitoring, and transient/ambiguous database failures remain retry/support cases rather than triggering a refund.

## Admin Dashboard migration audit (2026-10-27)

Verified locally from `lib/admin_web_main.dart`, `lib/features/admin/data/admin_repository.dart`, `server.js`, and `shop_routes.js`: the web app uses a separate bearer-token admin session and these Express-backed capabilities. It has not been migrated to Supabase.

| Admin capability | Existing Express source | Supabase migration stage |
|---|---|---|
| Admin login/session/logout | `POST /api/admin/login`, `GET /api/admin/session`, `POST /api/admin/logout` | Supabase Auth password session for pre-provisioned admin identities; require trusted `app_metadata.role=admin`; provide a controlled provisioning/revocation process before cutover |
| Dealer list, approval/status, deletion | `GET /api/admin/dealers`, `POST /api/admin/set-status`, `DELETE /api/admin/users/:id` and `/dealers/:id` | Admin-only Edge Function/RPC; approval remains server-side, auditable, and never dealer-editable; deletion requires separate retention/foreign-key policy review |
| Dashboard stats and analytics | `GET /api/admin/dashboard-stats`, `GET /api/admin/analytics` | Read-only, admin-verified Edge Function or stable SQL views/RPC with bounded date filters; avoid exposing raw user/payment data to the browser |
| Product CRUD and stock | `GET/POST /api/admin/products`, `PUT/DELETE /api/admin/products/:id` | Admin Edge Function validates SKU/category/prices/stock; no direct client table grants; prefer deactivate over destructive delete where orders reference products |
| Bulk products | `POST /api/admin/products/bulk`; Flutter Web parses Excel/CSV before posting | Browser parser can remain; Edge Function validates the entire batch, detects duplicate SKUs, applies an atomic import or returns per-row errors, and never trusts purchase price from an unauthorized role |
| Category CRUD | `GET/POST /api/admin/categories`, `PUT/DELETE /api/admin/categories/:id` | Admin Edge Function; preserve current product/category relationship behavior and avoid deleting referenced categories without a safe reassignment rule |
| Orders, fulfillment, payment/invoice status | `GET /api/admin/orders`, `PUT /api/admin/orders/:id/status`; Admin Web derives Payments/Invoices views from loaded order records | Read through admin-only Edge Function/RPC; status/payment writes must validate provider evidence or actual COD collection; invoice metadata cannot imply payment |
| Shop administration | `GET/POST /api/admin/shop/employees`, `PUT /api/admin/shop/employees/:id/active`, `PUT /api/admin/shop/orders/:orderId/assignment` | Keep on trusted Edge Functions only after employee identity/assignment model is mapped; never expose password hashes or allow client-chosen shop identity |
| Enquiries, notifications, refunds | `GET /api/admin/shop/enquiries`, `GET /api/admin/shop/notifications`, `PUT /api/admin/shop/orders/:orderId/refund` | Admin/employee-scoped Edge Functions; refunds require durable idempotency, authorization, and provider/billing evidence; notification data must be scoped |
| Product/category images | Web form sends image through existing Express upload flow; `SupabaseImageStorage` helper exists but requires Supabase admin app metadata | Create/verify Storage bucket and admin-only upload function/policies; inventory and migrate existing image files/URLs before removing Express uploads |

**Admin migration order:** (1) provision Supabase admin identity and test revocation/role denial; (2) migrate read-only dashboard stats and catalog reads; (3) product/category CRUD and Storage; (4) validated bulk import; (5) dealer approval; (6) orders and analytics; (7) shop assignment, delivery/refunds, notifications; (8) parity/browser tests and only then remove Admin Web's Express dependency. Each stage should remain behind a false-by-default flag and retain the Express rollback path.

**Unverified/admin risks:** live admin accounts are not confirmed linked to Supabase Auth; no admin role provisioning mechanism exists in the audited Flutter code; Storage bucket deployment and persistent object migration are not verified; no Edge Function parity, RLS integration, browser tests, or deployment has been performed. The web UI currently loads admin data through Express and keeps the Express token in secure storage; no code was changed to alter that flow in this stage.

### Local Admin Orders read pilot (2026-10-27)

- [x] Added `admin-orders` as a read-only Edge Function draft using verified Supabase Auth and server-controlled `app_metadata.role=admin` before any privileged table query.
- [x] The repository selects explicit order and order-item columns, omits purchase price, GST identifiers, PAN, password hashes, and other unused order columns, pages results with bounded order/item counts, and sanitizes database errors.
- [x] Delivery rows use `delivery_confirmed` where present and fall back to legacy `delivered` only when that column is missing. Delivered quantities count only after confirmation. Financial calculations use the immutable order-item `unit_price` snapshot.
- [x] Response shape follows the existing Express Admin Orders contract, including payment and delivery status, employee attribution, and the current single-shop fallback. It does not query the absent `shop_order_assignments` table.
- [x] Added `USE_SUPABASE_ADMIN_ORDERS`, false by default, and route only `GET orders` to the Edge Function when an authorized Supabase admin session exists. Writes and other admin routes remain on Express.
- [ ] Verify schema compatibility, role denial, totals, delivery variants, and response parity against an isolated Supabase staging project. The function is not deployed and the flag remains disabled.
- [ ] Run browser tests for empty/multiple orders, delivery states, and page reload before marking the route migrated.

The `/api/admin/set-status` approval action now has a local `admin-dealer-approval` Edge Function path. This pilot uses the current `users.id`, `email`, `mobile`, `status`, and `is_approved` fields and requires no SQL migration. `USE_SUPABASE_ADMIN_DEALER_APPROVAL` defaults to false; Express remains the default and fallback. Node handler tests pass, but the Flutter route test and remote Auth/PostgreSQL/browser checks remain pending. See the dated local admin dealer-approval stage above.

### Local Admin Analytics read pilot (2026-10-28)

- [x] Added a read-only `admin-analytics` Edge Function pilot for `GET /api/admin/analytics`, retaining the existing `period` query behavior and JSON response fields (`revenue`, `chart`, `topProducts`, `lowStock`).
- [x] The function verifies the Supabase bearer token with Auth and requires a confirmed email plus trusted `app_metadata.role=admin` before database reads. It uses explicit non-secret projections from `orders`, `order_items`, and `products`, bounded pagination, sanitized errors, and no writes or schema changes.
- [x] Added the Flutter Web route adapter and `USE_SUPABASE_ADMIN_ANALYTICS` flag, default false. Only the analytics GET is eligible; Express remains the default and no failed request is replayed through Express after an opted-in request.
- [x] Local unit tests cover revenue and chart payloads across periods, canceled-order exclusion, top products, low stock, safe projections, malformed data, error sanitization, method restrictions, and admin authorization.
- [ ] Not deployed or compiled with Deno; PostgreSQL column compatibility, edge authorization, browser rendering/parity, timezone parity with the old host, and real production dataset bounds remain unverified. No migration SQL is required by this pilot.

### Local Admin Order Status mutation pilot (2026-10-28)

- [x] Added an `admin-order-status` Edge Function and Flutter Web route adapter for only `PUT /api/admin/orders/:id/status`; its own `USE_SUPABASE_ADMIN_ORDER_STATUS` flag defaults to false.
- [x] Added the local-only RPC draft `supabase/drafts/unreconciled/20261028_admin_order_status.sql`. It creates no tables and updates no records on installation; the function locks the order and order items, checks a confirmed Auth user with trusted `raw_app_meta_data.role=admin`, blocks status overrides after Shop delivery records exist, and prevents direct clients from executing the RPC. Execution is granted only to the server's service role.
- [x] Added handler/repository/route tests and included the SQL draft in the disposable local PostgreSQL harness to verify service-role authorization, ordinary-role denial, non-admin denial, missing order handling, incomplete Delivered rejection, and delivery-owned status protection.
- [ ] Not deployed or tested against Supabase Auth/PostgREST/browser. This draft assumes the audited existing `shop_delivery_items` columns are present. Shop delivery must use compatible order/item locking before this RPC can be considered race-safe across both writers; verify that in staging before enabling.

## Latest local verification (2026-10-28)

- `npm test`: 140 passed, 0 failed, 1 skipped (opt-in local PostgreSQL test).
- `scripts/test-supabase-staging-local.ps1`: 1/1 passed after extending the disposable Storage metadata fixture and exercising stage 005 twice.
- Full Flutter suite: 78 passed, 0 failed, 4 preview-gated tests skipped. A stale `Product Description` expectation was corrected; product import code was already returning the template description correctly.
- Full Flutter analysis before the local checkout lint fix: 27 informational lints, no warning/error diagnostics, exit code 1 because info-level diagnostics are treated as failure. Targeted Dart analysis for the changed checkout/Supabase route files after the fix reports no issues.
- Deno 2.9.6 checked all 14 local Edge Function `index.ts` entrypoints successfully (`--no-config --no-lock`); this validates source/type resolution only, not deployed runtime behavior.
- Live read-only audit: connected to the existing configured project; 15 public tables, RLS on all, rows present in 11, zero public/Storage policies, no Storage buckets, and one public function. No business values were read.
- No production SQL, Storage object, function deployment, project setting, feature flag, or release APK changed. All Supabase flags remain disabled and Express remains active.
- Still unverified: Supabase Auth/email/provider settings, production function inventory, staging SQL/Auth/PostgREST/Storage integration, browser and real-device paths, image migration, Razorpay/payment verification, and full route parity.

### Local Auth password-change slice (2026-10-28)

- [x] Added a default-off Supabase Auth path for the existing profile password-change interaction. When `USE_SUPABASE_AUTH` is enabled and a verified Supabase session exists, the app verifies that the session email matches the displayed profile, reauthenticates using the current password, and updates only if the authenticated user ID remains unchanged.
- [x] Preserved the existing Express `/api/user/change-password` fallback when the Supabase Auth path is disabled or no Supabase session exists. No UI fields, password storage, database schema, or approval state changed.
- [x] Added an isolated Dart unit test for reauthentication ordering, identity mismatch, failed reauthentication, and minimum password validation, plus Node source-contract tests for the adapter and route gating.
- [x] Direct SDK `dart.exe format` formatted the four touched Dart files and completed with no changes on the final pass. The `dart.bat` wrapper stalled.
- [x] Focused Node source-contract tests: 3/3 passed. Full `npm test`: 143 passed, 0 failed, 1 skipped (opt-in PostgreSQL test).
- [x] The sandboxed Flutter invocation could not access the SDK cache lockfile. ACL inspection showed the file was accessible and an exclusive read found no held handle; no lockfile was deleted. Running the Flutter SDK tool with approved access outside the sandbox completed the focused tests.
- [x] Focused Flutter tests on final source: 9 passed, 0 failed, 1 preview-gated test skipped. This includes the password-policy test and compilation of the adapter/Profile screen, Supabase flag defaults, catalog fixtures, and category matching/navigation.
- [x] Disposable local PostgreSQL staging harness: 1/1 passed, including staged catalog/RLS assertions. Synthetic data only; Supabase Auth/PostgREST/Storage runtime remains unverified.
- [x] Full `npm test`: 143 passed, 0 failed, 1 skipped; `git diff --check` passed (line-ending warning only).
- [ ] Targeted `dart analyze` stalled after its initial analysis message. Focused Flutter test compilation passed, but full static analysis remains unverified.
- [ ] Supabase Auth provider/session behavior and password update were not tested against staging. No live setting or database change was made; flags remain disabled and Express remains active by default.

### Existing-project dealer profile/address verification (2026-10-28)

- [x] Applied the additive `002_dealer_profile_addresses.sql` draft only to the repository's disposable local Supabase stack (`ro_catalog_local_test`, loopback ports 54331/54332). The migration's profile-link RPC, RLS, address RPCs, and grants were exercised through local Supabase Auth and PostgREST; no hosted project was created or modified.
- [x] The first integration attempt exposed that direct dealer profile `PATCH` requires broader `users` SELECT privileges than the design allows. Replaced direct profile updates with `ro_update_current_dealer_profile`, which derives the authenticated dealer server-side, validates editable fields and rejects a mobile already assigned to another dealer. Direct table UPDATE is not granted.
- [x] The passing local integration test used two synthetic Auth identities and verified new profiles remain pending, each dealer reads/updates only its own profile and addresses, duplicate mobile rejection, protected approval fields, default-address replacement, foreign-address read/default/save/delete denial, and own-address deletion. Catalog visibility/purchase-price denial and public-image read/admin-only upload checks also passed in the same run.
- [x] `npm test`: 143 passed, 0 failed, 2 skipped (145 total; opt-in PostgreSQL tests skipped by default). Node syntax checks passed. The guarded local Supabase Auth/PostgREST/RLS/Storage test passed 1/1.
- [x] `flutter test test/supabase_dealer_data_mapping_test.dart`: 7 passed. Targeted `flutter analyze lib/core/supabase/supabase_dealer_data_repository.dart`: no issues found.
- [ ] Hosted Auth identity linking, actual email delivery, live PostgREST behavior, and production data compatibility remain unverified. Production `USE_SUPABASE_DEALER_DATA` stays false, Express remains default, and no SQL/deployment/settings/data changes were made.

### Local order-history continuation verification (2026-10-29)

- [x] `npm test`: 143 passed, 0 failed, 2 skipped. Corrected a stale contract assertion that still expected the removed unverified JWT email fallback.
- [x] `scripts/test-supabase-staging-local.ps1`: disposable local PostgreSQL harness passed 1/1 for dealer isolation, stock bounds, and safe cart retries. A sandboxed attempt could not access Docker; the same repository test was then run with approved Docker access. It did not connect to the hosted project.
- [x] Disposable local Supabase Auth/PostgREST/RLS/Storage integration passed 1/1 with synthetic fixtures, including verified versus unverified legacy-email access checks. Flutter was not rerun in this SQL/test-only continuation; the prior focused Flutter result remains 7/7 as previously reported.
- [x] Targeted Node syntax checks passed. No hosted SQL, function deployment, feature-flag change, production data/settings change, or APK build occurred.

### Local admin catalog and bulk-import SQL verification (2026-10-29)

- [x] Extended the disposable PostgreSQL harness to apply `20261029_admin_catalog.sql` and `20261030_admin_bulk_import.sql` only to the empty loopback test database.
- [x] Category RPC checks passed: authenticated direct execution denied; verified non-admin identity denied even via service role; authorized admin create/update/delete succeeded; renaming synchronized product category keys; deleting a referenced category moved the synthetic product to Spares.
- [x] Bulk import RPC checks passed: valid product inserted; an existing SKU and duplicate SKU within the batch were skipped; retrying the same request fingerprint returned the stored response without a duplicate insert; malformed price was rejected with no partial product row.
- [ ] Product single-item CRUD still has handler-level tests only. Supabase Edge Runtime/Auth token binding, Storage upload through the function, browser integration, and hosted schema compatibility are not verified. Admin flags remain false and Express remains default.

### Checkout, payment, and delivery migration gate (2026-10-29)

- [x] The full Node suite passed the existing checkout/payment unit and contract tests as part of the 143 passing tests, including price/stock validation, request idempotency, Razorpay signature checks, and refund-reconciliation state handling.
- Historical status at this checkpoint (superseded by the dated follow-up below): checkout/payment drafts had not yet passed the PostgreSQL harness, and delivery had no Supabase mutation. The following section records later local checkout/payment and delivery SQL tests; hosted compatibility and Edge Runtime remain open.
- [ ] Razorpay sandbox credentials/provider calls, COD production semantics, cancellation/restocking, and duplicate refund behavior are not verified against a real or isolated provider/backend integration.
- [x] Express remains the active fallback; checkout, payment, inventory, delivery, and refund flags remain false. No hosted SQL, deployment, payment setting, or production data was changed.

### Local checkout/payment follow-up and Admin Catalog Edge Runtime attempt (2026-10-29)

- [x] `npm test`: 143 passed, 0 failed, 2 skipped (145 total; opt-in PostgreSQL test skipped by the default suite).
- [x] `scripts/test-supabase-staging-local.ps1`: 1/1 passed on a disposable loopback PostgreSQL 15 container. It applied checkout, refund-reconciliation, and the new shop-delivery draft and exercised server-derived prices/totals, unapproved dealer rejection, insufficient stock rejection, COD order commit and one-time stock deduction, idempotent COD retry, cancellation/restock once, refusal to restock after delivery activity, Razorpay-session amount matching, paid finalization replay, COD cancellation denial for paid orders, one-time refund-reconciliation claiming, employee authorization, explicit delivery statuses, partial/full calculations, COD collection once, and adjustment retry protection. Shop employee/assignment Auth identities and notification schema in this fixture were synthetic; this does not establish compatibility with the existing Supabase schema.
- [x] Payment verification helper/contract tests passed in the Node suite, including Razorpay signature validation and replay safeguards. No Razorpay sandbox/provider request was made; local SQL finalization was called directly with synthetic verified payment identifiers and does not verify the Edge Function's provider verification path.
- [ ] `scripts/test-supabase-catalog-local.ps1` reached the local Auth/Storage test cleanup but exited 1 because its cleanup request returned HTTP 400. Since the test output/exit cannot be independently recovered from that run, no Admin Catalog/Bulk Import Edge Runtime result is credited as passing. Catalog/category/bulk SQL RPC PostgreSQL coverage remains passing as recorded above; actual Edge Function Auth/Storage execution and browser behavior remain unverified.
- [x] Updated the local catalog integration harness to use the cached Supabase CLI, a temporary process-only CLI profile, a strict empty-public-schema/loopback guard, and no automatic database reset. The cleanup path now avoids retaining/deleting the image fixture when Flutter is explicitly skipped. This final harness revision has not been rerun; the current disposable local database contains synthetic fixtures from the attempted run, so it will fail closed until a fresh empty local Supabase stack is prepared.
- [x] Added local-only `supabase/drafts/unreconciled/20261031_shop_delivery.sql` plus `shop-delivery` Edge Function and shared request/repository handler. SQL is additive: nullable employee Auth linking, empty explicit order assignments, explicit confirmation flag, and a unique COD collection ledger; existing rows are not automatically assigned or linked. RPC derives employee and shop from verified Auth linkage, checks assignment, locks order/items, requires explicit item status, calculates from order-item unit-price snapshots, keeps original order totals immutable, and records shortages as admin-review notifications rather than issuing a refund.
- [x] Added unit coverage in `test/supabase_shop_delivery.test.cjs` (5/5 passed) for missing/dealer/unverified Auth, payload allow-listing and independent status booleans, bad quantities/duplicate rows, privileged RPC arguments, sanitized errors, and payment/collection attestation gating.
- [ ] Delivery Edge Function/Deno runtime, employee Auth provisioning and linking, assignment management UI/API, Storage-independent deployment, concurrent transaction behavior through PostgREST, and Admin Web reload are not yet verified. Live schema lacks `shop_order_assignments`, employee Auth links and `shop_delivery_items.delivery_confirmed`; do not apply this draft before reviewing actual column types, duplicate `order_item_id` rows/indexes, and a secure account-link workflow.
- [ ] Checkout/payment remain local drafts, not a complete API migration. `20261027_secure_checkout.sql` and `20261028_checkout_refund_reconciliation.sql` are not deployed. Current tests do not cover Razorpay HTTP provider calls/webhooks, shared Express/Supabase inventory writers, real assignment data, invoice/reward parity, or Supabase Edge Runtime behavior.
- [x] No hosted SQL, function deployment, production setting/data change, feature-flag change, backend restart, or APK build was performed. Express remains the active fallback; all Supabase flags remain disabled.

#### Final local verification after delivery draft

- [x] `npm test`: 148 passed, 0 failed, 2 skipped (150 total).
- [x] `node --test test/supabase_shop_delivery.test.cjs`: 5 passed, 0 failed; Node syntax checks and targeted `git diff --check` passed.
- [x] Latest `scripts/test-supabase-staging-local.ps1`: 1/1 passed. Delivery coverage includes draft save without confirmation/notification, partial then full confirmation using stored line-price snapshots, immutable order total, partial COD denial, authorized full COD collection, retry without duplicate collection, denied dealer RPC call, private assignment/cash tables, and preventing quantity changes after a processed refund.
- [ ] Admin Catalog/Bulk Import local Auth/Storage Edge Runtime command returned exit code 1 because the fixture cleanup endpoint returned HTTP 400. The final revised script now skips automatic DB reset, refuses non-empty public schemas, and avoids retaining the image fixture when Flutter is skipped, but could not be rerun against the now non-empty disposable database. Thus no Edge Runtime pass is claimed.
- [ ] Deno/Edge runtime type-check for the new `shop-delivery` entry point was unavailable because Deno is not on PATH/in the checked install locations. The handler is covered by Node unit tests; no deployed/runtime test has been run.

**Next safe stage:** rerun Admin Catalog/Bulk Import on a newly empty disposable local Supabase runtime and capture the complete Edge test result (the current local public schema contains synthetic fixtures, and the harness now refuses to reset it). In parallel, add a trusted admin employee provisioning/link and order-assignment flow; then test the `shop-delivery` Edge Function against that local Auth runtime. No hosted operation is authorized by this checklist.

### Isolated Edge Runtime retry and current verification (2026-10-29)

- [x] Parameterized the local catalog integration harness with explicit temporary workdir, project ID, and loopback API/database ports. The empty-schema assertion and Edge test now read those expected ports; the harness still rejects linked project metadata and any pre-existing public tables and never runs `db reset`.
- [x] `npm test`: 148 passed, 0 failed, 2 skipped (150 total). `node --test test/supabase_shop_delivery.test.cjs`: 5 passed, 0 failed. `scripts/test-supabase-staging-local.ps1`: 1 passed, 0 failed against its disposable loopback PostgreSQL container. `git diff --check` passed for the migration/test files reviewed in this stage.
- [x] Attempted a fresh local Supabase CLI stack using a new temporary project ID/workdir and unique loopback API/database/shadow ports. The existing project ID/workdir was not reused and no linked `project-ref` was present. Docker diagnostics showed uncached Supabase Storage/Postgres image pulls; no containers for the new profile started and its ports stayed closed. Only the CLI process launched for this attempt was stopped; existing local Supabase and MySQL containers were left running.
- [ ] Admin Catalog/Bulk Import Auth/PostgREST/Storage Edge Runtime tests remain unverified: the fresh stack could not start because its required local images did not finish pulling. The earlier run exited during fixture cleanup with HTTP 400, and is not counted as a pass.
- [ ] Shop Delivery Edge Runtime/Auth integration remains unverified for the same local runtime blocker. Only its 5 Node handler tests and the PostgreSQL RPC transaction tests pass; the function has not been exercised through the local Auth/Edge Gateway.
- [x] No hosted Supabase command, SQL, deployment, production setting/data change, migration flag change, Express change, or APK build occurred. The 66-route inventory remains unchanged in disposition; Express remains active and all Supabase flags remain disabled.

**Next action:** make the missing local Supabase Docker images available to the local Docker engine (or restore Docker image-pull connectivity), then rerun `scripts/test-supabase-catalog-local.ps1` with a newly empty, isolated workdir/ports. After that passes, use the same local Auth runtime to test `shop-delivery`; do not reuse the fixture-filled catalog database or apply anything remotely.

### Repeat verification attempt (2026-10-29)

- [x] Repeated the full Node suite and disposable PostgreSQL checkout/payment/delivery harness after the prior entry: Node remains 148 passed, 0 failed, 2 skipped; PostgreSQL remains 1 passed, 0 failed. No regression was found.
- [ ] A further local Edge Runtime image-pull attempt was stopped after layer initialization stalled without a registry error or a new image becoming available. The existing local Auth/Storage stack was left running; no function was served in this attempt.
- [x] Re-ran `npm test`: 148 passed, 0 failed, 2 skipped. The skipped tests are opt-in staging/integration checks, not failures.
- [x] Re-ran `scripts/test-supabase-staging-local.ps1`: 1 passed, 0 failed. This verifies the local PostgreSQL draft transactions for checkout, payment finalization/reconciliation, cancellation/restocking, and delivery calculations/authorization only.
- [x] Re-ran `node --test test/supabase_shop_delivery.test.cjs`: 5 passed, 0 failed; relevant JavaScript syntax checks passed.
- [ ] Retried the isolated Supabase Auth/Storage/Edge Runtime stack with a new temporary workdir and non-conflicting loopback ports. Startup reached Docker image pulls but did not progress or start containers. The CLI requested newer Postgres and Storage image tags than those cached locally; the download was interrupted after making no visible progress. No database container or function runtime for the new test profile started, and the prior fixture-filled stack was not reused.
- [ ] Admin Catalog and Bulk Import Edge Function integration, including authenticated CRUD/import and Storage upload, remains unverified. Shop Delivery Edge Function runtime/Auth remains unverified. Do not infer those tests from the passing SQL/handler tests.
- [x] No hosted project, remote SQL, deployment, production data/settings, feature flags, Express fallback, or APK was changed.

**Next action:** restore image-pull availability for the Supabase CLI-required local Postgres/Storage image tags, then rerun the catalog Edge test from a fresh isolated workdir. Once Admin Catalog/Bulk Import passes, test Shop Delivery through local Auth and the Edge Gateway.

### Continued local runtime and production-review work (2026-10-29)

- [x] Rechecked the local migration state and hosted-project audit documents. The existing project is data-bearing; no separate hosted project is in scope. `supabase/migrations/` still has no executable versioned migration set; staging SQL and unreconciled drafts are not safe to run remotely as-is.
- [x] Added `SUPABASE_PRODUCTION_DEPLOYMENT_REVIEW.md` with the existing candidate SQL files, dependency order, schema/data/security impacts, deployment command forms, prerequisites, and explicit approval gates. It does not authorize or execute a production operation.
- [x] Retried the required local Docker image pull. Docker could reach registry metadata and announce layers, but the image did not complete or produce a specific transport error. The pull was interrupted; no unrelated container was stopped or removed. This does not establish whether the cause is registry throttling, Docker Desktop transport, or another layer-delivery issue.
- [x] Repeated verification results available in this checkpoint: `npm test` 148 passed, 0 failed, 2 skipped (150 total); `scripts/test-supabase-staging-local.ps1` 1 passed, 0 failed; `node --test test/supabase_shop_delivery.test.cjs` 5 passed, 0 failed. These are Node/local-PostgreSQL tests only.
- [ ] Admin Catalog/Bulk Import through local Supabase Auth, Storage and Edge Gateway remains unverified. The prior API cleanup failed with HTTP 400; the new isolated Supabase runtime cannot start until its uncached Docker images finish pulling.
- [ ] Shop Delivery through local Auth/Edge Gateway remains unverified. Handler unit and PostgreSQL transaction tests do not prove Edge Runtime deployment behavior.
- [ ] A fresh `flutter test --no-pub` attempt remained silent for approximately 40 seconds and was interrupted; it produced no test results. Prior focused Flutter tests recorded earlier (7/7) are not a result for this attempt. Diagnose the Flutter/Dart runner lock before claiming current Flutter verification.
- [x] Docker diagnosis: daemon is responsive; the current shell has no HTTP(S) proxy variables, while `docker info` reports a configured proxy. Registry manifest and redirect metadata are reachable from the host, but layer pulls stall. The proxy host resolves from a running local container, while its configured port 3128 is not reachable from that container. This is a strong proxy-path suspicion, not conclusive proof of the daemon's exact layer failure. No image completed downloading.
- [x] Confirmed the required `storage-api:v1.84.19` tag is not cached and the currently running disposable local stack still uses cached Storage `v1.80.2` and Postgres `17.11.0.003`. Existing local Supabase and MySQL containers remain up; none were stopped or reset. Correcting the Docker Desktop proxy/direct setting may restart the engine and interrupt these containers, so it was not changed under the current no-stop instruction.
- [x] Read-only health checks on the existing disposable local stack returned Auth HTTP 200 and Storage HTTP 200. These are service-health checks only, not functional Auth/Storage/RLS/Edge integration tests.
- [x] Focused Node authorization/validation tests for Admin Catalog, dealer approval, and Shop Delivery passed 20/20. The tests exercise handlers/repositories with fakes; they do not count as Edge Runtime/PostgREST integration.
- [ ] No hosted schema, Auth/Storage configuration, production data, Edge Function, feature flag, Express fallback, APK, or dashboard deployment was changed. Fresh production schema compatibility, Deno checks, Flutter/browser integration, SMTP and Razorpay sandbox behavior remain outstanding.

**Next safe action:** restore Docker image-layer downloads, then create a fresh isolated local Supabase runtime and rerun Admin Catalog/Bulk Import Edge tests followed by Shop Delivery Edge tests. Do not apply the existing draft files to the hosted project. The exact candidate file order and each data impact are documented in `SUPABASE_PRODUCTION_DEPLOYMENT_REVIEW.md`; final executable SQL still requires reconciliation against a fresh read-only live schema snapshot and separate approval.

### Railway API recovery attempt (2026-10-29)

- [x] Railway sign-in completed. The linked production project is `motivated-light`; the existing `RO_MobileApp` service URL is `https://romobileapp-production.up.railway.app`.
- [x] The app service and its attached legacy MySQL service are offline. All returned recent app deployments are marked `REMOVED`; there is no running API deployment.
- [x] Inspected Railway variable names without displaying values. Existing database variables are legacy `DB_*` settings; the current backend uses PostgreSQL via `SUPABASE_DB_URL`/`DATABASE_URL` or PostgreSQL host variables.
- [x] Configured the Railway service with the existing Supabase database URL, project URL, publishable key under the backend's expected anon-key name, CA certificate path, existing admin/session settings, Google client ID, and production Node environment. All values were sent through stdin and suppressed; automatic deployments were skipped. No SQL, schema, or database data changed. `AUTO_APPLY_SCHEMA` was not configured.
- [x] Added `/health`, which performs only `SELECT 1` and returns status without database detail. Added `.gitignore` entries for local JSON database snapshots so they are not included in future uploads. Targeted syntax/diff checks passed.
- [x] The current Node backend ran locally against the existing Supabase connection: `/health` returned HTTP 200; `/api/products` returned HTTP 200 with 19 actual products. The sanitized read-only schema audit confirmed the target project, 15 public tables, and existing records; it found no public RLS policies, Storage buckets, or deployed Edge Functions.
- [x] `npm test`: 148 passed, 0 failed, 2 skipped (150 total).
- [ ] Railway deployment was attempted but blocked by: `Your trial has expired. Please select a plan to continue using Railway.` The service remains offline; remote `/health` and `/api/products` remain unverified. The APK must not be represented as ready to share.
- [ ] Supabase direct-client migration flags remain disabled. No hosted SQL or Edge Functions were deployed. Razorpay keys are absent locally, so real Razorpay checkout is not configured; image uploads remain filesystem-backed until Storage migration is completed.
- [ ] Once deployment access is restored, verify remote health/product endpoints and critical auth/order routes, then rebuild the APK against the reachable production API before sharing.
