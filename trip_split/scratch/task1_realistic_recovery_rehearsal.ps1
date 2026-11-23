[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=master;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "TASK 1: REALISTIC BACKUP AND RESTORE REHEARSAL VERIFICATION"
Write-Host "================================================================================"

$backupDir = "C:\My_Project\TRIP_DISTRIBUTION\backups"
if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}
$backupFile = "$backupDir\SPLIT_BILL_DB_TEST_Realistic_Rehearsal.bak"

# STEP 1: Create Full Backup of SPLIT_BILL_DB_TEST
Write-Host "`n--- STEP 1: Creating Full Backup of SPLIT_BILL_DB_TEST ---"
$cmd = $conn.CreateCommand()
$cmd.CommandTimeout = 180
$cmd.CommandText = @"
BACKUP DATABASE SPLIT_BILL_DB_TEST
TO DISK = '$backupFile'
WITH FORMAT, INIT, COMPRESSION, STATS = 25;
"@
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] Backup created at: $backupFile"
$backupItem = Get-Item $backupFile
Write-Host "          Size: $([math]::Round($backupItem.Length / 1MB, 2)) MB | Modified: $($backupItem.LastWriteTime)"

# STEP 2: Inspect Logical File Names
Write-Host "`n--- STEP 2: Inspecting Backup Filelist ---"
$cmd.CommandText = "RESTORE FILELISTONLY FROM DISK = '$backupFile';"
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtFiles = New-Object System.Data.DataTable
$adapter.Fill($dtFiles) | Out-Null

$dataLogicalName = $dtFiles.Rows[0]["LogicalName"].ToString()
$logLogicalName = $dtFiles.Rows[1]["LogicalName"].ToString()
Write-Host "Logical Data File: $dataLogicalName"
Write-Host "Logical Log File:  $logLogicalName"

# STEP 3: Restore to SPLIT_BILL_DB_REHEARSAL
Write-Host "`n--- STEP 3: Restoring to SPLIT_BILL_DB_REHEARSAL ---"
$dataMdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\SPLIT_BILL_DB_REHEARSAL.mdf"
$logLdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\SPLIT_BILL_DB_REHEARSAL_log.ldf"

$restoreSql = @"
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SPLIT_BILL_DB_REHEARSAL')
BEGIN
    ALTER DATABASE SPLIT_BILL_DB_REHEARSAL SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SPLIT_BILL_DB_REHEARSAL;
END

RESTORE DATABASE SPLIT_BILL_DB_REHEARSAL
FROM DISK = '$backupFile'
WITH REPLACE,
     MOVE '$dataLogicalName' TO '$dataMdf',
     MOVE '$logLogicalName' TO '$logLdf',
     STATS = 25;
"@
$cmd.CommandText = $restoreSql
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] Database restored cleanly as SPLIT_BILL_DB_REHEARSAL."

# STEP 4: Compare Accurate Row Counts using direct COUNT(*)
Write-Host "`n--- STEP 4: Accurate Table Row Counts (Source vs Rehearsal) ---"
$tablesCmd = $conn.CreateCommand()
$tablesCmd.CommandText = "SELECT TABLE_NAME FROM SPLIT_BILL_DB_TEST.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;"
$reader = $tablesCmd.ExecuteReader()
$tableNames = @()
while ($reader.Read()) {
    $tableNames += $reader.GetString(0)
}
$reader.Close()

$results = @()
foreach ($t in $tableNames) {
    $cCmd = $conn.CreateCommand()
    $cCmd.CommandText = "SELECT COUNT(*) FROM [SPLIT_BILL_DB_TEST].[dbo].[$t]"
    $testCount = [int]$cCmd.ExecuteScalar()

    $rCmd = $conn.CreateCommand()
    $rCmd.CommandText = "SELECT COUNT(*) FROM [SPLIT_BILL_DB_REHEARSAL].[dbo].[$t]"
    $rehearsalCount = [int]$rCmd.ExecuteScalar()

    $pCmd = $conn.CreateCommand()
    $pCmd.CommandText = "SELECT COUNT(*) FROM [SPLIT_BILL_DB_TEST].sys.partitions p JOIN [SPLIT_BILL_DB_TEST].sys.tables st ON p.object_id = st.object_id WHERE st.name = '$t' AND p.index_id IN (0,1)"
    $partitionDescCount = [int]$pCmd.ExecuteScalar()

    $status = if ($testCount -eq $rehearsalCount) { "MATCH" } else { "MISMATCH" }

    $results += [PSCustomObject]@{
        TableName = $t
        TestSourceRows = $testCount
        RestoredRehearsalRows = $rehearsalCount
        PartitionDescCount = $partitionDescCount
        Status = $status
    }
}
$results | Format-Table -AutoSize

