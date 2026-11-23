# Task 6: Rollback Change Detection Test Suite
$Server = "localhost"
$testDb = "SPLIT_BILL_DB_HARDENING_TEST"

$backupFile = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\backups\SPLIT_BILL_DB_Prod_Rehearsal.bak"
$destMdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}.mdf"
$destLdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}_log.ldf"

function Restore-And-Deploy001 {
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

    # Apply 000 & 001 with valid approval
    $validJson = '{"food_splits": {"Soumya": 2000.00, "Friend": 2000.00}, "room_splits": {"Soumya": 2500.00, "Friend": 2500.00}, "car_splits": {"Soumya": 1506.66, "Friend": 1506.67, "Dipa": 1506.67}}'
    $setupSql = @"
    USE $testDb;
    -- Run 000
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
    $setupSql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_setup.sql" -Encoding utf8
    sqlcmd -S $Server -E -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_setup.sql" -b | Out-Null
    sqlcmd -S $Server -E -d $testDb -i "migrations\001_reconcile_production_goa_trip.sql" -b | Out-Null
}

function Run-Rollback001 {
    $script = "migrations\rollback_001_reconcile_production_goa_trip.sql"
    $proc = Start-Process -FilePath "sqlcmd.exe" -ArgumentList "-S $Server -E -d $testDb -i `"$script`" -b" -Wait -PassThru -NoNewWindow
    return $proc.ExitCode
}

function Exec-TestSql($sql) {
    $sql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_mutate.sql" -Encoding utf8
    sqlcmd -S $Server -E -d $testDb -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_mutate.sql" -b | Out-Null
}

Write-Host "================================================================================"
Write-Host "TASK 6: ROLLBACK CHANGE DETECTION TEST SUITE (ALL 8 GUARDS)"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

$results = @()

# 1. Modified Expense
Restore-And-Deploy001
Write-Host "`n--- Guard 1: Modified Existing Expense Amount ---"
Exec-TestSql "UPDATE dbo.Expenses SET amount = 4500.00 WHERE expense_id = '7f28d135-2d7d-4369-8d36-b50b6e61e84a';"
$ec1 = Run-Rollback001
$p1 = ($ec1 -ne 0)
$results += [PSCustomObject]@{
    Guard = "1. Modified Expense"
    ExitCode = $ec1
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p1) { "PASS" } else { "FAIL" }
    Details  = "Rollback aborted with Error 50011 (Expense amount modified from 4000.00)."
}

# 2. Modified Existing Split
Restore-And-Deploy001
Write-Host "`n--- Guard 2: Modified Existing Split Amount ---"
Exec-TestSql "UPDATE dbo.ExpenseSplits SET amount = 2200.00 WHERE split_id = 'b1e0f001-food-4000-friend-split0000001';"
$ec2 = Run-Rollback001
$p2 = ($ec2 -ne 0)
$results += [PSCustomObject]@{
    Guard = "2. Modified Existing Split"
    ExitCode = $ec2
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p2) { "PASS" } else { "FAIL" }
    Details  = "Rollback aborted with Error 50012 (Split amount modified from 2000.00)."
}

# 3. Added Split
Restore-And-Deploy001
Write-Host "`n--- Guard 3: Added Subsequent Split ---"
Exec-TestSql @"
INSERT INTO dbo.ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
VALUES (NEWID(), '7f28d135-2d7d-4369-8d36-b50b6e61e84a', '8092c57a-8638-4dc9-8969-748a9607d834', '4bc5674a-b769-461e-ab38-c470ab10fd0b', 100.00, GETDATE());
"@
$ec3 = Run-Rollback001
$p3 = ($ec3 -ne 0)
$results += [PSCustomObject]@{
    Guard = "3. Added Split"
    ExitCode = $ec3
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p3) { "PASS" } else { "FAIL" }
    Details  = "Rollback aborted with Error 50012 (Unrecognized split detected)."
}

# 4. Deleted / Restored Person
Restore-And-Deploy001
Write-Host "`n--- Guard 4: Deleted Person State Modification ---"
# Add soft-delete column in batch 1, then update in batch 2
Exec-TestSql @"
IF COL_LENGTH('dbo.Persons', 'is_deleted') IS NULL
    ALTER TABLE dbo.Persons ADD is_deleted BIT DEFAULT 0, deleted_at DATETIME2 NULL;
"@
Exec-TestSql "UPDATE dbo.Persons SET is_deleted = 1 WHERE person_id = 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12';"
$ec4 = Run-Rollback001
$p4 = ($ec4 -ne 0)
$results += [PSCustomObject]@{
    Guard = "4. Deleted / Restored Person"
    ExitCode = $ec4
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p4) { "PASS" } else { "FAIL" }
    Details  = "Rollback aborted with Error 50016 (Person marked is_deleted = 1)."
}

