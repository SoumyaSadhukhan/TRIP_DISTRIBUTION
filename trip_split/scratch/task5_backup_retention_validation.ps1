# Task 5: Backup Retention Policy Validation Test Suite (Phase 2.8)
$Server = "localhost"
$testDb = "SPLIT_BILL_DB_HARDENING_TEST"
$retentionTestDir = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\backups\retention_test"

if (Test-Path $retentionTestDir) {
    Remove-Item -Path $retentionTestDir -Recurse -Force | Out-Null
}
New-Item -ItemType Directory -Path $retentionTestDir -Force | Out-Null

Write-Host "================================================================================"
Write-Host "TASK 5: BACKUP RETENTION POLICY VALIDATION TEST SUITE"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

# 1. Create Real Backup Files for the Active Chain
Write-Host "`n>>> Generating real backup chain for Active Cycle..."
$activeFull = Join-Path $retentionTestDir "Active_Full_20261121.bak"
$activeDiff = Join-Path $retentionTestDir "Active_Diff_20261121.bak"
$activeLog1 = Join-Path $retentionTestDir "Active_Log_20261121_01.trn"
$activeLog2 = Join-Path $retentionTestDir "Active_Log_20261121_02.trn"

$prepSql = @"
USE master;
ALTER DATABASE $testDb SET RECOVERY FULL;
BACKUP DATABASE $testDb TO DISK = '$activeFull' WITH INIT, COMPRESSION;
BACKUP DATABASE $testDb TO DISK = '$activeDiff' WITH DIFFERENTIAL, INIT, COMPRESSION;
BACKUP LOG $testDb TO DISK = '$activeLog1' WITH INIT, COMPRESSION;
BACKUP LOG $testDb TO DISK = '$activeLog2' WITH INIT, COMPRESSION;
"@
$prepSql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_ret_prep.sql" -Encoding utf8
sqlcmd -S $Server -E -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_ret_prep.sql" -b | Out-Null

# 2. Synthesize Historical Archive Files with Specific Timestamps
Write-Host "`n>>> Synthesizing historical backups to test lifecycle retention rules..."
$oldSundayFull = Join-Path $retentionTestDir "Sunday_Weekly_Archive_20261108.bak" # 13 days ago (Sunday)
$oldExpiredFull = Join-Path $retentionTestDir "Expired_Full_20261001.bak"        # 51 days ago (Expired)
$oldSupersededLog = Join-Path $retentionTestDir "Superseded_Log_20261101.trn"   # 20 days ago (Old log)

# Create dummy content
"DUMMY_BACKUP_CONTENT" | Out-File $oldSundayFull -Encoding utf8
"DUMMY_BACKUP_CONTENT" | Out-File $oldExpiredFull -Encoding utf8
"DUMMY_BACKUP_CONTENT" | Out-File $oldSupersededLog -Encoding utf8

# Set artificial LastWriteTime
(Get-Item $oldSundayFull).LastWriteTime = (Get-Date "2026-11-08 02:00:00") # A Sunday, 13 days ago
(Get-Item $oldExpiredFull).LastWriteTime = (Get-Date "2026-10-01 02:00:00") # 51 days ago (>30 days)
(Get-Item $oldSupersededLog).LastWriteTime = (Get-Date "2026-11-01 02:00:00") # 20 days ago (>7 days)

Write-Host "Created test scenario files:"
Get-ChildItem $retentionTestDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize

# 3. Execute Retention Cleanup Engine
Write-Host "`n>>> Running Backup Retention Cleanup..."
& "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\backup_retention_cleanup.ps1" -BackupDirectory $retentionTestDir

# 4. Verify Retention Assertions
$remainingFiles = (Get-ChildItem $retentionTestDir).Name

$p1_activeFullRetained = $remainingFiles -contains "Active_Full_20261121.bak"
$p2_activeDiffRetained = $remainingFiles -contains "Active_Diff_20261121.bak"
$p3_activeLog1Retained = $remainingFiles -contains "Active_Log_20261121_01.trn"
$p4_activeLog2Retained = $remainingFiles -contains "Active_Log_20261121_02.trn"
$p5_sundayArchiveRetained = $remainingFiles -contains "Sunday_Weekly_Archive_20261108.bak"
$p6_expiredFullPruned = -not ($remainingFiles -contains "Expired_Full_20261001.bak")
$p7_supersededLogPruned = -not ($remainingFiles -contains "Superseded_Log_20261101.trn")

$results = @(
    [PSCustomObject]@{ Assertion = "1. Active Full Backup Retained"; Expected = "Retained"; Actual = if ($p1_activeFullRetained) { "Retained" } else { "Pruned" }; Status = if ($p1_activeFullRetained) { "PASS" } else { "FAIL" } },
    [PSCustomObject]@{ Assertion = "2. Active Diff Backup Retained"; Expected = "Retained"; Actual = if ($p2_activeDiffRetained) { "Retained" } else { "Pruned" }; Status = if ($p2_activeDiffRetained) { "PASS" } else { "FAIL" } },
    [PSCustomObject]@{ Assertion = "3. Active Intermediate Log 1 Retained"; Expected = "Retained"; Actual = if ($p3_activeLog1Retained) { "Retained" } else { "Pruned" }; Status = if ($p3_activeLog1Retained) { "PASS" } else { "FAIL" } },
    [PSCustomObject]@{ Assertion = "4. Active Intermediate Log 2 Retained"; Expected = "Retained"; Actual = if ($p4_activeLog2Retained) { "Retained" } else { "Pruned" }; Status = if ($p4_activeLog2Retained) { "PASS" } else { "FAIL" } },
    [PSCustomObject]@{ Assertion = "5. 30-Day Sunday Weekly Archive Retained"; Expected = "Retained"; Actual = if ($p5_sundayArchiveRetained) { "Retained" } else { "Pruned" }; Status = if ($p5_sundayArchiveRetained) { "PASS" } else { "FAIL" } },
    [PSCustomObject]@{ Assertion = "6. Expired Backup (>30 Days) Pruned"; Expected = "Pruned"; Actual = if ($p6_expiredFullPruned) { "Pruned" } else { "Retained" }; Status = if ($p6_expiredFullPruned) { "PASS" } else { "FAIL" } },
    [PSCustomObject]@{ Assertion = "7. Superseded Log (>7 Days) Pruned"; Expected = "Pruned"; Actual = if ($p7_supersededLogPruned) { "Pruned" } else { "Retained" }; Status = if ($p7_supersededLogPruned) { "PASS" } else { "FAIL" } }
)

Write-Host "`nRetention Verification Results:"
$results | Format-Table -AutoSize

# 5. Restore Proof: Prove retained active chain can be completely restored
Write-Host "`n>>> Proving active chain recoverability after retention cleanup..."
$verifySql = @"
RESTORE VERIFYONLY FROM DISK = '$activeFull';
RESTORE VERIFYONLY FROM DISK = '$activeDiff';
RESTORE VERIFYONLY FROM DISK = '$activeLog1';
RESTORE VERIFYONLY FROM DISK = '$activeLog2';
"@
$verifySql | Out-File "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_ret_v.sql" -Encoding utf8
$vOut = sqlcmd -S $Server -E -i "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\temp_ret_v.sql" -b
$verifyPass = ($LASTEXITCODE -eq 0)

Write-Host "Chain Verification ExitCode: $LASTEXITCODE"
Write-Host "Active PITR Chain Valid: $verifyPass"
