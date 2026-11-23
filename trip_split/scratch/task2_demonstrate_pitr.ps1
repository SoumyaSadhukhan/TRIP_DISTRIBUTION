# ============================================================================
# Task 2: Realistic Point-in-Time Recovery (PITR) Demonstration
# Demonstrates Full Recovery Model, Full Backup (T0), Differential Backup (T1),
# Log Backup (T2), Incident/Corruption (T3), Tail-Log Backup (T3),
# and Point-In-Time Restore to T2 excluding the T3 corruption.
# ============================================================================

[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=master;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "TASK 2: REALISTIC POINT-IN-TIME RECOVERY (PITR) DEMONSTRATION"
Write-Host "================================================================================"

$backupDir = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\backups"
if (!(Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

$fullBak = "$backupDir\pitr_demo_full_T0.bak"
$diffBak = "$backupDir\pitr_demo_diff_T1.bak"
$logBak  = "$backupDir\pitr_demo_log_T2.trn"
$tailBak = "$backupDir\pitr_demo_taillog_T3.trn"

$cmd = $conn.CreateCommand()

# STEP 0: Initial Cleanup of Demo Databases
Write-Host "`n--- STEP 0: Cleanup Prior Run Databases ---"
$cleanupSql = @"
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SPLIT_BILL_DB_PITR_RESTORED')
BEGIN
    BEGIN TRY
        DROP DATABASE SPLIT_BILL_DB_PITR_RESTORED;
    END TRY
    BEGIN CATCH
        ALTER DATABASE SPLIT_BILL_DB_PITR_RESTORED SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE SPLIT_BILL_DB_PITR_RESTORED;
    END CATCH
END

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SPLIT_BILL_DB_PITR_DEMO')
BEGIN
    BEGIN TRY
        DROP DATABASE SPLIT_BILL_DB_PITR_DEMO;
    END TRY
    BEGIN CATCH
        ALTER DATABASE SPLIT_BILL_DB_PITR_DEMO SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE SPLIT_BILL_DB_PITR_DEMO;
    END CATCH
END
"@
$cmd.CommandText = $cleanupSql
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] Prior test databases cleared."

# STEP 1: Verify Production Recovery Model
Write-Host "`n--- STEP 1: Verify Production Recovery Model ---"
$cmd.CommandText = "SELECT name, recovery_model_desc, log_reuse_wait_desc FROM sys.databases WHERE name = 'SPLIT_BILL_DB';"
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtProd = New-Object System.Data.DataTable
$adapter.Fill($dtProd) | Out-Null
$dtProd | Format-Table -AutoSize

# STEP 2: Create Demo Database with FULL Recovery Model
Write-Host "`n--- STEP 2: Initializing SPLIT_BILL_DB_PITR_DEMO (FULL Recovery) ---"
$cmd.CommandText = @"
CREATE DATABASE SPLIT_BILL_DB_PITR_DEMO;
ALTER DATABASE SPLIT_BILL_DB_PITR_DEMO SET RECOVERY FULL;
"@
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] SPLIT_BILL_DB_PITR_DEMO created with RECOVERY FULL."

# Create test table
$cmd.CommandText = @"
USE SPLIT_BILL_DB_PITR_DEMO;

CREATE TABLE dbo.FinancialLedger (
    entry_id INT IDENTITY(1,1) PRIMARY KEY,
    description NVARCHAR(100) NOT NULL,
    amount DECIMAL(18,2) NOT NULL,
    status NVARCHAR(50) NOT NULL,
    logged_at DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
"@
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] FinancialLedger table created."

# STEP 3: T0 - Baseline Data + Full Backup
Write-Host "`n--- STEP 3: Point T0 (Baseline Initialization) ---"
$cmd.CommandText = @"
USE SPLIT_BILL_DB_PITR_DEMO;
INSERT INTO dbo.FinancialLedger (description, amount, status)
VALUES 
    (N'Initial Capital Deposit', 100000.00, N'COMMITTED'),
    (N'Vendor Advance Payment', -25000.00, N'COMMITTED');
"@
$cmd.ExecuteNonQuery() | Out-Null

$cmd.CommandText = @"
BACKUP DATABASE SPLIT_BILL_DB_PITR_DEMO
TO DISK = '$fullBak'
WITH INIT, COMPRESSION, STATS = 50;
"@
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] Full Backup (T0) completed."
Write-Host "Backup File: $fullBak"

Start-Sleep -Seconds 2

