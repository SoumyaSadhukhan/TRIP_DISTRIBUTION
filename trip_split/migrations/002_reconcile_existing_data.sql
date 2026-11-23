-- ============================================================================
-- SCRIPT: 002_reconcile_existing_data.sql
-- TARGET: Pre-migration data reconciliation (Tested on SPLIT_BILL_DB_TEST)
-- PURPOSE: Resolve duplicate records, orphan records, and restore zero-sum balances
-- ============================================================================

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

PRINT '============================================================================';
PRINT 'STEP 1: CONSOLIDATE DUPLICATE PERSON IN TRIP bf3cc27d (Sonagachi)';
PRINT '============================================================================';
-- Person 13dd5762 was created after 145a5e1b, has 0 transactions, 0 splits, 0 balance
DELETE FROM Persons 
WHERE person_id = '13dd5762-1d8c-4899-a264-38ddcc481369' 
  AND trip_id = 'bf3cc27d-d1b8-448b-a65b-3a255d2a246c';
PRINT 'Removed duplicate Person 13dd5762. Retained Person 145a5e1b.';

-- Verification:
SELECT 'Duplicate Persons in Sonagachi' AS CheckName, COUNT(*) AS DuplicateCount 
FROM Persons 
WHERE trip_id = 'bf3cc27d-d1b8-448b-a65b-3a255d2a246c' AND name = 'Soumya Sadhukhan'
HAVING COUNT(*) > 1;

PRINT '============================================================================';
PRINT 'STEP 2: REMOVE DUPLICATE FRIEND CONNECTION (User 1 and User 2)';
PRINT '============================================================================';
-- Duplicate connection created at 22:49:05 vs original at 22:47:03
DELETE FROM FriendConnections 
WHERE connection_id = '14a28c69-5f02-49de-8fde-fc438ffac48c';
PRINT 'Removed duplicate FriendConnection 14a28c69. Retained 44f15b07.';

-- Verification:
SELECT 'Duplicate FriendConnections' AS CheckName, COUNT(*) AS DuplicateCount 
FROM FriendConnections 
WHERE user_id = '7ecc14fe-8797-4d93-a24b-96eeb9ef71fd' AND friend_user_id = '1e9915be-3e4c-46d0-8fce-ce19067eb02b'
HAVING COUNT(*) > 1;

