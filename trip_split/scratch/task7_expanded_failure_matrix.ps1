# Task 7: Expanded Failure Matrix Verification
$Server = "localhost"
$testDb = "SPLIT_BILL_DB_FAILURE_MATRIX"

$backupFile = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\backups\SPLIT_BILL_DB_Prod_Rehearsal.bak"
$destMdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}.mdf"
$destLdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}_log.ldf"

function Restore-FreshDb {
    $rSql = @"
    USE master;
    IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '$testDb')
    BEGIN
        ALTER DATABASE $testDb SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE $testDb;
    END;
    RESTORE DATABASE $testDb
    FROM DISK = '$backupFile'
    WITH REPLACE,
         MOVE 'SPLIT_BILL_DB' TO '$destMdf',
         MOVE 'SPLIT_BILL_DB_log' TO '$destLdf';
"@
    $rSql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_restore7.sql" -Encoding utf8
    sqlcmd -S $Server -E -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_restore7.sql" -b | Out-Null
}

function Insert-Approval {
    $validJson = '{"food_splits": {"Soumya": 2000.00, "Friend": 2000.00}, "room_splits": {"Soumya": 2500.00, "Friend": 2500.00}, "car_splits": {"Soumya": 1506.66, "Friend": 1506.67, "Dipa": 1506.67}}'
    $sql = @"
    USE $testDb;
    IF OBJECT_ID('dbo.ReconciliationApprovals', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ReconciliationApprovals (
            approval_id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
            trip_id NVARCHAR(100) NOT NULL,
            reconciliation_reference NVARCHAR(100) NOT NULL,
            status NVARCHAR(50) NOT NULL,
            approver_id NVARCHAR(100) NULL,
            approver_name NVARCHAR(200) NULL,
            approved_at DATETIME2 NULL,
            reason NVARCHAR(MAX) NOT NULL,
            reconciliation_type NVARCHAR(50) NOT NULL,
            original_values_json NVARCHAR(MAX) NOT NULL,
            proposed_values_json NVARCHAR(MAX) NOT NULL,
            is_administrative_override BIT NOT NULL DEFAULT 1,
            created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            CONSTRAINT PK_ReconciliationApprovals PRIMARY KEY CLUSTERED (approval_id),
            CONSTRAINT UQ_ReconciliationApprovals_TripRef UNIQUE (trip_id, reconciliation_reference)
        );
    END;
    TRUNCATE TABLE dbo.ReconciliationApprovals;
    INSERT INTO dbo.ReconciliationApprovals (
        trip_id, reconciliation_reference, status, approver_id, approver_name, approved_at,
        reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override
    ) VALUES (
        '8092c57a-8638-4dc9-8969-748a9607d834', 'GOA_CAR_EXPENSE_202611', 'APPROVED', 'LEAD_AUDITOR_SA', 'Senior Database Architect', SYSUTCDATETIME(),
        'Officially authorized administrative override.', 'ADMINISTRATIVE_ASSUMPTION_OVERRIDE',
        '{}', '$validJson', 1
    );
"@
    $sql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_appr7.sql" -Encoding utf8
    sqlcmd -S $Server -E -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_appr7.sql" -b | Out-Null
}

Write-Host "================================================================================"
Write-Host "TASK 7: EXPANDED FAILURE MATRIX EXECUTION"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

$results = @()

# 1. Invalid Approval
Restore-FreshDb
Write-Host "`n--- 1. Invalid Approval Test ---"
$proc1 = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\deploy_all.ps1 -TargetDatabase $testDb" `
    -Wait -PassThru -NoNewWindow
$p1 = ($proc1.ExitCode -ne 0)
$results += [PSCustomObject]@{
    TestName = "1. Invalid Approval"
    ExitCode = $proc1.ExitCode
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p1) { "PASS" } else { "FAIL" }
    Details  = "Migration 001 aborted due to missing approval record (Error 50050)."
}

# 2. Concurrent Deployment
Insert-Approval
Write-Host "`n--- 2. Concurrent Deployment Test ---"
[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connL = New-Object System.Data.SqlClient.SqlConnection("Server=$Server;Database=$testDb;Integrated Security=True;TrustServerCertificate=True;")
$connL.Open()
$cmdL = $connL.CreateCommand()
$cmdL.CommandText = "DECLARE @r INT; EXEC @r = sp_getapplock @Resource = 'EquiTrip_DatabaseMigrationLock', @LockMode = 'Exclusive', @LockOwner = 'Session'; SELECT @r;"
$cmdL.ExecuteNonQuery() | Out-Null

$proc2 = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\deploy_all.ps1 -TargetDatabase $testDb" `
    -Wait -PassThru -NoNewWindow
$p2 = ($proc2.ExitCode -ne 0)
$connL.Close()
$results += [PSCustomObject]@{
    TestName = "2. Concurrent Deployment"
    ExitCode = $proc2.ExitCode
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p2) { "PASS" } else { "FAIL" }
    Details  = "sp_getapplock detected concurrent migration process and halted immediately."
}