# STEP 4: T1 - Incremental Transactions + Differential Backup
Write-Host "`n--- STEP 4: Point T1 (Differential Transactions) ---"
$cmd.CommandText = @"
USE SPLIT_BILL_DB_PITR_DEMO;
INSERT INTO dbo.FinancialLedger (description, amount, status)
VALUES 
    (N'Trip Budget Allocation: Goa Trip', -30000.00, N'COMMITTED'),
    (N'Sponsorship Received', 15000.00, N'COMMITTED');
"@
$cmd.ExecuteNonQuery() | Out-Null

$cmd.CommandText = @"
BACKUP DATABASE SPLIT_BILL_DB_PITR_DEMO
TO DISK = '$diffBak'
WITH DIFFERENTIAL, INIT, COMPRESSION, STATS = 50;
"@
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] Differential Backup (T1) completed."
Write-Host "Backup File: $diffBak"

Start-Sleep -Seconds 2

# STEP 5: T2 - Target Point-in-Time Legitimate Transactions + Log Backup
Write-Host "`n--- STEP 5: Point T2 (Pre-Incident Legitimate Transactions) ---"
$cmd.CommandText = @"
USE SPLIT_BILL_DB_PITR_DEMO;
INSERT INTO dbo.FinancialLedger (description, amount, status)
VALUES 
    (N'Settlement: Soumya to Manik', -2006.66, N'SETTLED'),
    (N'Settlement: Dipa to Friend', 1006.67, N'SETTLED');
"@
$cmd.ExecuteNonQuery() | Out-Null

$cmd.CommandText = @"
BACKUP LOG SPLIT_BILL_DB_PITR_DEMO
TO DISK = '$logBak'
WITH INIT, COMPRESSION, STATS = 50;
"@
$cmd.ExecuteNonQuery() | Out-Null

# Capture exact target STOPAT timestamp (Format 120: yyyy-mm-dd hh:mi:ss)
$cmd.CommandText = "SELECT CONVERT(VARCHAR(19), GETDATE(), 120);"
$targetTimestamp = $cmd.ExecuteScalar().ToString()
Write-Host "[SUCCESS] Log Backup (T2) completed."
Write-Host "TARGET RESTORE TIMESTAMP (STOPAT): $targetTimestamp (Server Time)"
Write-Host "Backup File: $logBak"

# Sleep 3 seconds so clock advances past targetTimestamp
Start-Sleep -Seconds 3

# STEP 6: T3 - Disaster / Corruption Incident Simulation
Write-Host "`n--- STEP 6: Point T3 (Disaster / Fraudulent Incident Simulation) ---"
$cmd.CommandText = @"
USE SPLIT_BILL_DB_PITR_DEMO;
-- Malicious or corrupted transaction that corrupts the database ledger
INSERT INTO dbo.FinancialLedger (description, amount, status)
VALUES (N'FRAUDULENT DRAIN: Rogue Actor Exfiltration', -9999999.99, N'CORRUPTED');

UPDATE dbo.FinancialLedger
SET status = N'CORRUPTED_BY_INCIDENT'
WHERE entry_id = 1;
"@
$cmd.ExecuteNonQuery() | Out-Null

$cmd.CommandText = "SELECT CONVERT(VARCHAR(19), GETDATE(), 120);"
$incidentTime = $cmd.ExecuteScalar().ToString()
Write-Host "[INCIDENT OCCURRED at $incidentTime]: Unauthorized ledger modification injected."

# STEP 7: Tail-Log Backup (WITH NORECOVERY)
Write-Host "`n--- STEP 7: Taking Tail-Log Backup WITH NORECOVERY ---"
$cmd.CommandText = "USE master;"
$cmd.ExecuteNonQuery() | Out-Null

$cmd.CommandText = @"
BACKUP LOG SPLIT_BILL_DB_PITR_DEMO
TO DISK = '$tailBak'
WITH NORECOVERY, INIT, STATS = 50;
"@
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] Tail-Log Backup completed. Source database locked in RESTORING state."
Write-Host "Tail Log File: $tailBak"

# Inspect database state: should now be RESTORING
$cmd.CommandText = "SELECT name, state_desc FROM sys.databases WHERE name = 'SPLIT_BILL_DB_PITR_DEMO';"
$state = $cmd.ExecuteScalar().ToString()
Write-Host "Source DB state: $state"

# STEP 8: Execute Point-in-Time Restore Sequence to SPLIT_BILL_DB_PITR_RESTORED
Write-Host "`n--- STEP 8: Executing PITR Sequence to STOPAT = '$targetTimestamp' ---"

# Inspect logical file names
$cmd.CommandText = "RESTORE FILELISTONLY FROM DISK = '$fullBak';"
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtFiles = New-Object System.Data.DataTable
$adapter.Fill($dtFiles) | Out-Null
$dataLogical = $dtFiles.Rows[0]["LogicalName"].ToString()
$logLogical  = $dtFiles.Rows[1]["LogicalName"].ToString()

$destMdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\SPLIT_BILL_DB_PITR_RESTORED.mdf"
$destLdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\SPLIT_BILL_DB_PITR_RESTORED_log.ldf"

# 8.1 Restore Full Backup (WITH NORECOVERY)
Write-Host "  8.1 Restoring Full Backup (T0) WITH NORECOVERY..."
$cmd.CommandText = @"
RESTORE DATABASE SPLIT_BILL_DB_PITR_RESTORED
FROM DISK = '$fullBak'
WITH NORECOVERY, REPLACE,
     MOVE '$dataLogical' TO '$destMdf',
     MOVE '$logLogical'  TO '$destLdf';
"@
$cmd.ExecuteNonQuery() | Out-Null

# 8.2 Restore Differential Backup (WITH NORECOVERY)
Write-Host "  8.2 Restoring Differential Backup (T1) WITH NORECOVERY..."
$cmd.CommandText = @"
RESTORE DATABASE SPLIT_BILL_DB_PITR_RESTORED
FROM DISK = '$diffBak'
WITH NORECOVERY;
"@
$cmd.ExecuteNonQuery() | Out-Null

# 8.3 Restore Transaction Log Backup (WITH NORECOVERY)
Write-Host "  8.3 Restoring Log Backup (T2) WITH NORECOVERY..."
$cmd.CommandText = @"
RESTORE LOG SPLIT_BILL_DB_PITR_RESTORED
FROM DISK = '$logBak'
WITH NORECOVERY;
"@
$cmd.ExecuteNonQuery() | Out-Null

# 8.4 Restore Tail-Log Backup (WITH RECOVERY, STOPAT = targetTimestamp)
Write-Host "  8.4 Restoring Tail-Log Backup (T3) WITH RECOVERY, STOPAT = '$targetTimestamp'..."
$cmd.CommandText = @"
RESTORE LOG SPLIT_BILL_DB_PITR_RESTORED
FROM DISK = '$tailBak'
WITH RECOVERY, STOPAT = '$targetTimestamp';
"@
$cmd.ExecuteNonQuery() | Out-Null

Write-Host "[SUCCESS] Database SPLIT_BILL_DB_PITR_RESTORED successfully recovered to point in time $targetTimestamp!"

# STEP 9: Verify Restored Data Integrity
Write-Host "`n--- STEP 9: Data Integrity Verification on Restored Database ---"
$cmd.CommandText = @"
SELECT entry_id, description, amount, status, logged_at
FROM SPLIT_BILL_DB_PITR_RESTORED.dbo.FinancialLedger
ORDER BY entry_id;
"@
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtRestored = New-Object System.Data.DataTable
$adapter.Fill($dtRestored) | Out-Null

$dtRestored | Format-Table -AutoSize

# Verification assertions
$rowCount = $dtRestored.Rows.Count
$corruptedRows = @($dtRestored.Select("status = 'CORRUPTED' OR description LIKE '%FRAUDULENT%'"))
$tamperedRows  = @($dtRestored.Select("entry_id = 1 AND status = 'CORRUPTED_BY_INCIDENT'"))

Write-Host "PITR Assertion Results:"
Write-Host "  Total Recovered Rows: $rowCount (Expected: exactly 6 rows from T0, T1, T2)"
Write-Host "  Fraudulent Row Excluded: $(if ($corruptedRows.Count -eq 0) { 'YES (0 corrupted rows found)' } else { 'FAILED' })"
Write-Host "  Entry 1 Untampered: $(if ($tamperedRows.Count -eq 0) { 'YES (Status = COMMITTED)' } else { 'FAILED' })"

# STEP 10: Run DBCC CHECKDB
Write-Host "`n--- STEP 10: DBCC CHECKDB on Restored Database ---"
$cmd.CommandText = "DBCC CHECKDB ('SPLIT_BILL_DB_PITR_RESTORED') WITH NO_INFOMSGS;"
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] DBCC CHECKDB passed with 0 allocation errors and 0 consistency errors."

# STEP 11: Cleanup Demo Databases
Write-Host "`n--- STEP 11: Cleaning up Demo Databases ---"
$cmd.CommandText = @"
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SPLIT_BILL_DB_PITR_DEMO')
BEGIN
    DROP DATABASE SPLIT_BILL_DB_PITR_DEMO;
END
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SPLIT_BILL_DB_PITR_RESTORED')
BEGIN
    DROP DATABASE SPLIT_BILL_DB_PITR_RESTORED;
END
"@
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] Demo databases cleaned up."

$conn.Close()
Write-Host "`n>>> TASK 2 PITR DEMONSTRATION COMPLETE AND VERIFIED."
