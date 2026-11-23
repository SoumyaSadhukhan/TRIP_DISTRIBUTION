SET NOCOUNT ON;

PRINT '=== 1. COLUMN DEFINITIONS ===';
SELECT 
    t.name AS TableName,
    c.name AS ColumnName,
    ty.name AS DataType,
    c.max_length AS MaxLength,
    c.is_nullable AS IsNullable,
    ISNULL(dc.definition, 'NONE') AS DefaultDefinition
FROM sys.tables t
JOIN sys.columns c ON t.object_id = c.object_id
JOIN sys.types ty ON c.user_type_id = ty.user_type_id
LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
ORDER BY t.name, c.column_id;

PRINT '=== 2. NULL VALUES IN IMPORTANT COLUMNS ===';
SELECT 'Users.phone_number' AS Col, COUNT(*) AS NullCount FROM Users WHERE phone_number IS NULL
UNION ALL
SELECT 'Users.email', COUNT(*) FROM Users WHERE email IS NULL
UNION ALL
SELECT 'Trips.user_id', COUNT(*) FROM Trips WHERE user_id IS NULL
UNION ALL
SELECT 'Persons.trip_id', COUNT(*) FROM Persons WHERE trip_id IS NULL
UNION ALL
SELECT 'Persons.user_id', COUNT(*) FROM Persons WHERE user_id IS NULL
UNION ALL
SELECT 'Persons.phone_number', COUNT(*) FROM Persons WHERE phone_number IS NULL
UNION ALL
SELECT 'Expenses.trip_id', COUNT(*) FROM Expenses WHERE trip_id IS NULL
UNION ALL
SELECT 'Expenses.paid_by_person_id', COUNT(*) FROM Expenses WHERE paid_by_person_id IS NULL
UNION ALL
SELECT 'ExpenseSplits.expense_id', COUNT(*) FROM ExpenseSplits WHERE expense_id IS NULL
UNION ALL
SELECT 'ExpenseSplits.person_id', COUNT(*) FROM ExpenseSplits WHERE person_id IS NULL
UNION ALL
SELECT 'SettlementTransactions.trip_id', COUNT(*) FROM SettlementTransactions WHERE trip_id IS NULL
UNION ALL
SELECT 'SettlementTransactions.from_person_id', COUNT(*) FROM SettlementTransactions WHERE from_person_id IS NULL
UNION ALL
SELECT 'SettlementTransactions.to_person_id', COUNT(*) FROM SettlementTransactions WHERE to_person_id IS NULL
UNION ALL
SELECT 'TripCollaborators.trip_id', COUNT(*) FROM TripCollaborators WHERE trip_id IS NULL
UNION ALL
SELECT 'TripCollaborators.user_id', COUNT(*) FROM TripCollaborators WHERE user_id IS NULL
UNION ALL
SELECT 'FriendConnections.user_id', COUNT(*) FROM FriendConnections WHERE user_id IS NULL
UNION ALL
SELECT 'FriendConnections.friend_user_id', COUNT(*) FROM FriendConnections WHERE friend_user_id IS NULL;

PRINT '=== 3. DUPLICATE RECORDS INVESTIGATION ===';
PRINT '-- Duplicate Users (by phone)';
SELECT phone_number, COUNT(*) AS DuplicateCount FROM Users GROUP BY phone_number HAVING COUNT(*) > 1;

PRINT '-- Duplicate Users (by email, non-null)';
SELECT email, COUNT(*) AS DuplicateCount FROM Users WHERE email IS NOT NULL AND email <> '' GROUP BY email HAVING COUNT(*) > 1;

PRINT '-- Duplicate Persons within same trip (by phone)';
SELECT trip_id, phone_number, COUNT(*) AS DuplicateCount FROM Persons WHERE phone_number IS NOT NULL GROUP BY trip_id, phone_number HAVING COUNT(*) > 1;

PRINT '-- Duplicate Persons within same trip (by name)';
SELECT trip_id, name, COUNT(*) AS DuplicateCount FROM Persons GROUP BY trip_id, name HAVING COUNT(*) > 1;

PRINT '-- Duplicate TripCollaborators (same trip + user)';
SELECT trip_id, user_id, COUNT(*) AS DuplicateCount FROM TripCollaborators WHERE user_id IS NOT NULL GROUP BY trip_id, user_id HAVING COUNT(*) > 1;

