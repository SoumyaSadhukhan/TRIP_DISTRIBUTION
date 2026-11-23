# ============================================================================
# Backup Retention & PITR Chain Lifecycle Management
# Policy:
#   - 7-Day Continuous Point-In-Time Recovery (PITR)
#   - 30-Day Weekly Full Backup Archival
#   - Strict Chain Preservation: Refuses to delete any log or diff file belonging
#     to the active recovery chain.
# ============================================================================
param(
    [string]$BackupDirectory = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\backups",
    [int]$ContinuousRetentionDays = 7,
    [int]$WeeklyRetentionDays = 30,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================================"
Write-Host "BACKUP RETENTION CLEANUP ENGINE"
Write-Host "Backup Directory:         $BackupDirectory"
Write-Host "Continuous PITR Window:   $ContinuousRetentionDays days"
Write-Host "Weekly Archival Window:   $WeeklyRetentionDays days"
Write-Host "Mode:                     $(if ($WhatIf) { 'WHAT-IF (SIMULATION)' } else { 'LIVE PRUNING' })"
Write-Host "Timestamp:                $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

if (!(Test-Path $BackupDirectory)) {
    Write-Host "Backup directory does not exist: $BackupDirectory" -ForegroundColor Yellow
    exit 0
}

$files = Get-ChildItem -Path $BackupDirectory -File | Where-Object { $_.Extension -in '.bak', '.trn' }

if ($files.Count -eq 0) {
    Write-Host "No backup files found in $BackupDirectory."
    exit 0
}

# Identify files by type
$fullBackups = $files | Where-Object { $_.Name -like "*Full*" -or ($_.Extension -eq ".bak" -and $_.Name -notlike "*Diff*") } | Sort-Object LastWriteTime -Descending
$diffBackups = $files | Where-Object { $_.Name -like "*Diff*" } | Sort-Object LastWriteTime -Descending
$logBackups  = $files | Where-Object { $_.Extension -eq ".trn" -or $_.Name -like "*Log*" } | Sort-Object LastWriteTime -Descending

# Active Full Backup is the most recent full backup
$activeFull = $fullBackups | Select-Object -First 1

if ($activeFull) {
    Write-Host "[ACTIVE FULL] Most recent base full backup: $($activeFull.Name) ($( $activeFull.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') ))" -ForegroundColor Cyan
}

$now = Get-Date
$cutoffContinuous = $now.AddDays(-$ContinuousRetentionDays)
$cutoffWeekly = $now.AddDays(-$WeeklyRetentionDays)

$actions = @()

foreach ($file in $files) {
    $isProtected = $false
    $reason = ""
    $action = "RETAIN"

    # Rule 1: Active Full Backup is unconditionally protected
    if ($activeFull -and $file.FullName -eq $activeFull.FullName) {
        $isProtected = $true
        $reason = "Active base full backup for current restore chain."
    }
    # Rule 2: Files modified after the active full backup belong to the active chain!
    elseif ($activeFull -and $file.LastWriteTime -ge $activeFull.LastWriteTime) {
        $isProtected = $true
        $reason = "Belongs to active PITR chain (dependent on active full backup)."
    }
    # Rule 3: Superseded files within the 7-day continuous retention window
    elseif ($file.LastWriteTime -ge $cutoffContinuous) {
        $isProtected = $true
        $reason = "Within 7-day continuous recovery window."
    }
    # Rule 4: Weekly full backups within 30 days
    elseif ($file.Extension -eq ".bak" -and $file.LastWriteTime -ge $cutoffWeekly -and $file.LastWriteTime.DayOfWeek -eq 'Sunday') {
        $isProtected = $true
        $reason = "Within 30-day weekly archival window (Sunday retention)."
    }
    # Eligible for pruning
    else {
        $action = "PRUNE"
        $reason = "Superseded by subsequent full backups and outside retention window."
    }

    if ($action -eq "PRUNE") {
        if (!$WhatIf) {
            Remove-Item -Path $file.FullName -Force
            $action = "DELETED"
        } else {
            $action = "WOULD_DELETE"
        }
    }

    $actions += [PSCustomObject]@{
        FileName      = $file.Name
        Type          = $file.Extension.ToUpper().Replace('.', '')
        SizeKB        = [math]::Round($file.Length / 1KB, 2)
        LastModified  = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        Action        = $action
        ProtectionReason = $reason
    }
}

Write-Host "`nLifecycle Audit Summary:"
$actions | Format-Table -AutoSize

$prunedCount = ($actions | Where-Object { $_.Action -in 'DELETED', 'WOULD_DELETE' }).Count
$retainedCount = ($actions | Where-Object { $_.Action -eq 'RETAIN' }).Count

Write-Host "Total Files Evaluated: $($files.Count)"
Write-Host "Files Retained:        $retainedCount"
Write-Host "Files Pruned:          $prunedCount"
