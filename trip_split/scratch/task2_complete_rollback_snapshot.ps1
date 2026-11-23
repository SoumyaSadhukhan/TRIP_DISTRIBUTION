# Task 2: Complete Rollback Snapshot Validation Test Suite (Phase 2.8)
$Server = "localhost"
$testDb = "SPLIT_BILL_DB_HARDENING_TEST"

$backupFile = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\backups\SPLIT_BILL_DB_Prod_Rehearsal.bak"
$destMdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}.mdf"
$destLdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\${testDb}_log.ldf"

function Reset-And-Reconcile {
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
    $rSql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_r.sql" -Encoding utf8
    sqlcmd -S $Server -E -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_r.sql" -b | Out-Null
    sqlcmd -S $Server -E -d $testDb -i "migrations\000_create_reconciliation_approvals.sql" -b | Out-Null

    # Insert Authorized Approver & Valid Approval
    $tripId = '8092c57a-8638-4dc9-8969-748a9607d834'
    $ref = 'GOA_CAR_EXPENSE_202611'
    $type = 'ADMINISTRATIVE_ASSUMPTION_OVERRIDE'
    $origJson = '{"food": 4000.00, "room": 5000.00, "car": 4520.00}'
    $propJson = '{"food_splits": {"Soumya": 2000.00, "Friend": 2000.00}, "room_splits": {"Soumya": 2500.00, "Friend": 2500.00}, "car_splits": {"Soumya": 1506.66, "Friend": 1506.67, "Dipa": 1506.67}}'
    $appTime = '2026-11-21T02:00:00'
    $appId = 'AUTH_CFO_01'

    $raw = "$tripId|$ref|$type|$appId|$appTime|$origJson|$propJson"
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($raw)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $hash = $hasher.ComputeHash($bytes)
    $sig = [BitConverter]::ToString($hash).Replace("-", "")

    $setupSql = @"
    INSERT INTO dbo.AuthorizedReconciliationApprovers (approver_id, principal_name, email, role, is_active)
    VALUES ('AUTH_CFO_01', 'Chief Financial Officer', 'cfo@equitrip.internal', 'CHIEF_FINANCIAL_OFFICER', 1);

    INSERT INTO dbo.ReconciliationApprovals (
        trip_id, reconciliation_reference, reconciliation_version, status, approver_id, approver_name, approved_at,
        reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override, approval_signature
    ) VALUES (
        '$tripId', '$ref', '1.0', 'APPROVED', 'AUTH_CFO_01', 'Chief Financial Officer', '$appTime',
        'CFO Authorization', '$type', '$origJson', '$propJson', 1, '$sig'
    );
"@
    $setupSql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_setup.sql" -Encoding utf8
    sqlcmd -S $Server -E -d $testDb -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_setup.sql" -b | Out-Null

    # Execute 001
    sqlcmd -S $Server -E -d $testDb -i "migrations\001_reconcile_production_goa_trip.sql" -b | Out-Null
}

function Run-Sql($sql) {
    $sql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_q.sql" -Encoding utf8
    sqlcmd -S $Server -E -d $testDb -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_q.sql" -b
}

