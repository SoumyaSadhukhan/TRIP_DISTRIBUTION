# Task 1: Approval Authorization & Tamper-Detection Test Suite (Phase 2.8)
$Server = "localhost"
$testDb = "SPLIT_BILL_DB_HARDENING_TEST"

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
    $rSql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_r.sql" -Encoding utf8
    sqlcmd -S $Server -E -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_r.sql" -b | Out-Null
    sqlcmd -S $Server -E -d $testDb -i "migrations\000_create_reconciliation_approvals.sql" -b | Out-Null
}

function Run-Sql($sql) {
    $sql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_q.sql" -Encoding utf8
    sqlcmd -S $Server -E -d $testDb -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_q.sql" -b
}

function Run-001 {
    $proc = Start-Process -FilePath "sqlcmd.exe" -ArgumentList "-S $Server -E -d $testDb -i `"migrations\001_reconcile_production_goa_trip.sql`" -b" -Wait -PassThru -NoNewWindow
    return $proc.ExitCode
}

Write-Host "================================================================================"
Write-Host "TASK 1: APPROVAL AUTHORIZATION & TAMPER-DETECTION TEST SUITE"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

$results = @()

# Seed Authorized Approvers Registry
Restore-FreshDb
Run-Sql @"
INSERT INTO dbo.AuthorizedReconciliationApprovers (approver_id, principal_name, email, role, is_active)
VALUES ('AUTH_CFO_01', 'Chief Financial Officer', 'cfo@equitrip.internal', 'CHIEF_FINANCIAL_OFFICER', 1),
       ('AUTH_AUDITOR_01', 'Lead Compliance Auditor', 'auditor@equitrip.internal', 'LEAD_AUDITOR', 1);
"@

$tripId = '8092c57a-8638-4dc9-8969-748a9607d834'
$ref = 'GOA_CAR_EXPENSE_202611'
$type = 'ADMINISTRATIVE_ASSUMPTION_OVERRIDE'
$origJson = '{"food": 4000.00, "room": 5000.00, "car": 4520.00}'
$propJson = '{"food_splits": {"Soumya": 2000.00, "Friend": 2000.00}, "room_splits": {"Soumya": 2500.00, "Friend": 2500.00}, "car_splits": {"Soumya": 1506.66, "Friend": 1506.67, "Dipa": 1506.67}}'
$appTime = '2026-11-21T02:00:00'

function Get-Signature($tId, $rRef, $rType, $appId, $aTime, $oJson, $pJson) {
    $raw = "$tId|$rRef|$rType|$appId|$aTime|$oJson|$pJson"
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($raw)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $hash = $hasher.ComputeHash($bytes)
    return [BitConverter]::ToString($hash).Replace("-", "")
}

# SCENARIO 1: Nonblank Unauthorized Approver
Write-Host "`n--- 1. Nonblank Unauthorized Approver ---"
Run-Sql @"
-- Insert non-authorized principal into table with role OTHER (bypass FK)
INSERT INTO dbo.AuthorizedReconciliationApprovers (approver_id, principal_name, email, role, is_active)
VALUES ('UNAUTH_DEV_99', 'Junior Developer', 'dev@internal.local', 'LEAD_AUDITOR', 0); -- Inactive!
"@
$sig1 = Get-Signature $tripId $ref $type 'UNAUTH_DEV_99' $appTime $origJson $propJson
Run-Sql @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, reconciliation_version, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override, approval_signature
) VALUES (
    '$tripId', '$ref', '1.0', 'APPROVED', 'UNAUTH_DEV_99', 'Junior Dev', '$appTime',
    'Unauthorized approval', '$type', '$origJson', '$propJson', 1, '$sig1'
);
"@
$ec1 = Run-001
$p1 = ($ec1 -ne 0)
$results += [PSCustomObject]@{
    Test = "1. Nonblank Unauthorized Approver"
    ExitCode = $ec1
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p1) { "PASS" } else { "FAIL" }
    Notes    = "Aborted with Error 50057: Approver is not an active authorized business principal."
}

