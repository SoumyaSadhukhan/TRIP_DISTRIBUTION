# ============================================================================
# Hardened Migration Deployment Runner: deploy_all.ps1 (Phase 2.6)
# Strictly enforces migration sequence 001 -> 002 -> 003 -> 004
# Features:
# - Production execution protection guard.
# - Dry-run mode (-DryRun).
# - Tracking table (dbo.__MigrationHistory).
# - IMMEDIATE HALT ON FAILURE (NO AUTOMATIC DESTRUCTIVE ROLLBACK).
# - Error output and transaction status preservation.
# ============================================================================

param(
    [string]$Server = "localhost",
    [string]$TargetDatabase = "SPLIT_BILL_DB_TEST",
    [switch]$ConfirmProductionExecution,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================================"
Write-Host "EQUITRIP HARDENED DATABASE MIGRATION RUNNER"
Write-Host "Target Server:   $Server"
Write-Host "Target Database: $TargetDatabase"
Write-Host "Execution Mode:  $(if ($DryRun) { 'DRY RUN (NO COMMIT)' } else { 'LIVE EXECUTION' })"
Write-Host "Timestamp:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

# 1. PRODUCTION EXECUTION GUARD
if ($TargetDatabase -eq "SPLIT_BILL_DB" -and !$ConfirmProductionExecution) {
    Write-Host "[FATAL SAFETY GUARD BLOCKED] Target is production database 'SPLIT_BILL_DB'." -ForegroundColor Red
    Write-Host "Execution is blocked unless -ConfirmProductionExecution is explicitly provided." -ForegroundColor Red
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

# 1.1 ACQUIRE EXCLUSIVE APPLICATION DEPLOYMENT LOCK
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
    Write-Host "[FATAL LOCK CONTENDED] Failed to acquire exclusive deployment lock (Result: $lockRes)." -ForegroundColor Red
    Write-Host "Another deployment or rollback process is currently running on ${TargetDatabase}." -ForegroundColor Red
    $conn.Close()
    exit 1
}
Write-Host "[LOCK ACQUIRED] Exclusive session lock 'EquiTrip_DatabaseMigrationLock' acquired." -ForegroundColor Green

$cmd = $conn.CreateCommand()

# 2. Ensure Schema Tracking Table Exists (Skipped in Dry Run if missing)
if (!$DryRun) {
    $cmd.CommandText = @"
    IF OBJECT_ID('dbo.__MigrationHistory', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.__MigrationHistory (
            migration_id NVARCHAR(100) NOT NULL PRIMARY KEY,
            script_name NVARCHAR(260) NOT NULL,
            applied_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
            applied_by NVARCHAR(100) NOT NULL,
            execution_time_ms INT NOT NULL,
            status NVARCHAR(50) NOT NULL
        );
    END;
"@
    $cmd.ExecuteNonQuery() | Out-Null
}

$migrationDir = $PSScriptRoot
$migrations = @(
    @{ Id = "000"; Script = "000_create_reconciliation_approvals.sql"; Rollback = "" },
    @{ Id = "001"; Script = "001_reconcile_production_goa_trip.sql"; Rollback = "rollback_001_reconcile_production_goa_trip.sql" },
    @{ Id = "002"; Script = "002_composite_foreign_keys.sql";        Rollback = "rollback_002_composite_foreign_keys.sql" },
    @{ Id = "003"; Script = "003_soft_delete_support.sql";          Rollback = "rollback_003_soft_delete_support.sql" },
    @{ Id = "004"; Script = "004_harden_otp_schema.sql";            Rollback = "rollback_004_harden_otp_schema.sql" }
)

$completedMigrations = @()

# Ambient transaction for Dry-Run mode spanning all migrations
if ($DryRun) {
    Write-Host "[DRY RUN INITIALIZED] Ambient transaction opened. All modifications will be rolled back." -ForegroundColor Cyan
    $ambientCmd = $conn.CreateCommand()
    $ambientCmd.CommandText = "BEGIN TRANSACTION;"
    $ambientCmd.ExecuteNonQuery() | Out-Null
}

try {
    foreach ($m in $migrations) {
        $scriptPath = Join-Path $migrationDir $m.Script
        if (!(Test-Path $scriptPath)) {
            Write-Host "[FATAL] Migration script not found: $scriptPath" -ForegroundColor Red
            $conn.Close()
            exit 1
        }

        Write-Host "`n>>> Processing Migration $($m.Id): $($m.Script)..."
        $sqlContent = Get-Content $scriptPath -Raw

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $stepFailed = $false
        $errorMessage = ""

        # Split batches by standard GO lines
        $batches = [System.Text.RegularExpressions.Regex]::Split($sqlContent, '^\s*GO\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        try {
            foreach ($batch in $batches) {
                $trimmed = $batch.Trim()
                if ($trimmed.Length -eq 0) { continue }
                $bCmd = $conn.CreateCommand()
                $bCmd.CommandText = $trimmed
                $bCmd.CommandTimeout = 120
                $bCmd.ExecuteNonQuery() | Out-Null
            }
        } catch {
            $stepFailed = $true
            $errorMessage = $_.Exception.Message
        }

        $stopwatch.Stop()

        if ($stepFailed) {
            Write-Host "`n[MIGRATION FAILED] Error in $($m.Script): $errorMessage" -ForegroundColor Red
            if ($DryRun) {
                Write-Host "[DRY RUN ABORTED] Error encountered during dry-run validation." -ForegroundColor Red
            } else {
                Write-Host "[SAFETY HALT] Automatic rollback has been DISABLED to preserve state for operator inspection." -ForegroundColor Yellow
                Write-Host "Completed migrations prior to failure: $($completedMigrations -join ', ')" -ForegroundColor Yellow
                Write-Host "Database remains locked at failure state. To roll back explicitly, run:" -ForegroundColor Yellow
                Write-Host "  .\rollback_all.ps1 -TargetDatabase $TargetDatabase -ConfirmRollback" -ForegroundColor Yellow
            }
            if ($DryRun) {
                $rbAmb = $conn.CreateCommand()
                $rbAmb.CommandText = "IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;"
                $rbAmb.ExecuteNonQuery() | Out-Null
            }
            $conn.Close()
            exit 1
        } else {
            if (!$DryRun) {
                # Record in Migration History
                $histCmd = $conn.CreateCommand()
                $histCmd.CommandText = @"
                IF OBJECT_ID('dbo.__MigrationHistory', 'U') IS NOT NULL
                BEGIN
                    IF EXISTS (SELECT 1 FROM dbo.__MigrationHistory WHERE migration_id = '$($m.Id)')
                        UPDATE dbo.__MigrationHistory SET applied_at = SYSUTCDATETIME(), execution_time_ms = $($stopwatch.ElapsedMilliseconds), status = 'SUCCESS' WHERE migration_id = '$($m.Id)';
                    ELSE
                        INSERT INTO dbo.__MigrationHistory (migration_id, script_name, applied_by, execution_time_ms, status)
                        VALUES ('$($m.Id)', '$($m.Script)', SYSTEM_USER, $($stopwatch.ElapsedMilliseconds), 'SUCCESS');
                END;
"@
                $histCmd.ExecuteNonQuery() | Out-Null
                Write-Host "[SUCCESS] Migration $($m.Id) applied and recorded in __MigrationHistory in $($stopwatch.ElapsedMilliseconds)ms." -ForegroundColor Green
            } else {
                Write-Host "[DRY RUN VALIDATED] Migration $($m.Id) executed cleanly in $($stopwatch.ElapsedMilliseconds)ms." -ForegroundColor Cyan
            }
            $completedMigrations += $m.Id
        }
    }
} finally {
    if ($DryRun) {
        $rbAmb = $conn.CreateCommand()
        $rbAmb.CommandText = "IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;"
        $rbAmb.ExecuteNonQuery() | Out-Null
        Write-Host "`n[DRY RUN ROLLED BACK] Ambient transaction rolled back successfully. Zero modifications committed." -ForegroundColor Cyan
    }
    # Release Application Deployment Lock
    try {
        if ($conn.State -eq [System.Data.ConnectionState]::Open) {
            $relCmd = $conn.CreateCommand()
            $relCmd.CommandText = "EXEC sp_releaseapplock @Resource = 'EquiTrip_DatabaseMigrationLock', @LockOwner = 'Session';"
            $relCmd.ExecuteNonQuery() | Out-Null
            Write-Host "[LOCK RELEASED] Session lock 'EquiTrip_DatabaseMigrationLock' released." -ForegroundColor Green
        }
    } catch {}
}

Write-Host "`n================================================================================"
if ($DryRun) {
    Write-Host "[DRY RUN COMPLETE] All migrations passed validation with ZERO data modified." -ForegroundColor Cyan
} else {
    Write-Host "[DEPLOYMENT COMPLETE] All migrations applied successfully." -ForegroundColor Green
}
Write-Host "================================================================================"

$conn.Close()
