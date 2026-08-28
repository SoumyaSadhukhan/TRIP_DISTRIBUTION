// server/routes/friendsRoutes.js
const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const { getPool, sql } = require('../db');

// Middleware to authenticate token from header
async function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) return next();

  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('token', sql.NVarChar(500), token)
      .query('SELECT user_id, phone_number FROM UserTokens WHERE auth_token = @token AND is_active = 1');

    if (result.recordset.length > 0) {
      req.user = result.recordset[0];
    }
  } catch (err) {
    console.error('Friends auth middleware error:', err);
  }
  next();
}

router.use(authenticateToken);

// 1. Check Batch of Contacts to find Registered Users
router.post('/check-contacts', async (req, res) => {
  try {
    const { contacts = [] } = req.body;
    if (!Array.isArray(contacts) || contacts.length === 0) {
      return res.json({ success: true, registeredUsers: [] });
    }

    const cleanPhones = contacts
      .map(c => typeof c === 'string' ? c : (c.phone || c.phoneNumber || ''))
      .map(p => p.replace(/[^0-9]/g, ''))
      .filter(p => p.length >= 7)
      .map(p => p.slice(-10)); // Match last 10 digits

    if (cleanPhones.length === 0) {
      return res.json({ success: true, registeredUsers: [] });
    }

    const pool = await getPool();
    const phoneList = cleanPhones.map(p => `'${p}'`).join(',');

    const query = `
      SELECT user_id, phone_number, full_name, diet_type, diet_name
      FROM Users
      WHERE RIGHT(phone_number, 10) IN (${phoneList}) AND is_active = 1
    `;

    const result = await pool.request().query(query);

    const registeredUsers = result.recordset.map(u => ({
      userId: u.user_id,
      phone: u.phone_number,
      fullName: u.full_name,
      dietType: u.diet_type ?? 0,
      dietName: u.diet_name || 'Vegetarian',
      isRegistered: true,
    }));

    return res.json({ success: true, registeredUsers });
  } catch (err) {
    console.error('check-contacts error:', err);
    return res.status(500).json({ success: false, message: 'Failed to check contacts: ' + err.message });
  }
});

