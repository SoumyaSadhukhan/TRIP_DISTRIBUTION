// server/routes/notificationRoutes.js
const express = require('express');
const router = express.Router();
const { getPool, sql } = require('../db');

// Middleware to authenticate token
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
  } catch (err) {}
  next();
}

router.use(authenticateToken);

// 1. Get Notifications for User
router.get('/', async (req, res) => {
  try {
    const userId = req.query.userId || (req.user && req.user.user_id);
    if (!userId) {
      return res.status(400).json({ success: false, message: 'User ID is required' });
    }

    const pool = await getPool();
    const result = await pool.request()
      .input('userId', sql.NVarChar(100), userId)
      .query(`
        SELECT TOP 50 notification_id, user_id, trip_id, trip_name, title, message, type, amount, is_read, created_at
        FROM Notifications
        WHERE user_id = @userId
        ORDER BY created_at DESC
      `);

    const notifications = result.recordset.map(n => ({
      id: n.notification_id,
      userId: n.user_id,
      tripId: n.trip_id,
      tripName: n.trip_name,
      title: n.title,
      message: n.message,
      type: n.type,
      amount: parseFloat(n.amount || 0),
      isRead: n.is_read === true || n.is_read === 1,
      createdAt: n.created_at ? new Date(n.created_at).toISOString() : new Date().toISOString(),
    }));

    return res.json({ success: true, notifications });
  } catch (err) {
    console.error('get-notifications error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 2. Get Unread Count
router.get('/unread-count', async (req, res) => {
  try {
    const userId = req.query.userId || (req.user && req.user.user_id);
    if (!userId) {
      return res.json({ success: true, count: 0 });
    }

    const pool = await getPool();
    const result = await pool.request()
      .input('userId', sql.NVarChar(100), userId)
      .query('SELECT COUNT(*) as unreadCount FROM Notifications WHERE user_id = @userId AND is_read = 0');

    return res.json({ success: true, count: result.recordset[0].unreadCount || 0 });
  } catch (err) {
    return res.json({ success: true, count: 0 });
  }
});

// 3. Mark Notifications as Read
router.post('/mark-read', async (req, res) => {
  try {
    const { notificationId, userId } = req.body;
    const effectiveUserId = userId || (req.user && req.user.user_id);
    const pool = await getPool();

    if (notificationId) {
      await pool.request()
        .input('id', sql.NVarChar(100), notificationId)
        .query('UPDATE Notifications SET is_read = 1 WHERE notification_id = @id');
    } else if (effectiveUserId) {
      await pool.request()
        .input('userId', sql.NVarChar(100), effectiveUserId)
        .query('UPDATE Notifications SET is_read = 1 WHERE user_id = @userId');
    }

    return res.json({ success: true, message: 'Marked as read' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
