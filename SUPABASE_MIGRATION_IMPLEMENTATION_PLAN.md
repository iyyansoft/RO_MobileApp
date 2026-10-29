# Supabase-primary migration implementation plan

## Target and boundaries

The target is the existing Supabase project: Flutter mobile, Flutter Web admin, Supabase PostgreSQL, Supabase Auth, RLS, Storage, RPC, and Edge Functions. Express remains an unchanged fallback during rollout and is retired only after every route has a tested Supabase replacement. No MySQL database is part of the target.

This document and the accompanying SQL are local implementation artifacts only. They do not apply SQL, alter production data, enable client migration flags, deploy functions, or build an APK. Client flags remain disabled by default. SMTP/Resend setup is intentionally deferred; email-dependent auth and notifications remain on the current Express path until an email provider is available.

## Verified live-schema audit (2026-10-27)

The audit used a read-only PostgreSQL transaction and queried schema metadata only; no business rows were selected and no database objects or data were changed.

- The live database contains 15 public tables: the 11 core tables (`users`, `user_addresses`, `categories`, `products`, `cart_items`, `orders`, `order_items`, `rewards_history`, `otp_codes`, `support_tickets`, `payment_sessions`) plus `shop_employees`, `shop_delivery_items`, `shop_admin_notifications`, and `shop_product_enquiries`. `shop_order_assignments` is absent.
- Existing PK/FK/unique constraints connect cart to users/products, order items to orders, orders and rewards to users/orders, addresses and support tickets to users, products to categories, and shop delivery/notification/enquiry rows to their existing records. No assignment-table FK exists because that table is absent. Six identity sequences exist for cart, order items, OTP, rewards, notifications, and support tickets.
- RLS is enabled but not forced on all 15 public tables and `storage.objects`. The audit found no RLS policies on those tables or `storage.objects`.
- `anon` and `authenticated` currently have broad table-level privileges (including write privileges) on the 15 public business tables. With no policies those roles currently have no RLS-visible rows, but the grants are excessive and become dangerous if a permissive policy is added or RLS is disabled.
- There are no public views, no Storage buckets, and only the existing `ro_set_updated_at()` public trigger function. `users.auth_user_id` is absent. `shop_delivery_items.delivery_confirmed` is absent in the live schema although the local shop migration contains an additive path for it.
- The admin web repository still uses Express `/api/admin/*` by default. Dealer login/signup and email OTP remain Express by default. Shop employee login and delivery remain Express. Local Edge Function drafts exist but none have been deployed.
- No email service configuration was inspected or changed. Razorpay and email secrets were not read or displayed.

The live schema is verified at the metadata level, but no production row counts or personal/business records were inspected. The local migration still requires staging validation and explicit approval before application.

## Work order and completion criteria

### 1. Database authorization foundation — prepared locally

The former combined draft `supabase/drafts/unreconciled/20261026_auth_rls_storage.sql` is retained for reference, not as an executable migration. It requires the missing assignment table and mixes unrelated phases. Read [SUPABASE_STAGING_MIGRATION_PLAN.md](SUPABASE_STAGING_MIGRATION_PLAN.md) before staging; the smaller ordered drafts are in `supabase/staging/`.

- Link an Auth identity to a dealer profile through a unique `users.auth_user_id` foreign key.
- Keep new dealer accounts `pending` and `is_approved = false`; an Auth identity must never approve itself.
- Add explicit dealer-owned policies for profiles, addresses, cart reads/deletes, orders, order items, rewards, and support tickets.
- Allow email fallback only for legacy orders/tickets whose `user_id` is null. A matching email cannot override a conflicting non-null owner ID.
- Use atomic RPCs for cart add/update and address save/default changes. Direct cart writes and address inserts/updates are revoked.
- Insert support tickets through an RPC that derives identity/email from the verified Auth session.
- Expose catalog reads through a view that omits `purchase_price`.
- Remove inherited table and identity-sequence grants from `PUBLIC`, `anon`, and `authenticated`; grant only the client operations required by these paths.
- Keep OTP and payment-session records inaccessible to client roles.
- Add admin-claim-only write policies for the product image bucket.
- Revoke the existing broad client table grants for the core and shop business tables, and stop with an error if unreviewed policies already exist on affected relations, because permissive policies may broaden access.

No SQL has been applied. The staged profile/address, cart, and order-history drafts verify their required columns and use only existing business tables. Checkout remains blocked by the missing assignment relation and shop migration mismatch. Other type/grant/policy constraints are documented in the staging plan.