PRINT '-- Duplicate FriendConnections (same pair)';
SELECT user_id, friend_user_id, COUNT(*) AS DuplicateCount FROM FriendConnections GROUP BY user_id, friend_user_id HAVING COUNT(*) > 1;

PRINT '-- Duplicate ExpenseSplits (same expense + person)';
SELECT expense_id, person_id, COUNT(*) AS DuplicateCount FROM ExpenseSplits GROUP BY expense_id, person_id HAVING COUNT(*) > 1;

PRINT '=== 4. ORPHAN RECORDS INVESTIGATION ===';
PRINT '-- Orphan Persons (trip_id not in Trips)';
SELECT p.person_id, p.name, p.trip_id FROM Persons p LEFT JOIN Trips t ON p.trip_id = t.trip_id WHERE t.trip_id IS NULL;

PRINT '-- Persons with invalid user_id (not in Users)';
SELECT p.person_id, p.name, p.user_id FROM Persons p LEFT JOIN Users u ON p.user_id = u.user_id WHERE p.user_id IS NOT NULL AND u.user_id IS NULL;

PRINT '-- Orphan Expenses (trip_id not in Trips)';
SELECT e.expense_id, e.description, e.amount, e.trip_id FROM Expenses e LEFT JOIN Trips t ON e.trip_id = t.trip_id WHERE t.trip_id IS NULL;

PRINT '-- Orphan Expenses (paid_by_person_id not in Persons)';
SELECT e.expense_id, e.description, e.amount, e.paid_by_person_id, e.trip_id FROM Expenses e LEFT JOIN Persons p ON e.paid_by_person_id = p.person_id WHERE p.person_id IS NULL;

PRINT '-- Orphan ExpenseSplits (expense_id not in Expenses)';
SELECT s.split_id, s.expense_id, s.person_id FROM ExpenseSplits s LEFT JOIN Expenses e ON s.expense_id = e.expense_id WHERE e.expense_id IS NULL;

PRINT '-- Orphan ExpenseSplits (person_id not in Persons)';
SELECT s.split_id, s.expense_id, s.person_id, s.amount FROM ExpenseSplits s LEFT JOIN Persons p ON s.person_id = p.person_id WHERE p.person_id IS NULL;

PRINT '-- Orphan SettlementTransactions (trip_id not in Trips)';
SELECT st.settlement_id, st.trip_id FROM SettlementTransactions st LEFT JOIN Trips t ON st.trip_id = t.trip_id WHERE t.trip_id IS NULL;

PRINT '-- Orphan SettlementTransactions (from_person_id not in Persons)';
SELECT st.settlement_id, st.from_person_id FROM SettlementTransactions st LEFT JOIN Persons p ON st.from_person_id = p.person_id WHERE p.person_id IS NULL;

PRINT '-- Orphan SettlementTransactions (to_person_id not in Persons)';
SELECT st.settlement_id, st.to_person_id FROM SettlementTransactions st LEFT JOIN Persons p ON st.to_person_id = p.person_id WHERE p.person_id IS NULL;

PRINT '-- Orphan TripCollaborators (trip_id not in Trips)';
SELECT tc.collab_id, tc.trip_id FROM TripCollaborators tc LEFT JOIN Trips t ON tc.trip_id = t.trip_id WHERE t.trip_id IS NULL;

PRINT '-- Orphan TripCollaborators (user_id not in Users)';
SELECT tc.collab_id, tc.user_id FROM TripCollaborators tc LEFT JOIN Users u ON tc.user_id = u.user_id WHERE tc.user_id IS NOT NULL AND u.user_id IS NULL;

PRINT '-- Orphan FriendConnections (user_id or friend_user_id not in Users)';
SELECT fc.connection_id, fc.user_id, fc.friend_user_id FROM FriendConnections fc 
LEFT JOIN Users u1 ON fc.user_id = u1.user_id 
LEFT JOIN Users u2 ON fc.friend_user_id = u2.user_id 
WHERE u1.user_id IS NULL OR u2.user_id IS NULL;

PRINT '-- Orphan Notifications (user_id not in Users)';
SELECT n.notification_id, n.user_id FROM Notifications n LEFT JOIN Users u ON n.user_id = u.user_id WHERE u.user_id IS NULL;

PRINT '-- Orphan UserTokens (user_id not in Users)';
SELECT ut.token_id, ut.user_id FROM UserTokens ut LEFT JOIN Users u ON ut.user_id = u.user_id WHERE u.user_id IS NULL;
