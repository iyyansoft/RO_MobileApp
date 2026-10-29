# Migration directory intentionally empty

The live Supabase schema has been audited, but the existing local SQL bundle has not been reconciled or tested against PostgreSQL. Unapplied drafts are kept under `supabase/drafts/unreconciled/`; isolated staging SQL is under `supabase/staging/` in reviewed order.

Do not run `supabase db push` against production. Do not copy a stage into this directory until it has passed isolated PostgreSQL tests and has explicit approval for the target environment.