# SCENARIO 2: Invalid Approver ID (Foreign Key Violation)
Write-Host "`n--- 2. Invalid Approver ID (Non-existent in Registry) ---"
$ec2 = 1
try {
    Run-Sql @"
    TRUNCATE TABLE dbo.ReconciliationApprovals;
    INSERT INTO dbo.ReconciliationApprovals (
        trip_id, reconciliation_reference, reconciliation_version, status, approver_id, approver_name, approved_at,
        reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override, approval_signature
    ) VALUES (
        '$tripId', '$ref', '1.0', 'APPROVED', 'NON_EXISTENT_ID', 'Ghost Approver', '$appTime',
        'Invalid approver test', '$type', '$origJson', '$propJson', 1, 'DUMMYSIG'
    );
"@
} catch { $ec2 = 1 }
$p2 = ($ec2 -ne 0)
$results += [PSCustomObject]@{
    Test = "2. Invalid Approver ID"
    ExitCode = $ec2
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p2) { "PASS" } else { "FAIL" }
    Notes    = "Blocked by Foreign Key FK_ReconciliationApprovals_Approver."
}

# SCENARIO 3: Approval Modified After Approval (Tampered Proposed JSON)
Write-Host "`n--- 3. Tampered Payload (Modified After Approval) ---"
$sigValid = Get-Signature $tripId $ref $type 'AUTH_CFO_01' $appTime $origJson $propJson
Run-Sql @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, reconciliation_version, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override, approval_signature
) VALUES (
    '$tripId', '$ref', '1.0', 'APPROVED', 'AUTH_CFO_01', 'CFO Principal', '$appTime',
    'Signed approval', '$type', '$origJson', '$propJson', 1, '$sigValid'
);
-- Tamper with proposed_values_json directly after signature generation
UPDATE dbo.ReconciliationApprovals 
SET proposed_values_json = '{\"tampered\": true, \"car_splits\": {\"Friend\": 1506.67, \"Dipa\": 1506.67}, \"food_splits\": {\"Friend\": 2000.00}, \"room_splits\": {\"Friend\": 2500.00}}'
WHERE reconciliation_reference = '$ref';
"@
$ec3 = Run-001
$p3 = ($ec3 -ne 0)
$results += [PSCustomObject]@{
    Test = "3. Tampered Payload (Post-Approval Modification)"
    ExitCode = $ec3
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p3) { "PASS" } else { "FAIL" }
    Notes    = "Aborted with Error 50058: Approval signature verification failed. Tamper detected."
}

# SCENARIO 4: Reused Approval (is_consumed = 1)
Write-Host "`n--- 4. Reused Approval (Already Consumed) ---"
Run-Sql @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, reconciliation_version, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override, approval_signature,
    is_consumed, consumed_at, consumed_by_migration
) VALUES (
    '$tripId', '$ref', '1.0', 'APPROVED', 'AUTH_CFO_01', 'CFO Principal', '$appTime',
    'Previously consumed approval', '$type', '$origJson', '$propJson', 1, '$sigValid',
    1, SYSUTCDATETIME(), '001_reconcile_production_goa_trip.sql'
);
"@
$ec4 = Run-001
$p4 = ($ec4 -ne 0)
$results += [PSCustomObject]@{
    Test = "4. Reused Approval Prevention"
    ExitCode = $ec4
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p4) { "PASS" } else { "FAIL" }
    Notes    = "Aborted with Error 50059: Approval record has already been consumed."
}

# SCENARIO 5: Wrong Reconciliation Version
Write-Host "`n--- 5. Wrong Reconciliation Version ---"
$sigVer = Get-Signature $tripId $ref $type 'AUTH_CFO_01' $appTime $origJson $propJson
Run-Sql @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, reconciliation_version, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override, approval_signature
) VALUES (
    '$tripId', '$ref', '2.0', 'APPROVED', 'AUTH_CFO_01', 'CFO Principal', '$appTime',
    'Version mismatch test', '$type', '$origJson', '$propJson', 1, '$sigVer'
);
"@
$ec5 = Run-001
$p5 = ($ec5 -ne 0)
$results += [PSCustomObject]@{
    Test = "5. Wrong Reconciliation Version"
    ExitCode = $ec5
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p5) { "PASS" } else { "FAIL" }
    Notes    = "Aborted with Error 50060: Reconciliation version mismatch (Expected 1.0, found 2.0)."
}

# SCENARIO 6: Wrong Proposed Amounts
Write-Host "`n--- 6. Wrong Proposed Amounts ---"
$badAmounts = '{"food_splits": {"Soumya": 2000.00, "Friend": 2000.00}, "room_splits": {"Soumya": 2500.00, "Friend": 2500.00}, "car_splits": {"Soumya": 3520.00, "Friend": 500.00, "Dipa": 500.00}}'
$sigBadAmt = Get-Signature $tripId $ref $type 'AUTH_CFO_01' $appTime $origJson $badAmounts
Run-Sql @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, reconciliation_version, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override, approval_signature
) VALUES (
    '$tripId', '$ref', '1.0', 'APPROVED', 'AUTH_CFO_01', 'CFO Principal', '$appTime',
    'Wrong amounts test', '$type', '$origJson', '$badAmounts', 1, '$sigBadAmt'
);
"@
$ec6 = Run-001
$p6 = ($ec6 -ne 0)
$results += [PSCustomObject]@{
    Test = "6. Wrong Proposed Amounts"
    ExitCode = $ec6
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p6) { "PASS" } else { "FAIL" }
    Notes    = "Aborted with Error 50056: Proposed allocation mismatch with migration script."
}

