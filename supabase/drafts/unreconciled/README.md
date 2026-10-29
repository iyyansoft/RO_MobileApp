# Unreconciled SQL drafts

These five SQL files were moved out of `supabase/migrations/` because the read-only production schema audit found dependencies that do not match the live project. Their SQL contents are retained for engineering reference and static tests only. They have not been executed in production or staging.

In particular, the auth/RLS bundle requires missing `shop_order_assignments`; the checkout bundle writes that table; the refund draft depends on checkout's private objects; and the admin/bulk drafts still require PostgreSQL, Storage, and browser integration tests. Do not run these files directly or copy them into an apply directory without reconciling each dependency in `SUPABASE_STAGING_MIGRATION_PLAN.md`.
