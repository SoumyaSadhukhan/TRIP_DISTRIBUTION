SET NOCOUNT ON;

PRINT '=== 1. ALL TRIPS IN DATABASE ===';
SELECT trip_id, name, user_id, currency_code, created_at FROM Trips ORDER BY created_at;

PRINT '=== 2. FINANCIAL RECONCILIATION PER TRIP ===';
SELECT 
    t.trip_id,
    t.name AS TripName,
    COUNT(DISTINCT p.person_id) AS MemberCount,
    COUNT(DISTINCT e.expense_id) AS ExpenseCount,
    ISNULL(SUM(DISTINCT CAST(e.amount AS DECIMAL(18,2))), 0) AS TotalExpensesFromExpenses,
    ISNULL((SELECT SUM(es.amount) FROM ExpenseSplits es WHERE es.trip_id = t.trip_id), 0) AS TotalSplitsAmount,
    ISNULL((SELECT SUM(p2.paid_amount) FROM Persons p2 WHERE p2.trip_id = t.trip_id), 0) AS SumPersonsPaid,
    ISNULL((SELECT SUM(p2.owed_amount) FROM Persons p2 WHERE p2.trip_id = t.trip_id), 0) AS SumPersonsOwed,
    ISNULL((SELECT SUM(p2.balance) FROM Persons p2 WHERE p2.trip_id = t.trip_id), 0) AS NetPersonsBalanceSum
FROM Trips t
LEFT JOIN Persons p ON t.trip_id = p.trip_id
LEFT JOIN Expenses e ON t.trip_id = e.trip_id
GROUP BY t.trip_id, t.name, t.created_at
ORDER BY t.created_at;

PRINT '=== 3. EXPENSES DETAIL PER TRIP ===';
SELECT 
    e.trip_id,
    t.name AS TripName,
    e.expense_id,
    e.description,
    e.amount,
    e.paid_by_person_id,
    ISNULL(p.name, '*** ORPHAN (NO PERSON) ***') AS PaidByName,
    (SELECT COUNT(*) FROM ExpenseSplits es WHERE es.expense_id = e.expense_id) AS SplitCount,
    (SELECT ISNULL(SUM(es.amount), 0) FROM ExpenseSplits es WHERE es.expense_id = e.expense_id) AS TotalSplitForExpense,
    e.amount - (SELECT ISNULL(SUM(es.amount), 0) FROM ExpenseSplits es WHERE es.expense_id = e.expense_id) AS SplitDifference
FROM Expenses e
JOIN Trips t ON e.trip_id = t.trip_id
LEFT JOIN Persons p ON e.paid_by_person_id = p.person_id
ORDER BY e.trip_id, e.created_at;

PRINT '=== 4. PERSONS DETAIL PER TRIP ===';
SELECT 
    p.trip_id,
    t.name AS TripName,
    p.person_id,
    p.name AS PersonName,
    p.phone_number,
    p.user_id,
    p.paid_amount,
    p.owed_amount,
    p.balance,
    -- Expected Paid from Expenses:
    (SELECT ISNULL(SUM(e.amount), 0) FROM Expenses e WHERE e.paid_by_person_id = p.person_id) AS ExpectedPaid,
    -- Expected Owed from ExpenseSplits:
    (SELECT ISNULL(SUM(es.amount), 0) FROM ExpenseSplits es WHERE es.person_id = p.person_id) AS ExpectedOwed,
    -- Expected Balance = ExpectedPaid - ExpectedOwed:
    (SELECT ISNULL(SUM(e.amount), 0) FROM Expenses e WHERE e.paid_by_person_id = p.person_id) - 
    (SELECT ISNULL(SUM(es.amount), 0) FROM ExpenseSplits es WHERE es.person_id = p.person_id) AS ExpectedBalance
FROM Persons p
JOIN Trips t ON p.trip_id = t.trip_id
ORDER BY p.trip_id, p.name;

PRINT '=== 5. SETTLEMENT TRANSACTIONS DETAIL ===';
SELECT 
    st.settlement_id,
    st.trip_id,
    t.name AS TripName,
    st.from_person_id,
    pFrom.name AS FromPersonName,
    st.to_person_id,
    pTo.name AS ToPersonName,
    st.amount,
    st.is_completed,
    st.status,
    st.settled_at
FROM SettlementTransactions st
LEFT JOIN Trips t ON st.trip_id = t.trip_id
LEFT JOIN Persons pFrom ON st.from_person_id = pFrom.person_id
LEFT JOIN Persons pTo ON st.to_person_id = pTo.person_id
ORDER BY st.settled_at;