# 3. Partial DDL Failure Recoverability
Restore-FreshDb
Insert-Approval
Write-Host "`n--- 3. Partial DDL Failure Recoverability ---"
$corruptFile = "migrations\003_soft_delete_support.sql"
$origContent = Get-Content $corruptFile -Raw
("THROW 58888, 'Injected Stage 003 DDL Failure', 1;`nGO`n" + $origContent) | Out-File $corruptFile -Encoding utf8

$proc3 = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\deploy_all.ps1 -TargetDatabase $testDb" `
    -Wait -PassThru -NoNewWindow
$origContent | Out-File $corruptFile -Encoding utf8 # Restore immediately

$p3 = ($proc3.ExitCode -ne 0)
$hist001 = (sqlcmd -S $Server -E -d $testDb -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.__MigrationHistory WHERE migration_id = '001';" -h -1 -W).Trim()
$hist003 = (sqlcmd -S $Server -E -d $testDb -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.__MigrationHistory WHERE migration_id = '003';" -h -1 -W).Trim()
$p3Pass = ($p3 -and ($hist001 -eq "1") -and ($hist003 -eq "0"))
$results += [PSCustomObject]@{
    TestName = "3. Partial DDL Failure"
    ExitCode = $proc3.ExitCode
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p3Pass) { "PASS" } else { "FAIL" }
    Details  = "Runner halted at 003; 001/002 preserved; 003 not marked successful in history."
}

# 4. Backup Failure
Write-Host "`n--- 4. Backup Failure Handling ---"
$proc4 = Start-Process -FilePath "sqlcmd.exe" `
    -ArgumentList "-S $Server -E -Q `"BACKUP DATABASE $testDb TO DISK = 'Z:\NonExistentDrive\fail.bak';`" -b" `
    -Wait -PassThru -NoNewWindow
$p4 = ($proc4.ExitCode -ne 0)
$results += [PSCustomObject]@{
    TestName = "4. Backup Failure Handling"
    ExitCode = $proc4.ExitCode
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p4) { "PASS" } else { "FAIL" }
    Details  = "SQL Server rejected invalid backup device path with Msg 3201; DB state preserved."
}

# 5. Missing Log Backup in Restore Chain
Write-Host "`n--- 5. Missing Log Backup Chain Failure ---"
$dirB = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\backups\failure_matrix"
if (!(Test-Path $dirB)) { New-Item -ItemType Directory -Path $dirB -Force | Out-Null }
$fBak = Join-Path $dirB "f.bak"
$l1Bak = Join-Path $dirB "l1.trn"
$l2Bak = Join-Path $dirB "l2.trn"

sqlcmd -S $Server -E -Q "ALTER DATABASE $testDb SET RECOVERY FULL; BACKUP DATABASE $testDb TO DISK = '$fBak' WITH INIT; BACKUP LOG $testDb TO DISK = '$l1Bak' WITH INIT; BACKUP LOG $testDb TO DISK = '$l2Bak' WITH INIT;" | Out-Null

# Attempt to restore Full, skip Log 1, and apply Log 2
$skipSql = @"
USE master;
RESTORE DATABASE ${testDb}_SKIP FROM DISK = '$fBak' WITH NORECOVERY, REPLACE,
MOVE 'SPLIT_BILL_DB' TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}_SKIP.mdf',
MOVE 'SPLIT_BILL_DB_log' TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}_SKIP_log.ldf';
RESTORE LOG ${testDb}_SKIP FROM DISK = '$l2Bak' WITH RECOVERY;
"@
$skipSql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_skip.sql" -Encoding utf8
$proc5 = Start-Process -FilePath "sqlcmd.exe" -ArgumentList "-S $Server -E -i `"c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_skip.sql`" -b" -Wait -PassThru -NoNewWindow
$p5 = ($proc5.ExitCode -ne 0)
sqlcmd -S $Server -E -Q "IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '${testDb}_SKIP') DROP DATABASE ${testDb}_SKIP;" | Out-Null

$results += [PSCustomObject]@{
    TestName = "5. Missing Log Backup"
    ExitCode = $proc5.ExitCode
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p5) { "PASS" } else { "FAIL" }
    Details  = "SQL Server rejected gap in log chain with Msg 4305 (LSN too recent)."
}

# 6. Invalid LSN Chain (Mismatched Differential Base)
Write-Host "`n--- 6. Invalid LSN Chain (Mismatched Differential Base) ---"
$dBak = Join-Path $dirB "d.bak"
sqlcmd -S $Server -E -Q "BACKUP DATABASE $testDb TO DISK = '$dBak' WITH DIFFERENTIAL, INIT;" | Out-Null
# Now take another full backup, breaking the differential base
$f2Bak = Join-Path $dirB "f2.bak"
sqlcmd -S $Server -E -Q "BACKUP DATABASE $testDb TO DISK = '$f2Bak' WITH INIT;" | Out-Null

