// server/routes/authRoutes.js
const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
const { getPool, sql } = require('../db');

function hashPassword(password) {
  return crypto.createHash('sha256').update(password).digest('hex');
}

function generateToken() {
  return crypto.randomBytes(32).toString('hex');
}

function generateOtp() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// 1. Send OTP (for Registration, Forgot Password, Login)
router.post('/send-otp', async (req, res) => {
  try {
    const { phone, purpose = 'REGISTER' } = req.body;
    if (!phone || phone.trim().length < 6) {
      return res.status(400).json({ success: false, message: 'Valid phone number is required.' });
    }

    const cleanPhone = phone.trim();
    const pool = await getPool();

    if (purpose === 'REGISTER') {
      const userCheck = await pool.request()
        .input('phone', sql.NVarChar(20), cleanPhone)
        .query('SELECT user_id FROM Users WHERE phone_number = @phone');
      if (userCheck.recordset.length > 0) {
        return res.status(400).json({ success: false, message: 'An account with this phone number already exists. Please log in.' });
      }
    }

    if (purpose === 'FORGOT_PASSWORD') {
      const userCheck = await pool.request()
        .input('phone', sql.NVarChar(20), cleanPhone)
        .query('SELECT user_id FROM Users WHERE phone_number = @phone');
      if (userCheck.recordset.length === 0) {
        return res.status(404).json({ success: false, message: 'No account found with this phone number.' });
      }
    }

    const otpCode = generateOtp();
    const otpId = uuidv4();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

    await pool.request()
      .input('phone', sql.NVarChar(20), cleanPhone)
      .input('purpose', sql.NVarChar(50), purpose)
      .query('UPDATE OtpVerification SET is_verified = 1 WHERE phone_number = @phone AND purpose = @purpose AND is_verified = 0');

    await pool.request()
      .input('otpId', sql.NVarChar(100), otpId)
      .input('phone', sql.NVarChar(20), cleanPhone)
      .input('otpCode', sql.NVarChar(10), otpCode)
      .input('purpose', sql.NVarChar(50), purpose)
      .input('expiresAt', sql.DateTime, expiresAt)
      .query(`
        INSERT INTO OtpVerification (otp_id, phone_number, otp_code, purpose, is_verified, expires_at, created_at)
        VALUES (@otpId, @phone, @otpCode, @purpose, 0, @expiresAt, GETDATE())
      `);

    console.log(`[OTP] Generated OTP for ${cleanPhone} (${purpose}): ${otpCode}`);

    return res.json({
      success: true,
      message: `OTP sent successfully to ${cleanPhone}.`,
      otp: otpCode,
      expiresInMinutes: 10,
    });
  } catch (err) {
    console.error('send-otp error:', err);
    return res.status(500).json({ success: false, message: 'Failed to send OTP: ' + err.message });
  }
});

// 2. Verify OTP
router.post('/verify-otp', async (req, res) => {
  try {
    const { phone, otp, purpose = 'REGISTER' } = req.body;
    if (!phone || !otp) {
      return res.status(400).json({ success: false, message: 'Phone and OTP are required.' });
    }

    const cleanPhone = phone.trim();
    const pool = await getPool();

    const result = await pool.request()
      .input('phone', sql.NVarChar(20), cleanPhone)
      .input('otp', sql.NVarChar(10), otp.trim())
      .input('purpose', sql.NVarChar(50), purpose)
      .query(`
        SELECT TOP 1 otp_id, expires_at
        FROM OtpVerification
        WHERE phone_number = @phone AND otp_code = @otp AND purpose = @purpose AND is_verified = 0
        ORDER BY created_at DESC
      `);

    if (result.recordset.length === 0) {
      return res.status(400).json({ success: false, message: 'Invalid or expired OTP code.' });
    }

    const record = result.recordset[0];
    if (new Date(record.expires_at) < new Date()) {
      return res.status(400).json({ success: false, message: 'OTP code has expired. Please request a new one.' });
    }

    await pool.request()
      .input('otpId', sql.NVarChar(100), record.otp_id)
      .query('UPDATE OtpVerification SET is_verified = 1 WHERE otp_id = @otpId');

    return res.json({ success: true, message: 'OTP verified successfully!' });
  } catch (err) {
    return res.status(500).json({ success: false, message: 'OTP verification failed: ' + err.message });
  }
});

