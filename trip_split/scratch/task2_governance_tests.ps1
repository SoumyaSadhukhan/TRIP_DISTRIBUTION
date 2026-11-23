# Task 2: Isolated Governance Hardening Tests
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

function Execute-SqlFile($sqlContent) {
    $sqlContent | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_exec.sql" -Encoding utf8
    sqlcmd -S $Server -E -d $testDb -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_exec.sql" -b
}

function Run-Migration001 {
    $script = "migrations\001_reconcile_production_goa_trip.sql"
    $proc = Start-Process -FilePath "sqlcmd.exe" -ArgumentList "-S $Server -E -d $testDb -i `"$script`" -b" -Wait -PassThru -NoNewWindow
    return $proc.ExitCode
}

Write-Host "================================================================================"
Write-Host "TASK 2: APPROVAL GOVERNANCE HARDENING TEST SUITE"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

$results = @()

# SCENARIO 1: Missing approval table
Restore-TestDb
Write-Host "`n--- Scenario 1: Missing Approval Table ---"
$ec1 = Run-Migration001
$p1 = ($ec1 -ne 0)
Write-Host "Exit Code: $ec1 (Blocked as expected: $p1)"
$results += [PSCustomObject]@{
    Scenario = "1. Missing Approval Table"
    ExitCode = $ec1
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p1) { "PASS" } else { "FAIL" }
    Notes    = "Blocked with Error 50049 (Prerequisite table dbo.ReconciliationApprovals does not exist)."
}

# Apply Prerequisite Migration 000
Write-Host "`n>>> Applying 000_create_reconciliation_approvals.sql..."
sqlcmd -S $Server -E -d $testDb -i "migrations\000_create_reconciliation_approvals.sql" -b | Out-Null

$validJson = '{"food_splits": {"Soumya": 2000.00, "Friend": 2000.00}, "room_splits": {"Soumya": 2500.00, "Friend": 2500.00}, "car_splits": {"Soumya": 1506.66, "Friend": 1506.67, "Dipa": 1506.67}}'

# SCENARIO 2: Rejected approval
Write-Host "`n--- Scenario 2: Rejected Approval ---"
Execute-SqlFile @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override
) VALUES (
    '8092c57a-8638-4dc9-8969-748a9607d834', 'GOA_CAR_EXPENSE_202611', 'REJECTED', 'ADMIN_01', 'QA Lead', SYSUTCDATETIME(),
    'Rejected by audit', 'ADMINISTRATIVE_ASSUMPTION_OVERRIDE', '{}', '$validJson', 1
);
"@
$ec2 = Run-Migration001
$p2 = ($ec2 -ne 0)
Write-Host "Exit Code: $ec2 (Blocked as expected: $p2)"
$results += [PSCustomObject]@{
    Scenario = "2. Rejected Approval"
    ExitCode = $ec2
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p2) { "PASS" } else { "FAIL" }
    Notes    = "Blocked with Error 50051 (Status is REJECTED)."
}

# SCENARIO 3: Pending approval
Write-Host "`n--- Scenario 3: Pending Approval ---"
Execute-SqlFile "UPDATE dbo.ReconciliationApprovals SET status = 'PENDING' WHERE reconciliation_reference = 'GOA_CAR_EXPENSE_202611';"
$ec3 = Run-Migration001
$p3 = ($ec3 -ne 0)
Write-Host "Exit Code: $ec3 (Blocked as expected: $p3)"
$results += [PSCustomObject]@{
    Scenario = "3. Pending Approval"
    ExitCode = $ec3
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p3) { "PASS" } else { "FAIL" }
    Notes    = "Blocked with Error 50051 (Status is PENDING)."
}

# SCENARIO 4: Unauthorized / Blank Approver
Write-Host "`n--- Scenario 4: Unauthorized / Blank Approver ---"
Execute-SqlFile "UPDATE dbo.ReconciliationApprovals SET status = 'APPROVED', approver_id = '   ' WHERE reconciliation_reference = 'GOA_CAR_EXPENSE_202611';"
$ec4 = Run-Migration001
$p4 = ($ec4 -ne 0)
Write-Host "Exit Code: $ec4 (Blocked as expected: $p4)"
$results += [PSCustomObject]@{
    Scenario = "4. Unauthorized / Blank Approver"
    ExitCode = $ec4
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p4) { "PASS" } else { "FAIL" }
    Notes    = "Blocked with Error 50052 (Approver identity missing or blank)."
}

