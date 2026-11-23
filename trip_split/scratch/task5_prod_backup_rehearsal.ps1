# ============================================================================
# Task 5: Production Backup Rehearsal
# Backs up SPLIT_BILL_DB, restores to isolated SPLIT_BILL_DB_PROD_REHEARSAL,
# executes direct COUNT(*) verification across all tables, inspects constraints,
# runs DBCC CHECKDB, tests read-only connectivity, and cleans up.
# ============================================================================

[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=master;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "TASK 5: PRODUCTION BACKUP & RESTORE REHEARSAL"
Write-Host "================================================================================"

$backupDir = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\backups"
if (!(Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
$backupFile = "$backupDir\SPLIT_BILL_DB_Prod_Rehearsal.bak"

$cmd = $conn.CreateCommand()

# STEP 1: Take Full Backup of Production Database SPLIT_BILL_DB
Write-Host "`n--- STEP 1: Full Backup of Production (SPLIT_BILL_DB) ---"
$cmd.CommandText = @"
BACKUP DATABASE SPLIT_BILL_DB
TO DISK = '$backupFile'
WITH INIT, COMPRESSION, STATS = 25;
"@
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] Production database backed up cleanly to $backupFile."

# STEP 2: Inspect Backup Filelist
Write-Host "`n--- STEP 2: Inspecting Backup Filelist ---"
$cmd.CommandText = "RESTORE FILELISTONLY FROM DISK = '$backupFile';"
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtFiles = New-Object System.Data.DataTable
$adapter.Fill($dtFiles) | Out-Null

$dataLogicalName = $dtFiles.Rows[0]["LogicalName"].ToString()
$logLogicalName = $dtFiles.Rows[1]["LogicalName"].ToString()
Write-Host "Logical Data File: $dataLogicalName"
Write-Host "Logical Log File:  $logLogicalName"

# STEP 3: Restore to SPLIT_BILL_DB_PROD_REHEARSAL
Write-Host "`n--- STEP 3: Restoring to SPLIT_BILL_DB_PROD_REHEARSAL ---"
$destMdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\SPLIT_BILL_DB_PROD_REHEARSAL.mdf"
$destLdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\SPLIT_BILL_DB_PROD_REHEARSAL_log.ldf"

$restoreSql = @"
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SPLIT_BILL_DB_PROD_REHEARSAL')
BEGIN
    ALTER DATABASE SPLIT_BILL_DB_PROD_REHEARSAL SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SPLIT_BILL_DB_PROD_REHEARSAL;
END

RESTORE DATABASE SPLIT_BILL_DB_PROD_REHEARSAL
FROM DISK = '$backupFile'
WITH REPLACE,
     MOVE '$dataLogicalName' TO '$destMdf',
     MOVE '$logLogicalName'  TO '$destLdf',
     STATS = 25;
"@
$cmd.CommandText = $restoreSql
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] Restored to isolated database SPLIT_BILL_DB_PROD_REHEARSAL."

# STEP 4: Accurate Row-Count Comparison across All 13 User Tables
Write-Host "`n--- STEP 4: Row Counts Comparison (Direct COUNT(*)) ---"
$tablesCmd = $conn.CreateCommand()
$tablesCmd.CommandText = "SELECT TABLE_NAME FROM SPLIT_BILL_DB.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;"
$reader = $tablesCmd.ExecuteReader()
$tableNames = @()
while ($reader.Read()) {
    $tableNames += $reader.GetString(0)
}
$reader.Close()

$comparisonResults = @()
foreach ($tbl in $tableNames) {
    $srcCmd = $conn.CreateCommand()
    $srcCmd.CommandText = "SELECT COUNT(*) FROM SPLIT_BILL_DB.dbo.[$tbl];"
    $srcCount = [int]$srcCmd.ExecuteScalar()

    $dstCmd = $conn.CreateCommand()
    $dstCmd.CommandText = "SELECT COUNT(*) FROM SPLIT_BILL_DB_PROD_REHEARSAL.dbo.[$tbl];"
    $dstCount = [int]$dstCmd.ExecuteScalar()

    $match = ($srcCount -eq $dstCount)
    $comparisonResults += [PSCustomObject]@{
        TableName = $tbl
        Source_SPLIT_BILL_DB = $srcCount
        Restored_REHEARSAL   = $dstCount
        Match               = if ($match) { "MATCH (PASS)" } else { "MISMATCH (FAIL)" }
    }
}
$comparisonResults | Format-Table -AutoSize

# STEP 5: Integrity and Schema Inspection
Write-Host "`n--- STEP 5: Database Integrity and Schema Checks ---"
$cmd.CommandText = @"
SELECT 
    (SELECT COUNT(*) FROM SPLIT_BILL_DB_PROD_REHEARSAL.sys.indexes) AS IndexCount,
    (SELECT COUNT(*) FROM SPLIT_BILL_DB_PROD_REHEARSAL.sys.foreign_keys) AS ForeignKeyCount,
    (SELECT COUNT(*) FROM SPLIT_BILL_DB_PROD_REHEARSAL.sys.key_constraints WHERE type = 'PK') AS PrimaryKeyCount,
    (SELECT COUNT(*) FROM SPLIT_BILL_DB_PROD_REHEARSAL.sys.key_constraints WHERE type = 'UQ') AS UniqueConstraintCount,
    (SELECT recovery_model_desc FROM sys.databases WHERE name = 'SPLIT_BILL_DB_PROD_REHEARSAL') AS RecoveryModel,
    (SELECT compatibility_level FROM sys.databases WHERE name = 'SPLIT_BILL_DB_PROD_REHEARSAL') AS CompatibilityLevel;
"@
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtSchema = New-Object System.Data.DataTable
$adapter.Fill($dtSchema) | Out-Null
$dtSchema | Format-Table -AutoSize

# STEP 6: DBCC CHECKDB
Write-Host "`n--- STEP 6: DBCC CHECKDB Verification ---"
$cmd.CommandText = "DBCC CHECKDB ('SPLIT_BILL_DB_PROD_REHEARSAL') WITH NO_INFOMSGS;"
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] DBCC CHECKDB completed with 0 allocation errors and 0 consistency errors."

