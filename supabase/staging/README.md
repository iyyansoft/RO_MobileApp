# Isolated staging only

This checkout has no configured staging URL, database URL, project reference, or Supabase CLI link. A remote staging project may exist outside this workspace, but its availability and identity cannot be confirmed here. A disposable local PostgreSQL test harness is available; it uses synthetic records and a minimal local Auth stub, not the Supabase project.

The SQL files in this directory use the `public` schema and are **not project-targeted**. They do not inspect or enforce a Supabase project reference. Do not run them in the SQL Editor or with `supabase db push` until staging has been independently identified. Do not use the production dashboard or production database URL.

Before an approved staging run:

1. Obtain the staging project reference and database connection from the staging project's own dashboard. Keep credentials private.
2. Verify the dashboard URL/project reference and compare it with the staging connection host; record the reference in review notes without recording credentials.
3. Ensure the staging database is isolated from production and has a restorable schema snapshot. Do not copy uncontrolled personal/business data into it.
4. Install/configure the Supabase CLI or PostgreSQL client and link only the verified staging project. Confirm the linked reference before any command that applies SQL.
5. Review and run `001_catalog_read.sql`, `002_dealer_profile_addresses.sql`, then `003_dealer_cart.sql` one at a time. Stop on any preflight error; do not bypass it or alter production to make it pass.
6. Capture schema, grants, and RLS policy metadata before and after. Test catalog visibility, dealer A/B isolation, pending/unapproved dealer behavior, cart add/update/remove/clear, stock boundaries, duplicate add retries, and persistence after a new session.
7. Do not proceed to `004_dealer_order_history.sql` until PostgreSQL cart tests pass and stage-2 Auth/approval behavior has been reviewed.
8. `005_product_image_storage.sql` provisions only the `ro-product-images` bucket at 5 MiB with JPG/PNG/WEBP MIME restrictions. It is idempotent when the existing configuration matches and aborts if it conflicts. It does not add client write policies or migrate/overwrite objects; the local admin-catalog function uses server-side service-role storage access. Run it only after approved staging identification and before testing that function's upload path.

For local SQL behavior tests, run `scripts/test-supabase-staging-local.ps1`. It refuses to reuse an existing container, binds only to `127.0.0.1`, uses temporary container storage, and removes the container it starts. It does not verify Supabase Auth, API grants, deployed Edge Functions, or remote configuration.

Stages 001–005 are local drafts only. No stage has been executed against production or remote staging. Feature flags remain disabled and Express remains the active fallback. A read-only audit of the existing production project found 15 public tables (all with RLS enabled, with rows in 11), zero public or Storage policies, no Storage buckets, and one existing public function (`ro_set_updated_at()`). This confirms the project is not an empty staging target.