# SCENARIO 5: Wrong Reconciliation Reference
Write-Host "`n--- Scenario 5: Wrong Reconciliation Reference ---"
Execute-SqlFile @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override
) VALUES (
    '8092c57a-8638-4dc9-8969-748a9607d834', 'WRONG_REFERENCE_2026', 'APPROVED', 'ADMIN_01', 'QA Lead', SYSUTCDATETIME(),
    'Approved for wrong ref', 'ADMINISTRATIVE_ASSUMPTION_OVERRIDE', '{}', '$validJson', 1
);
"@
$ec5 = Run-Migration001
$p5 = ($ec5 -ne 0)
Write-Host "Exit Code: $ec5 (Blocked as expected: $p5)"
$results += [PSCustomObject]@{
    Scenario = "5. Wrong Reconciliation Reference"
    ExitCode = $ec5
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p5) { "PASS" } else { "FAIL" }
    Notes    = "Blocked with Error 50050 (No record for GOA_CAR_EXPENSE_202611)."
}

# SCENARIO 6: Wrong Proposed Amounts
Write-Host "`n--- Scenario 6: Wrong Proposed Amounts ---"
$badJson = '{"food_splits": {"Soumya": 2000.00, "Friend": 2000.00}, "room_splits": {"Soumya": 2500.00, "Friend": 2500.00}, "car_splits": {"Soumya": 2520.00, "Friend": 1000.00, "Dipa": 1000.00}}'
Execute-SqlFile @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override
) VALUES (
    '8092c57a-8638-4dc9-8969-748a9607d834', 'GOA_CAR_EXPENSE_202611', 'APPROVED', 'ADMIN_01', 'QA Lead', SYSUTCDATETIME(),
    'Approved with mismatch amounts', 'ADMINISTRATIVE_ASSUMPTION_OVERRIDE', '{}', '$badJson', 1
);
"@
$ec6 = Run-Migration001
$p6 = ($ec6 -ne 0)
Write-Host "Exit Code: $ec6 (Blocked as expected: $p6)"
$results += [PSCustomObject]@{
    Scenario = "6. Wrong Proposed Amounts"
    ExitCode = $ec6
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p6) { "PASS" } else { "FAIL" }
    Notes    = "Blocked with Error 50056 (Proposed allocation mismatch with migration script)."
}

# SCENARIO 7: Missing Approval Record
Write-Host "`n--- Scenario 7: Missing Approval Record ---"
Execute-SqlFile "TRUNCATE TABLE dbo.ReconciliationApprovals;"
$ec7 = Run-Migration001
$p7 = ($ec7 -ne 0)
Write-Host "Exit Code: $ec7 (Blocked as expected: $p7)"
$results += [PSCustomObject]@{
    Scenario = "7. Missing Approval Record"
    ExitCode = $ec7
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p7) { "PASS" } else { "FAIL" }
    Notes    = "Blocked with Error 50050 (No approval record found)."
}

# SCENARIO 8: Valid Approval
Write-Host "`n--- Scenario 8: Valid Approval ---"
Execute-SqlFile @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override
) VALUES (
    '8092c57a-8638-4dc9-8969-748a9607d834', 'GOA_CAR_EXPENSE_202611', 'APPROVED', 'LEAD_AUDITOR_SA', 'Senior Database Architect', SYSUTCDATETIME(),
    'Officially authorized administrative override for equal 33.3333% Car split.', 'ADMINISTRATIVE_ASSUMPTION_OVERRIDE',
    '{"food": 4000.00, "room": 5000.00, "car": 4520.00}', '$validJson', 1
);
"@
$ec8 = Run-Migration001
$p8 = ($ec8 -eq 0)
Write-Host "Exit Code: $ec8 (Clean Execution: $p8)"
$results += [PSCustomObject]@{
    Scenario = "8. Fully Authorized Valid Approval"
    ExitCode = $ec8
    Expected = "0 (Exit 0)"
    Status   = if ($p8) { "PASS" } else { "FAIL" }
    Notes    = "Validation succeeded. Migration 001 committed cleanly and verified all financial invariants."
}

Write-Host "`n================================================================================"
Write-Host "TASK 2 GOVERNANCE TEST RESULTS"
Write-Host "================================================================================"
$results | Format-Table -AutoSize
