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

    const numericAmount = parseFloat(amount);
    if (isNaN(numericAmount) || numericAmount <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid settlement amount.' });
    }

    const settlementId = uuidv4();
    await pool.request()
      .input('settlementId', sql.NVarChar(100), settlementId)
      .input('tripId', sql.NVarChar(100), tripId)
      .input('fromPersonId', sql.NVarChar(100), fromPersonId)
      .input('toPersonId', sql.NVarChar(100), toPersonId)
      .input('amount', sql.Decimal(18, 2), numericAmount)
      .input('createdByUserId', sql.NVarChar(100), createdByUserId || '')
      .query(`
        INSERT INTO SettlementTransactions (settlement_id, trip_id, from_person_id, to_person_id, amount, is_completed, status, created_by_user_id, settled_at)
        VALUES (@settlementId, @tripId, @fromPersonId, @toPersonId, @amount, 0, 'PENDING', @createdByUserId, GETDATE())
      `);

    // Lookup persons & trip name for rich notification
    const personRes = await pool.request()
      .input('fromId', sql.NVarChar(100), fromPersonId)
      .input('toId', sql.NVarChar(100), toPersonId)
      .query('SELECT person_id, name, user_id, phone_number FROM Persons WHERE person_id IN (@fromId, @toId)');

    const tripRes = await pool.request()
      .input('tripId', sql.NVarChar(100), tripId)
      .query('SELECT name FROM Trips WHERE trip_id = @tripId');

    const tripName = tripRes.recordset.length > 0 ? tripRes.recordset[0].name : 'Trip';
    const fromP = personRes.recordset.find(p => p.person_id === fromPersonId);
    const toP = personRes.recordset.find(p => p.person_id === toPersonId);
    const fromName = fromP ? fromP.name : 'Member';
    const toName = toP ? toP.name : 'Member';

    // Target user to notify (the other party in the transaction)
    let targetUserId = (fromP && fromP.user_id && fromP.user_id !== createdByUserId) 
      ? fromP.user_id 
      : (toP && toP.user_id && toP.user_id !== createdByUserId ? toP.user_id : null);

    // If targetUserId is null, lookup user in Users table by phone number
    if (!targetUserId) {
      const candidatePhone = (fromP && fromP.user_id !== createdByUserId && fromP.phone_number) 
        ? fromP.phone_number 
        : (toP && toP.phone_number ? toP.phone_number : null);

      if (candidatePhone) {
        const cleanPhone = candidatePhone.replace(/[^0-9]/g, '');
        if (cleanPhone.length >= 10) {
          const last10 = cleanPhone.slice(-10);
          const userLookup = await pool.request()
            .input('phone', sql.NVarChar(50), `%${last10}%`)
            .query('SELECT TOP 1 user_id FROM Users WHERE phone_number LIKE @phone');
          if (userLookup.recordset.length > 0) {
            targetUserId = userLookup.recordset[0].user_id;
          }
        }
      }
    }

    if (targetUserId) {
      const notifId = uuidv4();
      const formattedAmt = numericAmount.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      const isCreatorPayer = fromP && fromP.user_id === createdByUserId;
      const title = isCreatorPayer 
        ? `💳 Settlement Statement - ₹${formattedAmt}`
        : `🔔 Payment Request Statement - ₹${formattedAmt}`;
      const message = isCreatorPayer
        ? `${fromName} sent a settlement statement of ₹${formattedAmt} for "${tripName}". Tap to view statement, pay, or edit amount.`
        : `${fromName} sent a payment request statement for ₹${formattedAmt} for "${tripName}". Tap to view statement, pay, or edit amount.`;

      await pool.request()
        .input('notifId', sql.NVarChar(100), notifId)
        .input('userId', sql.NVarChar(100), targetUserId)
        .input('tripId', sql.NVarChar(100), tripId)
        .input('tripName', sql.NVarChar(200), tripName)
        .input('settlementId', sql.NVarChar(100), settlementId)
        .input('title', sql.NVarChar(200), title)
        .input('message', sql.NVarChar(sql.MAX), message)
        .input('type', sql.NVarChar(50), 'SETTLEMENT_PROPOSAL')
        .input('amount', sql.Decimal(18, 2), numericAmount)
        .query(`
          INSERT INTO Notifications (notification_id, user_id, trip_id, trip_name, settlement_id, title, message, type, amount, is_read, created_at)
          VALUES (@notifId, @userId, @tripId, @tripName, @settlementId, @title, @message, @type, @amount, 0, GETDATE())
        `);
    }

    return res.json({ success: true, message: 'Settlement statement recorded and sent. Pending approval!', settlementId });
  } catch (err) {
    console.error('settle-request error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 4b. Edit / Update Settlement Amount (reflects on BOTH users' settlement transaction)
router.post('/settle-update', async (req, res) => {
  try {
    const { settlementId, amount, userId } = req.body;
    const pool = await getPool();

    if (!settlementId || amount === undefined || amount === null) {
      return res.status(400).json({ success: false, message: 'Settlement ID and new amount are required.' });
    }

    const newAmount = parseFloat(amount);
    if (isNaN(newAmount) || newAmount <= 0) {
      return res.status(400).json({ success: false, message: 'Amount must be a positive number.' });
    }

    // 1. Fetch existing settlement transaction
    const transRes = await pool.request()
      .input('settlementId', sql.NVarChar(100), settlementId)
      .query(`
        SELECT st.*, ISNULL(t.name, 'Trip') as trip_name
        FROM SettlementTransactions st
        LEFT JOIN Trips t ON st.trip_id = t.trip_id
        WHERE st.settlement_id = @settlementId
      `);

    if (transRes.recordset.length === 0) {
      return res.status(404).json({ success: false, message: 'Settlement transaction not found.' });
    }

    const transaction = transRes.recordset[0];
    const oldAmount = parseFloat(transaction.amount || 0);

    // 2. Update settlement transaction amount
    await pool.request()
      .input('settlementId', sql.NVarChar(100), settlementId)
      .input('amount', sql.Decimal(18, 2), newAmount)
      .query(`
        UPDATE SettlementTransactions
        SET amount = @amount, settled_at = GETDATE()
        WHERE settlement_id = @settlementId
      `);

    // 3. Lookup persons & user who made the edit
    const personRes = await pool.request()
      .input('fromId', sql.NVarChar(100), transaction.from_person_id)
      .input('toId', sql.NVarChar(100), transaction.to_person_id)
      .query('SELECT person_id, name, user_id, phone_number FROM Persons WHERE person_id IN (@fromId, @toId)');

    const fromP = personRes.recordset.find(p => p.person_id === transaction.from_person_id);
    const toP = personRes.recordset.find(p => p.person_id === transaction.to_person_id);
    const fromName = fromP ? fromP.name : 'Member';
    const toName = toP ? toP.name : 'Member';
    const tripName = transaction.trip_name || 'Trip';

    // Identify updater and target user to notify
    let updaterName = 'Member';
    let targetUserId = null;

    if (userId) {
      if (fromP && fromP.user_id === userId) {
        updaterName = fromP.name;
        targetUserId = toP ? toP.user_id : null;
      } else if (toP && toP.user_id === userId) {
        updaterName = toP.name;
        targetUserId = fromP ? fromP.user_id : null;
      } else {
        targetUserId = (transaction.created_by_user_id === userId)
          ? (toP && toP.user_id !== userId ? toP.user_id : (fromP ? fromP.user_id : null))
          : transaction.created_by_user_id;
      }
    } else {
      targetUserId = toP ? toP.user_id : null;
    }

    const formattedAmt = newAmount.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

    // 4. Update existing notifications with new amount
    await pool.request()
      .input('settlementId', sql.NVarChar(100), settlementId)
      .input('amount', sql.Decimal(18, 2), newAmount)
      .input('title', sql.NVarChar(200), `✏️ Revised Statement - ₹${formattedAmt}`)
      .input('message', sql.NVarChar(sql.MAX), `${updaterName} updated settlement statement to ₹${formattedAmt} for "${tripName}". Tap to view statement & pay/confirm.`)
      .query(`
        UPDATE Notifications
        SET amount = @amount, title = @title, message = @message
        WHERE settlement_id = @settlementId AND is_read = 0
      `);

    // 5. Insert notification for target user
    if (targetUserId && targetUserId !== userId) {
      const notifId = uuidv4();
      await pool.request()
        .input('notifId', sql.NVarChar(100), notifId)
        .input('userId', sql.NVarChar(100), targetUserId)
        .input('tripId', sql.NVarChar(100), transaction.trip_id)
        .input('tripName', sql.NVarChar(200), tripName)
        .input('settlementId', sql.NVarChar(100), settlementId)
        .input('title', sql.NVarChar(200), `✏️ Statement Amount Updated: ₹${formattedAmt}`)
        .input('message', sql.NVarChar(sql.MAX), `${updaterName} changed the settlement statement amount to ₹${formattedAmt}. Tap to view statement & pay.`)
        .input('type', sql.NVarChar(50), 'SETTLEMENT_PROPOSAL')
        .input('amount', sql.Decimal(18, 2), newAmount)
        .query(`
          INSERT INTO Notifications (notification_id, user_id, trip_id, trip_name, settlement_id, title, message, type, amount, is_read, created_at)
          VALUES (@notifId, @userId, @tripId, @tripName, @settlementId, @title, @message, @type, @amount, 0, GETDATE())
        `);
    }

    return res.json({
      success: true,
      message: `Settlement statement amount updated to ₹${formattedAmt}!`,
      settlementId,
      newAmount,
    });
  } catch (err) {
    console.error('settle-update error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 5. Get Pending Settlement Requests for User
router.get('/pending-settlements', async (req, res) => {
  try {
    const userId = req.query.userId || (req.user && req.user.user_id);
    const phone = req.query.phone || (req.user && req.user.phone_number);

    if (!userId && !phone) {
      return res.status(400).json({ success: false, message: 'User ID or phone number required.' });
    }

    const pool = await getPool();
    const cleanPhone = phone ? phone.replace(/[^0-9]/g, '').slice(-10) : '';

    const query = `
      SELECT 
        st.settlement_id,
        st.trip_id,
        ISNULL(t.name, 'Trip') as trip_name,
        st.from_person_id,
        ISNULL(fp.name, 'Member') as from_person_name,
        fp.user_id as from_user_id,
        fp.phone_number as from_phone,
        st.to_person_id,
        ISNULL(tp.name, 'Member') as to_person_name,
        tp.user_id as to_user_id,
        tp.phone_number as to_phone,
        st.amount,
        st.status,
        st.created_by_user_id,
        st.settled_at
      FROM SettlementTransactions st
      LEFT JOIN Trips t ON st.trip_id = t.trip_id
      LEFT JOIN Persons fp ON st.from_person_id = fp.person_id
      LEFT JOIN Persons tp ON st.to_person_id = tp.person_id
      WHERE st.status = 'PENDING'
        AND (
          fp.user_id = @userId 
          OR tp.user_id = @userId
          ${cleanPhone ? "OR fp.phone_number LIKE @phonePattern OR tp.phone_number LIKE @phonePattern" : ""}
          OR st.created_by_user_id = @userId
        )
      ORDER BY st.settled_at DESC
    `;

    const request = pool.request().input('userId', sql.NVarChar(100), userId || '');
    if (cleanPhone) {
      request.input('phonePattern', sql.NVarChar(50), `%${cleanPhone}%`);
    }

    const result = await request.query(query);
    const settlements = result.recordset.map(r => ({
      settlementId: r.settlement_id,
      tripId: r.trip_id,
      tripName: r.trip_name,
      fromPersonId: r.from_person_id,
      fromPersonName: r.from_person_name,
      fromPhone: r.from_phone,
      toPersonId: r.to_person_id,
      toPersonName: r.to_person_name,
      toPhone: r.to_phone,
      amount: parseFloat(r.amount || 0),
      status: r.status,
      createdByUserId: r.created_by_user_id,
      settledAt: r.settled_at ? new Date(r.settled_at).toISOString() : new Date().toISOString(),
      isPayer: (r.from_user_id === userId) || (cleanPhone && r.from_phone && r.from_phone.includes(cleanPhone)),
      isPayee: (r.to_user_id === userId) || (cleanPhone && r.to_phone && r.to_phone.includes(cleanPhone)),
    }));

    return res.json({ success: true, settlements });
  } catch (err) {
    console.error('pending-settlements error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 6. Accept Settlement Payment Request
router.post('/settle-accept', async (req, res) => {
  try {
    const { settlementId, userId } = req.body;
    const pool = await getPool();

    if (!settlementId) {
      return res.status(400).json({ success: false, message: 'Settlement ID required.' });
    }

    const updateRes = await pool.request()
      .input('settlementId', sql.NVarChar(100), settlementId)
      .query(`
        UPDATE SettlementTransactions 
        SET status = 'ACCEPTED', is_completed = 1, settled_at = GETDATE()
        OUTPUT inserted.trip_id, inserted.from_person_id, inserted.to_person_id, inserted.amount, inserted.created_by_user_id
        WHERE settlement_id = @settlementId
      `);

    if (updateRes.recordset.length > 0) {
      const record = updateRes.recordset[0];
      const tripId = record.trip_id;
      const amount = parseFloat(record.amount || 0);
      const createdByUserId = record.created_by_user_id;
      const fromPersonId = record.from_person_id;
      const toPersonId = record.to_person_id;

      // Lookup persons
      const personRes = await pool.request()
        .input('fromId', sql.NVarChar(100), fromPersonId)
        .input('toId', sql.NVarChar(100), toPersonId)
        .query('SELECT person_id, name, user_id FROM Persons WHERE person_id IN (@fromId, @toId)');

      const fromP = personRes.recordset.find(p => p.person_id === fromPersonId);
      const toP = personRes.recordset.find(p => p.person_id === toPersonId);
      const fromName = fromP ? fromP.name : 'Member';
      const toName = toP ? toP.name : 'Member';

      // Record settlement payment into Expenses & ExpenseSplits to update balances in DB
      try {
        const expenseId = uuidv4();
        const splitId = uuidv4();
        const expenseDesc = `Settlement: ${fromName} paid ${toName}`;

        await pool.request()
          .input('expenseId', sql.NVarChar(100), expenseId)
          .input('tripId', sql.NVarChar(100), tripId)
          .input('description', sql.NVarChar(500), expenseDesc)
          .input('amount', sql.Decimal(18, 2), amount)
          .input('categoryIndex', sql.Int, 5)
          .input('categoryName', sql.NVarChar(100), 'Settlement Payment')
          .input('paidByPersonId', sql.NVarChar(100), fromPersonId)
          .query(`
            INSERT INTO Expenses (expense_id, trip_id, description, amount, category_index, category_name, paid_by_person_id, expense_date, created_at)
            VALUES (@expenseId, @tripId, @description, @amount, @categoryIndex, @categoryName, @paidByPersonId, GETDATE(), GETDATE())
          `);

        await pool.request()
          .input('splitId', sql.NVarChar(100), splitId)
          .input('expenseId', sql.NVarChar(100), expenseId)
          .input('tripId', sql.NVarChar(100), tripId)
          .input('personId', sql.NVarChar(100), toPersonId)
          .input('amount', sql.Decimal(18, 2), amount)
          .query(`
            INSERT INTO ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
            VALUES (@splitId, @expenseId, @tripId, @personId, @amount, GETDATE())
          `);
      } catch (expErr) {
        console.warn('Settlement expense auto-recording note:', expErr);
      }

      // Mark related settlement notifications as read
      await pool.request()
        .input('settlementId', sql.NVarChar(100), settlementId)
        .input('tripId', sql.NVarChar(100), tripId)
        .query(`
          UPDATE Notifications 
          SET is_read = 1 
          WHERE settlement_id = @settlementId OR (trip_id = @tripId AND type = 'SETTLEMENT_PROPOSAL')
        `);

      // Notify the requester / counterparty that the payment was accepted/settled
      const targetNotifyUserId = (createdByUserId && createdByUserId !== userId)
        ? createdByUserId
        : (toP && toP.user_id !== userId ? toP.user_id : (fromP && fromP.user_id !== userId ? fromP.user_id : null));

      if (targetNotifyUserId) {
        const notifId = uuidv4();
        const formattedAmt = amount.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
        await pool.request()
          .input('notifId', sql.NVarChar(100), notifId)
          .input('userId', sql.NVarChar(100), targetNotifyUserId)
          .input('tripId', sql.NVarChar(100), tripId)
          .input('tripName', sql.NVarChar(200), 'Trip Settlement')
          .input('settlementId', sql.NVarChar(100), settlementId)
          .input('title', sql.NVarChar(200), `✅ Settlement Confirmed - ₹${formattedAmt}`)
          .input('message', sql.NVarChar(sql.MAX), `Settlement statement of ₹${formattedAmt} between ${fromName} and ${toName} is confirmed & settled! Balances updated.`)
          .input('type', sql.NVarChar(50), 'SETTLEMENT_ACCEPTED')
          .input('amount', sql.Decimal(18, 2), amount)
          .query(`
            INSERT INTO Notifications (notification_id, user_id, trip_id, trip_name, settlement_id, title, message, type, amount, is_read, created_at)
            VALUES (@notifId, @userId, @tripId, @tripName, @settlementId, @title, @message, @type, @amount, 0, GETDATE())
          `);
      }
    }

    return res.json({ success: true, message: 'Settlement payment accepted and recorded!' });
  } catch (err) {
    console.error('settle-accept error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// 7. Decline Settlement Payment Request
router.post('/settle-decline', async (req, res) => {
  try {
    const { settlementId, userId } = req.body;
    const pool = await getPool();

    if (!settlementId) {
      return res.status(400).json({ success: false, message: 'Settlement ID required.' });
    }

    const updateRes = await pool.request()
      .input('settlementId', sql.NVarChar(100), settlementId)
      .query(`
        UPDATE SettlementTransactions 
        SET status = 'DECLINED', is_completed = 0 
        OUTPUT inserted.trip_id, inserted.amount, inserted.created_by_user_id
        WHERE settlement_id = @settlementId
      `);

    if (updateRes.recordset.length > 0) {
      const record = updateRes.recordset[0];
      const tripId = record.trip_id;
      const amount = parseFloat(record.amount || 0);
      const createdByUserId = record.created_by_user_id;

      // Mark related settlement notifications as read
      await pool.request()
        .input('settlementId', sql.NVarChar(100), settlementId)
        .input('tripId', sql.NVarChar(100), tripId)
        .query(`
          UPDATE Notifications 
          SET is_read = 1 
          WHERE settlement_id = @settlementId OR (trip_id = @tripId AND type = 'SETTLEMENT_PROPOSAL')
        `);

      // Notify the requester that the payment was declined
      if (createdByUserId && createdByUserId !== userId) {
        const notifId = uuidv4();
        const formattedAmt = amount.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
        await pool.request()
          .input('notifId', sql.NVarChar(100), notifId)
          .input('userId', sql.NVarChar(100), createdByUserId)
          .input('tripId', sql.NVarChar(100), tripId)
          .input('tripName', sql.NVarChar(200), 'Trip Settlement')
          .input('settlementId', sql.NVarChar(100), settlementId)
          .input('title', sql.NVarChar(200), `❌ Settlement Declined - ₹${formattedAmt}`)
          .input('message', sql.NVarChar(sql.MAX), `Settlement request of ₹${formattedAmt} was declined by the member.`)
          .input('type', sql.NVarChar(50), 'SETTLEMENT_DECLINED')
          .input('amount', sql.Decimal(18, 2), amount)
          .query(`
            INSERT INTO Notifications (notification_id, user_id, trip_id, trip_name, settlement_id, title, message, type, amount, is_read, created_at)
            VALUES (@notifId, @userId, @tripId, @tripName, @settlementId, @title, @message, @type, @amount, 0, GETDATE())
          `);
      }
    }

    return res.json({ success: true, message: 'Settlement payment declined.' });
  } catch (err) {
    console.error('settle-decline error:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;


