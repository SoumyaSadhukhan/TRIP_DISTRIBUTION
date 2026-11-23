SET NOCOUNT ON;
USE [SPLIT_BILL_DB_TEST];

PRINT '============================================================================';
PRINT 'DIAGNOSTIC REPORT: DATA CONFLICTS IN SPLIT_BILL_DB_TEST';
PRINT '============================================================================';

PRINT '--- 1. DUPLICATE PERSONS IN TRIP bf3cc27d-d1b8-448b-a65b-3a255d2a246c ---';
SELECT person_id, trip_id, name, phone_number, user_id, paid_amount, owed_amount, balance, created_at 
FROM Persons 
WHERE trip_id = 'bf3cc27d-d1b8-448b-a65b-3a255d2a246c' AND name = 'Soumya Sadhukhan';

PRINT '--- 2. DUPLICATE FRIEND CONNECTIONS ---';
SELECT connection_id, user_id, friend_user_id, friend_phone, friend_name, status, requester_id, receiver_id, created_at 
FROM FriendConnections 
WHERE user_id = '7ecc14fe-8797-4d93-a24b-96eeb9ef71fd' AND friend_user_id = '1e9915be-3e4c-46d0-8fce-ce19067eb02b';

PRINT '--- 3. ORPHAN EXPENSES IN TRIP 8092c57a-8638-4dc9-8969-748a9607d834 ---';
SELECT e.expense_id, e.trip_id, e.description, e.amount, e.paid_by_person_id, e.split_type, e.created_at,
       CASE WHEN p.person_id IS NULL THEN 'ORPHAN (Person does not exist)' ELSE p.name END AS PersonStatus
FROM Expenses e
LEFT JOIN Persons p ON e.paid_by_person_id = p.person_id
WHERE e.trip_id = '8092c57a-8638-4dc9-8969-748a9607d834';

PRINT '--- 4. INCOMPLETE EXPENSE SPLITS IN TRIP 8092c57a-8638-4dc9-8969-748a9607d834 ---';
SELECT e.expense_id, e.description, e.amount AS ExpenseAmount, 
       ISNULL(SUM(es.amount), 0) AS TotalSplitsSum,
       e.amount - ISNULL(SUM(es.amount), 0) AS MissingSplitAmount,
       COUNT(es.split_id) AS ExistingSplitRows
FROM Expenses e
LEFT JOIN ExpenseSplits es ON e.expense_id = es.expense_id
WHERE e.trip_id = '8092c57a-8638-4dc9-8969-748a9607d834'
GROUP BY e.expense_id, e.description, e.amount;

PRINT '--- 5. POLLUTED GOA VACATION 2026 TEST EXPENSES (9f9fb249-75aa-426b-8190-ac178ea5e0aa) ---';
SELECT e.expense_id, e.description, e.amount, e.paid_by_person_id, p.name AS PaidByName, e.created_at
FROM Expenses e
JOIN Persons p ON e.paid_by_person_id = p.person_id
WHERE e.trip_id = '9f9fb249-75aa-426b-8190-ac178ea5e0aa'
ORDER BY e.created_at;

PRINT 'Settlements in Goa Vacation 2026:';
SELECT settlement_id, from_person_id, to_person_id, amount, is_completed, status, settled_at
FROM SettlementTransactions
WHERE trip_id = '9f9fb249-75aa-426b-8190-ac178ea5e0aa'
ORDER BY settled_at;
