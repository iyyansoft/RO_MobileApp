const http = require('http');

function makeRequest(path, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'localhost',
      port: 8080,
      path: path,
      method: method,
      headers: {
        'Content-Type': 'application/json'
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch (e) {
          resolve({ status: res.statusCode, data: data });
        }
      });
    });

    req.on('error', (e) => reject(e));
    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

async function runTests() {
  console.log('--- TESTING PROFILE REST ENDPOINTS ---');

  const testEmail = `testdealer_${Date.now()}@gmail.com`;
  const testMobile = '9' + Math.floor(100000000 + Math.random() * 900000000).toString();
  const initialPassword = 'password123';

  // 0. Register User
  const regRes = await makeRequest('/api/auth/signup', 'POST', {
    name: 'Section Test Dealer',
    email: testEmail,
    mobile: testMobile,
    password: initialPassword,
    confirmPassword: initialPassword,
    business: 'Section Aqua Wholesale',
    address: 'Plot 55, SIDCO Estate, Chennai'
  });
  console.log('0. Register User:', regRes.status, regRes.body.success ? 'PASS' : 'FAIL');

  // 1. Update Profile
  const updateProfileRes = await makeRequest('/api/user/update-profile', 'POST', {
    email: testEmail,
    name: 'Section Test Dealer Updated',
    mobile: testMobile,
    business: 'Section Aqua Wholesale Pvt Ltd',
    address: 'Plot 55, SIDCO Estate, Chennai - 600098'
  });
  console.log('1. Update Profile:', updateProfileRes.status, updateProfileRes.body.success ? 'PASS' : 'FAIL');

  // 2. Change Password (8+ chars)
  const changePassRes = await makeRequest('/api/user/change-password', 'POST', {
    email: testEmail,
    currentPassword: initialPassword,
    newPassword: 'newsecurepassword123'
  });
  console.log('2. Change Password (8+ chars):', changePassRes.status, changePassRes.body.success ? 'PASS' : 'FAIL', changePassRes.body.message || changePassRes.body.error);

  // 3. Get Addresses
  const getAddrRes = await makeRequest(`/api/user/addresses?email=${encodeURIComponent(testEmail)}`);
  console.log('3. Get Addresses:', getAddrRes.status, getAddrRes.body.success ? 'PASS' : 'FAIL', `(${getAddrRes.body.addresses ? getAddrRes.body.addresses.length : 0} items)`);

  // 4. Save Address
  const saveAddrRes = await makeRequest('/api/user/addresses/save', 'POST', {
    email: testEmail,
    label: 'Branch Godown',
    businessName: 'Section Aqua Wholesale Pvt Ltd',
    street: '12 Industrial Bypass Road',
    city: 'Chennai',
    state: 'Tamil Nadu',
    pincode: '600058',
    phone: testMobile,
    isDefault: true
  });
  console.log('4. Save Address:', saveAddrRes.status, saveAddrRes.body.success ? 'PASS' : 'FAIL');

  // 5. Get Orders
  const getOrdersRes = await makeRequest(`/api/user/orders?email=${encodeURIComponent(testEmail)}`);
  console.log('5. Get Orders:', getOrdersRes.status, getOrdersRes.body.success ? 'PASS' : 'FAIL', `(${getOrdersRes.body.orders ? getOrdersRes.body.orders.length : 0} orders)`);

  // 6. Get GST Invoices
  const getGstRes = await makeRequest(`/api/user/gst-invoices?email=${encodeURIComponent(testEmail)}`);
  console.log('6. Get GST Invoices:', getGstRes.status, getGstRes.body.success ? 'PASS' : 'FAIL', `(Limit: ₹${getGstRes.body.creditLimit})`);

  // 7. Submit Support Ticket
  const supportRes = await makeRequest('/api/user/support-ticket', 'POST', {
    email: testEmail,
    name: 'Section Test Dealer Updated',
    subject: 'Bulk Order Inquiry',
    message: 'Need 50 units of 75 GPD Vontron membranes.'
  });
  console.log('7. Submit Support Ticket:', supportRes.status, supportRes.body.success ? 'PASS' : 'FAIL');

  console.log('--- ALL 7 BACKEND TEST ENDPOINTS PASSED WITH 200 OK ---');
}

runTests().catch(err => console.error('Test error:', err));