// 3. Register Account with Phone, Full Name, Password, and OTP
router.post('/register', async (req, res) => {
  try {
    const { phone, fullName, password, otp, dietType = 0, deviceInfo = 'Mobile App' } = req.body;

    if (!phone || !fullName || !password) {
      return res.status(400).json({ success: false, message: 'Phone number, name, and password are required.' });
    }

    const cleanPhone = phone.trim();
    const cleanName = fullName.trim();
    const pool = await getPool();

    const existing = await pool.request()
      .input('phone', sql.NVarChar(20), cleanPhone)
      .query('SELECT user_id FROM Users WHERE phone_number = @phone');

    if (existing.recordset.length > 0) {
      return res.status(400).json({ success: false, message: 'Account with this phone number already exists.' });
    }

    if (otp) {
      const otpCheck = await pool.request()
        .input('phone', sql.NVarChar(20), cleanPhone)
        .input('otp', sql.NVarChar(10), otp.trim())
        .input('purpose', sql.NVarChar(50), 'REGISTER')
        .query(`
          SELECT TOP 1 otp_id, is_verified, expires_at
          FROM OtpVerification
          WHERE phone_number = @phone AND otp_code = @otp AND purpose = @purpose
          ORDER BY created_at DESC
        `);

      if (otpCheck.recordset.length === 0) {
        return res.status(400).json({ success: false, message: 'Invalid OTP code.' });
      }

      await pool.request()
        .input('otpId', sql.NVarChar(100), otpCheck.recordset[0].otp_id)
        .query('UPDATE OtpVerification SET is_verified = 1 WHERE otp_id = @otpId');
    }

    const userId = uuidv4();
    const passwordHash = hashPassword(password);
    const authToken = generateToken();
    const tokenExpiry = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000);
    const dietNames = ['Vegetarian', 'Non-Vegetarian', 'Non-Veg + Alcohol'];
    const dietName = dietNames[dietType] || 'Vegetarian';

    await pool.request()
      .input('userId', sql.NVarChar(100), userId)
      .input('phone', sql.NVarChar(20), cleanPhone)
      .input('fullName', sql.NVarChar(150), cleanName)
      .input('passwordHash', sql.NVarChar(255), passwordHash)
      .input('authToken', sql.NVarChar(500), authToken)
      .input('tokenExpiry', sql.DateTime, tokenExpiry)
      .input('dietType', sql.Int, dietType)
      .input('dietName', sql.NVarChar(50), dietName)
      .query(`
        INSERT INTO Users (user_id, phone_number, full_name, password_hash, auth_token, token_expiry, diet_type, diet_name, is_biometric_enabled, is_active, created_at, updated_at, last_login_at)
        VALUES (@userId, @phone, @fullName, @passwordHash, @authToken, @tokenExpiry, @dietType, @dietName, 0, 1, GETDATE(), GETDATE(), GETDATE())
      `);

    const tokenId = uuidv4();
    await pool.request()
      .input('tokenId', sql.NVarChar(100), tokenId)
      .input('userId', sql.NVarChar(100), userId)
      .input('phone', sql.NVarChar(20), cleanPhone)
      .input('authToken', sql.NVarChar(500), authToken)
      .input('deviceInfo', sql.NVarChar(255), deviceInfo)
      .input('expiresAt', sql.DateTime, tokenExpiry)
      .query(`
        INSERT INTO UserTokens (token_id, user_id, phone_number, auth_token, device_info, is_active, expires_at, created_at, last_used_at)
        VALUES (@tokenId, @userId, @phone, @authToken, @deviceInfo, 1, @expiresAt, GETDATE(), GETDATE())
      `);

    return res.json({
      success: true,
      message: 'Account created successfully!',
      user: {
        id: userId,
        phone: cleanPhone,
        fullName: cleanName,
        dietType: dietType,
        dietName: dietName,
        createdAt: new Date().toISOString(),
        lastLoginAt: new Date().toISOString(),
      },
      token: authToken,
    });
  } catch (err) {
    console.error('register error:', err);
    return res.status(500).json({ success: false, message: 'Registration failed: ' + err.message });
  }
});

