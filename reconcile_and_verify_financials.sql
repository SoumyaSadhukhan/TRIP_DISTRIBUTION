SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

USE [SPLIT_BILL_DB_TEST];

PRINT '============================================================================';
PRINT 'INDEPENDENT COMPREHENSIVE FINANCIAL RECONCILIATION AUDIT';
PRINT '============================================================================';

PRINT '--- CHECK 1: EXPENSES WITH INVALID OR ORPHAN PAYERS ---';
SELECT e.expense_id, e.trip_id, e.description, e.amount, e.paid_by_person_id
FROM Expenses e
LEFT JOIN Persons p ON e.paid_by_person_id = p.person_id AND e.trip_id = p.trip_id
WHERE p.person_id IS NULL;
PRINT 'Invalid Payer Count: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' (EXPECT: 0)';

PRINT '--- CHECK 2: EXPENSES WITHOUT SPLITS (ORPHAN SPLITLESS EXPENSES) ---';
SELECT e.expense_id, e.description, e.amount
FROM Expenses e
LEFT JOIN ExpenseSplits es ON e.expense_id = es.expense_id
WHERE es.split_id IS NULL;
PRINT 'Splitless Expense Count: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' (EXPECT: 0)';

PRINT '--- CHECK 3: SPLIT SUM VS EXPENSE TOTAL ACCURACY ---';
SELECT 
    e.trip_id,
    t.name AS TripName,
    e.expense_id,
    e.description,
    e.amount AS ExpenseAmount,
    ISNULL(SUM(es.amount), 0) AS TotalSplitsSum,
    e.amount - ISNULL(SUM(es.amount), 0) AS SplitDiscrepancy
FROM Expenses e
JOIN Trips t ON e.trip_id = t.trip_id
LEFT JOIN ExpenseSplits es ON e.expense_id = es.expense_id
GROUP BY e.trip_id, t.name, e.expense_id, e.description, e.amount
HAVING e.amount - ISNULL(SUM(es.amount), 0) <> 0;
PRINT 'Split Discrepancy Count: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' (EXPECT: 0)';

PRINT '--- CHECK 4: EXPENSE SPLITS REFERENCING PERSONS OUTSIDE THE TRIP ---';
SELECT es.split_id, es.expense_id, es.trip_id, es.person_id
FROM ExpenseSplits es
LEFT JOIN Persons p ON es.person_id = p.person_id AND es.trip_id = p.trip_id
WHERE p.person_id IS NULL;
PRINT 'Invalid Split Person Count: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' (EXPECT: 0)';

PRINT '--- CHECK 5: SETTLEMENTS REFERENCING INVALID OR CROSS-TRIP PERSONS ---';
SELECT st.settlement_id, st.trip_id, st.from_person_id, st.to_person_id, st.amount
FROM SettlementTransactions st
LEFT JOIN Persons pFrom ON st.from_person_id = pFrom.person_id AND st.trip_id = pFrom.trip_id
LEFT JOIN Persons pTo ON st.to_person_id = pTo.person_id AND st.trip_id = pTo.trip_id
WHERE pFrom.person_id IS NULL OR pTo.person_id IS NULL;
PRINT 'Invalid Settlement Person Count: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' (EXPECT: 0)';

PRINT '--- CHECK 6: INDEPENDENT BALANCE CALCULATION VS STORED BALANCE ---';
SELECT 
    p.trip_id,
    t.name AS TripName,
    p.person_id,
    p.name AS PersonName,
    p.balance AS StoredBalance,
    -- Independent calculation:
    ISNULL((SELECT SUM(e.amount) FROM Expenses e WHERE e.paid_by_person_id = p.person_id), 0) 
    + ISNULL((SELECT SUM(st.amount) FROM SettlementTransactions st WHERE st.from_person_id = p.person_id AND st.is_completed = 1), 0)
    AS IndependentlyCalculatedPaid,
    ISNULL((SELECT SUM(es.amount) FROM ExpenseSplits es WHERE es.person_id = p.person_id), 0)
    + ISNULL((SELECT SUM(st.amount) FROM SettlementTransactions st WHERE st.to_person_id = p.person_id AND st.is_completed = 1), 0)
    AS IndependentlyCalculatedOwed,
    (
      (ISNULL((SELECT SUM(e.amount) FROM Expenses e WHERE e.paid_by_person_id = p.person_id), 0) 
       + ISNULL((SELECT SUM(st.amount) FROM SettlementTransactions st WHERE st.from_person_id = p.person_id AND st.is_completed = 1), 0))
      -
      (ISNULL((SELECT SUM(es.amount) FROM ExpenseSplits es WHERE es.person_id = p.person_id), 0)
       + ISNULL((SELECT SUM(st.amount) FROM SettlementTransactions st WHERE st.to_person_id = p.person_id AND st.is_completed = 1), 0))
    ) AS IndependentlyCalculatedBalance,
    ABS(p.balance - (
      (ISNULL((SELECT SUM(e.amount) FROM Expenses e WHERE e.paid_by_person_id = p.person_id), 0) 
       + ISNULL((SELECT SUM(st.amount) FROM SettlementTransactions st WHERE st.from_person_id = p.person_id AND st.is_completed = 1), 0))
      -
      (ISNULL((SELECT SUM(es.amount) FROM ExpenseSplits es WHERE es.person_id = p.person_id), 0)
       + ISNULL((SELECT SUM(st.amount) FROM SettlementTransactions st WHERE st.to_person_id = p.person_id AND st.is_completed = 1), 0))
    )) AS BalanceDiscrepancy
FROM Persons p
JOIN Trips t ON p.trip_id = t.trip_id
ORDER BY p.trip_id, p.name;

PRINT '--- CHECK 7: EXACT ACTIVITYLOGS AUDIT TRAIL FOR GOA TRIP (8092c57a) ---';
SELECT 
    log_id,
    action_type,
    details,
    created_at
FROM ActivityLogs
WHERE trip_id = '8092c57a-8638-4dc9-8969-748a9607d834'
ORDER BY created_at;
