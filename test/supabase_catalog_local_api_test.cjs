const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const { Client } = require('pg');

const apiUrl = process.env.SUPABASE_LOCAL_TEST_API_URL;
const dbUrl = process.env.SUPABASE_LOCAL_TEST_DB_URL;
const anonKey = process.env.SUPABASE_LOCAL_TEST_ANON_KEY;
const serviceKey = process.env.SUPABASE_LOCAL_TEST_SERVICE_ROLE_KEY;
const edgeFunctionUrl = process.env.SUPABASE_LOCAL_TEST_EDGE_FUNCTION_URL;
const keepImageFixture = process.env.SUPABASE_LOCAL_TEST_KEEP_IMAGE_FIXTURE === '1';
const root = path.join(__dirname, '..');
const pngFixture = createOnePixelPng();

test('local Supabase Auth, dealer profile/address RLS, catalog, and Storage are least-privilege', {
  skip: !(apiUrl && dbUrl && anonKey && serviceKey),
}, async (t) => {
  const api = new URL(apiUrl);
  const db = new URL(dbUrl);
  assert.ok(['localhost', '127.0.0.1', '::1'].includes(api.hostname),
    'catalog API integration refuses non-loopback Supabase URLs');
  assert.ok(['localhost', '127.0.0.1', '::1'].includes(db.hostname),
    'catalog database integration refuses non-loopback PostgreSQL URLs');
  assert.equal(api.port, process.env.SUPABASE_LOCAL_TEST_API_PORT ?? '54331');
  assert.equal(db.port, process.env.SUPABASE_LOCAL_TEST_DB_PORT ?? '54332');
  assert.equal(db.pathname, '/postgres');
  assert.ok(!apiUrl.includes('czegmfzntnfpwaxgczds'), 'remote project URL is forbidden');
  const serviceClaims = JSON.parse(Buffer.from(serviceKey.split('.')[1] ?? '', 'base64url').toString('utf8'));
  assert.equal(serviceClaims.role, 'service_role',
    'local service credential must have service_role JWT claims for trusted test setup');

  const dbClient = new Client({ connectionString: dbUrl });
  await dbClient.connect();
  let dealerId;
  let objectPath;
  let adminId;
  const uploadedEdgeObjects = [];
  try {
    const preexisting = await dbClient.query(`
      SELECT table_name FROM information_schema.tables
      WHERE table_schema='public' AND table_name IN
        ('products','categories','users','user_addresses','orders','order_items',
         'rewards_history','support_tickets')
    `);
    assert.deepEqual(preexisting.rows, [],
      'refuse to overwrite any existing public fixture schema, even in local development');

    await dbClient.query(`
      CREATE TABLE public.categories (
        id varchar(64) PRIMARY KEY,
        key_name varchar(64) NOT NULL,
        title varchar(128) NOT NULL,
        description text,
        badge_text varchar(64),
        icon_color varchar(32),
        image_url varchar(255),
        display_order integer NOT NULL DEFAULT 0
      );
      CREATE TABLE public.products (
        id varchar(64) PRIMARY KEY,
        category_id varchar(64),
        category_key varchar(64) NOT NULL,
        sku varchar(64) NOT NULL,
        name varchar(512) NOT NULL,
        brand varchar(255) NOT NULL,
        purchase_price numeric(10,2) NOT NULL DEFAULT 0,
        price numeric(10,2) NOT NULL,
        mrp numeric(10,2) NOT NULL,
        moq varchar(64),
        badge varchar(64),
        rating varchar(64),
        img text,
        description text,
        specs_json json,
        features_json json,
        applications text,
        stock_quantity integer NOT NULL DEFAULT 50,
        min_stock integer NOT NULL DEFAULT 10,
        status varchar(32) NOT NULL DEFAULT 'active',
        created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT fk_products_categories FOREIGN KEY (category_id)
          REFERENCES public.categories(id) ON DELETE SET NULL
      );
      CREATE TABLE public.users (
        id varchar(64) PRIMARY KEY,
        email varchar(191) NOT NULL UNIQUE,
        mobile varchar(20) UNIQUE,
        name varchar(128) NOT NULL,
        password_hash varchar(255) NOT NULL,
        email_verified boolean NOT NULL DEFAULT false,
        gst_number varchar(15),
        business_name varchar(191),
        owner_name varchar(128),
        address text,
        status varchar(16) NOT NULL DEFAULT 'pending'
          CHECK (status IN ('pending','approved','rejected')),
        is_approved boolean NOT NULL DEFAULT false,
        reward_points integer NOT NULL DEFAULT 0,
        created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE public.user_addresses (
        id varchar(64) PRIMARY KEY,
        user_id varchar(64) NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
        label varchar(64) NOT NULL DEFAULT 'Main Warehouse',
        business_name varchar(191),
        street text NOT NULL,
        city varchar(100) NOT NULL,
        state varchar(100) NOT NULL,
        pincode varchar(20) NOT NULL,
        phone varchar(20),
        is_default boolean NOT NULL DEFAULT false,
        created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        full_name varchar(191),
        door_no varchar(64),
        area varchar(191),
        district varchar(100),
        landmark varchar(191),
        address_type varchar(64) DEFAULT 'Office',
        gst_number varchar(64)
      );
      INSERT INTO public.categories(id,key_name,title,display_order)
        VALUES ('local-cat-1','filters','Local Test Filters',1),
               ('local-cat-2','membranes','Local Test Membranes',2);
      INSERT INTO public.products
        (id,category_id,category_key,sku,name,brand,purchase_price,price,mrp,moq,
         img,description,specs_json,features_json,applications,stock_quantity,status)
        VALUES
        ('local-product-active','local-cat-1','filters','LOCAL-SKU-A','Local Active Product','Test Brand',4,10,12,'1',
         'https://example.invalid/local-active.png','local integration fixture', '{}','[]','test only',4,'active'),
        ('local-product-draft','local-cat-2','membranes','LOCAL-SKU-D','Local Draft Product','Test Brand',7,20,24,'1',
         'https://example.invalid/local-draft.png','local integration fixture', '{}','[]','test only',2,'draft'),
        ('local-product-inactive','local-cat-1','filters','LOCAL-SKU-I','Local Inactive Product','Test Brand',9,30,36,'1',
         'https://example.invalid/local-inactive.png','local integration fixture', '{}','[]','test only',1,'inactive');
    `);

    await dbClient.query(fs.readFileSync(
      path.join(root, 'supabase/staging/001_catalog_read.sql'), 'utf8'));
    await dbClient.query(fs.readFileSync(
      path.join(root, 'supabase/staging/002_dealer_profile_addresses.sql'), 'utf8'));
    await dbClient.query(`
      CREATE TABLE public.orders (
        order_id varchar(64) PRIMARY KEY, user_id varchar(64), user_email varchar(191),
        user_name varchar(128), user_business varchar(191), subtotal numeric(10,2) DEFAULT 0,
        discount numeric(10,2) DEFAULT 0, gst numeric(10,2) DEFAULT 0,
        delivery_fee numeric(10,2) DEFAULT 0, grand_total numeric(10,2) DEFAULT 0,
        with_gst boolean NOT NULL DEFAULT false, payment_status varchar(32),
        payment_method varchar(64), billing_address text, company_name varchar(191),
        gstin varchar(64), pan_number varchar(32), same_as_delivery boolean,
        delivery_address text, delivery_note text, status varchar(32), invoice_number varchar(64),
        created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE public.order_items (
        id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, order_id varchar(64) NOT NULL,
        product_id varchar(64), product_name varchar(512), brand varchar(255),
        unit_price numeric(10,2), quantity integer, moq varchar(64), img_src text, sku varchar(64)
      );
      CREATE TABLE public.rewards_history (
        id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, user_id varchar(64) NOT NULL,
        order_id varchar(64), order_amount numeric(10,2), points_earned integer,
        created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE public.support_tickets (
        id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, user_id varchar(64),
        user_email varchar(191), subject varchar(255) NOT NULL, message text NOT NULL,
        status varchar(32) NOT NULL DEFAULT 'open',
        created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    `);
    await dbClient.query(fs.readFileSync(
      path.join(root, 'supabase/staging/004_dealer_order_history.sql'), 'utf8'));
    await dbClient.query(fs.readFileSync(
      path.join(root, 'supabase/staging/005_product_image_storage.sql'), 'utf8'));
    if (edgeFunctionUrl) {
      await dbClient.query(fs.readFileSync(
        path.join(root, 'supabase/drafts/unreconciled/20261029_admin_catalog.sql'), 'utf8'));
      await dbClient.query(fs.readFileSync(
        path.join(root, 'supabase/drafts/unreconciled/20261030_admin_bulk_import.sql'), 'utf8'));
    }

    const viewCheck = await dbClient.query("SELECT to_regclass('public.catalog_products') AS view_name");
    assert.equal(viewCheck.rows[0].view_name, 'catalog_products', 'catalog view was installed in local PostgreSQL');

    // PostgREST applies schema-cache notifications asynchronously. Nudge it
    // after DDL and wait for the new view to become visible before asserting.
    await dbClient.query("NOTIFY pgrst, 'reload schema'");
    let anonCatalog;
    let anonCatalogText = '';
    for (let attempt = 0; attempt < 40; attempt += 1) {
      anonCatalog = await request('/rest/v1/catalog_products?select=id,category_id,category_key,category_name,sku,name,brand,price,dealer_price,mrp,moq,badge,rating,img,description,desc,specs,features,applications,stock_quantity,status,created_at&order=name.asc');
      anonCatalogText = await anonCatalog.text();
      if (anonCatalog.status !== 404 || !anonCatalogText.includes('PGRST205')) break;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    assert.equal(anonCatalog.status, 200,
      `anonymous catalog read is allowed; local PostgREST response: ${anonCatalogText}`);
    const anonProducts = JSON.parse(anonCatalogText);
    assert.deepEqual(anonProducts.map((row) => row.id), [
      'local-product-active', 'local-product-draft',
    ], 'catalog visibility matches Express: every status except inactive');
    assert.equal(anonProducts[0].dealer_price, 10);
    assert.equal(anonProducts[0].category_name, 'Local Test Filters');
    assert.ok(anonProducts.every((row) => !Object.hasOwn(row, 'purchase_price')),
      'purchase cost is absent from the catalog view');

    const anonCategories = await request('/rest/v1/categories?select=id,key_name,title,description,badge_text,icon_color,image_url,display_order&order=display_order.asc');
    assert.equal(anonCategories.status, 200, 'anonymous category read is allowed');
    assert.equal((await anonCategories.json()).length, 2);

    const privatePrice = await request('/rest/v1/products?select=id,purchase_price');
    assert.ok(privatePrice.status >= 400,
      'anonymous callers cannot read purchase_price from the base table');
    const anonymousWrite = await request('/rest/v1/products?id=eq.local-product-active', {
      method: 'PATCH', headers: { 'Content-Type': 'application/json', Prefer: 'return=representation' },
      body: JSON.stringify({ price: 0.01 }),
    });
    assert.ok(anonymousWrite.status >= 400, 'anonymous catalog writes are denied');

    const nonce = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const email = `catalog-dealer-${nonce}@example.test`;
    const password = `Local-test-${nonce}-Aa1!`;
    const created = await request('/auth/v1/admin/users', {
      method: 'POST', bearer: serviceKey, apiKey: serviceKey,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, email_confirm: true, app_metadata: { role: 'dealer' } }),
    });
    const createdBody = await created.text();
    assert.equal(created.status, 200,
      `local Auth admin can provision the synthetic test identity: ${createdBody}`);
    dealerId = JSON.parse(createdBody).id;

    const signedIn = await request('/auth/v1/token?grant_type=password', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
    assert.equal(signedIn.status, 200, 'synthetic dealer can receive a local Auth session');
    const token = (await signedIn.json()).access_token;
    assert.ok(token, 'Auth returned an access token for the synthetic dealer');

    await dbClient.query("NOTIFY pgrst, 'reload schema'");
    const syncProfile = await request('/rest/v1/rpc/sync_current_dealer_profile', {
      method: 'POST', bearer: token,
      headers: { 'Content-Type': 'application/json' }, body: '{}',
    });
    assert.equal(syncProfile.status, 200,
      'verified Auth identity can create a dealer profile through the profile-link RPC');
    const newProfile = await syncProfile.json();
    assert.equal(newProfile.status, 'pending', 'new Auth dealer must remain pending');
    assert.equal(newProfile.isApproved, false, 'profile sync must never auto-approve a dealer');

    await dbClient.query(`INSERT INTO public.orders
      (order_id,user_id,user_email,user_name,grand_total,status) VALUES
      ('local-order-owned',$1,$2,'Local Dealer',10,'Pending'),
      ('local-order-legacy',NULL,$2,'Legacy Local Dealer',20,'Pending'),
      ('local-order-other-email',NULL,'other@example.test','Other Dealer',30,'Pending')`,
    [newProfile.id, email]);
    await dbClient.query(`INSERT INTO public.order_items
      (order_id,product_id,product_name,brand,unit_price,quantity,sku) VALUES
      ('local-order-owned','local-product-active','Local Active Product','Test Brand',10,1,'LOCAL-SKU-A'),
      ('local-order-legacy','local-product-draft','Local Draft Product','Test Brand',20,1,'LOCAL-SKU-D'),
      ('local-order-other-email','local-product-active','Local Active Product','Test Brand',10,3,'LOCAL-SKU-A')`);
    await dbClient.query(`INSERT INTO public.rewards_history(user_id,order_id,order_amount,points_earned)
      VALUES ($1,'local-order-owned',10,1)`, [newProfile.id]);
    await dbClient.query(`INSERT INTO public.support_tickets(user_id,user_email,subject,message)
      VALUES (NULL,$1,'Legacy support','Legacy ticket for verified dealer')`, [email]);
    await dbClient.query("NOTIFY pgrst, 'reload schema'");
    const dealerOrders = await request('/rest/v1/orders?select=order_id,user_id,user_email&order=order_id.asc',
      { bearer: token });
    assert.equal(dealerOrders.status, 200, 'dealer can list only owned and verified-email legacy orders');
    assert.deepEqual((await dealerOrders.json()).map(({ order_id }) => order_id),
      ['local-order-legacy', 'local-order-owned']);
    const dealerItems = await request('/rest/v1/order_items?select=order_id,sku&order=order_id.asc',
      { bearer: token });
    assert.deepEqual((await dealerItems.json()).map(({ order_id }) => order_id),
      ['local-order-legacy', 'local-order-owned'], 'order item RLS follows the parent order owner');
    const dealerRewards = await request('/rest/v1/rewards_history?select=order_id,points_earned',
      { bearer: token });
    assert.deepEqual(await dealerRewards.json(), [{ order_id: 'local-order-owned', points_earned: 1 }]);
    const createTicket = await request('/rest/v1/rpc/ro_create_support_ticket', {
      method: 'POST', bearer: token,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_subject: 'Local support', p_message: 'Need help with a real order' }),
    });
    assert.equal(createTicket.status, 200, 'verified linked dealer can create a support ticket');
    const dealerTickets = await request('/rest/v1/support_tickets?select=user_id,user_email,subject&order=id.asc',
      { bearer: token });
    assert.equal(dealerTickets.status, 200);
    assert.deepEqual((await dealerTickets.json()).map(({ subject }) => subject),
      ['Legacy support', 'Local support']);

    const unverifiedEmail = `unverified-${nonce}@example.test`;
    const unverifiedPassword = `Local-test-${nonce}-Unverified-Aa1!`;
    const unverifiedCreated = await request('/auth/v1/admin/users', {
      method: 'POST', bearer: serviceKey, apiKey: serviceKey,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: unverifiedEmail, password: unverifiedPassword,
        email_confirm: true, app_metadata: { role: 'dealer' } }),
    });
    assert.equal(unverifiedCreated.status, 200);
    const unverifiedId = JSON.parse(await unverifiedCreated.text()).id;
    const unverifiedSignIn = await request('/auth/v1/token?grant_type=password', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: unverifiedEmail, password: unverifiedPassword }),
    });
    assert.equal(unverifiedSignIn.status, 200);
    const unverifiedToken = (await unverifiedSignIn.json()).access_token;
    const unverifiedSync = await request('/rest/v1/rpc/sync_current_dealer_profile', {
      method: 'POST', bearer: unverifiedToken,
      headers: { 'Content-Type': 'application/json' }, body: '{}',
    });
    assert.equal(unverifiedSync.status, 200);
    await dbClient.query('UPDATE auth.users SET email_confirmed_at=NULL WHERE id=$1', [unverifiedId]);
    await dbClient.query(`INSERT INTO public.orders
      (order_id,user_id,user_email,user_name,grand_total,status)
      VALUES ('local-order-unverified-email',NULL,$1,'Unverified Local Dealer',40,'Pending')`,
    [unverifiedEmail]);
    await dbClient.query(`INSERT INTO public.support_tickets(user_id,user_email,subject,message)
      VALUES (NULL,$1,'Unverified support','Must not be visible by email fallback')`, [unverifiedEmail]);
    const unverifiedOrders = await request('/rest/v1/orders?select=order_id',
      { bearer: unverifiedToken });
    assert.deepEqual(await unverifiedOrders.json(), [],
      'unconfirmed Auth email cannot read legacy orders by email match');
    const unverifiedTickets = await request('/rest/v1/support_tickets?select=subject',
      { bearer: unverifiedToken });
    assert.deepEqual(await unverifiedTickets.json(), [],
      'unconfirmed Auth email cannot read legacy support tickets');

    const profileRead = await request(
      `/rest/v1/users?select=id,email,name,status,is_approved&id=eq.${newProfile.id}`,
      { bearer: token },
    );
    assert.equal(profileRead.status, 200, 'dealer can read only its linked profile projection');
    const profileRows = await profileRead.json();
    assert.equal(profileRows.length, 1);
    assert.equal(profileRows[0].status, 'pending');
    const privateProfile = await request(
      `/rest/v1/users?select=password_hash,auth_user_id&id=eq.${newProfile.id}`,
      { bearer: token },
    );
    assert.ok(privateProfile.status >= 400, 'dealer cannot read password hashes or identity-link IDs');
    const updateProfile = (bearer, { name, mobile, business, address }) => request(
      '/rest/v1/rpc/ro_update_current_dealer_profile',
      { method: 'POST', bearer,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_name: name, p_mobile: mobile,
          p_business_name: business, p_address: address }) },
    );
    const profileUpdate = await updateProfile(token, {
      name: 'Updated Local Dealer', mobile: '9000000001',
      business: 'Local Test Co', address: 'Updated local street',
    });
    assert.equal(profileUpdate.status, 204, 'dealer can update only allow-listed profile fields through owner RPC');
    const updatedProfile = await request(
      `/rest/v1/users?select=id,name,owner_name,mobile,business_name,address&id=eq.${newProfile.id}`,
      { bearer: token },
    );
    assert.deepEqual(await updatedProfile.json(), [{ id: newProfile.id,
      name: 'Updated Local Dealer', owner_name: 'Updated Local Dealer', mobile: '9000000001',
      business_name: 'Local Test Co', address: 'Updated local street' }]);
    const invalidMobile = await updateProfile(token, {
      name: 'Updated Local Dealer', mobile: '123',
      business: 'Local Test Co', address: 'Updated local street',
    });
    assert.ok(invalidMobile.status >= 400, 'profile RPC rejects an invalid mobile number');
    const directProfileUpdate = await request(
      `/rest/v1/users?id=eq.${newProfile.id}`,
      { method: 'PATCH', bearer: token,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ is_approved: true }) },
    );
    assert.ok(directProfileUpdate.status >= 400,
      'dealer cannot bypass the profile RPC to update protected approval fields');
    const approvalEscalation = await request(
      `/rest/v1/users?id=eq.${newProfile.id}`,
      { method: 'PATCH', bearer: token,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: 'approved', is_approved: true }) },
    );
    assert.ok(approvalEscalation.status >= 400,
      'dealer cannot update approval state through PostgREST');

    const saveAddress = async (addressId, street, makeDefault) => request(
      '/rest/v1/rpc/ro_save_dealer_address',
      { method: 'POST', bearer: token,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_id: addressId, p_label: 'Office', p_business_name: 'Local Test Co',
          p_street: street, p_city: 'Pune', p_state: 'Maharashtra', p_pincode: '411001',
          p_phone: '9000000001', p_full_name: 'Local Dealer', p_door_no: '1',
          p_area: 'Camp', p_district: 'Pune', p_landmark: '', p_address_type: 'Office',
          p_gst_number: '', p_make_default: makeDefault }) },
    );
    const firstAddress = await saveAddress('local-address-1', '1 Main Road', true);
    assert.equal(firstAddress.status, 200, 'dealer can save its own address through the RPC');
    const secondAddress = await saveAddress('local-address-2', '2 Lake Road', true);
    assert.equal(secondAddress.status, 200, 'dealer can save a second default address');
    const ownAddressResponse = await request(
      '/rest/v1/user_addresses?select=id,user_id,is_default,street&order=id.asc',
      { bearer: token },
    );
    assert.equal(ownAddressResponse.status, 200);
    const ownAddresses = await ownAddressResponse.json();
    assert.deepEqual(ownAddresses.map(({ id, is_default }) => ({ id, is_default })), [
      { id: 'local-address-1', is_default: false },
      { id: 'local-address-2', is_default: true },
    ], 'making a second address default clears the first default');
    const setOwnDefault = await request('/rest/v1/rpc/ro_set_default_dealer_address', {
      method: 'POST', bearer: token,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_address_id: 'local-address-1' }),
    });
    assert.equal(setOwnDefault.status, 204, 'dealer can select an owned default address');

    const secondNonce = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const secondEmail = `address-dealer-${secondNonce}@example.test`;
    const secondPassword = `Local-test-${secondNonce}-Aa1!`;
    const secondCreated = await request('/auth/v1/admin/users', {
      method: 'POST', bearer: serviceKey, apiKey: serviceKey,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: secondEmail, password: secondPassword,
        email_confirm: true, app_metadata: { role: 'dealer' } }),
    });
    assert.equal(secondCreated.status, 200, 'local Auth provisions a second synthetic dealer');
    const secondDealerId = JSON.parse(await secondCreated.text()).id;
    const secondSignIn = await request('/auth/v1/token?grant_type=password', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: secondEmail, password: secondPassword }),
    });
    assert.equal(secondSignIn.status, 200);
    const secondToken = (await secondSignIn.json()).access_token;
    const secondSync = await request('/rest/v1/rpc/sync_current_dealer_profile', {
      method: 'POST', bearer: secondToken,
      headers: { 'Content-Type': 'application/json' }, body: '{}',
    });
    assert.equal(secondSync.status, 200);
    const secondOrders = await request('/rest/v1/orders?select=order_id&order=order_id.asc',
      { bearer: secondToken });
    assert.deepEqual(await secondOrders.json(), [], 'second dealer cannot see another dealer or email legacy orders');
    const secondRewards = await request('/rest/v1/rewards_history?select=order_id',
      { bearer: secondToken });
    assert.deepEqual(await secondRewards.json(), [], 'second dealer cannot see another dealer rewards');
    const secondTickets = await request('/rest/v1/support_tickets?select=subject',
      { bearer: secondToken });
    assert.deepEqual(await secondTickets.json(), [], 'second dealer cannot see another dealer support tickets');
    const secondOwnUpdate = await updateProfile(secondToken, {
      name: 'Dealer B Updated', mobile: '9000000002',
      business: 'Dealer B Co', address: 'Dealer B address',
    });
    assert.equal(secondOwnUpdate.status, 204,
      'dealer B can update its own profile without supplying dealer A ID');
    const duplicateMobile = await updateProfile(token, {
      name: 'Updated Local Dealer', mobile: '9000000002',
      business: 'Local Test Co', address: 'Updated local street',
    });
    assert.ok(duplicateMobile.status >= 400,
      'profile RPC rejects a mobile already owned by another dealer');
    const firstProfileAfterBUpdate = await request(
      `/rest/v1/users?select=id,name,mobile&id=eq.${newProfile.id}`, { bearer: token },
    );
    assert.deepEqual(await firstProfileAfterBUpdate.json(), [{
      id: newProfile.id, name: 'Updated Local Dealer', mobile: '9000000001',
    }], 'dealer B profile RPC cannot mutate dealer A profile');
    const foreignAddresses = await request(
      '/rest/v1/user_addresses?select=id&order=id.asc', { bearer: secondToken },
    );
    assert.equal(foreignAddresses.status, 200);
    assert.deepEqual(await foreignAddresses.json(), [], 'dealer B cannot read dealer A addresses');
    const foreignDefault = await request('/rest/v1/rpc/ro_set_default_dealer_address', {
      method: 'POST', bearer: secondToken,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_address_id: 'local-address-1' }),
    });
    assert.ok(foreignDefault.status >= 400, 'dealer B cannot select dealer A address as default');
    const foreignIdReuse = await request('/rest/v1/rpc/ro_save_dealer_address', {
      method: 'POST', bearer: secondToken,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_id: 'local-address-1', p_label: 'Office',
        p_business_name: 'Attacker Co', p_street: '3 Main Road', p_city: 'Pune',
        p_state: 'Maharashtra', p_pincode: '411001', p_phone: '9000000002',
        p_full_name: 'Dealer B', p_door_no: '3', p_area: 'Camp', p_district: 'Pune',
        p_landmark: '', p_address_type: 'Office', p_gst_number: '', p_make_default: true }),
    });
    assert.ok(foreignIdReuse.status >= 400,
      'dealer B cannot overwrite dealer A address by reusing its ID');
    const foreignDelete = await request(
      '/rest/v1/user_addresses?id=eq.local-address-1',
      { method: 'DELETE', bearer: secondToken },
    );
    assert.ok([200, 204].includes(foreignDelete.status));
    const ownerAddressAfterAttack = await request(
      '/rest/v1/user_addresses?select=id&id=eq.local-address-1', { bearer: token },
    );
    assert.deepEqual(await ownerAddressAfterAttack.json(), [{ id: 'local-address-1' }],
      'dealer B cannot delete dealer A address');
    const ownDelete = await request(
      '/rest/v1/user_addresses?id=eq.local-address-2',
      { method: 'DELETE', bearer: token },
    );
    assert.ok([200, 204].includes(ownDelete.status), 'dealer can delete its own address');

    const dealerCatalog = await request('/rest/v1/catalog_products?select=id,sku,name,dealer_price', {
      bearer: token,
    });
    assert.equal(dealerCatalog.status, 200, 'authenticated dealer can read the public catalog');
    assert.equal((await dealerCatalog.json()).length, 2);
    const dealerPrivatePrice = await request('/rest/v1/products?select=id,purchase_price', {
      bearer: token,
    });
    assert.ok(dealerPrivatePrice.status >= 400,
      'authenticated dealer cannot read purchase_price from the base table');
    const dealerWrite = await request('/rest/v1/products?id=eq.local-product-active', {
      method: 'PATCH', bearer: token,
      headers: { 'Content-Type': 'application/json', Prefer: 'return=representation' },
      body: JSON.stringify({ price: 0.01 }),
    });
    assert.ok(dealerWrite.status >= 400, 'authenticated dealer cannot write catalog rows');

    if (edgeFunctionUrl) {
      const adminEmail = `catalog-admin-${nonce}@example.test`;
      const adminPassword = `Local-test-${nonce}-Admin-Aa1!`;
      const adminCreated = await request('/auth/v1/admin/users', {
        method: 'POST', bearer: serviceKey, apiKey: serviceKey,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: adminEmail, password: adminPassword,
          email_confirm: true, app_metadata: { role: 'admin' } }),
      });
      const adminCreatedText = await adminCreated.text();
      assert.equal(adminCreated.status, 200,
        `local Auth can provision a synthetic administrator: ${adminCreatedText}`);
      adminId = JSON.parse(adminCreatedText).id;
      const adminSessionResponse = await request('/auth/v1/token?grant_type=password', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: adminEmail, password: adminPassword }),
      });
      assert.equal(adminSessionResponse.status, 200, 'verified local administrator can sign in');
      const adminToken = (await adminSessionResponse.json()).access_token;
      const adminCall = async (action, values = undefined, targetId = undefined, bearer = adminToken) => {
        const response = await fetch(new URL('/functions/v1/admin-catalog', edgeFunctionUrl), {
          method: 'POST',
          headers: {
            apikey: anonKey,
            Authorization: `Bearer ${bearer}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ action, ...(targetId ? { targetId } : {}), ...(values ? { values } : {}) }),
        });
        return { response, body: await response.json() };
      };

      const deniedDealer = await adminCall('list_products', undefined, undefined, token);
      assert.equal(deniedDealer.response.status, 403,
        'Edge Function rejects a signed-in dealer using trusted Auth app_metadata');
      const anonymous = await fetch(new URL('/functions/v1/admin-catalog', edgeFunctionUrl), {
        method: 'POST', headers: { apikey: anonKey, 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'list_products' }),
      });
      assert.ok(anonymous.status >= 400, 'Edge Function rejects unauthenticated callers');

      const categoryList = await adminCall('list_categories');
      assert.equal(categoryList.response.status, 200, 'Edge Function lists categories using local Auth and PostgREST');
      assert.equal(categoryList.body.categories.length, 2);
      const fallbackCategory = await adminCall('create_category', {
        title: 'Spares', key_name: 'spares', display_order: 3,
      });
      assert.equal(fallbackCategory.response.status, 201,
        `category RPC creates the safe reassignment target: ${JSON.stringify(fallbackCategory.body)}`);
      const createdCategory = await adminCall('create_category', {
        title: 'Edge Test Category', key_name: 'edge_test_category', display_order: 4,
      });
      assert.equal(createdCategory.response.status, 201,
        `category RPC succeeds through Edge Runtime: ${JSON.stringify(createdCategory.body)}`);
      const categoryId = createdCategory.body.category.id;

      const pngDataUrl = `data:image/png;base64,${pngFixture.toString('base64')}`;
      const createdProduct = await adminCall('create_product', {
        name: 'Local Edge Product', sku: `EDGE-${nonce.replaceAll('-', '').slice(-12)}`,
        category: 'filters', brand: 'Local Test', purchase_price: 5,
        price: 12, mrp: 15, stock_quantity: 8, min_stock: 1,
        img: pngDataUrl, description: 'Local Edge Runtime fixture',
      });
      assert.equal(createdProduct.response.status, 201,
        `product CRUD and Storage upload succeed through Edge Runtime: ${JSON.stringify(createdProduct.body)}`);
      const createdImageUrl = createdProduct.body.product.img;
      assert.match(createdImageUrl, /\/storage\/v1\/object\/public\/ro-product-images\/products\//);
      const createdProductId = createdProduct.body.product.id;
      const imageObjectPath = new URL(createdImageUrl).pathname
        .split('/storage/v1/object/public/ro-product-images/')[1];
      uploadedEdgeObjects.push(imageObjectPath);
      const storedImage = await request(
        `/storage/v1/object/public/ro-product-images/${imageObjectPath}`,
      );
      assert.equal(storedImage.status, 200, 'Edge Function image is readable from local Storage');
      assert.deepEqual(Buffer.from(await storedImage.arrayBuffer()), pngFixture);

      const updatedProduct = await adminCall('update_product', {
        name: 'Local Edge Product Updated', sku: createdProduct.body.product.sku,
        category: 'filters', brand: 'Local Test', purchase_price: 5,
        price: 12, mrp: 15, stock_quantity: 8, min_stock: 1,
        img: createdImageUrl, description: 'Updated local fixture',
      }, createdProductId);
      assert.equal(updatedProduct.response.status, 200, 'product update succeeds through Edge Runtime');
      assert.equal(updatedProduct.body.product.name, 'Local Edge Product Updated');

      const batch = [{ name: 'Local Edge Bulk Product',
        sku: `BULK-${nonce.replaceAll('-', '').slice(-12)}`,
        category: 'membranes', brand: 'Local Test', purchase_price: 3,
        price: 9, mrp: 11, stock_quantity: 4, min_stock: 0 }];
      const imported = await adminCall('bulk_import_products', { products: batch });
      assert.equal(imported.response.status, 201,
        `bulk import succeeds through Edge Runtime and PostgreSQL RPC: ${JSON.stringify(imported.body)}`);
      assert.equal(imported.body.importedCount, 1);
      assert.equal(imported.body.replayed, false);
      const replay = await adminCall('bulk_import_products', { products: batch });
      assert.equal(replay.response.status, 201, 'identical bulk retry succeeds');
      assert.equal(replay.body.importedCount, 1);
      assert.equal(replay.body.replayed, true);
      const productCount = await dbClient.query(
        'SELECT count(*)::int AS count FROM public.products WHERE sku=$1', [batch[0].sku]);
      assert.equal(productCount.rows[0].count, 1, 'bulk retry stores only one product');

      const duplicateProduct = await adminCall('create_product', {
        name: 'Duplicate Product', sku: batch[0].sku,
        category: 'membranes', price: 9, mrp: 11,
      });
      assert.equal(duplicateProduct.response.status, 409,
        'duplicate SKU is rejected instead of overwriting existing catalog data');
      const invalidBulk = await adminCall('bulk_import_products', { products: [
        { name: 'Invalid Price', sku: `BAD-${nonce.replaceAll('-', '').slice(-12)}`,
          category: 'filters', price: 'not-a-number', mrp: 11 },
      ] });
      assert.equal(invalidBulk.response.status, 201,
        'invalid row is reported as skipped without database mutation');
      assert.equal(invalidBulk.body.importedCount, 0);
      assert.equal(invalidBulk.body.skippedCount, 1);

      const reassignedProduct = await adminCall('create_product', {
        name: 'Edge Category Child', sku: `CHILD-${nonce.replaceAll('-', '').slice(-12)}`,
        category: 'edge_test_category', price: 8, mrp: 10,
      });
      assert.equal(reassignedProduct.response.status, 201);
      const deletedCategory = await adminCall('delete_category', undefined, categoryId);
      assert.equal(deletedCategory.response.status, 200,
        'category deletion reassigns linked products to the existing Spares category');
      assert.equal(deletedCategory.body.reassignedCount, 1);
      const reassigned = await dbClient.query(
        'SELECT category_key FROM public.products WHERE sku=$1',
        [reassignedProduct.body.product.sku]);
      assert.equal(reassigned.rows[0].category_key, 'spares');

      const deactivated = await adminCall('deactivate_product', undefined, createdProductId);
      assert.equal(deactivated.response.status, 200, 'product removal is a soft deactivation');
      assert.equal(deactivated.body.product.status, 'inactive');

      const adminDeleted = await request(`/auth/v1/admin/users/${adminId}`, {
        method: 'DELETE', bearer: serviceKey, apiKey: serviceKey,
      });
      assert.ok([200, 204].includes(adminDeleted.status), 'synthetic local administrator cleanup succeeds');
      adminId = undefined;
    }

    const object = await request('/storage/v1/object/ro-product-images/local-test/catalog-image.png', {
      method: 'POST', bearer: serviceKey, apiKey: serviceKey,
      headers: { 'Content-Type': 'image/png', 'x-upsert': 'false' },
      body: pngFixture,
    });
    assert.ok([200, 201].includes(object.status), 'trusted local service role can seed one test image');
    objectPath = 'local-test/catalog-image.png';
    const imageUrl = new URL(
      '/storage/v1/object/public/ro-product-images/local-test/catalog-image.png', api,
    ).toString();
    await dbClient.query('UPDATE public.products SET img = $1 WHERE id IN ($2, $3)', [
      imageUrl, 'local-product-active', 'local-product-draft',
    ]);
    await dbClient.query('UPDATE public.categories SET image_url = $1', [imageUrl]);
    const publicImage = await request(`/storage/v1/object/public/ro-product-images/${objectPath}`);
    assert.equal(publicImage.status, 200, 'public image bucket serves the image without a session');
    assert.deepEqual(Buffer.from(await publicImage.arrayBuffer()), pngFixture);
    const dealerImage = await request(`/storage/v1/object/public/ro-product-images/${objectPath}`, {
      bearer: token,
    });
    assert.equal(dealerImage.status, 200, 'authenticated dealer can read a public catalog image');

    const anonUpload = await request('/storage/v1/object/ro-product-images/unauthorized/blocked.png', {
      method: 'POST', headers: { 'Content-Type': 'image/png' },
      body: Buffer.from('must-not-persist'),
    });
    assert.ok(anonUpload.status >= 400, 'anonymous Storage uploads are denied');
    const dealerUpload = await request('/storage/v1/object/ro-product-images/unauthorized/blocked.png', {
      method: 'POST', bearer: token,
      headers: { 'Content-Type': 'image/png' }, body: Buffer.from('must-not-persist'),
    });
    assert.ok(dealerUpload.status >= 400, 'dealer Storage uploads are denied');

    // Local-only cleanup of the Auth user and uploaded fixture object.
    if (!keepImageFixture) {
      await deleteImageFixture();
      objectPath = undefined;
    }
    const userDeleted = await request(`/auth/v1/admin/users/${dealerId}`, {
      method: 'DELETE', bearer: serviceKey, apiKey: serviceKey,
    });
    assert.ok([200, 204].includes(userDeleted.status), 'local synthetic Auth user cleanup succeeded');
    dealerId = undefined;
  } finally {
    for (const imagePath of uploadedEdgeObjects.splice(0)) {
      await request('/storage/v1/object/ro-product-images', {
        method: 'DELETE', bearer: serviceKey, apiKey: serviceKey,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prefixes: [imagePath] }),
      }).catch(() => {});
    }
    if (adminId) {
      await request(`/auth/v1/admin/users/${adminId}`, {
        method: 'DELETE', bearer: serviceKey, apiKey: serviceKey,
      }).catch(() => {});
    }
    if (objectPath && !keepImageFixture) {
      await deleteImageFixture().catch(() => {});
    }
    if (dealerId) {
      await request(`/auth/v1/admin/users/${dealerId}`, {
        method: 'DELETE', bearer: serviceKey, apiKey: serviceKey,
      }).catch(() => {});
    }
    await dbClient.end();
  }

  async function request(route, options = {}) {
    const headers = new Headers(options.headers ?? {});
    headers.set('apikey', options.apiKey ?? anonKey);
    headers.set('Authorization', `Bearer ${options.bearer ?? anonKey}`);
    const { bearer, apiKey, ...fetchOptions } = options;
    return fetch(new URL(route, api), { ...fetchOptions, headers });
  }

  async function deleteImageFixture() {
    const remove = await request('/storage/v1/object/ro-product-images', {
      method: 'DELETE', bearer: serviceKey, apiKey: serviceKey,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefixes: [objectPath] }),
    });
    assert.ok([200, 204].includes(remove.status), 'local test object cleanup succeeded');
  }
});

function createOnePixelPng() {
  const crcTable = Array.from({ length: 256 }, (_, index) => {
    let crc = index;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) ? (0xedb88320 ^ (crc >>> 1)) : (crc >>> 1);
    }
    return crc >>> 0;
  });
  const chunk = (type, data) => {
    const typeBytes = Buffer.from(type, 'ascii');
    const length = Buffer.alloc(4);
    length.writeUInt32BE(data.length);
    const crcInput = Buffer.concat([typeBytes, data]);
    let crc = 0xffffffff;
    for (const byte of crcInput) crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
    const crcBytes = Buffer.alloc(4);
    crcBytes.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
    return Buffer.concat([length, typeBytes, data, crcBytes]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(1, 0);
  header.writeUInt32BE(1, 4);
  header[8] = 8; // 8-bit RGBA
  header[9] = 6;
  const pixel = Buffer.from([0, 0x18, 0x88, 0xff, 0xff]); // filter + RGBA
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', header),
    chunk('IDAT', zlib.deflateSync(pixel)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}