### 2. Identity and account linking

Use Supabase Auth as the final dealer/admin/employee identity provider. Dealer profile linking must require the authenticated, verified identity and preserve existing approval state. Existing accounts need a controlled account-linking or password recovery process; password hashes must never be delivered to clients.

**Blocked until email setup:** signup verification, email OTP login, email password recovery, and email notifications. Because Resend is unavailable and no SMTP setup is authorized, keep those flows on Express and do not enable the Supabase Auth flag yet. Password-only migration should not be considered complete until the chosen verified account-linking flow is tested.

Admin and employee role claims must be provisioned through a trusted server-side process, never user-editable metadata. Admin dashboard access must require a verified admin claim.

### 3. Catalog and images

- Move catalog reads to the safe `catalog_products` view and public category reads after RLS/grant tests pass.
- Upload product/category images to the existing project's Storage, under an admin-only write policy and bounded MIME/size rules.
- Migrate image files and update URLs only after every object is verified. Keep current upload handling until this is complete.
- Never expose `purchase_price` to dealer or anonymous clients.

### 4. Dealer-owned data

- Move profile reads/approved profile edits, saved addresses, cart, order history/details, rewards history, and support ticket submission to RLS-protected Data API/RPC paths.
- Use database functions for stock-validated cart mutations and atomic address save/default changes.
- Keep order and reward ledgers read-only from dealer clients.
- Deploy/test each path separately, then enable `USE_SUPABASE_DEALER_DATA` only in a test build after the complete policy set is installed and verified.

### 5. Checkout and payment

Implement trusted Edge Functions and transactional SQL functions:

1. `create-razorpay-order`: quote using database prices/stock and create/reuse a gateway order.
2. `verify-razorpay-payment`: verify signature and captured/authorized state with server-held keys.
3. `place-order`: create COD or verified online order, order items, stock effects, rewards, payment records, and shop routing atomically with idempotency.
4. `razorpay-webhook` if the current merchant configuration uses webhooks; verify webhook signature and deduplicate event IDs.

No client-supplied price, total, stock, payment status, or refund value is authoritative. COD must remain pending until real collection is recorded.

**External configuration required:** Razorpay test/live keys and webhook configuration in Edge Function secrets. Payment cutover waits for test-mode parity and duplicate/retry tests.

### 6. Admin operations and bulk import

Use admin-authorized Edge Functions (or tightly scoped RPCs called only after JWT role verification) for dealer approval/status, product/category mutations, deletion safeguards, stock and price changes, bulk Excel/CSV import, and admin-only reports. The browser receives only the publishable key. Admin role assignment/revocation must be operationally documented and audited.

### 7. Shop employee, delivery, and refund operations

Create trusted employee provisioning/session paths and shop-scoped operations:

- `shop-employee-session` or Auth invitation/provisioning flow.
- `shop-orders` / `shop-dashboard` / `shop-reports` scoped by the employee's assigned shop.
- `confirm-delivery` for independently confirmed item quantities, status, timestamps, and employee ID.
- `admin-assign-order` and `admin-refund` for admin-only assignment/refund decisions.
- `submit-enquiry` and admin enquiry/notification access.

Delivery/refund operations must be transactional, assignment-checked, quantity-checked against ordered values, and idempotent. The Admin Panel reads saved database results, not local Flutter state. Shop/payment live schema must be reconciled before writing these functions.

### 8. Invoices and notifications

- Keep invoice data under dealer ownership RLS.
- Inventory the current Puppeteer PDF output and choose a compatible renderer. Supabase Edge Functions may not provide the same Chromium runtime; if so, use a separately approved rendering service or a verified browser-side PDF only when it does not expose privileged data.
- Email invoice/OTP/support notifications require an active email provider. Keep these on Express until configuration is available; do not fake successful sending.

### 9. Cutover and Express retirement

Run side-by-side parity tests in staging. Enable one feature flag at a time only after its implementation, RLS tests, and rollback path pass. Keep Express available throughout the staged rollout. Remove Express routes/dependencies only when logs and integration tests confirm no remaining callers and every required feature has a tested Supabase equivalent.

## Proposed Edge Function inventory

