# Release runbook: Bulk Orders, Rewards v2, Cabinet pricing (branch `release/neeroplus-bulk-rewards-2026-11-21`)

Status: **prepared, not executed.** Nothing in this file has been run against
production. Every production step needs explicit approval from the owner.

## Owner decisions (2026-11-21)

* Do **not** delete the 18 SAMPLE_ products or the 3 dealer cart lines: the catalogue
  import runs with `--keep-samples` (adds the PDF products only).
* Do not delete ABC / RO_1 / RO_2 / RO_3 (review report prepared).
* Stock for the 78 new products comes only from the owner's inventory count
  (stock-entry spreadsheet); nothing is assumed. Bulk Orders open per product only
  after its real stock is entered.
* Keep the 23 unused images and the staging backup until the owner approves removal.

## Verified on 2026-11-21 (staging = local Postgres 17.12 restored from the production backup)

| Check | Result |
|---|---|
| Production backup (`pg_dump` public schema + JSON per table) | 16 tables, 274 rows; restore identical to production (row count + md5 of every table, sequences, 47 indexes, 53 constraints, 2 triggers, RLS on 16 tables) |
| Migration 010 + 011 on staging | ~0.45 s each; no original value changed; row counts unchanged; reward balances = ledger (5,570) |
| Re-running 010 + 011 / rollback SQL | no change / schema and data identical to before |
| Current production code (3df211f) on migrated schema; new code on unmigrated schema | both work (login, cart, order, admin cancel) |
| New code on migrated schema | 2.5% with decimals (6,660 -> 166.50), reversal on cancel |
| Catalogue import `--keep-samples` | 78 added; SAMPLE_ products, cart lines, all order lines, orders, users, rewards byte-identical |
| Bulk pricing before stock | 0 offers opened (64 wait for stock) |
| Stock entry from the spreadsheet | only `stock_quantity` changes; blank rows skipped; stale dry run and invalid values refused; rollback exact |
| Bulk pricing after stock | only stocked products with an offer opened; server: stocked bulk add 200, unstocked 409 OUT_OF_STOCK |
| Full rollback (bulk, stock, catalogue) | every table identical to before |
| Admin Dashboard stock edit (real admin.html, headless Chrome) | only `stock_quantity` changes (whole-row diff on an imported, a Cabinet, a SAMPLE_ and the RO_1 product); blank stock refused (fixed in this branch) |
| Shop dashboard date fix | old formula gave yesterday 00:00-10:59 IST; new formula correct all day |

## Sequence (each step: approval -> run -> verify -> continue)

0. Quiet window; no catalogue/price edits in the admin panel during the release.
1. **Fresh backup** (read-only): `pg_dump --schema=public --format=custom` (verify-full SSL)
   and `node scripts/backup_database.cjs`; restore into scratch Postgres and compare checksums.
2. **Migrations** (one transaction each): `010_reward_ledger.sql`, then `011_bulk_orders.sql`.
   Verify column types, `SUM(reward_points)` unchanged, new indexes present.
3. **Backend (Render)**: deploy the release commit; check `/api/categories`, `/api/products` = 200.
4. **Frontend (Vercel)**: deploy after Render is live; sign in and check Home, Categories,
   Bulk Orders (empty until step 7), Cart, Profile rewards, Admin stock edit.
5. **Catalogue import (add only)**: `node scripts/pdf_catalog_import.cjs --keep-samples` (dry run),
   then `APPLY_PDF_CATALOG_IMPORT=YES node scripts/pdf_catalog_import.cjs --apply --keep-samples`
   (own backup, uploads 78 images to Storage, one transaction). The 78 products are Out of Stock.
6. **Stock entry** (owner's counted quantities only):
   `python scripts/stock_entry_template.py read <filled.xlsx> entries.json`,
   `node scripts/stock_entry_import.cjs entries.json` (dry run, owner reviews),
   then `APPLY_STOCK_ENTRY=YES node scripts/stock_entry_import.cjs entries.json --apply`.
   Individual corrections: Admin Dashboard > Products > Edit > Available Stock Quantity.
7. **Bulk prices**: `node scripts/bulk_pricing_import.cjs` (dry run lists ready vs waiting),
   then `APPLY_BULK_PRICING=YES node scripts/bulk_pricing_import.cjs --apply`. Only products with
   stock > 0 get an offer; re-run after later stock counts to open the rest.
8. **CAB-02 image** (pending the supplier photo, see below). **Android**: create the company key once with
   `scripts\create-signing-key.ps1`, then `scripts\build-release-aab.ps1` (docs/ANDROID_RELEASE_SIGNING.md).

## Rollback

| Step | How | Safe when |
|---|---|---|
| 7 bulk prices | `ROLLBACK_BULK_PRICING=YES node scripts/bulk_pricing_import.cjs --rollback` | no bulk cart lines (script refuses otherwise) |
| 6 stock | `ROLLBACK_STOCK_ENTRY=YES node scripts/stock_entry_import.cjs --rollback backups/stock_entry_before_<stamp>.json` | stock not changed since by orders/edits (script refuses per product otherwise) |
| 5 catalogue | `ROLLBACK_PDF_CATALOG_IMPORT=YES node scripts/pdf_catalog_import.cjs --rollback backups/<its backup>` | before dealers order the new products |
| 3/4 code | Render: redeploy 3df211f; Vercel: promote previous deployment | always (old code works on the migrated schema) |
| 2 migrations | SQL in each migration header (011 first) | only while no bulk lines / decimal points / claims exist; afterwards prefer code rollback |
| anything | restore the step-1 `pg_dump` | last resort: loses every later change |

## Repository visibility (checked 2026-11-21)

The GitHub repository `iyyansoft/RO_MobileApp` is **public**. Therefore:

* Stock-entry spreadsheets, supplier PDFs, extracted price data, backups, `.env` and signing
  keys stay outside Git (`.gitignore` covers them). The filled stock sheet lives in
  `%USERPROFILE%\ro_mobile_build\release_prep\`.
* The supplier price-list PDFs and extracted price data were committed in `da74ae4` and removed
  in `3df211f`; they are still downloadable from the public history. Removing them needs a
  history rewrite and force push (owner decision), or making the repository private.
* `supabase/.temp/pooler-url` (database user name and host, no password) is tracked from
  earlier work; now ignored for the future, not deleted.
* No `.env`, password, API secret, signing key or database dump has ever been committed.

## Open review items (no action without approval)

* **SAMPLE_ products**: in active use (39 order lines, latest order 2026-11-20, 11 Shop
  delivery records, 3 dealer carts). If they should leave the catalogue later, prefer
  status `inactive` (hidden, reversible) over deleting. Report: `NeeroPlus_Product_Review_Report.xlsx`.
* **ABC / RO_1 / RO_2 / RO_3**: look like test entries (default image, stock 50 = old form
  default, no description); ABC is on 2 orders, so it should be hidden, not deleted, if confirmed.
* **CAB-02 Dolphin gold plus/ABS** has no image. Task: get the real product photo from the
  supplier (Dolphin gold plus, ABS cabinet; not a similar model), JPG/PNG/WebP, product on a
  plain white background, at least 800 px on the long side; Admin Dashboard > Products >
  CAB-02 > Edit > Upload image (resized to 1200 px, stored in the database) > Save; check
  the product card, product page and WhatsApp share card. Only after approval.
* **23 unused images**: deleted only in the local working copy, still in Git; unchanged.
* **Staging copy** (Docker container `ro-staging`, localhost-only port 55432) and the backups
  folder contain customer data; `backups\` is restricted to the owner, SYSTEM and Administrators.
