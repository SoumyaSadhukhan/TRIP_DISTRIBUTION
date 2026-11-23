[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "TASK 6: STRICTLY READ-ONLY PREFLIGHT DIAGNOSTICS FOR SPLIT_BILL_DB"
Write-Host "================================================================================"

function Query-Report($title, $sql) {
    Write-Host "`n>>> $title"
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $dt = New-Object System.Data.DataTable
    $adapter.Fill($dt) | Out-Null
    if ($dt.Rows.Count -eq 0) {
        Write-Host "    [ZERO RECORDS FOUND / CLEAN]"
    } else {
        $dt | Format-Table -AutoSize
    }
    return $dt.Rows.Count
}

# 1. Duplicate composite keys
Query-Report "1A. Duplicate Composite Keys in Persons (person_id, trip_id)" @"
SELECT person_id, trip_id, COUNT(*) AS DuplicateCount
FROM dbo.Persons
GROUP BY person_id, trip_id
HAVING COUNT(*) > 1;
"@

Query-Report "1B. Duplicate Composite Keys in Expenses (expense_id, trip_id)" @"
SELECT expense_id, trip_id, COUNT(*) AS DuplicateCount
FROM dbo.Expenses
GROUP BY expense_id, trip_id
HAVING COUNT(*) > 1;
"@

# 2. Orphan payer references
Query-Report "2. Orphan Payer References in Expenses" @"
SELECT e.expense_id, e.trip_id, e.description, e.amount, e.paid_by_person_id
FROM dbo.Expenses e
LEFT JOIN dbo.Persons p ON e.paid_by_person_id = p.person_id
WHERE p.person_id IS NULL;
"@

# 3. Orphan expense splits
Query-Report "3A. Orphan Expense References in ExpenseSplits" @"
SELECT es.split_id, es.expense_id, es.trip_id, es.person_id, es.amount
FROM dbo.ExpenseSplits es
LEFT JOIN dbo.Expenses e ON es.expense_id = e.expense_id
WHERE e.expense_id IS NULL;
"@

Query-Report "3B. Orphan Person References in ExpenseSplits" @"
SELECT es.split_id, es.expense_id, es.trip_id, es.person_id, es.amount
FROM dbo.ExpenseSplits es
LEFT JOIN dbo.Persons p ON es.person_id = p.person_id
WHERE p.person_id IS NULL;
"@

# 4. Cross-trip references
Query-Report "4A. Cross-Trip Payer References in Expenses" @"
SELECT e.expense_id, e.trip_id AS ExpenseTripId, e.paid_by_person_id, p.trip_id AS PersonTripId
FROM dbo.Expenses e
JOIN dbo.Persons p ON e.paid_by_person_id = p.person_id
WHERE e.trip_id <> p.trip_id;
"@

Query-Report "4B. Cross-Trip Expense References in ExpenseSplits" @"
SELECT es.split_id, es.trip_id AS SplitTripId, es.expense_id, e.trip_id AS ExpenseTripId
FROM dbo.ExpenseSplits es
JOIN dbo.Expenses e ON es.expense_id = e.expense_id
WHERE es.trip_id <> e.trip_id;
"@

Query-Report "4C. Cross-Trip Person References in ExpenseSplits" @"
SELECT es.split_id, es.trip_id AS SplitTripId, es.person_id, p.trip_id AS PersonTripId
FROM dbo.ExpenseSplits es
JOIN dbo.Persons p ON es.person_id = p.person_id
WHERE es.trip_id <> p.trip_id;
"@

# 5. Cross-trip settlements
Query-Report "5A. Cross-Trip From-Person References in Settlements" @"
SELECT st.settlement_id, st.trip_id AS SettlementTripId, st.from_person_id, p.trip_id AS PersonTripId
FROM dbo.SettlementTransactions st
JOIN dbo.Persons p ON st.from_person_id = p.person_id
WHERE st.trip_id <> p.trip_id;
"@

Query-Report "5B. Cross-Trip To-Person References in Settlements" @"
SELECT st.settlement_id, st.trip_id AS SettlementTripId, st.to_person_id, p.trip_id AS PersonTripId
FROM dbo.SettlementTransactions st
JOIN dbo.Persons p ON st.to_person_id = p.person_id
WHERE st.trip_id <> p.trip_id;
"@

# 6. Financial discrepancies
Query-Report "6A. Expense Splits Total Discrepancy (Sum of splits != Expense amount)" @"
SELECT e.expense_id, e.trip_id, e.description, e.amount AS ExpenseAmount, 
       ISNULL(SUM(es.amount), 0) AS SplitsTotal,
       (e.amount - ISNULL(SUM(es.amount), 0)) AS Discrepancy
FROM dbo.Expenses e
LEFT JOIN dbo.ExpenseSplits es ON e.expense_id = es.expense_id
GROUP BY e.expense_id, e.trip_id, e.description, e.amount
HAVING ABS(e.amount - ISNULL(SUM(es.amount), 0)) > 0.009;
"@

Query-Report "6B. Trip Total Balance Discrepancy (Sum of balances != 0.00)" @"
SELECT t.trip_id, t.name, SUM(p.balance) AS SumBalances
FROM dbo.Trips t
JOIN dbo.Persons p ON t.trip_id = p.trip_id
GROUP BY t.trip_id, t.name
HAVING ABS(SUM(p.balance)) > 0.009;
"@

Query-Report "6C. Person Stored vs Calculated Net Balance Discrepancy" @"
WITH PersonCalc AS (
    SELECT 
        p.person_id,
        p.trip_id,
        p.name,
        p.balance AS StoredBalance,
        ISNULL(paid.TotalPaid, 0.00) AS ExpectedPaid,
        ISNULL(owed.TotalOwed, 0.00) AS ExpectedOwed,
        ISNULL(settleFrom.TotalSettled, 0.00) AS SettleFrom,
        ISNULL(settleTo.TotalReceived, 0.00) AS SettleTo,
        (ISNULL(paid.TotalPaid, 0.00) + ISNULL(settleFrom.TotalSettled, 0.00)) - 
        (ISNULL(owed.TotalOwed, 0.00) + ISNULL(settleTo.TotalReceived, 0.00)) AS ExpectedNetBalance
    FROM dbo.Persons p
    LEFT JOIN (
        SELECT paid_by_person_id, SUM(amount) AS TotalPaid
        FROM dbo.Expenses
        GROUP BY paid_by_person_id
    ) paid ON p.person_id = paid.paid_by_person_id
    LEFT JOIN (
        SELECT es.person_id, SUM(es.amount) AS TotalOwed
        FROM dbo.ExpenseSplits es
        GROUP BY es.person_id
    ) owed ON p.person_id = owed.person_id
    LEFT JOIN (
        SELECT from_person_id, SUM(amount) AS TotalSettled
        FROM dbo.SettlementTransactions
        WHERE status IN ('ACCEPTED', 'COMPLETED') AND is_completed = 1
        GROUP BY from_person_id
    ) settleFrom ON p.person_id = settleFrom.from_person_id
    LEFT JOIN (
        SELECT to_person_id, SUM(amount) AS TotalReceived
        FROM dbo.SettlementTransactions
        WHERE status IN ('ACCEPTED', 'COMPLETED') AND is_completed = 1
        GROUP BY to_person_id
    ) settleTo ON p.person_id = settleTo.to_person_id
)
SELECT person_id, trip_id, name, StoredBalance, ExpectedNetBalance,
       (StoredBalance - ExpectedNetBalance) AS Difference
FROM PersonCalc
WHERE ABS(StoredBalance - ExpectedNetBalance) > 0.009;
"@

# 7. Existing schema conflicts
Query-Report "7A. Conflicting Proposed Migration Constraints in Production" @"
SELECT name, type_desc 
FROM sys.objects 
WHERE name IN (
    'UQ_Persons_PersonTrip', 'UQ_Expenses_ExpenseTrip',
    'FK_Expenses_Persons_Trip', 'FK_ExpenseSplits_Expenses_Trip',
    'FK_ExpenseSplits_Persons_Trip', 'FK_Settlements_Persons_From_Trip',
    'FK_Settlements_Persons_To_Trip', 'DF_Trips_IsDeleted',
    'DF_Expenses_IsDeleted', 'DF_Persons_IsDeleted',
    'DF_OtpVerification_FailedAttempts', 'DF_OtpVerification_MaxAttempts',
    'IX_Trips_IsDeleted', 'IX_Expenses_IsDeleted', 'IX_Persons_IsDeleted',
    'IX_OtpVerification_Lookup', 'IX_OtpVerification_IpRateLimit'
);
"@

Query-Report "7B. Conflicting Proposed Columns in Production" @"
SELECT t.name AS TableName, c.name AS ColumnName, ty.name AS TypeName
FROM sys.tables t
JOIN sys.columns c ON t.object_id = c.object_id
JOIN sys.types ty ON c.user_type_id = ty.user_type_id
WHERE (t.name IN ('Trips', 'Expenses', 'Persons') AND c.name IN ('is_deleted', 'deleted_at'))
   OR (t.name = 'OtpVerification' AND c.name IN ('otp_hash', 'failed_attempts', 'max_attempts', 'lockout_until', 'ip_address'));
"@

# 8. Existing indexes and foreign keys in production
Query-Report "8A. Existing Foreign Keys in SPLIT_BILL_DB" @"
SELECT fk.name AS ForeignKeyName, tp.name AS ParentTable, tr.name AS ReferencedTable
FROM sys.foreign_keys fk
JOIN sys.tables tp ON fk.parent_object_id = tp.object_id
JOIN sys.tables tr ON fk.referenced_object_id = tr.object_id
ORDER BY tp.name, fk.name;
"@

Query-Report "8B. Existing Unique Constraints in SPLIT_BILL_DB" @"
SELECT kc.name AS ConstraintName, t.name AS TableName
FROM sys.key_constraints kc
JOIN sys.tables t ON kc.parent_object_id = t.object_id
WHERE kc.type = 'UQ'
ORDER BY t.name, kc.name;
"@

$conn.Close()
Write-Host "`n================================================================================"
Write-Host "TASK 6 PREFLIGHT DIAGNOSTICS COMPLETED (STRICTLY READ-ONLY)"
Write-Host "================================================================================"
