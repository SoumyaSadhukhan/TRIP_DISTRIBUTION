// server/routes/tripRoutes.js
const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
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
  } catch (err) {
    console.error('Token auth middleware error:', err);
  }
  next();
}

router.use(authenticateToken);

// 1. Get All Trips for a User (Owned + Collaborative / Shared)
router.get('/', async (req, res) => {
  try {
    const userId = req.query.userId || (req.user && req.user.user_id);
    const phone = req.query.phone || (req.user && req.user.phone_number);

    if (!userId && !phone) {
      return res.status(400).json({ success: false, message: 'User identifier required.' });
    }

    const pool = await getPool();
    const cleanPhone = phone ? phone.replace(/[^0-9]/g, '').slice(-10) : '';

    // Fetch trips where user is Creator OR Member in Persons / Collaborators
    let tripsQuery = `
      SELECT DISTINCT t.trip_id, t.user_id, t.name, t.description, t.created_at, t.updated_at
      FROM Trips t
      LEFT JOIN Persons p ON t.trip_id = p.trip_id
      LEFT JOIN TripCollaborators tc ON t.trip_id = tc.trip_id
      WHERE (1=0)
    `;

    const request = pool.request();
    if (userId) {
      tripsQuery += ' OR t.user_id = @userId OR p.user_id = @userId OR tc.user_id = @userId';
      request.input('userId', sql.NVarChar(100), userId);
    }
    if (cleanPhone) {
      tripsQuery += ' OR RIGHT(p.phone_number, 10) = @cleanPhone OR RIGHT(tc.phone_number, 10) = @cleanPhone';
      request.input('cleanPhone', sql.NVarChar(20), cleanPhone);
    }

    tripsQuery += ' ORDER BY t.created_at DESC';
    const tripsResult = await request.query(tripsQuery);
    const rawTrips = tripsResult.recordset;

    if (rawTrips.length === 0) {
      return res.json({ success: true, trips: [] });
    }

    const tripIds = rawTrips.map(t => `'${t.trip_id}'`).join(',');

    // Fetch Groups, Persons, Expenses, Splits
    const groupsResult = await pool.request().query(`
      SELECT * FROM Groups WHERE trip_id IN (${tripIds}) ORDER BY created_at ASC
    `);

    const personsResult = await pool.request().query(`
      SELECT * FROM Persons WHERE trip_id IN (${tripIds}) ORDER BY created_at ASC
    `);

    const expensesResult = await pool.request().query(`
      SELECT * FROM Expenses WHERE trip_id IN (${tripIds}) ORDER BY expense_date DESC
    `);

    const splitsResult = await pool.request().query(`
      SELECT * FROM ExpenseSplits WHERE trip_id IN (${tripIds})
    `);

    const splitsByExpenseId = {};
    for (const split of splitsResult.recordset) {
      if (!splitsByExpenseId[split.expense_id]) {
        splitsByExpenseId[split.expense_id] = [];
      }
      splitsByExpenseId[split.expense_id].push(split.person_id);
    }

    const expensesByTripId = {};
    for (const exp of expensesResult.recordset) {
      if (!expensesByTripId[exp.trip_id]) {
        expensesByTripId[exp.trip_id] = [];
      }
      expensesByTripId[exp.trip_id].push({
        id: exp.expense_id,
        description: exp.description,
        amount: parseFloat(exp.amount),
        category: exp.category_index ?? 0,
        paidById: exp.paid_by_person_id,
        date: exp.expense_date ? new Date(exp.expense_date).toISOString() : new Date().toISOString(),
        splitAmongIds: splitsByExpenseId[exp.expense_id] || [],
      });
    }

    const personsByGroupId = {};
    for (const person of personsResult.recordset) {
      if (!personsByGroupId[person.group_id]) {
        personsByGroupId[person.group_id] = [];
      }
      personsByGroupId[person.group_id].push({
        id: person.person_id,
        userId: person.user_id || '',
        phone: person.phone_number || '',
        name: person.name,
        dietType: person.diet_type ?? 0,
        paidAmount: parseFloat(person.paid_amount || 0),
        owedAmount: parseFloat(person.owed_amount || 0),
        balance: parseFloat(person.balance || 0),
      });
    }

    const groupsByTripId = {};
    for (const grp of groupsResult.recordset) {
      if (!groupsByTripId[grp.trip_id]) {
        groupsByTripId[grp.trip_id] = [];
      }
      groupsByTripId[grp.trip_id].push({
        id: grp.group_id,
        name: grp.name,
        members: personsByGroupId[grp.group_id] || [],
      });
    }

    const formattedTrips = rawTrips.map(t => ({
      id: t.trip_id,
      name: t.name,
      description: t.description || '',
      isOwner: t.user_id === userId,
      createdAt: t.created_at ? new Date(t.created_at).toISOString() : new Date().toISOString(),
      groups: groupsByTripId[t.trip_id] || [],
      expenses: expensesByTripId[t.trip_id] || [],
    }));

    return res.json({ success: true, trips: formattedTrips });
  } catch (err) {
    console.error('get-trips error:', err);
    return res.status(500).json({ success: false, message: 'Failed to fetch trips: ' + err.message });
  }
});