// 4. Login with Phone & Password
router.post('/login', async (req, res) => {
  try {
    const { phone, password, deviceInfo = 'Mobile App' } = req.body;

    if (!phone || !password) {
      return res.status(400).json({ success: false, message: 'Phone number and password are required.' });
    }

    const cleanPhone = phone.trim();
    const pool = await getPool();

    const userResult = await pool.request()
      .input('phone', sql.NVarChar(20), cleanPhone)
      .query(`
        SELECT user_id, phone_number, full_name, password_hash, diet_type, diet_name, is_biometric_enabled, created_at, last_login_at
        FROM Users
        WHERE phone_number = @phone AND is_active = 1
      `);

    if (userResult.recordset.length === 0) {
      return res.status(404).json({ success: false, message: 'User with this phone number not found.' });
    }

    const user = userResult.recordset[0];
    const passwordHash = hashPassword(password);

    if (user.password_hash !== passwordHash) {
      return res.status(401).json({ success: false, message: 'Incorrect password. Please try again.' });
    }

    const authToken = generateToken();
    const tokenExpiry = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000);
    const tokenId = uuidv4();

    await pool.request()
      .input('userId', sql.NVarChar(100), user.user_id)
      .input('authToken', sql.NVarChar(500), authToken)
      .input('tokenExpiry', sql.DateTime, tokenExpiry)
      .query(`
        UPDATE Users
        SET auth_token = @authToken, token_expiry = @tokenExpiry, last_login_at = GETDATE(), updated_at = GETDATE()
        WHERE user_id = @userId
      `);

    await pool.request()
      .input('tokenId', sql.NVarChar(100), tokenId)
      .input('userId', sql.NVarChar(100), user.user_id)
      .input('phone', sql.NVarChar(20), cleanPhone)
      .input('authToken', sql.NVarChar(500), authToken)
      .input('deviceInfo', sql.NVarChar(255), deviceInfo)
      .input('expiresAt', sql.DateTime, tokenExpiry)
      .query(`
        INSERT INTO UserTokens (token_id, user_id, phone_number, auth_token, device_info, is_active, expires_at, created_at, last_used_at)
        VALUES (@tokenId, @userId, @phone, @authToken, @deviceInfo, 1, @expiresAt, GETDATE(), GETDATE())
      `);

    return res.json({
      success: true,
      message: 'Login successful!',
      user: {
        id: user.user_id,
        phone: user.phone_number,
        fullName: user.full_name,
        dietType: user.diet_type ?? 0,
        dietName: user.diet_name || 'Vegetarian',
        isBiometricEnabled: user.is_biometric_enabled === 1 || user.is_biometric_enabled === true,
        createdAt: user.created_at,
        lastLoginAt: new Date().toISOString(),
      },
      token: authToken,
    });
  } catch (err) {
    console.error('login error:', err);
    return res.status(500).json({ success: false, message: 'Login failed: ' + err.message });
  }
});

// 5. Verify Token
router.post('/verify-token', async (req, res) => {
  try {
    const { token, phone } = req.body;
    if (!token) {
      return res.status(400).json({ valid: false, message: 'Token is required.' });
    }

    const pool = await getPool();

    let query = `
      SELECT TOP 1 ut.token_id, ut.user_id, ut.phone_number, ut.expires_at,
                   u.full_name, u.diet_type, u.diet_name, u.is_biometric_enabled, u.created_at, u.last_login_at
      FROM UserTokens ut
      INNER JOIN Users u ON ut.user_id = u.user_id
      WHERE ut.auth_token = @token AND ut.is_active = 1
    `;

    const request = pool.request().input('token', sql.NVarChar(500), token.trim());
    if (phone) {
      query += ' AND ut.phone_number = @phone';
      request.input('phone', sql.NVarChar(20), phone.trim());
    }

    const result = await request.query(query);

    if (result.recordset.length === 0) {
      return res.status(401).json({ valid: false, message: 'Session expired or invalid token.' });
    }

    const session = result.recordset[0];
    if (session.expires_at && new Date(session.expires_at) < new Date()) {
      return res.status(401).json({ valid: false, message: 'Token expired.' });
    }

    await pool.request()
      .input('tokenId', sql.NVarChar(100), session.token_id)
      .query('UPDATE UserTokens SET last_used_at = GETDATE() WHERE token_id = @tokenId');

    return res.json({
      valid: true,
      user: {
        id: session.user_id,
        phone: session.phone_number,
        fullName: session.full_name,
        dietType: session.diet_type ?? 0,
        dietName: session.diet_name || 'Vegetarian',
        isBiometricEnabled: session.is_biometric_enabled === 1 || session.is_biometric_enabled === true,
        createdAt: session.created_at,
        lastLoginAt: session.last_login_at,
      },
      token: token,
    });
  } catch (err) {
    return res.status(500).json({ valid: false, message: 'Token verification failed: ' + err.message });
  }
});