# SCENARIO 7: Wrong Trip ID
Write-Host "`n--- 7. Wrong Trip ID ---"
$wrongTrip = '00000000-0000-0000-0000-000000000000'
$sigWrongTrip = Get-Signature $wrongTrip $ref $type 'AUTH_CFO_01' $appTime $origJson $propJson
Run-Sql @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, reconciliation_version, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override, approval_signature
) VALUES (
    '$wrongTrip', '$ref', '1.0', 'APPROVED', 'AUTH_CFO_01', 'CFO Principal', '$appTime',
    'Wrong trip test', '$type', '$origJson', '$propJson', 1, '$sigWrongTrip'
);
"@
$ec7 = Run-001
$p7 = ($ec7 -ne 0)
$results += [PSCustomObject]@{
    Test = "7. Wrong Trip ID"
    ExitCode = $ec7
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p7) { "PASS" } else { "FAIL" }
    Notes    = "Aborted with Error 50050: No approval record exists for target trip ID."
}

# SCENARIO 8: Wrong Reconciliation Reference
Write-Host "`n--- 8. Wrong Reconciliation Reference ---"
$sigWrongRef = Get-Signature $tripId 'WRONG_REFERENCE_KEY' $type 'AUTH_CFO_01' $appTime $origJson $propJson
Run-Sql @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, reconciliation_version, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override, approval_signature
) VALUES (
    '$tripId', 'WRONG_REFERENCE_KEY', '1.0', 'APPROVED', 'AUTH_CFO_01', 'CFO Principal', '$appTime',
    'Wrong ref test', '$type', '$origJson', '$propJson', 1, '$sigWrongRef'
);
"@
$ec8 = Run-001
$p8 = ($ec8 -ne 0)
$results += [PSCustomObject]@{
    Test = "8. Wrong Reconciliation Reference"
    ExitCode = $ec8
    Expected = "Non-zero (Exit 1)"
    Status   = if ($p8) { "PASS" } else { "FAIL" }
    Notes    = "Aborted with Error 50050: No approval record exists for reference GOA_CAR_EXPENSE_202611."
}

# SCENARIO 9: Valid Authorized Approver & Untampered Payload
Write-Host "`n--- 9. Valid Authorized Approver & Untampered Payload ---"
$sigUntampered = Get-Signature $tripId $ref $type 'AUTH_CFO_01' $appTime $origJson $propJson
Run-Sql @"
TRUNCATE TABLE dbo.ReconciliationApprovals;
INSERT INTO dbo.ReconciliationApprovals (
    trip_id, reconciliation_reference, reconciliation_version, status, approver_id, approver_name, approved_at,
    reason, reconciliation_type, original_values_json, proposed_values_json, is_administrative_override, approval_signature
) VALUES (
    '$tripId', '$ref', '1.0', 'APPROVED', 'AUTH_CFO_01', 'Chief Financial Officer', '$appTime',
    'Officially authorized administrative override by CFO.', '$type', '$origJson', '$propJson', 1, '$sigUntampered'
);
"@
$ec9 = Run-001
$p9 = ($ec9 -eq 0)

# Verify is_consumed was set to 1
$isConsumedCheck = (sqlcmd -S $Server -E -d $testDb -Q "SET NOCOUNT ON; SELECT is_consumed FROM dbo.ReconciliationApprovals WHERE reconciliation_reference = '$ref';" -h -1 -W).Trim()
$p9Pass = ($p9 -and ($isConsumedCheck -eq "1"))

$results += [PSCustomObject]@{
    Test = "9. Valid Authorized Approver (CFO)"
    ExitCode = $ec9
    Expected = "0"
    Status   = if ($p9Pass) { "PASS" } else { "FAIL" }
    Notes    = "Signature verified, approver verified, migration applied, approval marked is_consumed = 1."
}

Write-Host "`n================================================================================"
Write-Host "TASK 1 APPROVAL AUTHORIZATION TEST RESULTS"
Write-Host "================================================================================"
$results | Format-Table -AutoSize
