# RO Wholesale App: existing Supabase project migration plan

**Status:** local preparation and disposable local testing only. The target is the existing project `czegmfzntnfpwaxgczds`; do not create or use another hosted project. No production SQL, data, Auth setting, Storage setting, or feature flag has been changed, and no function has been deployed. The repository's CLI link metadata points to the existing project. Each staged SQL file is generic `public`-schema SQL and cannot enforce project identity. Before any operation against the existing project, perform a read-only preflight, present the exact reviewed change and impact, and obtain explicit approval. Keep Express as the production fallback.

## Audited architecture and route coverage

The Flutter/Dart customer and shop app and Flutter Web Admin currently call the Node.js/Express API (`server.js`, `order_checkout.js`, `shop_routes.js`). Express uses the existing Supabase PostgreSQL database through `db.js`; it remains the authoritative production writer. Supabase Auth, Storage, Data API, RPC, and Edge Function changes are local opt-in drafts.

`MIGRATION_ENDPOINT_INVENTORY.md` is the route-by-route inventory. The audited API families are: dealer/Auth/OTP and profile; address/cart/order history/rewards/support/invoices; public products/categories; admin auth/dealers/catalog/bulk/orders/analytics; Razorpay order/payment verification and checkout; shop employee auth/orders/delivery/products/enquiries/reports; admin shop employees/assignment/enquiries/notifications/refunds. External services in source are SMTP/Nodemailer, Google OAuth, Razorpay, local filesystem image uploads, and Puppeteer PDF generation. Static `/admin` routes are not API endpoints.

The current client-side opt-in status is not equivalent to production migration: catalog reads, dealer data, checkout, Admin catalog, and bulk import flags all default off. Profile/address/cart/order-history/rewards/support repositories exist. Stage 002 now passes the disposable local Supabase Auth/PostgREST/RLS test with synthetic identities; cart/history also have local SQL harness results. No separate hosted staging project will be created. The existing hosted project is data-bearing and remains read-only until a precise change is approved. Profile edit is routed through an owner-derived RPC behind the dealer-data flag; invoice rendering, password operations, checkout/payment, admin writes, and shop operations stay on Express.

## Live-schema reconciliation (read-only metadata audit)

Verified live `public` objects: the 11 core application tables (`users`, `user_addresses`, `categories`, `products`, `orders`, `order_items`, `rewards_history`, `otp_codes`, `support_tickets`, `cart_items`, `payment_sessions`) plus four shop tables (`shop_employees`, `shop_delivery_items`, `shop_admin_notifications`, `shop_product_enquiries`). No application rows were selected.

Verified schema/security deltas:

- `shop_order_assignments` is absent. The previous broad auth/RLS draft and checkout draft both require it; checkout also writes it. Those files must not be applied as one migration.
- `users.auth_user_id` and `catalog_products` are absent. The first is added in staged phase 002; the second is created in staged phase 001.
- The live schema has no `public` RLS policies. RLS is enabled, but `anon` and `authenticated` currently have broad table grants. The new staging files revoke client grants only on tables in that phase, then grant exact read/update/delete columns and protected RPC execution.
- Read-only audit on 2026-10-28 found no Storage bucket or Storage policy; `storage.objects` RLS is enabled. `supabase/staging/005_product_image_storage.sql` now prepares the narrowly scoped product-image bucket, but it is local-only and unexecuted.
- `user_addresses` has additional live address columns not present in the original base schema draft; phases 002 preserves them.
- Several money fields are unbounded PostgreSQL `numeric`, while MySQL and the old base SQL specify bounded decimal precision. Do not narrow or cast populated columns until staging data is audited.
- Core foreign keys were verified for user/address/cart/order/order-item/reward/support/product/category relationships. Shop delivery FKs exist, but there is no assignment table relationship. A shop migration also expects a `delivery_confirmed` column that is not currently present.
- The live Express database role is non-superuser with `BYPASSRLS`; it remains compatible with the staged client-grant changes. Supabase API roles require the RLS policies.
- The prior Express password and Google signup handlers auto-approved new dealers. The local Express source now creates them pending and blocks password/OTP/Google/token-exchange sessions until admin approval. Existing records were not changed and the active server was not restarted; validate this behavior after the normal deployment/restart. The mismatch is corrected in source, but admin approval parity remains an integration gate.

The five previous files were moved from `supabase/migrations/` to `supabase/drafts/unreconciled/` without changing their SQL contents. They are drafts, not a runnable production migration chain. This prevents a routine Supabase CLI push from auto-applying the unverified checkout/admin bundle. The `supabase/migrations/` directory intentionally contains no SQL until an ordered, reviewed set is ready.

