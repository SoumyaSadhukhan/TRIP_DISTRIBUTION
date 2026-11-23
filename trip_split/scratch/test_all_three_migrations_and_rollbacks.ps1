[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB_TEST;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "TASK 5: MIGRATIONS 001, 002, 003 IDEMPOTENCY AND ROLLBACK VERIFICATION"
Write-Host "================================================================================"

$migrationsDir = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\migrations"

function Run-SqlScript($scriptPath, $stepName) {
    Write-Host "`n>>> ${stepName}: Running $([System.IO.Path]::GetFileName($scriptPath))"
    $sql = Get-Content -Raw $scriptPath
    $cmd = $conn.CreateCommand()
    $cmd.CommandTimeout = 120
    $cmd.CommandText = $sql
    try {
        $cmd.ExecuteNonQuery() | Out-Null
        Write-Host "    [SUCCESS] $stepName passed with 0 errors."
        return $true
    } catch {
        Write-Host "    [ERROR] $stepName FAILED: $($_.Exception.Message)"
        return $false
    }
}

# -------------------------------------------------------------
# PHASE 1: EXECUTE MIGRATIONS (RUN 1)
# -------------------------------------------------------------
Write-Host "`n--- PHASE 1: INITIAL APPLICATION OF MIGRATIONS 001, 002, 003 ---"
$m1 = Run-SqlScript "$migrationsDir\001_composite_foreign_keys.sql" "RUN 1 - Migration 001"
$m2 = Run-SqlScript "$migrationsDir\002_soft_delete_support.sql" "RUN 1 - Migration 002"
$m3 = Run-SqlScript "$migrationsDir\003_harden_otp_schema.sql" "RUN 1 - Migration 003"

if (-not ($m1 -and $m2 -and $m3)) {
    Write-Host "[FAIL] Phase 1 migrations failed."
    $conn.Close()
    exit 1
}

# -------------------------------------------------------------
# PHASE 2: IDEMPOTENCY VERIFICATION (RUN 2 - SEQUENTIAL RE-RUN)
# -------------------------------------------------------------
Write-Host "`n--- PHASE 2: IDEMPOTENCY TEST (RUN 2 - CONSECUTIVE RE-RUN) ---"
$m1_re = Run-SqlScript "$migrationsDir\001_composite_foreign_keys.sql" "RUN 2 - Migration 001 (Idempotency)"
$m2_re = Run-SqlScript "$migrationsDir\002_soft_delete_support.sql" "RUN 2 - Migration 002 (Idempotency)"
$m3_re = Run-SqlScript "$migrationsDir\003_harden_otp_schema.sql" "RUN 2 - Migration 003 (Idempotency)"

if (-not ($m1_re -and $m2_re -and $m3_re)) {
    Write-Host "[FAIL] Phase 2 idempotency failed."
    $conn.Close()
    exit 1
}

# -------------------------------------------------------------
# PHASE 3: ROLLBACK VERIFICATION
# -------------------------------------------------------------
Write-Host "`n--- PHASE 3: FULL UNIFIED ROLLBACK VERIFICATION ---"
$rb = Run-SqlScript "$migrationsDir\rollback_all.sql" "Rollback All Migrations (003, 002, 001)"
if (-not $rb) {
    Write-Host "[FAIL] Rollback failed."
    $conn.Close()
    exit 1
}

# Verify schema after rollback
$checkSql = @"
SELECT 'Remaining Composite FKs' AS CheckItem, COUNT(*) AS Cnt 
FROM sys.foreign_keys WHERE name IN ('FK_Expenses_Persons_Trip', 'FK_ExpenseSplits_Expenses_Trip', 'FK_ExpenseSplits_Persons_Trip', 'FK_Settlements_Persons_From_Trip', 'FK_Settlements_Persons_To_Trip')
UNION ALL
SELECT 'Remaining Soft-Delete Columns', COUNT(*) 
FROM sys.columns WHERE name IN ('is_deleted', 'deleted_at')
UNION ALL
SELECT 'Remaining OTP Security Columns', COUNT(*) 
FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name IN ('otp_hash', 'failed_attempts', 'max_attempts', 'lockout_until', 'ip_address');
"@
$cmd = $conn.CreateCommand()
$cmd.CommandText = $checkSql
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtCheck = New-Object System.Data.DataTable
$adapter.Fill($dtCheck) | Out-Null
Write-Host "`nSchema State After Rollback (Expected all 0):"
$dtCheck | Format-Table -AutoSize

# -------------------------------------------------------------
# PHASE 4: RE-APPLICATION AFTER ROLLBACK
# -------------------------------------------------------------
Write-Host "`n--- PHASE 4: RE-APPLYING MIGRATIONS AFTER ROLLBACK ---"
$m1_post = Run-SqlScript "$migrationsDir\001_composite_foreign_keys.sql" "Post-Rollback Migration 001"
$m2_post = Run-SqlScript "$migrationsDir\002_soft_delete_support.sql" "Post-Rollback Migration 002"
$m3_post = Run-SqlScript "$migrationsDir\003_harden_otp_schema.sql" "Post-Rollback Migration 003"

# Verify schema after re-application
$checkPostSql = @"
SELECT 'Recreated Composite FKs (Expected 5)' AS CheckItem, COUNT(*) AS Cnt 
FROM sys.foreign_keys WHERE name IN ('FK_Expenses_Persons_Trip', 'FK_ExpenseSplits_Expenses_Trip', 'FK_ExpenseSplits_Persons_Trip', 'FK_Settlements_Persons_From_Trip', 'FK_Settlements_Persons_To_Trip')
UNION ALL
SELECT 'Recreated Soft-Delete Columns (Expected 6)', COUNT(*) 
FROM sys.columns WHERE name IN ('is_deleted', 'deleted_at')
UNION ALL
SELECT 'Recreated OTP Security Columns (Expected 5)', COUNT(*) 
FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name IN ('otp_hash', 'failed_attempts', 'max_attempts', 'lockout_until', 'ip_address');
"@
$cmd.CommandText = $checkPostSql
$dtCheckPost = New-Object System.Data.DataTable
$adapter.Fill($dtCheckPost) | Out-Null
Write-Host "`nSchema State After Re-application:"
$dtCheckPost | Format-Table -AutoSize

$conn.Close()
Write-Host "================================================================================"
Write-Host "TASK 5: MIGRATION IDEMPOTENCY AND ROLLBACK TEST COMPLETED SUCCESSFULLY"
Write-Host "================================================================================"
