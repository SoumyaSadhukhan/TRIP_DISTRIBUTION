# ============================================================================
# Hardened Rollback Runner: rollback_all.ps1 (Phase 2.6)
# Features:
# - Production execution protection guard.
# - Explicit operator confirmation required (-ConfirmRollback).
# - Migration-specific / dependency-aware rollback.
# - Updates dbo.__MigrationHistory tracking table.
# - Immediate halt on error.
# ============================================================================

param(
    [string]$Server = "localhost",
    [string]$TargetDatabase = "SPLIT_BILL_DB_TEST",
    [string]$TargetMigration = "ALL",  # "ALL", "004", "003", "002", "001"
    [switch]$ConfirmRollback,
    [switch]$ConfirmProductionExecution
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================================"
Write-Host "EQUITRIP HARDENED DATABASE ROLLBACK RUNNER"
Write-Host "Target Server:    $Server"
Write-Host "Target Database:  $TargetDatabase"
Write-Host "Target Scope:     $TargetMigration"
Write-Host "Timestamp:        $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

# 1. EXPLICIT OPERATOR CONFIRMATION GUARD
if (!$ConfirmRollback) {
    Write-Host "[FATAL GUARD BLOCKED] Explicit operator confirmation is required to roll back migrations." -ForegroundColor Red
    Write-Host "Run with -ConfirmRollback to authorize rollback." -ForegroundColor Red
    exit 1
}

# 2. PRODUCTION EXECUTION GUARD
if ($TargetDatabase -eq "SPLIT_BILL_DB" -and !$ConfirmProductionExecution) {
    Write-Host "[FATAL SAFETY GUARD BLOCKED] Target is production database 'SPLIT_BILL_DB'." -ForegroundColor Red
    Write-Host "Rollback execution is blocked unless -ConfirmProductionExecution is explicitly provided." -ForegroundColor Red
    exit 1
}

[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=$Server;Database=$TargetDatabase;Integrated Security=True;TrustServerCertificate=True;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)

try {
    $conn.Open()
    Write-Host "[CONNECTED] Successfully connected to database ${TargetDatabase}."
} catch {
    Write-Host "[FATAL] Failed to connect to database ${TargetDatabase}: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 1.1 ACQUIRE EXCLUSIVE APPLICATION ROLLBACK LOCK
$lockCmd = $conn.CreateCommand()
$lockCmd.CommandText = @"
DECLARE @res INT;
EXEC @res = sp_getapplock 
    @Resource = 'EquiTrip_DatabaseMigrationLock', 
    @LockMode = 'Exclusive', 
    @LockOwner = 'Session', 
    @LockTimeout = 5000;
SELECT @res AS LockResult;
"@
$lockRes = [int]$lockCmd.ExecuteScalar()
if ($lockRes -lt 0) {
    Write-Host "[FATAL LOCK CONTENDED] Failed to acquire exclusive rollback lock (Result: $lockRes)." -ForegroundColor Red
    Write-Host "Another deployment or rollback process is currently running on ${TargetDatabase}." -ForegroundColor Red
    $conn.Close()
    exit 1
}
Write-Host "[LOCK ACQUIRED] Exclusive session lock 'EquiTrip_DatabaseMigrationLock' acquired." -ForegroundColor Green

$migrationDir = $PSScriptRoot
$allRollbacks = @(
    @{ Id = "004"; Script = "rollback_004_harden_otp_schema.sql" },
    @{ Id = "003"; Script = "rollback_003_soft_delete_support.sql" },
    @{ Id = "002"; Script = "rollback_002_composite_foreign_keys.sql" },
    @{ Id = "001"; Script = "rollback_001_reconcile_production_goa_trip.sql" }
)

# Filter scope
$rollbacksToRun = @()
if ($TargetMigration -eq "ALL") {
    $rollbacksToRun = $allRollbacks
} else {
    $matched = $allRollbacks | Where-Object { $_.Id -eq $TargetMigration }
    if (!$matched) {
        Write-Host "[FATAL] Invalid TargetMigration '$TargetMigration'. Must be ALL, 004, 003, 002, or 001." -ForegroundColor Red
        $conn.Close()
        exit 1
    }
    $rollbacksToRun = @($matched)
}

try {
    foreach ($rb in $rollbacksToRun) {
        $scriptPath = Join-Path $migrationDir $rb.Script
        if (!(Test-Path $scriptPath)) {
            Write-Host "[FATAL] Rollback script not found: $scriptPath" -ForegroundColor Red
            exit 1
        }

        Write-Host "`n>>> Running Rollback $($rb.Id): $($rb.Script)..."
        $sqlContent = Get-Content $scriptPath -Raw

        $batches = [System.Text.RegularExpressions.Regex]::Split($sqlContent, '^\s*GO\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        $stepFailed = $false
        $errorMessage = ""

        foreach ($batch in $batches) {
            $trimmed = $batch.Trim()
            if ($trimmed.Length -eq 0) { continue }

            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $trimmed
            $cmd.CommandTimeout = 120

            try {
                $cmd.ExecuteNonQuery() | Out-Null
            } catch {
                $stepFailed = $true
                $errorMessage = $_.Exception.Message
                break
            }
        }

        if ($stepFailed) {
            Write-Host "[ROLLBACK FAILED] Error in $($rb.Script): $errorMessage" -ForegroundColor Red
            Write-Host "[SAFETY HALT] Halting rollback immediately to prevent partial inconsistency." -ForegroundColor Red
            exit 1
        } else {
            # Update Tracking Table
            $histCmd = $conn.CreateCommand()
            $histCmd.CommandText = @"
            IF OBJECT_ID('dbo.__MigrationHistory', 'U') IS NOT NULL
            BEGIN
                DELETE FROM dbo.__MigrationHistory WHERE migration_id = '$($rb.Id)';
            END;
"@
            $histCmd.ExecuteNonQuery() | Out-Null
            Write-Host "[SUCCESS] Rollback $($rb.Id) completed and removed from __MigrationHistory." -ForegroundColor Green
        }
    }
} finally {
    # Release Application Rollback Lock
    try {
        if ($conn.State -eq [System.Data.ConnectionState]::Open) {
            $relCmd = $conn.CreateCommand()
            $relCmd.CommandText = "EXEC sp_releaseapplock @Resource = 'EquiTrip_DatabaseMigrationLock', @LockOwner = 'Session';"
            $relCmd.ExecuteNonQuery() | Out-Null
            Write-Host "[LOCK RELEASED] Session lock 'EquiTrip_DatabaseMigrationLock' released." -ForegroundColor Green
        }
    } catch {}
    $conn.Close()
}