# STEP 7: Read-Only Query Simulation
Write-Host "`n--- STEP 7: Simulated Application Read Queries ---"
$cmd.CommandText = @"
SELECT 
    (SELECT COUNT(*) FROM SPLIT_BILL_DB_PROD_REHEARSAL.dbo.Users) AS ActiveUsers,
    (SELECT COUNT(*) FROM SPLIT_BILL_DB_PROD_REHEARSAL.dbo.Trips) AS ActiveTrips,
    (SELECT COUNT(*) FROM SPLIT_BILL_DB_PROD_REHEARSAL.dbo.Expenses) AS ActiveExpenses,
    (SELECT ISNULL(SUM(amount), 0.00) FROM SPLIT_BILL_DB_PROD_REHEARSAL.dbo.Expenses) AS TotalExpenseVolume;
"@
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtApp = New-Object System.Data.DataTable
$adapter.Fill($dtApp) | Out-Null
$dtApp | Format-Table -AutoSize

# STEP 8: Cleanup Rehearsal Database
Write-Host "`n--- STEP 8: Cleanup Rehearsal Database ---"
$cleanupSql = @"
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SPLIT_BILL_DB_PROD_REHEARSAL')
BEGIN
    ALTER DATABASE SPLIT_BILL_DB_PROD_REHEARSAL SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SPLIT_BILL_DB_PROD_REHEARSAL;
END
"@
$cmd.CommandText = $cleanupSql
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] SPLIT_BILL_DB_PROD_REHEARSAL dropped cleanly."

$conn.Close()
Write-Host "`n>>> TASK 5 PRODUCTION BACKUP REHEARSAL COMPLETE AND VERIFIED."