// 6. Update User Profile (Dietary Preference, Name)
router.post('/profile', async (req, res) => {
  try {
    const { userId, fullName, dietType } = req.body;
    if (!userId) {
      return res.status(400).json({ success: false, message: 'User ID is required' });
    }

    const dietNames = ['Vegetarian', 'Non-Vegetarian', 'Non-Veg + Alcohol'];
    const resolvedDietName = dietNames[dietType] || 'Vegetarian';
    const pool = await getPool();

    let query = 'UPDATE Users SET updated_at = GETDATE()';
    const request = pool.request().input('userId', sql.NVarChar(100), userId);

    if (fullName) {
      query += ', full_name = @fullName';
      request.input('fullName', sql.NVarChar(150), fullName.trim());
    }
    if (typeof dietType === 'number') {
      query += ', diet_type = @dietType, diet_name = @dietName';
      request.input('dietType', sql.Int, dietType);
      request.input('dietName', sql.NVarChar(50), resolvedDietName);
    }

    query += ' WHERE user_id = @userId';
    await request.query(query);

    const userRes = await pool.request()
      .input('userId', sql.NVarChar(100), userId)
      .query('SELECT user_id, phone_number, full_name, diet_type, diet_name, is_biometric_enabled, created_at, last_login_at FROM Users WHERE user_id = @userId');

    const u = userRes.recordset[0] || {};

    return res.json({
      success: true,
      message: 'Profile updated successfully!',
      user: {
        id: u.user_id || userId,
        phone: u.phone_number || '',
        fullName: u.full_name || fullName || '',
        dietType: u.diet_type ?? dietType ?? 0,
        dietName: u.diet_name || resolvedDietName,
        isBiometricEnabled: u.is_biometric_enabled === 1 || u.is_biometric_enabled === true,
        createdAt: u.created_at,
        lastLoginAt: u.last_login_at,
      },
      dietType: u.diet_type ?? dietType ?? 0,
      dietName: u.diet_name || resolvedDietName,
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 7. Reset Password
router.post('/reset-password', async (req, res) => {
  try {
    const { phone, otp, newPassword } = req.body;
    if (!phone || !otp || !newPassword) {
      return res.status(400).json({ success: false, message: 'Phone, OTP, and new password are required.' });
    }

    const cleanPhone = phone.trim();
    const pool = await getPool();

    const otpResult = await pool.request()
      .input('phone', sql.NVarChar(20), cleanPhone)
      .input('otp', sql.NVarChar(10), otp.trim())
      .input('purpose', sql.NVarChar(50), 'FORGOT_PASSWORD')
      .query(`
        SELECT TOP 1 otp_id, expires_at
        FROM OtpVerification
        WHERE phone_number = @phone AND otp_code = @otp AND purpose = @purpose
        ORDER BY created_at DESC
      `);

    if (otpResult.recordset.length === 0) {
      return res.status(400).json({ success: false, message: 'Invalid OTP code.' });
    }

    const record = otpResult.recordset[0];
    if (new Date(record.expires_at) < new Date()) {
      return res.status(400).json({ success: false, message: 'OTP has expired. Please request a new one.' });
    }

    await pool.request()
      .input('otpId', sql.NVarChar(100), record.otp_id)
      .query('UPDATE OtpVerification SET is_verified = 1 WHERE otp_id = @otpId');

    const newHash = hashPassword(newPassword);
    const newToken = generateToken();
    const tokenExpiry = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000);

    await pool.request()
      .input('phone', sql.NVarChar(20), cleanPhone)
      .input('passwordHash', sql.NVarChar(255), newHash)
      .input('authToken', sql.NVarChar(500), newToken)
      .input('tokenExpiry', sql.DateTime, tokenExpiry)
      .query(`
        UPDATE Users
        SET password_hash = @passwordHash, auth_token = @authToken, token_expiry = @tokenExpiry, updated_at = GETDATE()
        WHERE phone_number = @phone
      `);

    await pool.request()
      .input('phone', sql.NVarChar(20), cleanPhone)
      .query('UPDATE UserTokens SET is_active = 0 WHERE phone_number = @phone');

    return res.json({ success: true, message: 'Password updated successfully!' });
  } catch (err) {
    return res.status(500).json({ success: false, message: 'Password reset failed: ' + err.message });
  }
});

// 8. Toggle Biometric
router.post('/toggle-biometric', async (req, res) => {
  try {
    const { userId, enabled } = req.body;
    if (!userId) return res.status(400).json({ success: false, message: 'User ID is required.' });

    const pool = await getPool();
    await pool.request()
      .input('userId', sql.NVarChar(100), userId)
      .input('enabled', sql.Bit, enabled ? 1 : 0)
      .query('UPDATE Users SET is_biometric_enabled = @enabled, updated_at = GETDATE() WHERE user_id = @userId');

    return res.json({ success: true, isBiometricEnabled: enabled });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 9. Logout
router.post('/logout', async (req, res) => {
  try {
    const { token } = req.body;
    if (token) {
      const pool = await getPool();
      await pool.request()
        .input('token', sql.NVarChar(500), token.trim())
        .query('UPDATE UserTokens SET is_active = 0 WHERE auth_token = @token');
    }
    return res.json({ success: true, message: 'Logged out successfully.' });
  } catch (err) {
    return res.json({ success: true });
  }
});

module.exports = router;
