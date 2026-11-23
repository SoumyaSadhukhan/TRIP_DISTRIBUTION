SET NOCOUNT ON;
USE [SPLIT_BILL_DB_TEST];

PRINT '=== 1. CONSOLIDATE DUPLICATE PERSON IN SONAGACHI TRIP ===';
-- Delete duplicate Person 13dd5762-1d8c-4899-a264-38ddcc481369 (created later, zero transactions)
DELETE FROM Persons 
WHERE person_id = '13dd5762-1d8c-4899-a264-38ddcc481369' 
  AND trip_id = 'bf3cc27d-d1b8-448b-a65b-3a255d2a246c';
PRINT 'Removed duplicate person 13dd5762. Retained 145a5e1b.';

PRINT '=== 2. REMOVE DUPLICATE FRIEND CONNECTION ===';
-- Delete duplicate connection 14a28c69-5f02-49de-8fde-fc438ffac48c (created at 22:49:05)
DELETE FROM FriendConnections 
WHERE connection_id = '14a28c69-5f02-49de-8fde-fc438ffac48c';
PRINT 'Removed duplicate FriendConnection 14a28c69. Retained 44f15b07.';

PRINT '=== 3. RESTORE MISSING PERSONS IN GOA TRIP (8092c57a) ===';
-- Reconstruct the missing persons referenced by Expenses
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

PRINT '=== 4. RESTORE MISSING SPLITS IN GOA TRIP (8092c57a) ===';
-- Split for Food (4000 total: 2000 for Soumya already exists; add 2000 for Friend)
IF NOT EXISTS (SELECT 1 FROM ExpenseSplits WHERE expense_id = '7f28d135-2d7d-4369-8d36-b50b6e61e84a' AND person_id = 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12')
BEGIN
    INSERT INTO ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
    VALUES (NEWID(), '7f28d135-2d7d-4369-8d36-b50b6e61e84a', '8092c57a-8638-4dc9-8969-748a9607d834', 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12', 2000.00, '2026-11-17 11:45:43');
    PRINT 'Restored Food split for Friend (2000.00).';
END;

-- Split for Room (5000 total: 2500 for Soumya already exists; add 2500 for Friend)
IF NOT EXISTS (SELECT 1 FROM ExpenseSplits WHERE expense_id = '79d4d8ad-0df4-4896-a863-b18fe1a0919f' AND person_id = 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12')
BEGIN
    INSERT INTO ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
    VALUES (NEWID(), '79d4d8ad-0df4-4896-a863-b18fe1a0919f', '8092c57a-8638-4dc9-8969-748a9607d834', 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12', 2500.00, '2026-11-17 11:46:01');
    PRINT 'Restored Room split for Friend (2500.00).';
END;

-- Splits for Car (4520 total: 1506.66 for Soumya already exists; add 1506.67 for Friend and 1506.67 for Dipa)
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

PRINT '=== 5. CLEAN POLLUTED DUPLICATE TEST EXPENSES IN GOA VACATION 2026 ===';
-- Delete duplicate expenses a34cb5fb and 1609f0d5 (inserted Nov 20 22:48 by tests)
DELETE FROM ExpenseSplits WHERE expense_id IN ('a34cb5fb-3a65-4407-b1f2-daccdfc69366', '1609f0d5-a016-45b1-a2fa-222669cb5ec6');
DELETE FROM Expenses WHERE expense_id IN ('a34cb5fb-3a65-4407-b1f2-daccdfc69366', '1609f0d5-a016-45b1-a2fa-222669cb5ec6');
PRINT 'Cleaned duplicate test expenses from Goa Vacation 2026.';

-- Reset Goa Vacation 2026 balances to zero (matching its existing settlements)
UPDATE Persons SET paid_amount = 3000.00, owed_amount = 1000.00, balance = 0.00 WHERE person_id = '9ceea718-fe0e-4957-957a-2ee9d802f1d1'; -- User 1
UPDATE Persons SET paid_amount = 1500.00, owed_amount = 750.00, balance = 0.00 WHERE person_id = '7d8a73a9-7bff-46d7-b4c6-359df8ef4a4b'; -- User 2
UPDATE Persons SET paid_amount = 0.00, owed_amount = 1750.00, balance = 0.00 WHERE person_id = '94508c11-4edc-4063-9146-3978b6f1890a'; -- User 3

PRINT '=== VERIFYING RECONCILIATION IN TEST DB ===';
SELECT 
    t.trip_id,
    t.name,
    COUNT(DISTINCT p.person_id) AS MemberCount,
    COUNT(DISTINCT e.expense_id) AS ExpenseCount,
    ISNULL(SUM(p.balance), 0) AS NetPersonsBalanceSum
FROM Trips t
LEFT JOIN Persons p ON t.trip_id = p.trip_id
LEFT JOIN Expenses e ON t.trip_id = e.trip_id
GROUP BY t.trip_id, t.name;