// 2. Batch Sync Trips (With Collaborative Member Linking & Real-Time Notifications)
router.post('/sync', async (req, res) => {
  try {
    const { userId, trips = [] } = req.body;
    const effectiveUserId = userId || (req.user && req.user.user_id);

    if (!effectiveUserId) {
      return res.status(400).json({ success: false, message: 'User ID is required for sync.' });
    }

    const pool = await getPool();

    for (const trip of trips) {
      const tripId = trip.id;
      const tripName = trip.name || 'Untitled Trip';
      const description = trip.description || '';
      const createdAt = trip.createdAt ? new Date(trip.createdAt) : new Date();

      // A. Upsert into Trips table
      await pool.request()
        .input('tripId', sql.NVarChar(100), tripId)
        .input('userId', sql.NVarChar(100), effectiveUserId)
        .input('name', sql.NVarChar(200), tripName)
        .input('description', sql.NVarChar(sql.MAX), description)
        .input('createdAt', sql.DateTime, createdAt)
        .query(`
          IF EXISTS (SELECT 1 FROM Trips WHERE trip_id = @tripId)
            UPDATE Trips SET name = @name, description = @description, updated_at = GETDATE() WHERE trip_id = @tripId
          ELSE
            INSERT INTO Trips (trip_id, user_id, name, description, created_at, updated_at)
            VALUES (@tripId, @userId, @name, @description, @createdAt, GETDATE())
        `);

      // B. Clean and rewrite Groups and Persons for this trip
      await pool.request()
        .input('tripId', sql.NVarChar(100), tripId)
        .query('DELETE FROM Persons WHERE trip_id = @tripId; DELETE FROM Groups WHERE trip_id = @tripId; DELETE FROM TripCollaborators WHERE trip_id = @tripId;');

      const memberUserIds = new Set();

      if (Array.isArray(trip.groups)) {
        for (const group of trip.groups) {
          const groupId = group.id;
          const groupName = group.name || 'Group';

          await pool.request()
            .input('groupId', sql.NVarChar(100), groupId)
            .input('tripId', sql.NVarChar(100), tripId)
            .input('name', sql.NVarChar(200), groupName)
            .query('INSERT INTO Groups (group_id, trip_id, name, created_at) VALUES (@groupId, @tripId, @name, GETDATE())');

          if (Array.isArray(group.members)) {
            for (const member of group.members) {
              const personId = member.id;
              const personName = member.name || 'Member';
              let memberPhone = member.phone || '';
              let memberUserId = member.userId || '';
              let dietType = typeof member.dietType === 'number' ? member.dietType : 0;
              const dietNames = ['Vegetarian', 'Non-Vegetarian', 'Non-Veg + Alcohol'];

              // If phone provided, auto-link user ID and default diet type from Users profile
              if (memberPhone && !memberUserId) {
                const userMatch = await pool.request()
                  .input('phone', sql.NVarChar(20), `%${memberPhone.replace(/[^0-9]/g, '').slice(-10)}`)
                  .query('SELECT user_id, full_name, diet_type FROM Users WHERE phone_number LIKE @phone');
                if (userMatch.recordset.length > 0) {
                  memberUserId = userMatch.recordset[0].user_id;
                  if (member.dietType == null) {
                    dietType = userMatch.recordset[0].diet_type ?? dietType;
                  }
                }
              }

              if (memberUserId) {
                memberUserIds.add(memberUserId);

                // Insert into TripCollaborators
                const collabId = uuidv4();
                await pool.request()
                  .input('collabId', sql.NVarChar(100), collabId)
                  .input('tripId', sql.NVarChar(100), tripId)
                  .input('userId', sql.NVarChar(100), memberUserId)
                  .input('personId', sql.NVarChar(100), personId)
                  .input('phone', sql.NVarChar(20), memberPhone)
                  .query('INSERT INTO TripCollaborators (collab_id, trip_id, user_id, person_id, phone_number, role, joined_at) VALUES (@collabId, @tripId, @userId, @personId, @phone, \'MEMBER\', GETDATE())');
              }

              const dietName = dietNames[dietType] || 'Vegetarian';
              const paidAmount = parseFloat(member.paidAmount || 0);
              const owedAmount = parseFloat(member.owedAmount || 0);
              const balance = parseFloat(member.balance || 0);

              await pool.request()
                .input('personId', sql.NVarChar(100), personId)
                .input('groupId', sql.NVarChar(100), groupId)
                .input('tripId', sql.NVarChar(100), tripId)
                .input('userId', sql.NVarChar(100), memberUserId)
                .input('phone', sql.NVarChar(20), memberPhone)
                .input('name', sql.NVarChar(150), personName)
                .input('dietType', sql.Int, dietType)
                .input('dietName', sql.NVarChar(50), dietName)
                .input('paidAmount', sql.Decimal(18, 2), paidAmount)
                .input('owedAmount', sql.Decimal(18, 2), owedAmount)
                .input('balance', sql.Decimal(18, 2), balance)
                .query(`
                  INSERT INTO Persons (person_id, group_id, trip_id, user_id, phone_number, name, diet_type, diet_name, paid_amount, owed_amount, balance, created_at)
                  VALUES (@personId, @groupId, @tripId, @userId, @phone, @name, @dietType, @dietName, @paidAmount, @owedAmount, @balance, GETDATE())
                `);
            }
          }
        }
      }

      // C. Clean and rewrite Expenses and ExpenseSplits
      await pool.request()
        .input('tripId', sql.NVarChar(100), tripId)
        .query('DELETE FROM ExpenseSplits WHERE trip_id = @tripId; DELETE FROM Expenses WHERE trip_id = @tripId;');

      if (Array.isArray(trip.expenses)) {
        for (const exp of trip.expenses) {
          const expenseId = exp.id;
          const description = exp.description || 'Expense';
          const amount = parseFloat(exp.amount || 0);
          const categoryIndex = typeof exp.category === 'number' ? exp.category : 0;
          const categoryNames = ['Vegetarian', 'Non-Vegetarian', 'Alcohol', 'Mixed (Veg + Non-Veg)', 'Mixed + Alcohol', 'Transport', 'Accommodation', 'Miscellaneous'];
          const categoryName = categoryNames[categoryIndex] || 'Miscellaneous';
          const paidById = exp.paidById;
          const expenseDate = exp.date ? new Date(exp.date) : new Date();

          await pool.request()
            .input('expenseId', sql.NVarChar(100), expenseId)
            .input('tripId', sql.NVarChar(100), tripId)
            .input('description', sql.NVarChar(500), description)
            .input('amount', sql.Decimal(18, 2), amount)
            .input('categoryIndex', sql.Int, categoryIndex)
            .input('categoryName', sql.NVarChar(100), categoryName)
            .input('paidById', sql.NVarChar(100), paidById)
            .input('expenseDate', sql.DateTime, expenseDate)
            .query(`
              INSERT INTO Expenses (expense_id, trip_id, description, amount, category_index, category_name, paid_by_person_id, expense_date, created_at)
              VALUES (@expenseId, @tripId, @description, @amount, @categoryIndex, @categoryName, @paidById, @expenseDate, GETDATE())
            `);

          if (Array.isArray(exp.splitAmongIds) && exp.splitAmongIds.length > 0) {
            const splitAmount = amount / exp.splitAmongIds.length;
            for (const personId of exp.splitAmongIds) {
              const splitId = uuidv4();
              await pool.request()
                .input('splitId', sql.NVarChar(100), splitId)
                .input('expenseId', sql.NVarChar(100), expenseId)
                .input('tripId', sql.NVarChar(100), tripId)
                .input('personId', sql.NVarChar(100), personId)
                .input('amount', sql.Decimal(18, 2), splitAmount)
                .query(`
                  INSERT INTO ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
                  VALUES (@splitId, @expenseId, @tripId, @personId, @amount, GETDATE())
                `);
            }
          }
        }
      }

      // D. Build person map for rich notification formatting
      const personNameMap = {};
      if (Array.isArray(trip.groups)) {
        for (const group of trip.groups) {
          if (Array.isArray(group.members)) {
            for (const member of group.members) {
              personNameMap[member.id] = member.name || 'Member';
            }
          }
        }
      }

      // Find trip creator user_id to also notify if another collaborator made the edit
      const tripOwnerRes = await pool.request()
        .input('tripId', sql.NVarChar(100), tripId)
        .query('SELECT user_id FROM Trips WHERE trip_id = @tripId');
      if (tripOwnerRes.recordset.length > 0 && tripOwnerRes.recordset[0].user_id) {
        memberUserIds.add(tripOwnerRes.recordset[0].user_id);
      }

      // Discover any additional users registered with the member phone numbers
      const phoneList = [];
      if (Array.isArray(trip.groups)) {
        for (const group of trip.groups) {
          if (Array.isArray(group.members)) {
            for (const m of group.members) {
              if (m.phone) {
                const clean = m.phone.replace(/[^0-9]/g, '').slice(-10);
                if (clean.length >= 10) phoneList.push(clean);
              }
            }
          }
        }
      }

      if (phoneList.length > 0) {
        const phoneClauses = phoneList.map(p => `'${p}'`).join(',');
        const usersByPhone = await pool.request().query(`
          SELECT user_id FROM Users WHERE RIGHT(phone_number, 10) IN (${phoneClauses})
        `);
        for (const u of usersByPhone.recordset) {
          memberUserIds.add(u.user_id);
        }
      }

      // Generate rich notifications for recent expenses
      const latestExpense = Array.isArray(trip.expenses) && trip.expenses.length > 0
          ? trip.expenses[trip.expenses.length - 1]
          : null;

      for (const targetUserId of memberUserIds) {
        if (targetUserId && targetUserId !== effectiveUserId) {
          const notifId = uuidv4();
          let title = `Trip Updated: ${tripName}`;
          let message = `Trip "${tripName}" has been updated with new expenses and balances.`;
          let notifAmount = 0.0;
          let notifType = 'EXPENSE_UPDATED';

          if (latestExpense) {
            const expDesc = latestExpense.description || 'Expense';
            const expAmt = parseFloat(latestExpense.amount || 0);
            const payerName = personNameMap[latestExpense.paidById] || 'A member';
            const splitCount = Array.isArray(latestExpense.splitAmongIds) && latestExpense.splitAmongIds.length > 0
                ? latestExpense.splitAmongIds.length
                : 1;

            title = `💸 ${expDesc} - ₹${expAmt.toLocaleString('en-IN')}`;
            message = `${payerName} recorded "${expDesc}" of ₹${expAmt.toLocaleString('en-IN')} in "${tripName}" (Split among ${splitCount} member${splitCount > 1 ? 's' : ''}).`;
            notifAmount = expAmt;
            notifType = 'EXPENSE_ADDED';
          }

          await pool.request()
            .input('notifId', sql.NVarChar(100), notifId)
            .input('userId', sql.NVarChar(100), targetUserId)
            .input('tripId', sql.NVarChar(100), tripId)
            .input('tripName', sql.NVarChar(200), tripName)
            .input('title', sql.NVarChar(200), title)
            .input('message', sql.NVarChar(sql.MAX), message)
            .input('type', sql.NVarChar(50), notifType)
            .input('amount', sql.Decimal(18, 2), notifAmount)
            .query(`
              INSERT INTO Notifications (notification_id, user_id, trip_id, trip_name, title, message, type, amount, is_read, created_at)
              VALUES (@notifId, @userId, @tripId, @tripName, @title, @message, @type, @amount, 0, GETDATE())
            `);
        }
      }
    }

    return res.json({ success: true, message: 'All collaborative trip data synced successfully!' });
  } catch (err) {
    console.error('sync-trips error:', err);
    return res.status(500).json({ success: false, message: 'Sync failed: ' + err.message });
  }
});

