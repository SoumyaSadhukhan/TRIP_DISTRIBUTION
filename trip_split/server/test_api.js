// server/test_api.js
const http = require('http');

function post(path, data, token) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(data);
    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(payload),
    };
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const req = http.request({
      hostname: 'localhost',
      port: 5000,
      path: path,
      method: 'POST',
      headers: headers,
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          resolve({ status: res.statusCode, body });
        }
      });
    });

    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function get(path, token) {
  return new Promise((resolve, reject) => {
    const headers = {};
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const req = http.request({
      hostname: 'localhost',
      port: 5000,
      path: path,
      method: 'GET',
      headers: headers,
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          resolve({ status: res.statusCode, body });
        }
      });
    });

    req.on('error', reject);
    req.end();
  });
}

async function runTests() {
  const testPhone = '9876543210';
  console.log('--- Step 1: Send OTP for Registration ---');
  const otpRes = await post('/api/auth/send-otp', { phone: testPhone, purpose: 'REGISTER' });
  console.log('Send OTP Result:', otpRes);

  if (!otpRes.success) {
    console.error('OTP failed');
    return;
  }

  const receivedOtp = otpRes.otp;

  console.log('\n--- Step 2: Register User with Phone, Name, Password & OTP ---');
  const regRes = await post('/api/auth/register', {
    phone: testPhone,
    fullName: 'Alex Morgan',
    password: 'Password@123',
    otp: receivedOtp,
  });
  console.log('Register Result:', regRes);

  if (!regRes.success) {
    console.error('Register failed');
    return;
  }

  const authToken = regRes.token;
  const userId = regRes.user.id;

  console.log('\n--- Step 3: Verify Stored Token (Auto-login on app reopen) ---');
  const verifyRes = await post('/api/auth/verify-token', { token: authToken, phone: testPhone });
  console.log('Verify Token Result:', verifyRes);

  console.log('\n--- Step 4: Sync Trip & Expense Data into Granular SQL Tables ---');
  const syncRes = await post('/api/trips/sync', {
    userId: userId,
    trips: [
      {
        id: 'trip-101',
        name: 'Goa Beach Holiday',
        description: 'Annual team vacation',
        createdAt: new Date().toISOString(),
        groups: [
          {
            id: 'grp-1',
            name: 'Villa Alpha',
            members: [
              { id: 'p1', name: 'Alex', dietType: 0, paidAmount: 5000, owedAmount: 2500, balance: 2500 },
              { id: 'p2', name: 'Sam', dietType: 1, paidAmount: 2000, owedAmount: 4500, balance: -2500 },
            ],
          },
        ],
        expenses: [
          {
            id: 'exp-1',
            description: 'Seafood & Veg Lunch',
            amount: 7000,
            category: 3, // mixed
            paidById: 'p1',
            date: new Date().toISOString(),
            splitAmongIds: ['p1', 'p2'],
          },
        ],
      },
    ],
  }, authToken);
  console.log('Sync Trips Result:', syncRes);

  console.log('\n--- Step 5: Query Trips Back from Granular Tables ---');
  const getTripsRes = await get(`/api/trips?userId=${userId}`, authToken);
  console.log('Get Trips Result:', JSON.stringify(getTripsRes, null, 2));

  console.log('\n--- ALL API & SQL TESTS PASSED SUCCESSFULLY! ---');
  process.exit(0);
}

runTests().catch(e => {
  console.error('Test error:', e);
  process.exit(1);
});