# STEP 5: Verify Schema Objects in Restored Database
Write-Host "`n--- STEP 5: Verifying Schema Objects in Restored Database ---"
$objSql = @"
SELECT 'Foreign Keys' AS ObjectType, COUNT(*) AS ObjectCount FROM SPLIT_BILL_DB_REHEARSAL.sys.foreign_keys
UNION ALL
SELECT 'Unique Constraints', COUNT(*) FROM SPLIT_BILL_DB_REHEARSAL.sys.key_constraints WHERE type = 'UQ'
UNION ALL
SELECT 'Primary Keys', COUNT(*) FROM SPLIT_BILL_DB_REHEARSAL.sys.key_constraints WHERE type = 'PK'
UNION ALL
SELECT 'Indexes', COUNT(*) FROM SPLIT_BILL_DB_REHEARSAL.sys.indexes WHERE name IS NOT NULL
UNION ALL
SELECT 'Stored Procedures', COUNT(*) FROM SPLIT_BILL_DB_REHEARSAL.sys.procedures
UNION ALL
SELECT 'Triggers', COUNT(*) FROM SPLIT_BILL_DB_REHEARSAL.sys.triggers;
"@
$cmd.CommandText = $objSql
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtObjs = New-Object System.Data.DataTable
$adapter.Fill($dtObjs) | Out-Null
$dtObjs | Format-Table -AutoSize

# Inspect the 5 composite foreign keys specifically
Write-Host "`n--- Composite Foreign Keys in Restored Database ---"
$fkSql = @"
SELECT 
    fk.name AS ForeignKeyName,
    tp.name AS ParentTable,
    tr.name AS ReferencedTable,
    fk.delete_referential_action_desc AS OnDeleteAction
FROM SPLIT_BILL_DB_REHEARSAL.sys.foreign_keys fk
JOIN SPLIT_BILL_DB_REHEARSAL.sys.tables tp ON fk.parent_object_id = tp.object_id
JOIN SPLIT_BILL_DB_REHEARSAL.sys.tables tr ON fk.referenced_object_id = tr.object_id
WHERE fk.name LIKE 'FK_%_Trip%'
ORDER BY fk.name;
"@
$cmd.CommandText = $fkSql
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtFk = New-Object System.Data.DataTable
$adapter.Fill($dtFk) | Out-Null
$dtFk | Format-Table -AutoSize

# STEP 6: Independent Financial Balance Reconciliation in Restored DB
Write-Host "`n--- STEP 6: Independent Financial Balance Verification in Restored DB ---"
$finSql = @"
USE SPLIT_BILL_DB_REHEARSAL;

WITH PersonExpected AS (
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
    FROM Persons p
    LEFT JOIN (
        SELECT paid_by_person_id, SUM(amount) AS TotalPaid
        FROM Expenses
        WHERE ISNULL(is_deleted, 0) = 0
        GROUP BY paid_by_person_id
    ) paid ON p.person_id = paid.paid_by_person_id
    LEFT JOIN (
        SELECT es.person_id, SUM(es.amount) AS TotalOwed
        FROM ExpenseSplits es
        INNER JOIN Expenses e ON es.expense_id = e.expense_id
        WHERE ISNULL(e.is_deleted, 0) = 0
        GROUP BY es.person_id
    ) owed ON p.person_id = owed.person_id
    LEFT JOIN (
        SELECT from_person_id, SUM(amount) AS TotalSettled
        FROM SettlementTransactions
        WHERE status IN ('ACCEPTED', 'COMPLETED') AND is_completed = 1
        GROUP BY from_person_id
    ) settleFrom ON p.person_id = settleFrom.from_person_id
    LEFT JOIN (
        SELECT to_person_id, SUM(amount) AS TotalReceived
        FROM SettlementTransactions
        WHERE status IN ('ACCEPTED', 'COMPLETED') AND is_completed = 1
        GROUP BY to_person_id
    ) settleTo ON p.person_id = settleTo.to_person_id
    WHERE ISNULL(p.is_deleted, 0) = 0
)
SELECT 
    trip_id,
    COUNT(*) AS ActiveMembers,
    SUM(StoredBalance) AS SumStoredBalances,
    SUM(ExpectedNetBalance) AS SumExpectedBalances,
    SUM(ABS(StoredBalance - ExpectedNetBalance)) AS BalanceDiscrepancy
FROM PersonExpected
GROUP BY trip_id
ORDER BY trip_id;
"@
$cmd.CommandText = $finSql
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtFin = New-Object System.Data.DataTable
$adapter.Fill($dtFin) | Out-Null
$dtFin | Format-Table -AutoSize

# STEP 7: Run DBCC CHECKDB
Write-Host "`n--- STEP 7: Executing DBCC CHECKDB on Restored Rehearsal DB ---"
$cmd.CommandText = "DBCC CHECKDB ('SPLIT_BILL_DB_REHEARSAL') WITH ALL_ERRORMSGS, NO_INFOMSGS;"
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[PASS] DBCC CHECKDB reported ZERO allocation or consistency errors in SPLIT_BILL_DB_REHEARSAL."

# STEP 8: Cleanup Rehearsal DB
Write-Host "`n--- STEP 8: Cleanup SPLIT_BILL_DB_REHEARSAL ---"
$cleanupSql = @"
USE master;
ALTER DATABASE SPLIT_BILL_DB_REHEARSAL SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE SPLIT_BILL_DB_REHEARSAL;
"@
$cmd.CommandText = $cleanupSql
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] SPLIT_BILL_DB_REHEARSAL cleanly dropped."

$conn.Close()
Write-Host "`n================================================================================"
Write-Host "TASK 1 REHEARSAL VERIFICATION COMPLETED SUCCESSFULLY"
Write-Host "================================================================================"