// 2. Search Single Phone Number
router.post('/search', async (req, res) => {
  try {
    const { phone } = req.body;
    if (!phone) {
      return res.status(400).json({ success: false, message: 'Phone number required' });
    }

    const cleanPhone = phone.replace(/[^0-9]/g, '').slice(-10);
    const pool = await getPool();

    const result = await pool.request()
      .input('phone', sql.NVarChar(20), `%${cleanPhone}%`)
      .query(`
        SELECT TOP 10 user_id, phone_number, full_name, diet_type, diet_name
        FROM Users
        WHERE phone_number LIKE @phone AND is_active = 1
      `);

    const users = result.recordset.map(u => ({
      userId: u.user_id,
      phone: u.phone_number,
      fullName: u.full_name,
      dietType: u.diet_type ?? 0,
      dietName: u.diet_name || 'Vegetarian',
    }));

    return res.json({ success: true, users });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 3. Get Connected Friends List for User
router.get('/', async (req, res) => {
  try {
    const userId = req.query.userId || (req.user && req.user.user_id);
    if (!userId) {
      return res.status(400).json({ success: false, message: 'User ID required' });
    }

    const pool = await getPool();
    const result = await pool.request()
      .input('userId', sql.NVarChar(100), userId)
      .query(`
        SELECT fc.connection_id, fc.user_id, fc.friend_user_id, fc.friend_phone, fc.friend_name,
               ISNULL(u.diet_type, fc.diet_type) as diet_type,
               ISNULL(u.diet_name, fc.diet_name) as diet_name,
               fc.status, fc.created_at
        FROM FriendConnections fc
        LEFT JOIN Users u ON (
          CASE WHEN fc.user_id = @userId THEN fc.friend_user_id ELSE fc.user_id END
        ) = u.user_id
        WHERE (fc.user_id = @userId OR fc.friend_user_id = @userId)
          AND fc.status IN ('ACCEPTED', 'CONNECTED')
        ORDER BY fc.friend_name ASC
      `);

    const friends = result.recordset.map(f => ({
      id: f.connection_id,
      userId: f.user_id,
      friendUserId: f.friend_user_id,
      phone: f.friend_phone,
      name: f.friend_name,
      dietType: f.diet_type ?? 0,
      dietName: f.diet_name || 'Vegetarian',
      status: f.status,
      createdAt: f.created_at,
    }));

    return res.json({ success: true, friends });
  } catch (err) {
    console.error('get-friends error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 4. Get Pending Incoming Friend Requests for User
router.get('/requests', async (req, res) => {
  try {
    const userId = req.query.userId || (req.user && req.user.user_id);
    if (!userId) {
      return res.status(400).json({ success: false, message: 'User ID required' });
    }

    const pool = await getPool();
    const result = await pool.request()
      .input('userId', sql.NVarChar(100), userId)
      .query(`
        SELECT fc.connection_id, fc.user_id as requester_id, u.full_name as requester_name,
               u.phone_number as requester_phone, u.diet_type, u.diet_name, fc.created_at
        FROM FriendConnections fc
        JOIN Users u ON fc.user_id = u.user_id
        WHERE (fc.friend_user_id = @userId OR fc.receiver_id = @userId)
          AND fc.status = 'PENDING'
        ORDER BY fc.created_at DESC
      `);

    const requests = result.recordset.map(r => ({
      id: r.connection_id,
      requesterId: r.requester_id,
      requesterName: r.requester_name,
      requesterPhone: r.requester_phone,
      dietType: r.diet_type ?? 0,
      dietName: r.diet_name || 'Vegetarian',
      createdAt: r.created_at,
    }));

    return res.json({ success: true, requests });
  } catch (err) {
    console.error('get-requests error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 5. Send Friend Request / Add Connection
router.post('/add', async (req, res) => {
  try {
    const { userId, friendPhone, friendName, friendUserId, dietType = 0, dietName = 'Vegetarian' } = req.body;
    const effectiveUserId = userId || (req.user && req.user.user_id);

    if (!effectiveUserId || !friendPhone) {
      return res.status(400).json({ success: false, message: 'User ID and friend phone required' });
    }

    const pool = await getPool();
    const cleanPhone = friendPhone.trim();
    const cleanDigits = cleanPhone.replace(/[^0-9]/g, '').slice(-10);

    // Look up if requester user exists
    const requesterRes = await pool.request()
      .input('userId', sql.NVarChar(100), effectiveUserId)
      .query('SELECT full_name FROM Users WHERE user_id = @userId');
    const requesterName = requesterRes.recordset.length > 0 ? requesterRes.recordset[0].full_name : 'A user';

    // Look up if target friend is registered
    let targetUserId = friendUserId;
    let targetDietType = dietType;
    let targetDietName = dietName;
    let targetName = friendName;

    const userLookup = await pool.request()
      .input('phone', sql.NVarChar(20), `%${cleanDigits}`)
      .query('SELECT user_id, full_name, diet_type, diet_name FROM Users WHERE phone_number LIKE @phone');

    if (userLookup.recordset.length > 0) {
      const matched = userLookup.recordset[0];
      targetUserId = matched.user_id;
      targetName = matched.full_name || friendName;
      targetDietType = matched.diet_type ?? dietType;
      targetDietName = matched.diet_name || dietName;
    }

    // Check if already exists in FriendConnections
    const existing = await pool.request()
      .input('userId', sql.NVarChar(100), effectiveUserId)
      .input('targetId', sql.NVarChar(100), targetUserId || '')
      .input('phone', sql.NVarChar(20), cleanPhone)
      .query(`
        SELECT connection_id, status FROM FriendConnections
        WHERE (user_id = @userId AND (friend_user_id = @targetId OR friend_phone = @phone))
           OR (user_id = @targetId AND friend_user_id = @userId)
      `);

    if (existing.recordset.length > 0) {
      const currentStatus = existing.recordset[0].status;
      if (currentStatus === 'ACCEPTED' || currentStatus === 'CONNECTED') {
        return res.json({ success: true, message: 'Already connected as friends.' });
      }
      return res.json({ success: true, message: 'Friend request is already pending.' });
    }

    const connectionId = uuidv4();
    const status = targetUserId ? 'PENDING' : 'ACCEPTED'; // Auto-accept if unregistered phone contact

    await pool.request()
      .input('connectionId', sql.NVarChar(100), connectionId)
      .input('userId', sql.NVarChar(100), effectiveUserId)
      .input('friendUserId', sql.NVarChar(100), targetUserId || '')
      .input('friendPhone', sql.NVarChar(20), cleanPhone)
      .input('friendName', sql.NVarChar(150), targetName || 'Friend')
      .input('dietType', sql.Int, targetDietType)
      .input('dietName', sql.NVarChar(50), targetDietName)
      .input('status', sql.NVarChar(50), status)
      .input('requesterId', sql.NVarChar(100), effectiveUserId)
      .input('receiverId', sql.NVarChar(100), targetUserId || '')
      .query(`
        INSERT INTO FriendConnections (connection_id, user_id, friend_user_id, friend_phone, friend_name, diet_type, diet_name, status, requester_id, receiver_id, created_at)
        VALUES (@connectionId, @userId, @friendUserId, @friendPhone, @friendName, @dietType, @dietName, @status, @requesterId, @receiverId, GETDATE())
      `);

    // If registered user, send Friend Request Notification
    if (targetUserId) {
      const notifId = uuidv4();
      await pool.request()
        .input('notifId', sql.NVarChar(100), notifId)
        .input('userId', sql.NVarChar(100), targetUserId)
        .input('title', sql.NVarChar(200), '🤝 Friend Request')
        .input('message', sql.NVarChar(sql.MAX), `${requesterName} sent you a Trip Friend request on EquiTrip.`)
        .input('type', sql.NVarChar(50), 'FRIEND_REQUEST')
        .query(`
          INSERT INTO Notifications (notification_id, user_id, title, message, type, is_read, created_at)
          VALUES (@notifId, @userId, @title, @message, @type, 0, GETDATE())
        `);
    }

    return res.json({
      success: true,
      message: targetUserId ? 'Friend request sent!' : 'Friend added to your list!',
      friend: {
        id: connectionId,
        userId: effectiveUserId,
        friendUserId: targetUserId,
        phone: cleanPhone,
        name: targetName,
        dietType: targetDietType,
        dietName: targetDietName,
        status: status,
      },
    });
  } catch (err) {
    console.error('add-friend error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 6. Accept Friend Request
router.post('/accept', async (req, res) => {
  try {
    const { connectionId, userId } = req.body;
    const effectiveUserId = userId || (req.user && req.user.user_id);

    if (!connectionId) {
      return res.status(400).json({ success: false, message: 'Connection ID required' });
    }

    const pool = await getPool();

    // Get the request details
    const reqRes = await pool.request()
      .input('connectionId', sql.NVarChar(100), connectionId)
      .query('SELECT user_id, friend_user_id FROM FriendConnections WHERE connection_id = @connectionId');

    if (reqRes.recordset.length === 0) {
      return res.status(404).json({ success: false, message: 'Friend request not found.' });
    }

    const requesterId = reqRes.recordset[0].user_id;

    // Update status to ACCEPTED
    await pool.request()
      .input('connectionId', sql.NVarChar(100), connectionId)
      .query("UPDATE FriendConnections SET status = 'ACCEPTED' WHERE connection_id = @connectionId");

    // Get acceptor user name
    const acceptorRes = await pool.request()
      .input('userId', sql.NVarChar(100), effectiveUserId)
      .query('SELECT full_name FROM Users WHERE user_id = @userId');
    const acceptorName = acceptorRes.recordset.length > 0 ? acceptorRes.recordset[0].full_name : 'A member';

    // Notify original requester
    const notifId = uuidv4();
    await pool.request()
      .input('notifId', sql.NVarChar(100), notifId)
      .input('userId', sql.NVarChar(100), requesterId)
      .input('title', sql.NVarChar(200), '🎉 Friend Request Accepted')
      .input('message', sql.NVarChar(sql.MAX), `${acceptorName} accepted your Trip Friend request! You are now connected.`)
      .input('type', sql.NVarChar(50), 'FRIEND_ACCEPTED')
      .query(`
        INSERT INTO Notifications (notification_id, user_id, title, message, type, is_read, created_at)
        VALUES (@notifId, @userId, @title, @message, @type, 0, GETDATE())
      `);

    return res.json({ success: true, message: 'Friend request accepted!' });
  } catch (err) {
    console.error('accept-friend error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 7. Decline / Remove Friend Connection
router.post('/decline', async (req, res) => {
  try {
    const { connectionId } = req.body;
    const pool = await getPool();
    await pool.request()
      .input('connectionId', sql.NVarChar(100), connectionId)
      .query('DELETE FROM FriendConnections WHERE connection_id = @connectionId');

    return res.json({ success: true, message: 'Friend request declined' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 8. Delete Friend Connection
router.delete('/:id', async (req, res) => {
  try {
    const connectionId = req.params.id;
    const pool = await getPool();
    await pool.request()
      .input('connectionId', sql.NVarChar(100), connectionId)
      .query('DELETE FROM FriendConnections WHERE connection_id = @connectionId');

    return res.json({ success: true, message: 'Friend removed' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;