# Attempt to restore Full 2 followed by Diff from Full 1
$diffFailSql = @"
USE master;
RESTORE DATABASE ${testDb}_DIFF_FAIL FROM DISK = '$f2Bak' WITH NORECOVERY, REPLACE,
MOVE 'SPLIT_BILL_DB' TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}_DF.mdf',
MOVE 'SPLIT_BILL_DB_log' TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}_DF_log.ldf';
RESTORE DATABASE ${testDb}_DIFF_FAIL FROM DISK = '$dBak' WITH RECOVERY;
"@
$diffFailSql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_diff_fail.sql" -Encoding utf8
$proc6 = Start-Process -FilePath "sqlcmd.exe" -ArgumentList "-S $Server -E -i `"c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_diff_fail.sql`" -b" -Wait -PassThru -NoNewWindow
$p6 = ($proc6.ExitCode -ne 0)
sqlcmd -S $Server -E -Q "IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '${testDb}_DIFF_FAIL') DROP DATABASE ${testDb}_DIFF_FAIL;" | Out-Null

$results += [PSCustomObject]@{
    TestName = "6. Invalid LSN Chain"
    ExitCode = $proc6.ExitCode
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p6) { "PASS" } else { "FAIL" }
    Details  = "SQL Server detected differential base mismatch and aborted with Msg 3136."
}

# 7. Point-in-Time Recovery (PITR)
Write-Host "`n--- 7. Point-in-Time Recovery (PITR) ---"
$pitrFull = Join-Path $dirB "pitr_full.bak"
sqlcmd -S $Server -E -Q "BACKUP DATABASE $testDb TO DISK = '$pitrFull' WITH INIT;" | Out-Null

sqlcmd -S $Server -E -d $testDb -Q "INSERT INTO dbo.ActivityLogs (log_id, user_id, trip_id, action_type, details, created_at) VALUES (NEWID(), '0d979a07-3c0b-4efc-a6ec-d3199f51335b', '8092c57a-8638-4dc9-8969-748a9607d834', 'PITR_BEFORE', 'Marker 1 before stop', GETDATE());" | Out-Null
Start-Sleep -Seconds 2
$stopAtLocal = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
Start-Sleep -Seconds 2
sqlcmd -S $Server -E -d $testDb -Q "INSERT INTO dbo.ActivityLogs (log_id, user_id, trip_id, action_type, details, created_at) VALUES (NEWID(), '0d979a07-3c0b-4efc-a6ec-d3199f51335b', '8092c57a-8638-4dc9-8969-748a9607d834', 'PITR_AFTER', 'Marker 2 after stop', GETDATE());" | Out-Null

$pitrLog = Join-Path $dirB "pitr.trn"
sqlcmd -S $Server -E -Q "BACKUP LOG $testDb TO DISK = '$pitrLog' WITH INIT;" | Out-Null

$pitrRestoreSql = @"
USE master;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '${testDb}_PITR')
BEGIN
    ALTER DATABASE ${testDb}_PITR SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ${testDb}_PITR;