// 3. Delete Trip (Creator Only)
router.delete('/:id', async (req, res) => {
  try {
    const tripId = req.params.id;
    const userId = req.query.userId || (req.user && req.user.user_id);
    const pool = await getPool();

    if (userId) {
      const ownerCheck = await pool.request()
        .input('tripId', sql.NVarChar(100), tripId)
        .query('SELECT user_id FROM Trips WHERE trip_id = @tripId');
      if (ownerCheck.recordset.length > 0 && ownerCheck.recordset[0].user_id) {
        if (ownerCheck.recordset[0].user_id !== userId) {
          return res.status(403).json({ success: false, message: 'Only the trip creator can delete this trip.' });
        }
      }
    }

    await pool.request()
      .input('tripId', sql.NVarChar(100), tripId)
      .query(`
        DELETE FROM Notifications WHERE trip_id = @tripId;
        DELETE FROM TripCollaborators WHERE trip_id = @tripId;
        DELETE FROM ActivityLogs WHERE trip_id = @tripId;
        DELETE FROM SettlementTransactions WHERE trip_id = @tripId;
        DELETE FROM ExpenseSplits WHERE trip_id = @tripId;
        DELETE FROM Expenses WHERE trip_id = @tripId;
        DELETE FROM Persons WHERE trip_id = @tripId;
        DELETE FROM Groups WHERE trip_id = @tripId;
        DELETE FROM Trips WHERE trip_id = @tripId;
      `);

    return res.json({ success: true, message: 'Trip deleted.' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 4. Record Settlement Payment Request (Payer / Payee proposal)
router.post('/settle-request', async (req, res) => {
  try {
    const { tripId, fromPersonId, toPersonId, amount, createdByUserId } = req.body;
    const pool = await getPool();

    if (!tripId || !fromPersonId || !toPersonId || !amount) {
      return res.status(400).json({ success: false, message: 'Missing required settlement parameters.' });
    }

    const settlementId = uuidv4();
    await pool.request()
      .input('settlementId', sql.NVarChar(100), settlementId)
      .input('tripId', sql.NVarChar(100), tripId)
      .input('fromPersonId', sql.NVarChar(100), fromPersonId)
      .input('toPersonId', sql.NVarChar(100), toPersonId)
      .input('amount', sql.Decimal(18, 2), parseFloat(amount))
      .input('createdByUserId', sql.NVarChar(100), createdByUserId || '')
      .query(`
        INSERT INTO SettlementTransactions (settlement_id, trip_id, from_person_id, to_person_id, amount, is_completed, status, created_by_user_id, settled_at)
        VALUES (@settlementId, @tripId, @fromPersonId, @toPersonId, @amount, 0, 'PENDING', @createdByUserId, GETDATE())
      `);

    // Lookup persons & trip name for rich notification
    const personRes = await pool.request()
      .input('fromId', sql.NVarChar(100), fromPersonId)
      .input('toId', sql.NVarChar(100), toPersonId)
      .query('SELECT person_id, name, user_id FROM Persons WHERE person_id IN (@fromId, @toId)');

    const tripRes = await pool.request()
      .input('tripId', sql.NVarChar(100), tripId)
      .query('SELECT name FROM Trips WHERE trip_id = @tripId');

    const tripName = tripRes.recordset.length > 0 ? tripRes.recordset[0].name : 'Trip';
    const fromP = personRes.recordset.find(p => p.person_id === fromPersonId);
    const toP = personRes.recordset.find(p => p.person_id === toPersonId);
    const fromName = fromP ? fromP.name : 'Member';
    const toName = toP ? toP.name : 'Member';

    // Target user to notify (the other side of transaction)
    const targetUserId = (fromP && fromP.user_id !== createdByUserId) ? fromP.user_id : (toP ? toP.user_id : null);

    if (targetUserId) {
      const notifId = uuidv4();
      const formattedAmt = parseFloat(amount).toLocaleString('en-IN');
      await pool.request()
        .input('notifId', sql.NVarChar(100), notifId)
        .input('userId', sql.NVarChar(100), targetUserId)
        .input('tripId', sql.NVarChar(100), tripId)
        .input('tripName', sql.NVarChar(200), tripName)
        .input('title', sql.NVarChar(200), `💳 Settlement Request - ₹${formattedAmt}`)
        .input('message', sql.NVarChar(sql.MAX), `${fromName} recorded a settlement payment of ₹${formattedAmt} to ${toName} in "${tripName}". Tap to accept.`)
        .input('type', sql.NVarChar(50), 'SETTLEMENT_PROPOSAL')
        .input('amount', sql.Decimal(18, 2), parseFloat(amount))
        .query(`
          INSERT INTO Notifications (notification_id, user_id, trip_id, trip_name, title, message, type, amount, is_read, created_at)
          VALUES (@notifId, @userId, @tripId, @tripName, @title, @message, @type, @amount, 0, GETDATE())
        `);
    }

    return res.json({ success: true, message: 'Settlement proposal recorded. Pending approval!', settlementId });
  } catch (err) {
    console.error('settle-request error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 5. Accept Settlement Payment Request
router.post('/settle-accept', async (req, res) => {
  try {
    const { settlementId, userId } = req.body;
    const pool = await getPool();

    if (!settlementId) {
      return res.status(400).json({ success: false, message: 'Settlement ID required.' });
    }

    await pool.request()
      .input('settlementId', sql.NVarChar(100), settlementId)
      .query("UPDATE SettlementTransactions SET status = 'ACCEPTED', is_completed = 1 WHERE settlement_id = @settlementId");

    return res.json({ success: true, message: 'Settlement payment accepted!' });
  } catch (err) {
    console.error('settle-accept error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 6. Decline Settlement Payment Request
router.post('/settle-decline', async (req, res) => {
  try {
    const { settlementId } = req.body;
    const pool = await getPool();

    await pool.request()
      .input('settlementId', sql.NVarChar(100), settlementId)
      .query("DELETE FROM SettlementTransactions WHERE settlement_id = @settlementId AND status = 'PENDING'");

    return res.json({ success: true, message: 'Settlement payment declined.' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
