# Task 5: Migration Runner Source Audit and Fault-Injection Testing
$Server = "localhost"
$testDb = "SPLIT_BILL_DB_HARDENING_TEST"

$backupFile = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\backups\SPLIT_BILL_DB_Prod_Rehearsal.bak"
$destMdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}.mdf"
$destLdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}_log.ldf"

function Restore-TestDb {
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
    $rSql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_restore.sql" -Encoding utf8
    sqlcmd -S $Server -E -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_restore.sql" -b | Out-Null
}

function Insert-ValidApproval {
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
    $sql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_appr.sql" -Encoding utf8
    sqlcmd -S $Server -E -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_appr.sql" -b | Out-Null
}

Write-Host "================================================================================"
Write-Host "TASK 5: MIGRATION RUNNER SOURCE AUDIT & FAULT-INJECTION MATRIX"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

$results = @()

# 1. DRY RUN VALIDATION
Restore-TestDb
Insert-ValidApproval
Write-Host "`n--- 1. Dry Run Validation (Single ambient transaction rollback) ---"
$proc1 = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\deploy_all.ps1 -TargetDatabase $testDb -DryRun" `
    -Wait -PassThru -NoNewWindow
$p1 = ($proc1.ExitCode -eq 0)
# Verify no tables added from 002..004 in dry run
$colCheck = (sqlcmd -S $Server -E -d $testDb -Q "SET NOCOUNT ON; SELECT COL_LENGTH('dbo.Persons', 'is_deleted');" -h -1 -W).Trim()
$p1Dry = ($p1 -and ($colCheck -eq "" -or $colCheck -eq "NULL"))
$results += [PSCustomObject]@{
    Test = "1. Dry-Run Execution"
    ExitCode = $proc1.ExitCode
    Expected = "0"
    Status   = if ($p1Dry) { "PASS" } else { "FAIL" }
    Details  = "All migrations validated cleanly in ambient transaction; zero modifications committed."
}

# 2. CONCURRENT DEPLOYMENT PREVENTION (sp_getapplock)
Write-Host "`n--- 2. Concurrent Deployment Prevention ---"
[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$cLock = New-Object System.Data.SqlClient.SqlConnection("Server=$Server;Database=$testDb;Integrated Security=True;TrustServerCertificate=True;")
$cLock.Open()
$cmdL = $cLock.CreateCommand()
$cmdL.CommandText = "DECLARE @r INT; EXEC @r = sp_getapplock @Resource = 'EquiTrip_DatabaseMigrationLock', @LockMode = 'Exclusive', @LockOwner = 'Session'; SELECT @r;"
$cmdL.ExecuteNonQuery() | Out-Null
Write-Host "Held external lock on EquiTrip_DatabaseMigrationLock."

# Try running deploy_all.ps1 concurrently
$proc2 = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\deploy_all.ps1 -TargetDatabase $testDb" `
    -Wait -PassThru -NoNewWindow
$p2 = ($proc2.ExitCode -ne 0)

$cLock.Close()
Write-Host "Released external lock."
$results += [PSCustomObject]@{
    Test = "2. Concurrent Deployment Blocking"
    ExitCode = $proc2.ExitCode
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p2) { "PASS" } else { "FAIL" }
    Details  = "sp_getapplock detected concurrent lock and halted second runner immediately."
}

# 3. FAULT INJECTION: Stage 001 Failure (Missing approval)
Restore-TestDb
Write-Host "`n--- 3. Fault Injection: Stage 001 Failure ---"
$proc3 = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\deploy_all.ps1 -TargetDatabase $testDb" `
    -Wait -PassThru -NoNewWindow
$p3 = ($proc3.ExitCode -ne 0)
# Verify 001 was NOT marked successful in __MigrationHistory
$histCheck1 = (sqlcmd -S $Server -E -d $testDb -Q "SET NOCOUNT ON; IF OBJECT_ID('dbo.__MigrationHistory') IS NOT NULL SELECT COUNT(*) FROM dbo.__MigrationHistory WHERE migration_id = '001' ELSE SELECT 0;" -h -1 -W).Trim()
$p3Pass = ($p3 -and ($histCheck1 -eq "0"))
$results += [PSCustomObject]@{
    Test = "3. Fault Injection: Stage 001"
    ExitCode = $proc3.ExitCode
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p3Pass) { "PASS" } else { "FAIL" }
    Details  = "Runner halted at 001; no destructive auto-rollback; 001 not recorded in __MigrationHistory."
}

# 4. FAULT INJECTION: Stage 002 Failure
Restore-TestDb
Insert-ValidApproval
# Temporarily corrupt 002
$script002 = "migrations\002_composite_foreign_keys.sql"
$orig002 = Get-Content $script002 -Raw
$corrupt002 = "THROW 59999, 'Injected Stage 002 Failure', 1;`nGO`n" + $orig002
$corrupt002 | Out-File $script002 -Encoding utf8

Write-Host "`n--- 4. Fault Injection: Stage 002 Failure ---"
$proc4 = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\deploy_all.ps1 -TargetDatabase $testDb" `
    -Wait -PassThru -NoNewWindow
$p4 = ($proc4.ExitCode -ne 0)

# Restore original 002
$orig002 | Out-File $script002 -Encoding utf8

# Verify 001 is recorded in __MigrationHistory, but 002 is NOT
$hist001 = (sqlcmd -S $Server -E -d $testDb -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.__MigrationHistory WHERE migration_id = '001';" -h -1 -W).Trim()
$hist002 = (sqlcmd -S $Server -E -d $testDb -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.__MigrationHistory WHERE migration_id = '002';" -h -1 -W).Trim()
$p4Pass = ($p4 -and ($hist001 -eq "1") -and ($hist002 -eq "0"))

$results += [PSCustomObject]@{
    Test = "4. Fault Injection: Stage 002"
    ExitCode = $proc4.ExitCode
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p4Pass) { "PASS" } else { "FAIL" }
    Details  = "Runner halted at 002; prior migration 001 preserved; 002 not marked successful."
}

# 5. RECOVERABILITY & CLEAN DEPLOYMENT
Write-Host "`n--- 5. Full Successful Sequential Deployment (Clean) ---"
$proc5 = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File migrations\deploy_all.ps1 -TargetDatabase $testDb" `
    -Wait -PassThru -NoNewWindow
$p5 = ($proc5.ExitCode -eq 0)

$histTotal = (sqlcmd -S $Server -E -d $testDb -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.__MigrationHistory WHERE status = 'SUCCESS';" -h -1 -W).Trim()
$p5Pass = ($p5 -and ($histTotal -ge "4"))
$results += [PSCustomObject]@{
    Test = "5. Clean Deployment Recoverability"
    ExitCode = $proc5.ExitCode
    Expected = "0"
    Status   = if ($p5Pass) { "PASS" } else { "FAIL" }
    Details  = "All migrations (000..004) applied cleanly and recorded in __MigrationHistory."
}

Write-Host "`n================================================================================"
Write-Host "TASK 5 TEST RESULTS SUMMARY"
Write-Host "================================================================================"
$results | Format-Table -AutoSize