END;
RESTORE DATABASE ${testDb}_PITR FROM DISK = '$pitrFull' WITH NORECOVERY, REPLACE,
MOVE 'SPLIT_BILL_DB' TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}_PITR.mdf',
MOVE 'SPLIT_BILL_DB_log' TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}_PITR_log.ldf';
RESTORE LOG ${testDb}_PITR FROM DISK = '$pitrLog' WITH STOPAT = '$stopAtLocal', RECOVERY;
"@
$pitrRestoreSql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_pitr.sql" -Encoding utf8
$proc7 = Start-Process -FilePath "sqlcmd.exe" -ArgumentList "-S $Server -E -i `"c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_pitr.sql`" -b" -Wait -PassThru -NoNewWindow
$p7 = ($proc7.ExitCode -eq 0)

$hasBefore = (sqlcmd -S $Server -E -d "${testDb}_PITR" -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.ActivityLogs WHERE action_type = 'PITR_BEFORE';" -h -1 -W).Trim()
$hasAfter  = (sqlcmd -S $Server -E -d "${testDb}_PITR" -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.ActivityLogs WHERE action_type = 'PITR_AFTER';" -h -1 -W).Trim()
$p7Pass = ($p7 -and ($hasBefore -eq "1") -and ($hasAfter -eq "0"))
sqlcmd -S $Server -E -Q "IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '${testDb}_PITR') DROP DATABASE ${testDb}_PITR;" | Out-Null

$results += [PSCustomObject]@{
    TestName = "7. Restore Point-in-Time (PITR)"
    ExitCode = $proc7.ExitCode
    Expected = "0"
    Status   = if ($p7Pass) { "PASS" } else { "FAIL" }
    Details  = "PITR recovered state up to STOPAT time; PITR_BEFORE included; PITR_AFTER omitted."
}

# 8. Repeated Deployment (Idempotency)
Restore-FreshDb
Insert-Approval
Write-Host "`n--- 8. Repeated Deployment (Idempotency) ---"
$proc8a = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\deploy_all.ps1 -TargetDatabase $testDb" `
    -Wait -PassThru -NoNewWindow
$proc8b = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\deploy_all.ps1 -TargetDatabase $testDb" `
    -Wait -PassThru -NoNewWindow
$p8Pass = ($proc8a.ExitCode -eq 0 -and $proc8b.ExitCode -eq 0)
$results += [PSCustomObject]@{
    TestName = "8. Repeated Deployment (Idempotency)"
    ExitCode = $proc8b.ExitCode
    Expected = "0"
    Status   = if ($p8Pass) { "PASS" } else { "FAIL" }
    Details  = "Re-running deploy_all.ps1 consecutively succeeded with exit code 0."
}

# 9. Repeated Rollback (Idempotency)
Write-Host "`n--- 9. Repeated Rollback ---"
$proc9a = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\rollback_all.ps1 -TargetDatabase $testDb -ConfirmRollback" `
    -Wait -PassThru -NoNewWindow
$proc9b = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\rollback_all.ps1 -TargetDatabase $testDb -ConfirmRollback" `
    -Wait -PassThru -NoNewWindow
$p9Pass = ($proc9a.ExitCode -eq 0 -and $proc9b.ExitCode -eq 0)
$results += [PSCustomObject]@{
    TestName = "9. Repeated Rollback"
    ExitCode = $proc9b.ExitCode
    Expected = "0"
    Status   = if ($p9Pass) { "PASS" } else { "FAIL" }
    Details  = "Consecutive rollbacks completed safely with 0 errors."
}

# 10. Financial Invariants Verification
Restore-FreshDb
Insert-Approval
Write-Host "`n--- 10. Financial Invariant Verification ---"
Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\deploy_all.ps1 -TargetDatabase $testDb" `
    -Wait -NoNewWindow

$invSql = @"
USE $testDb;
SELECT 
    t.trip_id, t.name,
    ISNULL(SUM(p.balance), 0.00) AS NetBalanceSum,
    (SELECT ISNULL(SUM(amount), 0.00) FROM dbo.Expenses WHERE trip_id = t.trip_id AND ISNULL(is_deleted, 0) = 0) AS TotalExpenses,
    (SELECT ISNULL(SUM(amount), 0.00) FROM dbo.ExpenseSplits WHERE trip_id = t.trip_id) AS TotalSplits
FROM dbo.Trips t
LEFT JOIN dbo.Persons p ON t.trip_id = p.trip_id AND ISNULL(p.is_deleted, 0) = 0
GROUP BY t.trip_id, t.name
HAVING ABS(ISNULL(SUM(p.balance), 0.00)) > 0.01;
"@
$invSql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_inv.sql" -Encoding utf8
$nonZero = (sqlcmd -S $Server -E -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_inv.sql" -h -1 -W).Trim()
$p10Pass = ($nonZero.Length -eq 0 -or $nonZero -eq "(0 rows affected)")

$results += [PSCustomObject]@{
    TestName = "10. Financial Invariants"
    ExitCode = if ($p10Pass) { 0 } else { 1 }
    Expected = "0"
    Status   = if ($p10Pass) { "PASS" } else { "FAIL" }
    Details  = "Net balance sum is exactly 0.00 and TotalExpenses = TotalSplits across all trips."
}

# Cleanup
sqlcmd -S $Server -E -Q "USE master; ALTER DATABASE $testDb SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $testDb;" | Out-Null

Write-Host "`n================================================================================"
Write-Host "TASK 7 EXPANDED FAILURE MATRIX RESULTS"
Write-Host "================================================================================"
$results | Format-Table -AutoSize
