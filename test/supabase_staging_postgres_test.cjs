const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

const root = path.join(__dirname, '..');
const localUrl = process.env.SUPABASE_LOCAL_TEST_URL;
const sqlFile = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

test('staging migrations enforce dealer isolation, stock bounds and safe retries on local PostgreSQL', {
  skip: !localUrl,
}, async () => {
  const target = new URL(localUrl);
  assert.ok(['localhost', '127.0.0.1', '::1'].includes(target.hostname),
    'local PostgreSQL tests refuse any non-loopback host');
  assert.equal(target.port, '55432', 'local PostgreSQL tests require the dedicated test port');
  assert.equal(target.pathname, '/postgres', 'local PostgreSQL tests require the disposable postgres database');

  const client = new Client({ connectionString: localUrl });
  await client.connect();
  try {
    const publicTableCount = await client.query(`
      SELECT count(*)::int AS count FROM information_schema.tables
      WHERE table_schema='public' AND table_type='BASE TABLE'
    `);
    assert.equal(publicTableCount.rows[0].count, 0,
      'refuse to run on a non-empty local public schema');

    await client.query(sqlFile('test/fixtures/supabase_auth_bootstrap.sql'));
    await client.query(sqlFile('supabase_migration.sql'));
    // Minimal Storage metadata fixture; this disposable schema is not a
    // production Supabase Storage service and verifies bucket SQL semantics.
    await client.query(`CREATE SCHEMA storage;
      CREATE TABLE storage.buckets (
        id text PRIMARY KEY,
        name text NOT NULL,
        public boolean NOT NULL DEFAULT false,
        file_size_limit bigint,
        allowed_mime_types text[]
      )`);
    await client.query(sqlFile('supabase/staging/001_catalog_read.sql'));
    await client.query(sqlFile('supabase/staging/002_dealer_profile_addresses.sql'));
    await client.query(sqlFile('supabase/staging/003_dealer_cart.sql'));

    const authA = '00000000-0000-4000-8000-000000000001';
    const authB = '00000000-0000-4000-8000-000000000002';
    const authAdmin = '00000000-0000-4000-8000-000000000003';
    const authLegacy = '00000000-0000-4000-8000-000000000004';
    const authNewDealer = '00000000-0000-4000-8000-000000000005';
    const authUnverified = '00000000-0000-4000-8000-000000000006';
    const authEmployee = '00000000-0000-4000-8000-000000000007';
    await client.query(`
      INSERT INTO auth.users
        (id,email,email_confirmed_at,raw_user_meta_data,raw_app_meta_data) VALUES
        ($1,'dealer-a@example.test',CURRENT_TIMESTAMP,'{}'::jsonb,'{}'::jsonb),
        ($2,'dealer-b@example.test',CURRENT_TIMESTAMP,'{}'::jsonb,'{}'::jsonb),
        ($3,'admin@example.test',CURRENT_TIMESTAMP,'{}'::jsonb,'{"role":"admin"}'::jsonb),
        ($4,'legacy@example.test',CURRENT_TIMESTAMP,
          '{"name":"Linked Dealer","mobile":"9000000004"}'::jsonb,'{}'::jsonb),
        ($5,'new-dealer@example.test',CURRENT_TIMESTAMP,
          '{"name":"New Dealer","mobile":"9000000005","role":"admin"}'::jsonb,'{}'::jsonb),
        ($6,'unverified@example.test',NULL,'{}'::jsonb,'{}'::jsonb),
        ($7,'employee@example.test',CURRENT_TIMESTAMP,'{}'::jsonb,'{"role":"shop_employee"}'::jsonb)
    `, [authA, authB, authAdmin, authLegacy, authNewDealer, authUnverified, authEmployee]);
    await client.query(`
      INSERT INTO public.users
        (id,auth_user_id,email,name,password_hash,status,is_approved)
      VALUES
        ('dealer-a',$1,'dealer-a@example.test','Dealer A','!disabled','approved',true),
        ('dealer-b',$2,'dealer-b@example.test','Dealer B','!disabled','pending',false)
    `, [authA, authB]);
    await client.query(`
      INSERT INTO public.users
        (id,auth_user_id,email,name,password_hash,email_verified,status,is_approved)
      VALUES ('legacy-dealer',NULL,'legacy@example.test','Legacy Dealer','!legacy',false,'pending',false)
    `);
    await client.query(`
      INSERT INTO public.categories(id,key_name,title) VALUES ('cat-a','filters','Filters');
      INSERT INTO public.products
        (id,category_id,category_key,sku,name,brand,price,mrp,purchase_price,stock_quantity,status)
      VALUES
        ('product-a','cat-a','filters','SKU-A','Filter A','RO',10,12,4,5,'active'),
        ('product-b','cat-a','filters','SKU-B','Filter B','RO',20,24,8,8,'active')
    `);

    // The admin catalog and bulk-import SQL drafts are exercised only in this
    // disposable database. Production remains on Express until equivalent
    // Edge Function/Auth/browser integration has passed.
    await client.query(sqlFile('supabase/drafts/unreconciled/20261029_admin_catalog.sql'));
    await client.query(sqlFile('supabase/drafts/unreconciled/20261030_admin_bulk_import.sql'));
    await client.query(`INSERT INTO public.categories(id,key_name,title)
      VALUES ('cat-spares','spares','Spares')`);

    await client.query('SET ROLE authenticated');
    await assert.rejects(client.query(`SELECT public.ro_admin_create_category(
      $1,'cat-denied','{"title":"Denied","key_name":"denied"}'::jsonb
    )`, [authAdmin]), error => error.code === '42501',
    'ordinary authenticated clients cannot execute admin category RPCs');
    await client.query('RESET ROLE');

    await client.query('SET ROLE service_role');
    await assert.rejects(client.query(`SELECT public.ro_admin_create_category(
      $1,'cat-not-admin','{"title":"Not Admin","key_name":"not-admin"}'::jsonb
    )`, [authA]), error => error.code === '42501',
    'the RPC refuses a verified but non-admin Auth identity');
    const createdAdminCategory = await client.query(`SELECT public.ro_admin_create_category(
      $1,'cat-admin','{"title":"Admin Category","key_name":"admin-category","image_url":"https://images.example.test/category.png"}'::jsonb
    ) AS result`, [authAdmin]);
    assert.equal(createdAdminCategory.rows[0].result.key_name, 'admin-category');
    const renamedAdminCategory = await client.query(`SELECT public.ro_admin_update_category(
      $1,'cat-a','{"title":"Filter Media","key_name":"filter-media"}'::jsonb
    ) AS result`, [authAdmin]);
    assert.equal(renamedAdminCategory.rows[0].result.key_name, 'filter-media');
    await client.query('RESET ROLE');
    const renamedProduct = await client.query(`SELECT category_key FROM public.products
      WHERE id='product-a'`);
    assert.equal(renamedProduct.rows[0].category_key, 'filter-media',
      'category rename keeps existing product category keys synchronized');

    await client.query(`INSERT INTO public.categories(id,key_name,title)
      VALUES ('cat-to-delete','delete-me','Delete Me')`);
    await client.query(`INSERT INTO public.products
      (id,category_id,category_key,sku,name,brand,price,mrp,purchase_price,stock_quantity,status)
      VALUES ('product-to-reassign','cat-to-delete','delete-me','SKU-DELETE-TEST',
        'Delete Test Product','RO',1,2,0,1,'active')`);
    await client.query('SET ROLE service_role');
    const deletedAdminCategory = await client.query(`SELECT public.ro_admin_delete_category(
      $1,'cat-to-delete'
    ) AS result`, [authAdmin]);
    assert.equal(deletedAdminCategory.rows[0].result.reassignedCount, 1,
      'category delete reassigns linked products to the existing Spares category');
    await client.query('RESET ROLE');
    const reassignedProduct = await client.query(`SELECT category_id,category_key
      FROM public.products WHERE id='product-to-reassign'`);
    assert.deepEqual(reassignedProduct.rows[0], { category_id: 'cat-spares', category_key: 'spares' });

    const validBulkRow = {
      id: 'bulk-product-one', category_id: 'cat-a', category_key: 'filter-media',
      sku: 'BULK-LOCAL-1', name: 'Local Bulk Product', brand: 'RO',
      purchase_price: 10, price: 20, mrp: 25, moq: '1', badge: '', rating: '',
      img: '', description: 'Synthetic import fixture', specs_json: {}, features_json: [],
      applications: '', status: 'active', stock_quantity: 7, min_stock: 1,
    };
    const validBulkRows = [
      validBulkRow,
      { ...validBulkRow, id: 'bulk-existing-sku', sku: 'SKU-A' },
      { ...validBulkRow, id: 'bulk-duplicate-row', name: 'Duplicate Row' },
    ];
    await client.query('SET ROLE service_role');
    const imported = await client.query(`SELECT public.ro_admin_bulk_import_products(
      $1,$2,$3::jsonb,'[]'::jsonb
    ) AS result`, [authAdmin, 'a'.repeat(64), JSON.stringify(validBulkRows)]);
    assert.equal(imported.rows[0].result.importedCount, 1);
    assert.equal(imported.rows[0].result.skippedCount, 2,
      'bulk import skips existing database SKUs and duplicate SKUs within the batch');
    const replayed = await client.query(`SELECT public.ro_admin_bulk_import_products(
      $1,$2,$3::jsonb,'[]'::jsonb
    ) AS result`, [authAdmin, 'a'.repeat(64), JSON.stringify(validBulkRows)]);
    assert.equal(replayed.rows[0].result.replayed, true,
      'repeating an identical import fingerprint returns the stored outcome');
    await client.query('RESET ROLE');
    const bulkProductCount = await client.query(`SELECT count(*)::int AS count FROM public.products
      WHERE sku='BULK-LOCAL-1'`);
    assert.equal(bulkProductCount.rows[0].count, 1,
      'idempotent retry does not insert a duplicate product');

    await client.query('SET ROLE service_role');
    await assert.rejects(client.query(`SELECT public.ro_admin_bulk_import_products(
      $1,$2,$3::jsonb,'[]'::jsonb
    )`, [authAdmin, 'b'.repeat(64), JSON.stringify([{
      ...validBulkRow, id: 'invalid-price-product', sku: 'INVALID-PRICE', price: 'not-a-number',
    }])]), error => error.code === 'P0001',
    'the import RPC rejects invalid price types before writing product rows');
    await client.query('RESET ROLE');
    const invalidProductCount = await client.query(`SELECT count(*)::int AS count
      FROM public.products WHERE sku='INVALID-PRICE'`);
    assert.equal(invalidProductCount.rows[0].count, 0,
      'failed batch leaves no partially imported product');

    await setDealer(client, authLegacy, 'legacy@example.test');
    const linkedLegacy = await client.query('SELECT public.sync_current_dealer_profile() AS profile');
    assert.equal(linkedLegacy.rows[0].profile.id, 'legacy-dealer');
    await client.query('RESET ROLE');
    const legacyState = await client.query(`
      SELECT auth_user_id,email_verified,status,is_approved FROM public.users WHERE id='legacy-dealer'
    `);
    assert.equal(legacyState.rows[0].auth_user_id, authLegacy);
    assert.equal(legacyState.rows[0].email_verified, true);
    assert.equal(legacyState.rows[0].status, 'pending', 'linking must preserve pending approval');
    assert.equal(legacyState.rows[0].is_approved, false, 'linking must not approve a dealer');
    await setDealer(client, authLegacy, 'legacy@example.test');
    await assert.rejects(client.query(`UPDATE public.users SET status='approved',is_approved=true
      WHERE id='legacy-dealer'`), error => error.code === '42501',
    'dealer cannot directly self-approve through table grants');

    await setDealer(client, authNewDealer, 'new-dealer@example.test');
    const createdDealer = await client.query('SELECT public.sync_current_dealer_profile() AS profile');
    assert.equal(createdDealer.rows[0].profile.status, 'pending');
    assert.equal(createdDealer.rows[0].profile.isApproved, false,
      'user metadata role must not grant approval or admin status');
    await client.query('RESET ROLE');
    const newDealerState = await client.query(`
      SELECT status,is_approved FROM public.users WHERE auth_user_id=$1
    `, [authNewDealer]);
    assert.equal(newDealerState.rows[0].status, 'pending');
    assert.equal(newDealerState.rows[0].is_approved, false);

    await setDealer(client, authUnverified, 'unverified@example.test');
    await assert.rejects(client.query('SELECT public.sync_current_dealer_profile()'),
      error => error.code === '28000', 'unverified Auth accounts cannot create/link dealer profiles');

    // Saved-address/profile stage: verify the actual SQL grants, RLS, and RPCs
    // under the authenticated database role rather than only asserting SQL text.
    await setDealer(client, authA, 'dealer-a@example.test');
    let ownProfiles = await client.query('SELECT id,name,status,is_approved FROM public.users');
    assert.deepEqual(ownProfiles.rows, [{
      id: 'dealer-a', name: 'Dealer A', status: 'approved', is_approved: true,
    }]);
    const addressOne = await client.query(`SELECT public.ro_save_dealer_address(
      'address-a-1','Warehouse','Dealer A Co','12 Market Road','Pune','Maharashtra',
      '411001','9876543210','Dealer A','12','Industrial Estate','Pune','Near Market',
      'Warehouse','27AAPFU0939F1ZV',true
    ) AS id`);
    assert.equal(addressOne.rows[0].id, 'address-a-1');
    const addressTwo = await client.query(`SELECT public.ro_save_dealer_address(
      'address-a-2','Office','Dealer A Co','8 Lake Road','Pune','Maharashtra',
      '411002','9876543210','Dealer A','8','Camp','Pune','',
      'Office','',true
    ) AS id`);
    assert.equal(addressTwo.rows[0].id, 'address-a-2');
    let ownAddresses = await client.query(`SELECT id,user_id,is_default,street
      FROM public.user_addresses ORDER BY id`);
    assert.deepEqual(ownAddresses.rows, [
      { id: 'address-a-1', user_id: 'dealer-a', is_default: false, street: '12 Market Road' },
      { id: 'address-a-2', user_id: 'dealer-a', is_default: true, street: '8 Lake Road' },
    ], 'saving a new default clears the previous default for that dealer');
    await client.query("SELECT public.ro_set_default_dealer_address('address-a-1')");
    ownAddresses = await client.query(`SELECT id,is_default FROM public.user_addresses ORDER BY id`);
    assert.deepEqual(ownAddresses.rows, [
      { id: 'address-a-1', is_default: true },
      { id: 'address-a-2', is_default: false },
    ]);
    await client.query(`SELECT public.ro_update_current_dealer_profile(
      'Dealer A Updated','9876543211','Updated Co','Updated address')`);
    await assert.rejects(client.query("UPDATE public.users SET status='pending' WHERE id='dealer-a'"),
      error => error.code === '42501', 'dealer cannot modify approval status');

    await setDealer(client, authB, 'dealer-b@example.test');
    ownProfiles = await client.query('SELECT id FROM public.users');
    assert.deepEqual(ownProfiles.rows, [{ id: 'dealer-b' }], 'dealer B cannot read dealer A profile');
    ownAddresses = await client.query('SELECT id FROM public.user_addresses');
    assert.deepEqual(ownAddresses.rows, [], 'dealer B cannot read dealer A addresses');
    await assert.rejects(client.query(`SELECT public.ro_set_default_dealer_address('address-a-1')`),
      error => error.code === 'P0002', 'dealer B cannot set dealer A address as default');
    await assert.rejects(client.query(`SELECT public.ro_save_dealer_address(
      'address-a-1','Office','Attacker Co','1 Main Road','Pune','Maharashtra',
      '411001','9000000002','Dealer B','1','Camp','Pune','','Office','',true
    )`), error => error.code === '42501', 'dealer B cannot overwrite dealer A address by reusing its ID');
    await client.query("DELETE FROM public.user_addresses WHERE id='address-a-1'");
    await client.query('RESET ROLE');
    const retainedAddress = await client.query("SELECT id FROM public.user_addresses WHERE id='address-a-1'");
    assert.equal(retainedAddress.rowCount, 1, 'dealer B cannot delete dealer A address');
    await setDealer(client, authB, 'dealer-b@example.test');
    await assert.rejects(client.query("UPDATE public.users SET name='Attacker' WHERE id='dealer-a'"),
      error => error.code === '42501', 'dealer B cannot update profiles directly');
    await client.query('RESET ROLE');
    const retainedProfile = await client.query("SELECT name FROM public.users WHERE id='dealer-a'");
    assert.equal(retainedProfile.rows[0].name, 'Dealer A Updated', 'dealer B cannot update dealer A profile');

    await setDealer(client, authA, 'dealer-a@example.test');
    await client.query("DELETE FROM public.user_addresses WHERE id='address-a-1'");
    const deletedOwnAddress = await client.query("SELECT id FROM public.user_addresses WHERE id='address-a-1'");
    assert.equal(deletedOwnAddress.rowCount, 0, 'dealer can delete an address they own');
    await client.query('RESET ROLE');
    await client.query('SET ROLE anon');
    await assert.rejects(client.query('SELECT id FROM public.users'), error => error.code === '42501');
    await assert.rejects(client.query(`SELECT public.ro_save_dealer_address(
      'anonymous-address','Office',NULL,'1 Main Road','Pune','Maharashtra',
      '411001','9000000000','Anonymous',NULL,NULL,'Pune',NULL,'Office',NULL,false
    )`), error => error.code === '42501', 'anonymous clients cannot invoke dealer address RPCs');
    await client.query('RESET ROLE');

    await setDealer(client, authA, 'dealer-a@example.test');
    await client.query(`SELECT public.ro_add_cart_item(
      'product-a',2,'10000000-0000-4000-8000-000000000001'
    )`);
    // Replaying the same request must not add the quantity a second time.
    await client.query(`SELECT public.ro_add_cart_item(
      'product-a',2,'10000000-0000-4000-8000-000000000001'
    )`);
    let cart = await client.query('SELECT product_id,quantity FROM public.cart_items');
    assert.deepEqual(cart.rows, [{ product_id: 'product-a', quantity: 2 }]);

    await assert.rejects(client.query(`SELECT public.ro_add_cart_item(
      'product-a',3,'10000000-0000-4000-8000-000000000001'
    )`), (error) => error.code === '22023');
    await assert.rejects(client.query(`SELECT public.ro_add_cart_item(
      'product-a',4,'10000000-0000-4000-8000-000000000002'
    )`), (error) => error.code === '23514');
    cart = await client.query('SELECT product_id,quantity FROM public.cart_items');
    assert.deepEqual(cart.rows, [{ product_id: 'product-a', quantity: 2 }]);

    await client.query(`SELECT public.ro_add_cart_item(
      'product-a',3,'10000000-0000-4000-8000-000000000002'
    )`);
    await client.query(`SELECT public.ro_update_cart_item('product-a',5)`);
    await assert.rejects(client.query(`SELECT public.ro_update_cart_item('product-a',6)`),
      (error) => error.code === '23514');

    await setDealer(client, authB, 'dealer-b@example.test');
    cart = await client.query('SELECT product_id,quantity FROM public.cart_items');
    assert.deepEqual(cart.rows, [], 'dealer B cannot read dealer A cart');
    await client.query(`SELECT public.ro_add_cart_item(
      'product-a',1,'20000000-0000-4000-8000-000000000001'
    )`);
    cart = await client.query('SELECT product_id,quantity FROM public.cart_items');
    assert.deepEqual(cart.rows, [{ product_id: 'product-a', quantity: 1 }]);

    const concurrentClients = [new Client({ connectionString: localUrl }), new Client({ connectionString: localUrl })];
    await Promise.all(concurrentClients.map((connection) => connection.connect()));
    try {
      await Promise.all(concurrentClients.map((connection) =>
        setDealer(connection, authB, 'dealer-b@example.test')));
      const sameRequest = await Promise.allSettled(concurrentClients.map((connection) =>
        connection.query(`SELECT public.ro_add_cart_item(
          'product-b',2,'20000000-0000-4000-8000-000000000002'
        )`)));
      assert.ok(sameRequest.every((result) => result.status === 'fulfilled'),
        'concurrent replay of one request key must be accepted');
      let dealerBCart = await client.query(
        "SELECT product_id,quantity FROM public.cart_items WHERE product_id='product-b'",
      );
      assert.deepEqual(dealerBCart.rows, [{ product_id: 'product-b', quantity: 2 }],
        'concurrent identical retries apply the add once');

      const competingAdds = await Promise.allSettled(concurrentClients.map((connection, index) =>
        connection.query(`SELECT public.ro_add_cart_item(
          'product-b',5,$1::uuid
        )`, [index === 0
          ? '20000000-0000-4000-8000-000000000003'
          : '20000000-0000-4000-8000-000000000004'])));
      assert.equal(competingAdds.filter((result) => result.status === 'fulfilled').length, 1,
        'row locking must prevent concurrent adds from exceeding stock');
      assert.equal(competingAdds.filter((result) => result.status === 'rejected').length, 1);
      dealerBCart = await client.query(
        "SELECT product_id,quantity FROM public.cart_items WHERE product_id='product-b'",
      );
      assert.deepEqual(dealerBCart.rows, [{ product_id: 'product-b', quantity: 7 }]);
    } finally {
      await Promise.all(concurrentClients.map((connection) => connection.end()));
    }

    const freshClient = new Client({ connectionString: localUrl });
    await freshClient.connect();
    try {
      await setDealer(freshClient, authA, 'dealer-a@example.test');
      cart = await freshClient.query('SELECT product_id,quantity FROM public.cart_items');
      assert.deepEqual(cart.rows, [{ product_id: 'product-a', quantity: 5 }],
        'cart remains persisted across a new connection/session');
    } finally {
      await freshClient.end();
    }

    await client.query('RESET ROLE');
    await client.query(`INSERT INTO public.orders
      (order_id,user_id,user_email,user_name,delivery_address,invoice_number,with_gst)
      VALUES
        ('order-a','dealer-a','dealer-a@example.test','Dealer A','local','INV-A',true),
        ('order-b','dealer-b','dealer-b@example.test','Dealer B','local','INV-B',false),
        ('legacy-order-a',NULL,'dealer-a@example.test','Legacy Dealer A','local','INV-LA',false),
        ('unverified-order',NULL,'unverified@example.test','Unverified Dealer','local','INV-U',false)`);
    await client.query(`INSERT INTO public.order_items(order_id,product_id,product_name,unit_price,quantity)
      VALUES ('order-a','product-a','Filter A',10,1),('order-b','product-b','Filter B',20,2),
        ('legacy-order-a','product-a','Legacy Filter A',10,1),
        ('unverified-order','product-b','Unverified Filter',20,2)`);
    await client.query(`INSERT INTO public.rewards_history(user_id,order_id,order_amount,points_earned)
      VALUES ('dealer-a','order-a',10,1),('dealer-b','order-b',40,4)`);
    await client.query(`INSERT INTO public.support_tickets(user_id,user_email,subject,message)
      VALUES (NULL,'dealer-a@example.test','Legacy A','Verified legacy ticket'),
        (NULL,'unverified@example.test','Unverified','Must remain private')`);
    await client.query(sqlFile('supabase/staging/004_dealer_order_history.sql'));
    await client.query(sqlFile('supabase/staging/005_product_image_storage.sql'));
    await client.query(sqlFile('supabase/staging/005_product_image_storage.sql'));
    const imageBucket = await client.query(`SELECT id,name,public,file_size_limit,
      allowed_mime_types FROM storage.buckets WHERE id='ro-product-images'`);
    assert.deepEqual(imageBucket.rows, [{
      id: 'ro-product-images',
      name: 'ro-product-images',
      public: true,
      file_size_limit: '5242880',
      allowed_mime_types: ['image/jpeg', 'image/png', 'image/webp'],
    }], 'the bucket is narrowly configured and a compatible rerun is a no-op');

    await setDealer(client, authA, 'dealer-a@example.test');
    const visibleOrders = await client.query('SELECT order_id FROM public.orders ORDER BY order_id');
    assert.deepEqual(visibleOrders.rows, [
      { order_id: 'legacy-order-a' }, { order_id: 'order-a' },
    ], 'verified dealer can read its linked and email-matched legacy order');
    const visibleItems = await client.query('SELECT order_id FROM public.order_items ORDER BY order_id');
    assert.deepEqual(visibleItems.rows, [
      { order_id: 'legacy-order-a' }, { order_id: 'order-a' },
    ], 'order-item visibility follows the same verified parent-order ownership');
    const visibleRewards = await client.query('SELECT order_id FROM public.rewards_history');
    assert.deepEqual(visibleRewards.rows, [{ order_id: 'order-a' }]);
    const visibleInvoices = await client.query(`
      SELECT order_id,invoice_number FROM public.orders WHERE with_gst=true
    `);
    assert.deepEqual(visibleInvoices.rows, [{ order_id: 'order-a', invoice_number: 'INV-A' }]);

    await client.query(`SELECT public.ro_create_support_ticket('Local test','Staging policy test')`);
    const ownTickets = await client.query('SELECT user_id FROM public.support_tickets ORDER BY id');
    assert.deepEqual(ownTickets.rows, [
      { user_id: null }, { user_id: 'dealer-a' },
    ], 'dealer sees only own tickets and verified-email legacy tickets');

    await setDealer(client, authUnverified, 'unverified@example.test');
    assert.deepEqual((await client.query('SELECT order_id FROM public.orders')).rows, [],
      'unconfirmed JWT email cannot expose a legacy order with a matching email');
    assert.deepEqual((await client.query('SELECT id FROM public.order_items')).rows, [],
      'unconfirmed JWT email cannot expose line items from a legacy order');
    assert.deepEqual((await client.query('SELECT id FROM public.support_tickets')).rows, [],
      'unconfirmed JWT email cannot expose a legacy support ticket');
    await assert.rejects(client.query(`SELECT public.ro_create_support_ticket('No email','Denied')`),
      error => error.code === '28000', 'unverified users cannot create support tickets');

    await client.query('RESET ROLE');
    // The production schema audit reports this existing shop table, but the
    // base schema fixture intentionally omits it. Model only the columns this
    // RPC requires; this table exists solely in the disposable test database.
    await client.query(`CREATE TABLE public.shop_delivery_items (
      order_id varchar(64) NOT NULL,
      order_item_id bigint NOT NULL,
      delivered boolean NOT NULL DEFAULT false,
      delivered_quantity integer NOT NULL DEFAULT 0,
      undelivered_quantity integer NOT NULL DEFAULT 0,
      delivered_amount numeric(10,2) NOT NULL DEFAULT 0,
      refund_amount numeric(10,2) NOT NULL DEFAULT 0,
      refund_status varchar(32) NOT NULL DEFAULT 'not_required',
      recorded_by bigint,
      delivered_at timestamp without time zone,
      updated_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`);
    await client.query(`CREATE TABLE public.shop_employees (
      id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
      shop_name varchar(191) NOT NULL,
      active boolean NOT NULL DEFAULT true
    )`);
    await client.query(`CREATE TABLE public.shop_admin_notifications (
      order_id varchar(64) NOT NULL,
      employee_id bigint,
      notification_type varchar(64) NOT NULL,
      message text NOT NULL,
      refund_amount numeric(10,2) NOT NULL DEFAULT 0,
      created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
      read_at timestamp without time zone
    )`);
    await client.query(`INSERT INTO public.shop_employees(shop_name,active)
      VALUES ('Local Test Shop',true)`);
    await client.query(sqlFile('supabase/drafts/unreconciled/20261031_shop_delivery.sql'));
    await client.query(`UPDATE public.shop_employees SET auth_user_id=$1 WHERE shop_name='Local Test Shop'`, [authEmployee]);
    await client.query('SET ROLE authenticated');
    await assert.rejects(client.query('SELECT order_id FROM public.shop_order_assignments'),
      error => error.code === '42501', 'dealer client cannot read shop assignments');
    await assert.rejects(client.query('SELECT order_id FROM public.shop_cash_collections'),
      error => error.code === '42501', 'dealer client cannot read COD collection ledger');
    await client.query('RESET ROLE');
    await client.query(sqlFile('supabase/drafts/unreconciled/20261028_admin_order_status.sql'));

    await client.query('SET ROLE authenticated');
    await assert.rejects(client.query(`SELECT public.ro_admin_update_order_status(
      $1,'order-b','Shipped'
    )`, [authAdmin]), error => error.code === '42501',
    'browser authenticated role must not execute the privileged status RPC');
    await client.query('RESET ROLE');
    await client.query('SET ROLE service_role');
    const changedStatus = await client.query(`SELECT public.ro_admin_update_order_status(
      $1,'order-b','Shipped'
    ) AS result`, [authAdmin]);
    assert.equal(changedStatus.rows[0].result.status, 'Shipped');
    await client.query('RESET ROLE');
    const storedStatus = await client.query("SELECT status FROM public.orders WHERE order_id='order-b'");
    assert.equal(storedStatus.rows[0].status, 'Shipped');
    await client.query('SET ROLE service_role');
    await assert.rejects(client.query(`SELECT public.ro_admin_update_order_status(
      $1,'order-a','Delivered'
    )`, [authAdmin]), error => error.code === '55000',
    'an incomplete order cannot be set to Delivered');
    await assert.rejects(client.query(`SELECT public.ro_admin_update_order_status(
      $1,'missing-order','Shipped'
    )`, [authAdmin]), error => error.code === 'P0002');
    await assert.rejects(client.query(`SELECT public.ro_admin_update_order_status(
      $1,'order-a','Shipped'
    )`, [authA]), error => error.code === '28000',
    'dealer identity cannot call the admin RPC even through service role');
    await client.query('RESET ROLE');
    await client.query(`INSERT INTO public.shop_delivery_items(order_id,order_item_id,delivered,delivered_quantity)
      SELECT 'order-b',id,true,1 FROM public.order_items WHERE order_id='order-b' LIMIT 1`);
    await client.query('SET ROLE service_role');
    await assert.rejects(client.query(`SELECT public.ro_admin_update_order_status(
      $1,'order-b','Processing'
    )`, [authAdmin]), error => error.code === '55000',
    'submitted shop delivery owns the order status');
    await client.query('RESET ROLE');

    // A local-only checkout fixture validates the actual checkout/refund SQL
    // transactions against PostgreSQL. Shop assignment and employee tables
    // here are synthetic and are not claims about the live schema.
    await client.query(`UPDATE public.users SET email_verified=true WHERE id='dealer-a';
      INSERT INTO public.products
        (id,category_id,category_key,sku,name,brand,price,mrp,purchase_price,stock_quantity,status)
      VALUES ('checkout-fixture-product','cat-a','filters','CHECKOUT-LOCAL-1',
        'Checkout Fixture Product','Local Test',10,12,4,5,'active')`);
    await client.query(sqlFile('supabase/drafts/unreconciled/20261027_secure_checkout.sql'));
    await client.query(sqlFile('supabase/drafts/unreconciled/20261028_checkout_refund_reconciliation.sql'));
    const serviceQuery = async (sql, params = []) => {
      await client.query('SET ROLE service_role');
      try { return await client.query(sql, params); }
      finally { await client.query('RESET ROLE'); }
    };
    const checkoutPayload = {
      paymentMethod: 'Cash on Delivery',
      items: [{ id: 'checkout-fixture-product', quantity: 2 }],
      withGst: false,
      sameAsDelivery: true,
      deliveryAddress: { name: 'Dealer A', mobile: '9876543210', address: '12 Main Road',
        city: 'Pune', state: 'Maharashtra', pincode: '411001' },
    };
    const codRequestId = '10000000-0000-4000-8000-000000000001';
    const cod = await serviceQuery(`SELECT public.ro_finalize_checkout(
      $1,$2,$3::jsonb,NULL,NULL,NULL) AS result`,
    [authA, codRequestId, JSON.stringify(checkoutPayload)]);
    assert.equal(cod.rows[0].result.success, true);
    assert.equal(cod.rows[0].result.order.paymentStatus, 'due_on_delivery');
    const codOrderId = cod.rows[0].result.order.orderId;
    const afterCod = await client.query(`SELECT stock_quantity FROM public.products
      WHERE id='checkout-fixture-product'`);
    assert.equal(afterCod.rows[0].stock_quantity, 3, 'COD commit deducts server-verified stock once');
    const codAssignment = await client.query(
      'SELECT shop_name FROM public.shop_order_assignments WHERE order_id=$1', [codOrderId]);
    assert.deepEqual(codAssignment.rows, [{ shop_name: 'Local Test Shop' }]);
    const codReplay = await serviceQuery(`SELECT public.ro_finalize_checkout(
      $1,$2,$3::jsonb,NULL,NULL,NULL) AS result`,
    [authA, codRequestId, JSON.stringify(checkoutPayload)]);
    assert.equal(codReplay.rows[0].result.idempotent, true,
      'same COD request returns the saved order without a second inventory movement');
    assert.equal((await client.query(`SELECT stock_quantity FROM public.products
      WHERE id='checkout-fixture-product'`)).rows[0].stock_quantity, 3);

    const codCancel = await serviceQuery(
      'SELECT public.ro_cancel_checkout_order($1,$2) AS result', [authA, codOrderId]);
    assert.equal(codCancel.rows[0].result.inventoryRestocked, true);
    const cancelReplay = await serviceQuery(
      'SELECT public.ro_cancel_checkout_order($1,$2) AS result', [authA, codOrderId]);
    assert.equal(cancelReplay.rows[0].result.idempotent, true);
    assert.equal((await client.query(`SELECT stock_quantity FROM public.products
      WHERE id='checkout-fixture-product'`)).rows[0].stock_quantity, 5,
    'repeated cancellation cannot restock the same order twice');

    const deliveredPayload = { ...checkoutPayload, items: [{ id: 'checkout-fixture-product', quantity: 1 }] };
    const deliveryRequestId = '10000000-0000-4000-8000-000000000002';
    const pendingDeliveryOrder = await serviceQuery(`SELECT public.ro_finalize_checkout(
      $1,$2,$3::jsonb,NULL,NULL,NULL) AS result`,
    [authA, deliveryRequestId, JSON.stringify(deliveredPayload)]);
    const deliveryOrderId = pendingDeliveryOrder.rows[0].result.order.orderId;
    const deliveryItem = await client.query(
      'SELECT id FROM public.order_items WHERE order_id=$1 LIMIT 1', [deliveryOrderId]);
    await client.query(`INSERT INTO public.shop_delivery_items(order_id,order_item_id,delivered,delivered_quantity)
      VALUES ($1,$2,true,1)`, [deliveryOrderId, deliveryItem.rows[0].id]);
    await assert.rejects(serviceQuery(
      'SELECT public.ro_cancel_checkout_order($1,$2)', [authA, deliveryOrderId]),
    error => error.code === 'P0001',
    'checkout cancellation cannot restock an order after shop delivery activity exists');
    assert.equal((await client.query(`SELECT stock_quantity FROM public.products
      WHERE id='checkout-fixture-product'`)).rows[0].stock_quantity, 4,
    'delivery guard leaves the original inventory deduction intact');

    const razorPayload = { ...checkoutPayload, paymentMethod: 'Razorpay',
      items: [{ id: 'checkout-fixture-product', quantity: 1 }] };
    const razorRequestId = '10000000-0000-4000-8000-000000000003';
    const quote = await serviceQuery('SELECT public.ro_checkout_quote($1,$2::jsonb) AS result',
      [authA, JSON.stringify(razorPayload)]);
    const amountPaise = Math.round(Number(quote.rows[0].result.grandTotal) * 100);
    const gatewayOrderId = 'local_gateway_order_001';
    const registered = await serviceQuery(`SELECT public.ro_register_razorpay_checkout(
      $1,$2,$3::jsonb,$4,$5) AS result`,
    [authA, razorRequestId, JSON.stringify(razorPayload), gatewayOrderId, amountPaise]);
    assert.equal(registered.rows[0].result.amountPaise, amountPaise);
    const paid = await serviceQuery(`SELECT public.ro_finalize_checkout(
      $1,$2,$3::jsonb,$4,$5,NULL) AS result`,
    [authA, razorRequestId, JSON.stringify(razorPayload), gatewayOrderId, 'local_payment_001']);
    assert.equal(paid.rows[0].result.order.paymentStatus, 'paid');
    const paidReplay = await serviceQuery(`SELECT public.ro_finalize_checkout(
      $1,$2,$3::jsonb,$4,$5,NULL) AS result`,
    [authA, razorRequestId, JSON.stringify(razorPayload), gatewayOrderId, 'local_payment_001']);
    assert.equal(paidReplay.rows[0].result.idempotent, true,
      'verified payment finalization is idempotent for the same request/payment');
    await assert.rejects(serviceQuery(
      'SELECT public.ro_cancel_checkout_order($1,$2)', [authA, paid.rows[0].result.order.orderId]),
    error => error.code === 'P0001', 'paid Razorpay orders cannot use the COD cancellation/restock path');

    await assert.rejects(serviceQuery('SELECT public.ro_checkout_quote($1,$2::jsonb)',
      [authB, JSON.stringify(checkoutPayload)]), error => error.code === '42501',
    'unapproved dealer cannot obtain a checkout quote');
    const oversoldPayload = { ...checkoutPayload, items: [{ id: 'checkout-fixture-product', quantity: 99 }] };
    await assert.rejects(serviceQuery('SELECT public.ro_checkout_quote($1,$2::jsonb)',
      [authA, JSON.stringify(oversoldPayload)]), error => error.code === 'P0001',
    'checkout quote rejects insufficient stock');

    const refundRequestId = '10000000-0000-4000-8000-000000000004';
    const refundQuote = await serviceQuery('SELECT public.ro_checkout_quote($1,$2::jsonb) AS result',
      [authA, JSON.stringify(razorPayload)]);
    const refundAmount = Math.round(Number(refundQuote.rows[0].result.grandTotal) * 100);
    const refundGatewayOrder = 'local_gateway_order_002';
    await serviceQuery(`SELECT public.ro_register_razorpay_checkout($1,$2,$3::jsonb,$4,$5)`,
      [authA, refundRequestId, JSON.stringify(razorPayload), refundGatewayOrder, refundAmount]);
    const openedRefund = await serviceQuery(`SELECT public.ro_open_checkout_refund_reconciliation(
      $1,$2,$3,$4,$5,'stock_changed') AS result`,
    [authA, refundRequestId, refundGatewayOrder, 'local_payment_recovery_001', refundAmount]);
    assert.equal(openedRefund.rows[0].result.state, 'pending');
    const firstClaim = await serviceQuery(
      "SELECT public.ro_claim_checkout_refund('local_payment_recovery_001') AS result");
    const retryClaim = await serviceQuery(
      "SELECT public.ro_claim_checkout_refund('local_payment_recovery_001') AS result");
    assert.equal(firstClaim.rows[0].result.claimed, true);
    assert.equal(retryClaim.rows[0].result.claimed, false,
      'refund claim cannot be processed twice concurrently/repeatedly');
    const savedRefundState = await serviceQuery(`SELECT public.ro_set_checkout_refund_state(
      'local_payment_recovery_001','submitted','local_refund_001','pending',NULL) AS result`);
    assert.equal(savedRefundState.rows[0].result.state, 'submitted');

    // Delivery draft uses only synthetic Auth employees/order assignments in
    // this disposable PostgreSQL fixture. Production remains on Express.
    const shopDeliveryRequestId = '10000000-0000-4000-8000-000000000005';
    const deliveryPayload = { ...checkoutPayload, items: [{ id: 'checkout-fixture-product', quantity: 2 }] };
    const createdDeliveryOrder = await serviceQuery(`SELECT public.ro_finalize_checkout(
      $1,$2,$3::jsonb,NULL,NULL,NULL) AS result`,
    [authA, shopDeliveryRequestId, JSON.stringify(deliveryPayload)]);
    const shopDeliveryOrderId = createdDeliveryOrder.rows[0].result.order.orderId;
    const [deliveryLine] = (await client.query(
      'SELECT id,quantity,unit_price FROM public.order_items WHERE order_id=$1', [shopDeliveryOrderId])).rows;
    const partialDeliveryInput = [{ orderItemId: Number(deliveryLine.id), deliveredQuantity: 1, deliveryConfirmed: true }];
    const draftDelivery = await serviceQuery(`SELECT public.ro_submit_shop_delivery(
      $1,$2,'submit',$3::jsonb,false) AS result`,
    [authEmployee, shopDeliveryOrderId, JSON.stringify(partialDeliveryInput.map(item => ({ ...item, deliveryConfirmed: false })))]);
    assert.equal(draftDelivery.rows[0].result.status, 'Pending',
      'saving a draft quantity does not confirm physical delivery');
    assert.equal(draftDelivery.rows[0].result.cashCollected, false);
    assert.equal((await client.query('SELECT delivery_confirmed,delivered_quantity FROM public.shop_delivery_items WHERE order_item_id=$1',
      [deliveryLine.id])).rows[0].delivery_confirmed, false,
    'quantity and Delivered selection remain independent in submit mode');
    assert.equal((await client.query('SELECT count(*)::int AS count FROM public.shop_admin_notifications WHERE order_id=$1',
      [shopDeliveryOrderId])).rows[0].count, 0, 'draft shortage does not notify Admin before confirmation');
    const partialDelivery = await serviceQuery(`SELECT public.ro_submit_shop_delivery(
      $1,$2,'confirm',$3::jsonb,false) AS result`,
    [authEmployee, shopDeliveryOrderId, JSON.stringify(partialDeliveryInput)]);
    assert.equal(partialDelivery.rows[0].result.status, 'Partially Delivered');
    assert.equal(partialDelivery.rows[0].result.originalOrderValue, 20,
      'original line value uses ordered quantity times immutable dealer-price snapshot');
    assert.equal(partialDelivery.rows[0].result.deliveredValue, 10);
    assert.equal(partialDelivery.rows[0].result.undeliveredQuantity, 1);
    assert.equal(partialDelivery.rows[0].result.refundAmount, 10);
    const unchangedOrderTotal = await client.query(
      'SELECT grand_total,status,payment_status FROM public.orders WHERE order_id=$1', [shopDeliveryOrderId]);
    assert.notEqual(unchangedOrderTotal.rows[0].grand_total, null);
    assert.equal(unchangedOrderTotal.rows[0].status, 'Partially Delivered');
    assert.equal(unchangedOrderTotal.rows[0].payment_status, 'due_on_delivery',
      'partial delivery does not falsely mark COD as paid');
    assert.equal((await client.query('SELECT count(*)::int AS count FROM public.shop_admin_notifications WHERE order_id=$1',
      [shopDeliveryOrderId])).rows[0].count, 1, 'partial delivery creates an Admin notification');
    await assert.rejects(serviceQuery(`SELECT public.ro_submit_shop_delivery(
      $1,$2,'confirm',$3::jsonb,false)`,
    [authA, shopDeliveryOrderId, JSON.stringify(partialDeliveryInput)]), error => error.code === '42501',
    'dealer Auth identity cannot submit delivery even through the privileged RPC');
    await assert.rejects(serviceQuery(`SELECT public.ro_submit_shop_delivery(
      $1,$2,'confirm',$3::jsonb,true)`,
    [authEmployee, shopDeliveryOrderId, JSON.stringify(partialDeliveryInput)]), error => error.code === 'P0001',
    'COD cash cannot be recorded for a partial delivery');
    const fullDeliveryInput = [{ orderItemId: Number(deliveryLine.id), deliveredQuantity: 2, deliveryConfirmed: true }];
    const fullDelivery = await serviceQuery(`SELECT public.ro_submit_shop_delivery(
      $1,$2,'confirm',$3::jsonb,true) AS result`,
    [authEmployee, shopDeliveryOrderId, JSON.stringify(fullDeliveryInput)]);
    assert.equal(fullDelivery.rows[0].result.status, 'Delivered');
    assert.equal(fullDelivery.rows[0].result.deliveredValue, 20);
    assert.equal(fullDelivery.rows[0].result.refundAmount, 0);
    assert.equal(fullDelivery.rows[0].result.cashCollected, true);
    assert.equal(fullDelivery.rows[0].result.paymentStatus, 'paid');
    const collectedCount = () => client.query(
      'SELECT count(*)::int AS count FROM public.shop_cash_collections WHERE order_id=$1', [shopDeliveryOrderId]);
    assert.equal((await collectedCount()).rows[0].count, 1);
    const deliveredReplay = await serviceQuery(`SELECT public.ro_submit_shop_delivery(
      $1,$2,'confirm',$3::jsonb,true) AS result`,
    [authEmployee, shopDeliveryOrderId, JSON.stringify(fullDeliveryInput)]);
    assert.equal(deliveredReplay.rows[0].result.cashCollected, true);
    assert.equal((await collectedCount()).rows[0].count, 1,
      'delivery retry cannot duplicate the COD collection row');
    assert.equal((await client.query('SELECT count(*)::int AS count FROM public.shop_admin_notifications WHERE order_id=$1',
      [shopDeliveryOrderId])).rows[0].count, 0, 'full delivery clears the partial-delivery notification');
    await client.query("UPDATE public.shop_delivery_items SET refund_status='refunded' WHERE order_id=$1", [shopDeliveryOrderId]);
    await assert.rejects(serviceQuery(`SELECT public.ro_submit_shop_delivery(
      $1,$2,'confirm',$3::jsonb,false)`,
    [authEmployee, shopDeliveryOrderId, JSON.stringify(partialDeliveryInput)]), error => error.code === 'P0001',
    'a processed refund prevents later quantity reduction');
    await client.query('SET ROLE anon');
    await assert.rejects(client.query('SELECT purchase_price FROM public.products'),
      (error) => error.code === '42501');
    const safeCatalog = await client.query('SELECT sku,dealer_price FROM public.catalog_products ORDER BY sku');
    assert.equal(safeCatalog.rows.length, 5,
      'catalog includes admin category/bulk-import fixtures plus one isolated checkout fixture');
    assert.ok(safeCatalog.rows.every((row) => !Object.hasOwn(row, 'purchase_price')));
  } finally {
    await client.end();
  }
});

async function setDealer(client, authId, email) {
  await client.query('RESET ROLE');
  await client.query("SELECT set_config('request.jwt.claim.sub',$1,false)", [authId]);
  await client.query("SELECT set_config('request.jwt.claims',$1,false)", [JSON.stringify({ sub: authId, email })]);
  await client.query('SET ROLE authenticated');
}
