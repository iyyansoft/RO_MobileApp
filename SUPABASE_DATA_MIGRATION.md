# RO app MySQL-to-Supabase data import

`supabase_data_import.sql` is a data-only PostgreSQL import generated from the verified
`backup_ro_wholesale_db_20261012_163051_99e252.sql` and checked against
`supabase_migration.sql`. It contains dealer/contact/order data and password hashes.
Keep it private; it is excluded from Git by `.gitignore`. The backup is also excluded by
the existing `backup_*.sql` rule.

The offline converter is `scripts/prepare_supabase_data_import.js`. It reads local files
only and does not open a database connection. It checks all 11 table definitions and
columns, parses each mysqldump row, converts MySQL quoting and boolean/date/JSON types,
and refuses a row-count or schema mismatch. To regenerate after deliberately replacing
the source backup, review the script's source filename and expected counts first, then run:

```powershell
node scripts/prepare_supabase_data_import.js --replace
```

Do not run the generated SQL yet. When ready for a migration window:

1. Keep MySQL unchanged and take a fresh, consistent backup immediately before the
   migration. Confirm the backup includes all current tables and data; the import file
   is tied to the source backup by SHA-256 shown in its header.
2. Use a new, isolated Supabase project. Apply `supabase_migration.sql` first, as the
   project database owner. It creates the schema and enables RLS without client policies.
3. Confirm all 11 target tables are empty. Then run `supabase_data_import.sql` once as
   the project database owner (for example, from Supabase SQL Editor). The import is
   transactional, aborts if any target table is non-empty, asserts all source row counts,
   checks every foreign-key relationship, and advances each identity sequence after
   preserving explicit source IDs.
4. Verify the resulting counts below, check for null/empty password hashes without
   selecting their values, and compare business totals, ID sets, and timestamp ranges with
   the MySQL backup. Keep the source database and backup untouched until application and
   backend compatibility testing is complete.
5. Test authentication using a controlled account, including both password-hash
   verification and OTP behavior, plus catalog/category, cart, orders, rewards, addresses,
   and payment-session reads. Do not test a real Razorpay payment during schema validation.

Expected rows copied from this backup (69 rows total):

| Table | Rows |
|---|---:|
| `users` | 9 |
| `categories` | 6 |
| `products` | 19 |
| `orders` | 7 |
| `user_addresses` | 10 |
| `order_items` | 7 |
| `rewards_history` | 7 |
| `otp_codes` | 0 |
| `support_tickets` | 0 |
| `cart_items` | 4 |
| `payment_sessions` | 0 |

Import order follows the foreign keys: `users`, `categories`, `products`, `orders`,
`user_addresses`, `order_items`, `rewards_history`, `otp_codes`, `support_tickets`,
`cart_items`, then `payment_sessions`. The SQL import contains explicit column lists,
preserves primary/foreign key values, timestamps and password hashes, maps MySQL
`TINYINT(1)` flags to PostgreSQL booleans, and casts the email columns to `citext`.

The import itself aborts if any row count differs or a foreign-key reference is orphaned.
For a post-import review, this read-only query repeats the table counts:

```sql
SELECT 'users' AS table_name, COUNT(*) AS row_count FROM public.users
UNION ALL SELECT 'categories', COUNT(*) FROM public.categories
UNION ALL SELECT 'products', COUNT(*) FROM public.products
UNION ALL SELECT 'orders', COUNT(*) FROM public.orders
UNION ALL SELECT 'user_addresses', COUNT(*) FROM public.user_addresses
UNION ALL SELECT 'order_items', COUNT(*) FROM public.order_items
UNION ALL SELECT 'rewards_history', COUNT(*) FROM public.rewards_history
UNION ALL SELECT 'otp_codes', COUNT(*) FROM public.otp_codes
UNION ALL SELECT 'support_tickets', COUNT(*) FROM public.support_tickets
UNION ALL SELECT 'cart_items', COUNT(*) FROM public.cart_items
UNION ALL SELECT 'payment_sessions', COUNT(*) FROM public.payment_sessions
ORDER BY table_name;

SELECT COUNT(*) AS users_with_missing_password_hash
FROM public.users
WHERE password_hash IS NULL OR password_hash = '';
```

For the five identity columns (`order_items.id`, `rewards_history.id`, `otp_codes.id`,
`support_tickets.id`, and `cart_items.id`), confirm each sequence reported by
`pg_get_serial_sequence('public.<table>', 'id')` has its last value at or above the
table's maximum imported ID (empty tables are reset to start at 1).

The import does not change MySQL or configure the Node backend. The Node backend now uses
PostgreSQL through the `pg` driver and reads its connection URI from `SUPABASE_DB_URL`
(or discrete `PGHOST`/`PGUSER`/`PGPASSWORD` environment variables). Apply the schema and
data import before starting the backend; it does not apply DDL or import data at startup.
Keep the connection URI exclusively in the backend environment. Add narrowly scoped RLS
policies only after the backend authentication model is defined.