PRINT '============================================================================';
PRINT 'STEP 3: RESTORE MISSING PERSONS IN TRIP 8092c57a (goa)';
PRINT '============================================================================';
IF NOT EXISTS (SELECT 1 FROM Persons WHERE person_id = 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12')
BEGIN
    INSERT INTO Persons (person_id, trip_id, name, phone_number, user_id, paid_amount, owed_amount, balance, created_at)
    VALUES ('cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12', '8092c57a-8638-4dc9-8969-748a9607d834', 'Friend', '+919999000010', NULL, 5000.00, 6006.67, -1006.67, '2026-11-17 11:45:23');
    PRINT 'Restored Person cf8806d1 (Friend).';
END;

IF NOT EXISTS (SELECT 1 FROM Persons WHERE person_id = '76810b14-585c-438e-a3ed-2150440a2985')
BEGIN
    INSERT INTO Persons (person_id, trip_id, name, phone_number, user_id, paid_amount, owed_amount, balance, created_at)
    VALUES ('76810b14-585c-438e-a3ed-2150440a2985', '8092c57a-8638-4dc9-8969-748a9607d834', 'Dipa MOndal', '+919999000007', '4f16ae4b-63e0-453a-9e35-27e6a754981a', 4520.00, 1506.67, 3013.33, '2026-11-18 00:52:53');
    PRINT 'Restored Person 76810b14 (Dipa MOndal).';
END;

PRINT '============================================================================';
PRINT 'STEP 4: RESTORE MISSING EXPENSE SPLITS IN TRIP 8092c57a (goa)';
PRINT '============================================================================';
-- Restore Food split for Friend (2000.00)
IF NOT EXISTS (SELECT 1 FROM ExpenseSplits WHERE expense_id = '7f28d135-2d7d-4369-8d36-b50b6e61e84a' AND person_id = 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12')
BEGIN
    INSERT INTO ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
    VALUES (NEWID(), '7f28d135-2d7d-4369-8d36-b50b6e61e84a', '8092c57a-8638-4dc9-8969-748a9607d834', 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12', 2000.00, '2026-11-17 11:45:43');
    PRINT 'Restored Food split for Friend (2000.00).';
END;

-- Restore Room split for Friend (2500.00)
IF NOT EXISTS (SELECT 1 FROM ExpenseSplits WHERE expense_id = '79d4d8ad-0df4-4896-a863-b18fe1a0919f' AND person_id = 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12')
BEGIN
    INSERT INTO ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
    VALUES (NEWID(), '79d4d8ad-0df4-4896-a863-b18fe1a0919f', '8092c57a-8638-4dc9-8969-748a9607d834', 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12', 2500.00, '2026-11-17 11:46:01');
    PRINT 'Restored Room split for Friend (2500.00).';
END;

-- Restore Car splits for Friend (1506.67) and Dipa MOndal (1506.67)
IF NOT EXISTS (SELECT 1 FROM ExpenseSplits WHERE expense_id = 'c4dab9a5-cd80-407f-8b1e-55f849328446' AND person_id = 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12')
BEGIN
    INSERT INTO ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
    VALUES (NEWID(), 'c4dab9a5-cd80-407f-8b1e-55f849328446', '8092c57a-8638-4dc9-8969-748a9607d834', 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12', 1506.67, '2026-11-18 00:53:30');
    PRINT 'Restored Car split for Friend (1506.67).';
END;

IF NOT EXISTS (SELECT 1 FROM ExpenseSplits WHERE expense_id = 'c4dab9a5-cd80-407f-8b1e-55f849328446' AND person_id = '76810b14-585c-438e-a3ed-2150440a2985')
BEGIN
    INSERT INTO ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
    VALUES (NEWID(), 'c4dab9a5-cd80-407f-8b1e-55f849328446', '8092c57a-8638-4dc9-8969-748a9607d834', '76810b14-585c-438e-a3ed-2150440a2985', 1506.67, '2026-11-18 00:53:30');
    PRINT 'Restored Car split for Dipa MOndal (1506.67).';
END;

-- Verification of Goa Trip Splits & Balances:
SELECT e.expense_id, e.description, e.amount, ISNULL(SUM(es.amount), 0) AS TotalSplits,
       e.amount - ISNULL(SUM(es.amount), 0) AS Difference
FROM Expenses e
LEFT JOIN ExpenseSplits es ON e.expense_id = es.expense_id
WHERE e.trip_id = '8092c57a-8638-4dc9-8969-748a9607d834'
GROUP BY e.expense_id, e.description, e.amount;

PRINT '============================================================================';
PRINT 'STEP 5: REMOVE POLLUTED DUPLICATE TEST EXPENSES IN GOA VACATION 2026';
PRINT '============================================================================';
-- Duplicate expenses inserted by test runs on Nov 20 22:48
DELETE FROM ExpenseSplits WHERE expense_id IN ('a34cb5fb-3a65-4407-b1f2-daccdfc69366', '1609f0d5-a016-45b1-a2fa-222669cb5ec6');
DELETE FROM Expenses WHERE expense_id IN ('a34cb5fb-3a65-4407-b1f2-daccdfc69366', '1609f0d5-a016-45b1-a2fa-222669cb5ec6');
PRINT 'Deleted duplicate test expenses a34cb5fb and 1609f0d5.';

-- Reset Goa Vacation 2026 balances to zero (fully reconciled with its existing settlements)
UPDATE Persons SET paid_amount = 3000.00, owed_amount = 1000.00, balance = 0.00 WHERE person_id = '9ceea718-fe0e-4957-957a-2ee9d802f1d1'; -- User 1
UPDATE Persons SET paid_amount = 1500.00, owed_amount = 750.00, balance = 0.00 WHERE person_id = '7d8a73a9-7bff-46d7-b4c6-359df8ef4a4b'; -- User 2
UPDATE Persons SET paid_amount = 0.00, owed_amount = 1750.00, balance = 0.00 WHERE person_id = '94508c11-4edc-4063-9146-3978b6f1890a'; -- User 3

-- Final Verification across all trips:
PRINT '============================================================================';
PRINT 'FINAL RECONCILIATION VERIFICATION ACROSS ALL TRIPS';
PRINT '============================================================================';
SELECT 
    t.trip_id,
    t.name AS TripName,
    COUNT(DISTINCT p.person_id) AS MemberCount,
    COUNT(DISTINCT e.expense_id) AS ExpenseCount,
    ISNULL(SUM(p.balance), 0) AS NetPersonsBalanceSum
FROM Trips t
LEFT JOIN Persons p ON t.trip_id = p.trip_id
LEFT JOIN Expenses e ON t.trip_id = e.trip_id
GROUP BY t.trip_id, t.name;