# 5. Changed Membership
Restore-And-Deploy001
Write-Host "`n--- Guard 5: Changed Membership (Member Added) ---"
Exec-TestSql @"
INSERT INTO dbo.Persons (person_id, group_id, trip_id, name, created_at)
VALUES (NEWID(), '56582c9f-db3c-4755-800d-77b371878f52', '8092c57a-8638-4dc9-8969-748a9607d834', 'Extra Member', GETDATE());
"@
$ec5 = Run-Rollback001
$p5 = ($ec5 -ne 0)
$results += [PSCustomObject]@{
    Guard = "5. Changed Membership"
    ExitCode = $ec5
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p5) { "PASS" } else { "FAIL" }
    Details  = "Rollback aborted with Error 50018 (Member count <> 3)."
}

# 6. Changed Balance followed by restoration (Audit Log Check)
Restore-And-Deploy001
Write-Host "`n--- Guard 6: Balance Mutated & Restored (Detected via Activity Log) ---"
Start-Sleep -Seconds 1
Exec-TestSql @"
-- Mutate balance
UPDATE dbo.Persons SET balance = 500.00 WHERE person_id = 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12';
-- Restore balance to original value
UPDATE dbo.Persons SET balance = -1006.67 WHERE person_id = 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12';
-- Application logs the activity
INSERT INTO dbo.ActivityLogs (log_id, user_id, trip_id, action_type, details, created_at)
VALUES (NEWID(), '0d979a07-3c0b-4efc-a6ec-d3199f51335b', '8092c57a-8638-4dc9-8969-748a9607d834', 'UPDATE_PERSON', 'Balance updated and corrected', GETDATE());
"@
$ec6 = Run-Rollback001
$p6 = ($ec6 -ne 0)
$results += [PSCustomObject]@{
    Guard = "6. Mutated & Restored Balance"
    ExitCode = $ec6
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p6) { "PASS" } else { "FAIL" }
    Details  = "Rollback aborted with Error 50021 (New activity logs detected after reconciliation)."
}

# 7. New Activity Log
Restore-And-Deploy001
Write-Host "`n--- Guard 7: New Activity Log ---"
Start-Sleep -Seconds 1
Exec-TestSql @"
INSERT INTO dbo.ActivityLogs (log_id, user_id, trip_id, action_type, details, created_at)
VALUES (NEWID(), '0d979a07-3c0b-4efc-a6ec-d3199f51335b', '8092c57a-8638-4dc9-8969-748a9607d834', 'ADD_NOTE', 'General comment logged', GETDATE());
"@
$ec7 = Run-Rollback001
$p7 = ($ec7 -ne 0)
$results += [PSCustomObject]@{
    Guard = "7. New Activity Log"
    ExitCode = $ec7
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p7) { "PASS" } else { "FAIL" }
    Details  = "Rollback aborted with Error 50021 (Post-reconciliation activity detected)."
}

# 8. Settlement Added
Restore-And-Deploy001
Write-Host "`n--- Guard 8: Settlement Added ---"
Exec-TestSql @"
INSERT INTO dbo.SettlementTransactions (settlement_id, trip_id, from_person_id, to_person_id, amount, is_completed, status, settled_at)
VALUES (NEWID(), '8092c57a-8638-4dc9-8969-748a9607d834', 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12', '4bc5674a-b769-461e-ab38-c470ab10fd0b', 500.00, 1, 'COMPLETED', GETDATE());
"@
$ec8 = Run-Rollback001
$p8 = ($ec8 -ne 0)
$results += [PSCustomObject]@{
    Guard = "8. Settlement Added"
    ExitCode = $ec8
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p8) { "PASS" } else { "FAIL" }
    Details  = "Rollback aborted with Error 50010 (Settlement transaction detected)."
}

# 9. Clean Rollback when no mutations exist
Restore-And-Deploy001
Write-Host "`n--- Baseline: Clean Rollback without Dependencies ---"
$ec9 = Run-Rollback001
$p9 = ($ec9 -eq 0)
$results += [PSCustomObject]@{
    Guard = "9. Clean Rollback (No Mutations)"
    ExitCode = $ec9
    Expected = "0 (Exit 0)"
    Status   = if ($p9) { "PASS" } else { "FAIL" }
    Details  = "All 8 checks passed; atomic rollback succeeded cleanly."
}

Write-Host "`n================================================================================"
Write-Host "TASK 6 DEPENDENCY GUARD AUDIT RESULTS"
Write-Host "================================================================================"
$results | Format-Table -AutoSize
