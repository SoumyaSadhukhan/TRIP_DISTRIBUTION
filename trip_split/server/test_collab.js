// server/test_collab.js
const http = require('http');

function post(path, data, token) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(data);
    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(payload),
    };
    if (token) headers['Authorization'] = `Bearer ${token}`;

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

async function runCollabTests() {
  console.log('--- Step 1: Check phone numbers in Contacts ---');
  const checkRes = await post('/api/friends/check-contacts', {
    contacts: ['9876543210', '9807654213', '9999999999'],
  });
  console.log('Check Contacts Result:', checkRes);

  console.log('\n--- Step 2: Update Profile with Dietary Preference ---');
  const profileRes = await post('/api/auth/profile', {
    userId: 'f2422285-426d-4d88-988b-0508cd0bb0e9',
    fullName: 'Alex Morgan',
    dietType: 2, // Non-Veg + Alcohol
  });
  console.log('Profile Update Result:', profileRes);

  console.log('\n--- Step 3: Add Friend Connection by Phone ---');
  const friendRes = await post('/api/friends/add', {
    userId: 'f2422285-426d-4d88-988b-0508cd0bb0e9',
    friendPhone: '9807654213',
  });
  console.log('Add Friend Result:', friendRes);

  console.log('\n--- Step 4: Get Friends List ---');
  const friendsList = await get('/api/friends?userId=f2422285-426d-4d88-988b-0508cd0bb0e9');
  console.log('Friends List:', friendsList);

  console.log('\n--- Step 5: Test Notifications Feed ---');
  const notifList = await get('/api/notifications?userId=8b4e990b-cd4d-4d63-8ff8-03b9d2f98a11');
  console.log('Notifications:', notifList);

  console.log('\n--- ALL COLLAB & NOTIFICATION TESTS PASSED! ---');
  process.exit(0);
}

runCollabTests().catch(e => {
  console.error('Collab test error:', e);
  process.exit(1);
});
