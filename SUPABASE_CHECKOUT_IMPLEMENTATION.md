# Supabase checkout pilot (local draft)

This is the next migration stage only. It does not complete backend migration.
The existing Express checkout remains the default and fallback.

## Local implementation

- `supabase/drafts/unreconciled/20261027_secure_checkout.sql` is an unapplied private checkout and inventory-ledger draft plus service-role-only RPCs. The final transaction rechecks and locks stock, inserts the order/items/rewards, deducts stock, records one movement per order/product, and routes to a default/sole active shop atomically. It also contains a COD-only cancellation RPC that restores stock exactly once, only for orders with a recorded checkout deduction and no shop delivery activity. It is blocked by the missing live `shop_order_assignments` table and is not part of the staged rollout.
- `supabase/functions/create-razorpay-order` creates or reuses a provider order. The Supabase service role and Razorpay secret are only read in Edge Function runtime.
- `supabase/functions/verify-razorpay-payment` verifies signature and provider payment/order/amount/currency, captures an authorized payment, then finalizes the order through the RPC. A retry after capture can finish the same request without another payment.
- `supabase/functions/place-cod-order` commits an order with `payment_status='due_on_delivery'`; it never claims cash was collected.
- `supabase/functions/cancel-order` authenticates the caller, derives their Auth UID, and allows cancellation only through the owner-checked service RPC. Paid/collected orders and orders with delivery activity are rejected; online cancellation awaits a verified Razorpay refund workflow.
- Flutter calls these functions only when the existing Supabase Auth flow is active and `USE_SUPABASE_CHECKOUT=true`. The flag defaults to false. Express is unchanged and continues to handle checkout by default.

## Required sequence before enabling

1. Review the existing live-schema audit and both local migrations. The earlier Auth/RLS migration must be reviewed and applied first because this draft requires `users.auth_user_id`. Do not run either SQL file without explicit approval and a staging/backup plan.
2. Validate the SQL on a disposable/staging Supabase project matching the audited schema. Run privilege/RLS checks as anon, authenticated, and service role. The Edge service role bypasses RLS by design; only its Edge server code can call these service-only functions.
3. Deploy the four functions with Edge secrets set in Supabase settings: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, and optionally `SHOP_DEFAULT_NAME`. Never use service-role or Razorpay secrets in Flutter/browser build variables.
4. Configure Razorpay test keys and run negative, retry, replay, capture/finalization recovery, dealer isolation, pending/unapproved dealer, invalid GST, out-of-stock, and ambiguous-shop tests.
5. Test COD and Razorpay order visibility in dealer order history, Shop Current Orders, and Admin Orders; verify COD remains unpaid until the existing delivery/cash collection operation confirms actual collection.
6. Only after parity, approval, and end-to-end tests, explicitly enable `USE_SUPABASE_AUTH` and `USE_SUPABASE_CHECKOUT` for a staging build. Keep the Express fallback available until production cutover is separately approved.

## Known gaps / release blockers

- No SQL has been run and the Edge Functions are not deployed. Local SQL syntax was not checked by PostgreSQL because `psql`/Supabase CLI are unavailable in this environment.
- The live schema audit reported no `users.auth_user_id` before the Auth migration. This checkout SQL will intentionally fail its precondition until that prior migration is separately reviewed/applied.
- Inventory writes are now represented locally by a transaction-safe ledger, and COD pre-fulfillment cancellation is idempotent. The SQL has not been parsed/executed by PostgreSQL, so transaction behavior is unverified. Razorpay capture can succeed immediately before the final stock recheck fails; that path returns an explicit support/refund error but does not automatically issue a provider refund. A durable refund/reconciliation operation must be added and tested before production enablement.
- Partial-delivery shortage restocking is intentionally not automatic. Shop delivery and refund approval remain Express-owned; stock should be restored only when the admin/provider refund workflow confirms the shortage resolution. That workflow must be migrated as a later stage and share this inventory ledger before both checkout paths can run concurrently.
- The Express fallback currently does not participate in this new ledger. Do not enable Supabase checkout while Express checkout can concurrently create orders until both paths use a shared inventory transaction or traffic is isolated to one writer.
- Razorpay live/test-mode behavior, retries after provider capture, schema constraints, and Admin/Shop visibility have not been verified against Supabase or Razorpay.
- The Edge Functions use explicit Supabase Auth `getUser()` validation and `verify_jwt=false` only to permit unauthenticated CORS preflight handling. Do not remove the function-level bearer validation.
- No email configuration was changed. New signup, OTP delivery, password reset, admin operations, shop delivery/refunds, invoice rendering, image/bulk uploads, and reports remain on existing paths.

## Local test

`npm test` runs Node tests for the shared checkout rules and existing backend. The checkout tests exercise provider-payment field/status validation and statically verify SQL idempotency, stock-lock/decrement, cancellation restrictions, and ledger uniqueness. They do not substitute for PostgreSQL transaction tests, Edge Runtime, Razorpay, or emulator end-to-end tests.