| Function | Responsibilities | Secrets / authorization |
|---|---|---|
| `create-razorpay-order` | Trusted quote, stock validation, gateway order creation | Razorpay secrets; dealer JWT |
| `verify-razorpay-payment` | Signature/capture verification, payment session validation | Razorpay secrets; dealer JWT |
| `razorpay-webhook` | Verify and deduplicate gateway events | Razorpay webhook secret |
| `place-order` | Atomic COD/paid order finalization and idempotency | Dealer JWT; RPC does authoritative writes |
| `admin-dealer-action` | Approve/reject/status changes and guarded account operations | Verified admin claim |
| `admin-catalog-mutation` | Product/category/stock/price mutation | Verified admin claim; image bucket policy |
| `bulk-product-import` | Validate CSV/XLSX, deduplicate, commit batch | Verified admin claim; bounded file size |
| `shop-employee-provision` | Provision/deactivate employee identities | Verified admin claim; Auth admin API secret server-side |
| `shop-order-operations` | Assigned-shop order reads/dashboard/reports | Employee JWT and server-validated assignment |
| `confirm-delivery` | Transactional delivery, partial status, COD collection evidence | Employee JWT; assignment check; idempotency key |
| `admin-refund` | Record/approve refund adjustments | Verified admin claim; gateway secret if actually issuing a refund |
| `shop-enquiry` | Employee enquiry creation and admin inbox access | Employee/admin JWT by operation |
| `generate-invoice` | Generate or retrieve invoice artifact | Dealer/admin JWT; renderer configuration if needed |
| `send-notification` | OTP, recovery, invoice, or business email | Deferred until a permitted active email provider is configured |

Functions may be consolidated after route parity is mapped, but authorization must remain operation-specific. No function implementation or deployment currently exists in the repository.

## Test plan

### SQL and policy tests before any live application

- Review SQL against the exact live column types, constraints, grants, sequences, views, and existing policies.
- Apply only in an isolated staging Supabase project after approval.
- Test `anon`, authenticated dealer A, authenticated dealer B, admin, and employee identities.
- Prove dealer A cannot select/update/delete dealer B's profile, address, cart, order, order items, rewards, or tickets.
- Prove an order with non-null `user_id` is never exposed by matching email alone.
- Prove pending/rejected dealers remain unapproved and cannot perform approved-only purchase operations.
- Prove no dealer can select `purchase_price`, set prices/stock, write orders/payment status, write reward ledger rows, write OTP/payment sessions, or manipulate sequences.
- Prove cart RPCs enforce stock under concurrent requests; address save cannot alter ownership; concurrent default-address RPCs leave exactly one default.
- Prove an unreviewed permissive policy causes the migration to stop before policy installation.
- Prove image reads work as intended and all writes/deletes require trusted admin claims.

### Feature parity tests

- Auth: signup, email confirmation/OTP, password login/reset, session restore, approval status, legacy account linking, revoked/expired sessions.
- Catalog/storage: category/product reads, no purchase-price exposure, image upload/update/delete authorization, URL persistence after refresh.
- Dealer data: cart quantity and stock boundaries, address CRUD/default ownership, order history/details, reward history, support tickets.
- Checkout: COD and Razorpay test mode, authoritative pricing, GST, stock race, payment verification failure, idempotent retry, order visibility.
- Admin: dealer approval, product/category CRUD, bulk import validation/duplicates, reports and role denial.
- Shop: employee login/provisioning, assignment isolation, full/partial/zero delivery, checkbox status, totals, COD collection status, refunds, enquiries, reports, duplicate submission, admin synchronization.
- Invoices: GST and non-GST records, ownership isolation, generated/downloaded document parity.
- Regression: run backend tests, Flutter tests, Flutter analysis, and end-to-end staging checks. No production account or database is used for destructive scenarios.

## External services and configuration dependencies

- **Email:** Resend is suspended and SMTP configuration is intentionally skipped. Supabase email OTP, recovery, and email notifications are not ready; leave those flows on Express until an email provider is authorized and delivery is verified.
- **Google sign-in:** requires Google OAuth client/provider configuration.
- **Razorpay:** requires server-only test/live credentials, webhook secret/configuration, and payment-flow tests.
- **PDF invoices:** requires confirming Puppeteer output requirements and choosing a compatible renderer.
- **Storage:** requires bucket/policy review and a verified migration of current local image files.
- **Admin/employee claims:** requires secure provisioning and revocation procedure.

## Operational environment names (values omitted)

Client: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, existing `API_BASE_URL` during transition, and the existing opt-in flags (all remain false until ready).

Edge Function secrets when configured: Razorpay API/webhook secret names and any approved email provider secret names. Never place database passwords, service-role keys, or payment secrets in Flutter or browser builds.