## Ordered existing-project rollout

| Stage | Local SQL / action | Scope and gate |
|---|---|---|
| 0 | Test the reviewed SQL and RLS policies against the disposable local Supabase stack; do not create a hosted project | No production writes. Do not clone real personal data into an uncontrolled environment. Confirm Auth roles, PostgreSQL version (15+), extensions, and migration history. |
| 1 | `supabase/staging/001_catalog_read.sql` | Public categories + active product catalog only. Column-level grants, RLS, `security_invoker` view; no purchase price or write access. Validate product response and image URLs. |
| 2 | `supabase/staging/002_dealer_profile_addresses.sql` | Add Auth link column/FK/index, verified self-link RPC, self-profile read RLS, owner-derived profile-update RPC, and address list/save/default/delete. No direct `users` UPDATE is granted. New accounts stay pending. Synthetic local Supabase Auth/PostgREST tests pass; production email delivery is not verified. |
| 3 | `supabase/staging/003_dealer_cart.sql` | Dealer-owned cart read/delete and stock-locked add/update RPC. Preflights required columns, the exact existing valid non-partial unique `(user_id, product_id)` index, and absence of the RPCs/request ledger. Add requests use a persisted request UUID and private ledger to make retries idempotent. Checkout/order creation remains Express. |
| 4 | `supabase/staging/004_dealer_order_history.sql` | Owned order/item and reward reads plus scoped support ticket operations. No order/payment writes. Requires stage 2; legacy null-user order/item visibility is allowed only when the matching Supabase Auth identity is email-confirmed in the database. |
| 5 | Admin dealer directory/approval and catalog CRUD/import pilots | Local read-only dealer list and approval Edge Functions are separate opt-in routes. The category CRUD and bulk-import SQL RPC drafts now pass the disposable PostgreSQL harness for service-role-only execution, role denial, product reassignment, duplicate SKUs, import retry, and invalid-price rollback. Product CRUD still has handler-level tests only; all Edge Functions remain undeployed, browser/Edge Runtime and production-schema compatibility remain unverified. Keep every flag off. |
| 6 | Storage bucket, upload rules, image inventory/migration | Draft 005 creates only `ro-product-images` (public read, max 5 MiB, JPG/PNG/WEBP) and fails on conflicting existing settings. Provision only on the existing project after explicit approval. The Edge Function service role is the only upload path; no public client-write policy is created. Inventory and verify every existing object/URL before changing product/category rows. |
| 7 | Checkout/payment pilot (`20261027` / `20261028` drafts) | Blocked: absent shop assignment table, no shared inventory-writer strategy with Express, no stock reservation expiry, and no PostgreSQL/Razorpay integration tests. Keep COD, Razorpay, cancellation, refunds and inventory on Express. |
| 8 | Shop employees, assignment, delivery, refund, reports, invoices/admin analytics | Blocked until shop Auth/role/assignment schema and delivery-confirmation/status/refund invariants are reconciled; use transactional server-side functions only. |
| 9 | Cutover | Enable one feature flag at a time only after local browser/mobile tests, authorization tests, reload persistence, and approved read-only production verification. Express remains until complete parity. |

Use the disposable local Supabase stack for integration tests. The repository CLI link marker identifies the existing project, so never run db push or a deployment command from that link. Before any production operation, capture a verified backup, show the exact additive change and impact, and obtain explicit approval. The staged files remain outside supabase/migrations/ until reviewed and approved.

## Endpoint-to-Supabase disposition

Use the route inventory for request/response details. The safe target mapping is:

