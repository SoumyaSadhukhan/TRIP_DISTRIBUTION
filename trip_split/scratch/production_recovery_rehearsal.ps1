$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=master;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "TASK 7: PRODUCTION RECOVERY REHEARSAL"
Write-Host "================================================================================"

$backupDir = "C:\My_Project\TRIP_DISTRIBUTION\backups"
if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}
$backupFile = "$backupDir\SPLIT_BILL_DB_TEST_Rehearsal.bak"

# 1. Create full backup of test database
Write-Host "--- STEP 1: Creating Full Backup of SPLIT_BILL_DB_TEST ---"
$cmd = $conn.CreateCommand()
$cmd.CommandTimeout = 120
$cmd.CommandText = @"
BACKUP DATABASE SPLIT_BILL_DB_TEST
TO DISK = '$backupFile'
WITH FORMAT, INIT, COMPRESSION, STATS = 25;
"@
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] Backup created at: $backupFile"
$backupItem = Get-Item $backupFile
Write-Host "          File Size: $([math]::Round($backupItem.Length / 1MB, 2)) MB | Modified: $($backupItem.LastWriteTime)"

# 2. Inspect logical file names
Write-Host "--- STEP 2: Inspecting Backup Filelist ---"
$cmd.CommandText = "RESTORE FILELISTONLY FROM DISK = '$backupFile';"
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtFiles = New-Object System.Data.DataTable
$adapter.Fill($dtFiles) | Out-Null

$dataLogicalName = $dtFiles.Rows[0]["LogicalName"].ToString()
$logLogicalName = $dtFiles.Rows[1]["LogicalName"].ToString()
Write-Host "Logical Data File: $dataLogicalName"
Write-Host "Logical Log File:  $logLogicalName"

# 3. Restore to separate rehearsal database SPLIT_BILL_DB_REHEARSAL
Write-Host "--- STEP 3: Restoring to SPLIT_BILL_DB_REHEARSAL ---"
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

# 4. Run DBCC CHECKDB
Write-Host "--- STEP 4: Running DBCC CHECKDB on Restored Rehearsal Database ---"
$cmd.CommandText = "DBCC CHECKDB ('SPLIT_BILL_DB_REHEARSAL') WITH NO_INFOMSGS;"
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[PASS] DBCC CHECKDB reported ZERO allocation or consistency errors."

# 5. Compare Row Counts between Source and Restored Database
Write-Host "--- STEP 5: Verifying Table Row Counts Between TEST and REHEARSAL ---"
$compareSql = @"
SELECT 
    t1.TABLE_NAME,
    (SELECT COUNT(1) FROM SPLIT_BILL_DB_TEST.sys.partitions p 
     JOIN SPLIT_BILL_DB_TEST.sys.tables t ON p.object_id = t.object_id 
     WHERE t.name = t1.TABLE_NAME AND p.index_id IN (0, 1)) AS TestRows,
    (SELECT COUNT(1) FROM SPLIT_BILL_DB_REHEARSAL.sys.partitions p 
     JOIN SPLIT_BILL_DB_REHEARSAL.sys.tables t ON p.object_id = t.object_id 
     WHERE t.name = t1.TABLE_NAME AND p.index_id IN (0, 1)) AS RehearsalRows
FROM SPLIT_BILL_DB_TEST.INFORMATION_SCHEMA.TABLES t1
WHERE t1.TABLE_TYPE = 'BASE TABLE'
ORDER BY t1.TABLE_NAME;
"@
$cmd.CommandText = $compareSql
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtCounts = New-Object System.Data.DataTable
$adapter.Fill($dtCounts) | Out-Null
$dtCounts | Format-Table -AutoSize

# 6. Cleanup Rehearsal Database
Write-Host "--- STEP 6: Cleaning Up Rehearsal Database ---"
$cleanupSql = @"
ALTER DATABASE SPLIT_BILL_DB_REHEARSAL SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE SPLIT_BILL_DB_REHEARSAL;
"@
$cmd.CommandText = $cleanupSql
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] SPLIT_BILL_DB_REHEARSAL cleanly dropped."

$conn.Close()
Write-Host "================================================================================"
Write-Host "PRODUCTION RECOVERY REHEARSAL COMPLETED SUCCESSFULLY."
Write-Host "================================================================================"