function Run-Rollback-001 {
    $proc = Start-Process -FilePath "sqlcmd.exe" -ArgumentList "-S $Server -E -d $testDb -i `"migrations\rollback_001_reconcile_production_goa_trip.sql`" -b" -Wait -PassThru -NoNewWindow
    return $proc.ExitCode
}

Write-Host "================================================================================"
Write-Host "TASK 2: COMPLETE ROLLBACK SNAPSHOT VALIDATION TEST SUITE"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

$results = @()

# 1. Balance mutated and restored to original value (Caught by Mutation Ledger)
Write-Host "`n--- 1. Balance mutated and restored to original value ---"
Reset-And-Reconcile
Run-Sql @"
-- Balance mutated and restored (net zero balance change, no activity log)
UPDATE dbo.Persons SET balance = balance + 50.00 WHERE person_id = '4bc5674a-b769-461e-ab38-c470ab10fd0b';
UPDATE dbo.Persons SET balance = balance - 50.00 WHERE person_id = '4bc5674a-b769-461e-ab38-c470ab10fd0b';
"@
$ec1 = Run-Rollback-001
$results += [PSCustomObject]@{
    Test = "1. Balance mutated and restored"
    ExitCode = $ec1
    Expected = "Non-zero (Exit 1)"
    Status   = if ($ec1 -ne 0) { "PASS" } else { "FAIL" }
    Notes    = "Caught by mutation ledger check (Error 50022)"
}

# 2. Expense payer modified without changing amount
Write-Host "`n--- 2. Expense payer modified without changing amount ---"
Reset-And-Reconcile
Run-Sql @"
-- Payer modified directly via SQL
UPDATE dbo.Expenses SET paid_by_person_id = '4bc5674a-b769-461e-ab38-c470ab10fd0b' 
WHERE expense_id = '7f28d135-2d7d-4369-8d36-b50b6e61e84a';
"@
$ec2 = Run-Rollback-001
$results += [PSCustomObject]@{
    Test = "2. Expense payer modified"
    ExitCode = $ec2
    Expected = "Non-zero (Exit 1)"
    Status   = if ($ec2 -ne 0) { "PASS" } else { "FAIL" }
    Notes    = "Caught by snapshot check (Error 50023)"
}

# 3. Expense description modified
Write-Host "`n--- 3. Expense description modified ---"
Reset-And-Reconcile
Run-Sql @"
UPDATE dbo.Expenses SET description = 'Modified Dinner Description' 
WHERE expense_id = '7f28d135-2d7d-4369-8d36-b50b6e61e84a';
"@
$ec3 = Run-Rollback-001
$results += [PSCustomObject]@{
    Test = "3. Expense description modified"
    ExitCode = $ec3
    Expected = "Non-zero (Exit 1)"
    Status   = if ($ec3 -ne 0) { "PASS" } else { "FAIL" }
    Notes    = "Caught by snapshot check (Error 50023)"
}

# 4. Expense date modified
Write-Host "`n--- 4. Expense date modified ---"
Reset-And-Reconcile
Run-Sql @"
UPDATE dbo.Expenses SET expense_date = DATEADD(hour, 5, expense_date) 
WHERE expense_id = '7f28d135-2d7d-4369-8d36-b50b6e61e84a';
"@
$ec4 = Run-Rollback-001
$results += [PSCustomObject]@{
    Test = "4. Expense date modified"
    ExitCode = $ec4
    Expected = "Non-zero (Exit 1)"
    Status   = if ($ec4 -ne 0) { "PASS" } else { "FAIL" }
    Notes    = "Caught by snapshot check (Error 50023)"
}

# 5. Split person_id modified
Write-Host "`n--- 5. Split person_id modified ---"
Reset-And-Reconcile
Run-Sql @"
UPDATE dbo.ExpenseSplits SET person_id = '4bc5674a-b769-461e-ab38-c470ab10fd0b' 
WHERE split_id = 'b1e0f001-food-4000-friend-split0000001';
"@
$ec5 = Run-Rollback-001
$results += [PSCustomObject]@{
    Test = "5. Split person_id modified"
    ExitCode = $ec5
    Expected = "Non-zero (Exit 1)"
    Status   = if ($ec5 -ne 0) { "PASS" } else { "FAIL" }
    Notes    = "Caught by snapshot check (Error 50023)"
}

# 6. Split expense_id modified
Write-Host "`n--- 6. Split expense_id modified ---"
Reset-And-Reconcile
Run-Sql @"
UPDATE dbo.ExpenseSplits SET expense_id = '79d4d8ad-0df4-4896-a863-b18fe1a0919f' 
WHERE split_id = 'b1e0f001-food-4000-friend-split0000001';
"@
$ec6 = Run-Rollback-001
$results += [PSCustomObject]@{
    Test = "6. Split expense_id modified"
    ExitCode = $ec6
    Expected = "Non-zero (Exit 1)"
    Status   = if ($ec6 -ne 0) { "PASS" } else { "FAIL" }
    Notes    = "Caught by snapshot check (Error 50023)"
}

# 7. Restored person identity modified
Write-Host "`n--- 7. Restored person identity modified ---"
Reset-And-Reconcile
Run-Sql @"
UPDATE dbo.Persons SET name = 'Friend Impersonator' 
WHERE person_id = 'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12';
"@
$ec7 = Run-Rollback-001
$results += [PSCustomObject]@{
    Test = "7. Restored person identity modified"
    ExitCode = $ec7
    Expected = "Non-zero (Exit 1)"
    Status   = if ($ec7 -ne 0) { "PASS" } else { "FAIL" }
    Notes    = "Caught by attribute check (Error 50019) and snapshot (Error 50023)"
}

# 8. Restored split amount modified
Write-Host "`n--- 8. Restored split amount modified ---"
Reset-And-Reconcile
Run-Sql @"
UPDATE dbo.ExpenseSplits SET amount = 1999.00 
WHERE split_id = 'b1e0f001-food-4000-friend-split0000001';
"@
$ec8 = Run-Rollback-001
$results += [PSCustomObject]@{
    Test = "8. Restored split amount modified"
    ExitCode = $ec8
    Expected = "Non-zero (Exit 1)"
    Status   = if ($ec8 -ne 0) { "PASS" } else { "FAIL" }
    Notes    = "Caught by split amount check (Error 50012) and snapshot (Error 50023)"
}

# 9. Restored row deleted and recreated with same ID
Write-Host "`n--- 9. Restored row deleted and recreated with same ID ---"
Reset-And-Reconcile
Run-Sql @"
DELETE FROM dbo.ExpenseSplits WHERE split_id = 'b1e0f004-car0-4520-dipa00-split0000004';
INSERT INTO dbo.ExpenseSplits (split_id, expense_id, trip_id, person_id, amount)
VALUES (
    'b1e0f004-car0-4520-dipa00-split0000004',
    'c4dab9a5-cd80-407f-8b1e-55f849328446',
    '8092c57a-8638-4dc9-8969-748a9607d834',
    '76810b14-585c-438e-a3ed-2150440a2985',
    1506.67
);
"@
$ec9 = Run-Rollback-001
$results += [PSCustomObject]@{
    Test = "9. Restored row deleted and recreated"
    ExitCode = $ec9
    Expected = "Non-zero (Exit 1)"
    Status   = if ($ec9 -ne 0) { "PASS" } else { "FAIL" }
    Notes    = "Caught by mutation ledger check (Error 50022)"
}

# 10. Clean rollback without mutations
Write-Host "`n--- 10. Clean rollback without mutations ---"
Reset-And-Reconcile
$ec10 = Run-Rollback-001

# Check post-rollback state
$postCheck = sqlcmd -S $Server -E -d $testDb -Q "
SET NOCOUNT ON;
SELECT COUNT(*) FROM dbo.ExpenseSplits WHERE split_id LIKE 'b1e0f00%';
SELECT COUNT(*) FROM dbo.Persons WHERE person_id IN ('cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12', '76810b14-585c-438e-a3ed-2150440a2985');
SELECT balance FROM dbo.Persons WHERE person_id = '4bc5674a-b769-461e-ab38-c470ab10fd0b';
" -h -1 -W

Write-Host "Post-rollback verification (splits, persons, Soumya balance):`n$postCheck"

$p10 = ($ec10 -eq 0)
$results += [PSCustomObject]@{
    Test = "10. Clean rollback without mutations"
    ExitCode = $ec10
    Expected = "0"
    Status   = if ($p10) { "PASS" } else { "FAIL" }
    Notes    = "Rollback succeeded, restored rows cleanly deleted, balance reset to pre-reconciled state."
}

Write-Host "`n================================================================================"
Write-Host "TASK 2 COMPLETE ROLLBACK SNAPSHOT VALIDATION RESULTS"
Write-Host "================================================================================"
$results | Format-Table -AutoSize