- Public `GET /api/products` and `/api/categories`: Supabase Data API through the restricted catalog projection (implemented locally, default-off).
- Profile read/update and saved-address operations: Supabase RLS, column-scoped profile reads, owner-derived profile/address RPCs; local Auth/PostgREST/RLS integration passed, flag remains off.
- Cart read/remove/clear: Data API with owner RLS; add/update: stock-locked RPC (local repository and stage SQL prepared; unverified in PostgreSQL).
- Order history/details and rewards: Data API with dealer-owned RLS and selected columns. Support ticket create: owner-derived RPC. Invoice PDF remains Express/Puppeteer.
- Auth: Supabase Auth and verified profile-link RPC after provider setup; legacy OTP, Google, admin, and employee identity paths remain Express where configuration/authorization parity is incomplete.
- Dealer approval (`POST /api/admin/set-status`): local `admin-dealer-approval` Edge Function pilot now exists behind `USE_SUPABASE_ADMIN_DEALER_APPROVAL=false`; Express remains default. Verify trusted admin provisioning, existing `users` schema behavior, approval persistence, and pending-dealer blocking locally before considering any routing change on the existing project.
- Dealer directory (`GET /api/admin/dealers`): local `admin-dealers` read-only Edge Function pilot exists behind `USE_SUPABASE_ADMIN_DEALERS=false`. It uses verified Auth admin claims, an explicit safe column projection and paged reads. Express remains default; verify actual live columns, Auth authorization, result parity and browser rendering locally before enabling.
- Dashboard totals (`GET /api/admin/dashboard-stats`): local `admin-dashboard-stats` read-only Edge Function pilot exists behind `USE_SUPABASE_ADMIN_STATS=false`. It uses verified Auth admin claims and reads minimal summary columns in bounded pages; Express remains default. Compare aggregate parity, currency precision, latency, actual schema, and browser reload behavior on staging before enabling.
- Checkout/order creation, Razorpay verification/capture/refunds, inventory mutation, remaining admin writes, shop employee/delivery/refund, invoice rendering, and reports: keep Express until an Edge Function/RPC replacement is tested end-to-end.
- Product/category image Storage, bulk import, and admin catalog: local server-authorized Edge Function drafts only; not deployed or integration tested.

## Staging validation and rollback

For each stage: inspect the SQL diff and exact columns/constraints; apply only to disposable staging; capture grants/policy snapshots before and after; run anon, dealer A, dealer B, pending dealer, admin, and employee negative tests; assert no other dealer's records are visible; compare payloads with Express; verify retries and app restart persistence. A local PostgreSQL harness exercises stages 001–005 with synthetic records, an Auth stub, and a minimal fake Storage metadata schema, but does not replace Supabase staging tests. Do not use a service-role key in Flutter or browser code.

If a stage fails, discard/recreate the disposable staging branch from its snapshot rather than improvising production rollback SQL. Leave the stage unmerged and keep its feature flag false. For an already-reviewed stage, rollback the client by removing its build define; preserve additive database objects unless a separate reviewed cleanup is required.

## Remaining blockers

- The catalog/profile/address/history SQL has been exercised against the existing disposable local Supabase stack (Auth, PostgREST, RLS and Storage) using synthetic fixtures. The additional PostgreSQL harness covers cart/history stages. Hosted-project Auth linking, email delivery, Edge Runtime and production compatibility remain unverified. No separate hosted staging project is intended or required for this local test workflow.
- Flutter tests/analyzer did not complete in the current environment.
- Supabase Auth email/OTP configuration is not available, so real Auth delivery/linking has not been verified.
- No Edge Function deployment, browser integration, Storage migration, Razorpay sandbox test, production flag, or cutover has occurred.
- Missing shop assignment/`delivery_confirmed` schema and shared Express/Supabase stock-writing coordination block checkout/shop migration.

## Dealer profile/address local Supabase verification (2026-10-28)

Stage 002 passed 1/1 through the disposable local Supabase Auth/PostgREST/RLS/Storage test after replacing direct profile PATCH with `ro_update_current_dealer_profile`. The RPC derives dealer identity from the verified session, enforces profile field validation and duplicate-mobile rejection, and keeps approval fields server-owned. Two synthetic dealers could not read or mutate each other's profiles or addresses; address default/save/delete behavior passed. This is not hosted-project or real email verification. `USE_SUPABASE_DEALER_DATA` remains false, Express remains the active fallback, and no production changes were made.

## Dealer cart and order-history local Supabase verification (2026-10-29)

- [x] Stage 003 cart and stage 004 order-history SQL passed the disposable local PostgreSQL harness with synthetic users and records.
- [x] Local Supabase Auth/PostgREST/RLS integration covered cart ownership, stock limits, retry/idempotency, profile/address ownership, catalog/Storage reads, owned order/item/reward reads, and support-ticket submission.
- [x] A legacy order/item/ticket with a null dealer ID is visible only to a matching Auth user whose `auth.users.email_confirmed_at` is set. A bearer token carrying an email claim after that local Auth user is made unconfirmed does not retain legacy-email access. Stage 004 now derives fallback email from confirmed `auth.users`, rather than trusting `auth.jwt()->>'email'`.
- [x] Stage 004 support creation requires a confirmed Auth email and derives dealer ID from the linked profile. It does not permit clients to assign another dealer ID.
- [ ] No hosted SQL was applied. Checkout/order creation, payment, refund, inventory, admin writes, and shop delivery remain Express-only; hosted project compatibility and Flutter end-to-end cutover remain unverified.
- [x] Feature flags remain disabled and Express remains the active fallback. No production records or settings changed.
