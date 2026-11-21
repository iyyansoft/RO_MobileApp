# Release runbook: Bulk Orders, Rewards v2, Cabinet pricing (branch `release/neeroplus-bulk-rewards-2026-11-21`)

Status: **prepared, not executed.** Nothing in this file has been run against
production. Every production step needs explicit approval from the owner.

## Verified on 2026-11-21 (staging = local Postgres 17.12 restored from the production backup)

| Check | Result |
|---|---|
| Production backup (`pg_dump` public schema + JSON per table) | 16 tables, 274 rows; restore identical to production (row count + md5 of every table, sequences, 47 indexes, 53 constraints, 2 triggers, RLS on 16 tables) |
| Migration 010 + 011 on staging | ~0.45 s each; no original value in any table changed; row counts unchanged; reward balances = ledger (5,570 points) |
| Re-running 010 + 011 | no change (safe to repeat) |
| Rollback SQL (011 then 010) | schema and data identical to before |
| Current production code (3df211f) on migrated schema | login, cart, order, admin cancel: all OK |
| New code on unmigrated schema | all OK; rewards stay on the legacy 5% rule until 010 |
| New code on migrated schema | 2.5% with decimals (6,660 -> 166.50), reversal on cancel |
| PDF catalogue import (database part) | only `products`, `order_items.sku` (39 blank SKUs filled) and 3 cart lines on SAMPLE_ products change; all 45 kept products incl. 41 Cabinets byte-identical |
| Bulk pricing (`scripts/bulk_pricing_import.cjs`) | 64 offers set, no other column changed, second run sets 0, none above Dealer Price |
| Full rollback (bulk, then catalogue from its backup) | identical except JSON whitespace in specs/features text of the 18 restored SAMPLE_ products |
| Shop dashboard date fix | old formula gave yesterday from 00:00 to 10:59 IST; new formula correct all day (production DB runs in UTC) |

## Sequence (each step: approval -> run -> verify -> continue)

0. Pick a quiet window. No catalogue/price edits in the admin panel during the release.
1. **Fresh backup** (read-only): `pg_dump --schema=public --format=custom` (verify-full SSL) and
   `node scripts/backup_database.cjs`. Restore the dump into a scratch Postgres and compare
   checksums with production. Keep both backups offline.
2. **Migrations** (one transaction each): `010_reward_ledger.sql`, then `011_bulk_orders.sql`.
   010 aborts by itself if an order has two reward rows or a balance does not match the ledger.
   Verify: column types, `SUM(reward_points)` unchanged, new indexes present.
3. **Backend (Render)**: merge the PR to `main` (or deploy the branch commit). Wait for the
   Render deploy to be live; check `/api/categories` and `/api/products` return 200.
4. **Frontend (Vercel)**: deploy after Render is live (build: `scripts/vercel-build.sh`,
   API `https://ro-mobileapp.onrender.com/api/`). Open the site, sign in, check Home,
   Categories, Bulk Orders (empty until step 6), Cart, Profile rewards.
5. **PDF catalogue import**: `node scripts/pdf_catalog_import.cjs` (dry run, must be error-free),
   then `APPLY_PDF_CATALOG_IMPORT=YES node scripts/pdf_catalog_import.cjs --apply`
   (takes its own backup, uploads 78 images to Storage, one transaction).
6. **Bulk prices**: `node scripts/bulk_pricing_import.cjs` (dry run), then
   `APPLY_BULK_PRICING=YES node scripts/bulk_pricing_import.cjs --apply`.
7. **Stock**: the 78 imported products are created with stock 0 and are **out of stock** until
   stock is entered (this includes all 64 Bulk Orders offers).
8. **Android**: build an App Bundle with the release key (see below) and distribute.

## Rollback

| Step | How | Safe when |
|---|---|---|
| 6 bulk prices | `ROLLBACK_BULK_PRICING=YES node scripts/bulk_pricing_import.cjs --rollback` | no bulk cart lines exist (script refuses otherwise) |
| 5 catalogue | `ROLLBACK_PDF_CATALOG_IMPORT=YES node scripts/pdf_catalog_import.cjs --rollback backups/<its backup>` | before dealers order the new products (orders on PDF_ products would point at removed products) |
| 3/4 code | Render: redeploy previous commit 3df211f. Vercel: promote previous deployment | always; previous code works on the migrated schema (tested) |
| 2 migrations | SQL in each migration header (011 first) | only while no bulk lines and no decimal points / claims exist; after go-live prefer code rollback and keep the schema |
| anything | restore the step-1 `pg_dump` | last resort: loses every change made after the backup |

## Android release signing

Current APKs are signed with the Android **debug** key (not accepted by Google Play; an app
signed with one key cannot be updated by an APK signed with another). Before a store release:
create an upload keystore (`keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA
-keysize 2048 -validity 10000 -alias upload`), store it and its passwords outside the repository
(password manager + offline copy), add `android/key.properties`, switch the `release` build type
to a `release` signingConfig, enrol in Play App Signing, build `flutter build appbundle --release
--dart-define=API_BASE_URL=https://ro-mobileapp.onrender.com`, and raise `version:` in
`pubspec.yaml` for every upload. `key.properties`, `*.jks` and `*.keystore` are git-ignored.
