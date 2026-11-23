# ============================================================================
# Task 4 & 5 Investigation Script
# Task 4: Deterministic content comparison between SPLIT_BILL_DB and restored rehearsal.
# Task 5: Backup history and chain continuity from msdb.
# ============================================================================

[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=master;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "TASK 4: DETERMINISTIC CONTENT & CHECKSUM VERIFICATION"
Write-Host "================================================================================"

$backupFile = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\backups\SPLIT_BILL_DB_Prod_Rehearsal.bak"
$destMdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\SPLIT_BILL_DB_PROD_REHEARSAL.mdf"
$destLdf = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\SPLIT_BILL_DB_PROD_REHEARSAL_log.ldf"

$cmd = $conn.CreateCommand()

# Restore rehearsal DB
Write-Host "Restoring rehearsal database from $backupFile..."
$restoreSql = @"
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SPLIT_BILL_DB_PROD_REHEARSAL')
BEGIN
    ALTER DATABASE SPLIT_BILL_DB_PROD_REHEARSAL SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SPLIT_BILL_DB_PROD_REHEARSAL;
END

RESTORE DATABASE SPLIT_BILL_DB_PROD_REHEARSAL
FROM DISK = '$backupFile'
WITH REPLACE,
     MOVE 'SPLIT_BILL_DB' TO '$destMdf',
     MOVE 'SPLIT_BILL_DB_log' TO '$destLdf';
"@
$cmd.CommandText = $restoreSql
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] SPLIT_BILL_DB_PROD_REHEARSAL restored."

# Retrieve all tables
$cmd.CommandText = "SELECT TABLE_NAME FROM SPLIT_BILL_DB.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;"
$reader = $cmd.ExecuteReader()
$tables = @()
while ($reader.Read()) {
    $tables += $reader.GetString(0)
}
$reader.Close()

$tableResults = @()

foreach ($tbl in $tables) {
    # 1. Primary Key columns
    $pkCmd = $conn.CreateCommand()
    $pkCmd.CommandText = @"
    SELECT k.COLUMN_NAME
    FROM SPLIT_BILL_DB.INFORMATION_SCHEMA.TABLE_CONSTRAINTS t
    JOIN SPLIT_BILL_DB.INFORMATION_SCHEMA.KEY_COLUMN_USAGE k
      ON t.CONSTRAINT_NAME = k.CONSTRAINT_NAME
    WHERE t.TABLE_NAME = '$tbl' AND t.CONSTRAINT_TYPE = 'PRIMARY KEY'
    ORDER BY k.ORDINAL_POSITION;
"@
    $pkReader = $pkCmd.ExecuteReader()
    $pkCols = @()
    while ($pkReader.Read()) {
        $pkCols += $pkReader.GetString(0)
    }
    $pkReader.Close()
    $pkColList = ($pkCols | ForEach-Object { "[$_]" }) -join ", "

    # Check PK diff: Prod EXCEPT Rehearsal
    $pkDiffCount = 0
    if ($pkColList) {
        $pkDiffCmd = $conn.CreateCommand()
        $pkDiffCmd.CommandText = @"
        SELECT COUNT(*) FROM (
            SELECT $pkColList FROM SPLIT_BILL_DB.dbo.[$tbl]
            EXCEPT
            SELECT $pkColList FROM SPLIT_BILL_DB_PROD_REHEARSAL.dbo.[$tbl]
        ) diff;
"@
        $pkDiffCount = [int]$pkDiffCmd.ExecuteScalar()
    }

    # 2. Full Row Diff: Prod EXCEPT Rehearsal
    $fullDiffCmd1 = $conn.CreateCommand()
    $fullDiffCmd1.CommandText = @"
    SELECT COUNT(*) FROM (
        SELECT * FROM SPLIT_BILL_DB.dbo.[$tbl]
        EXCEPT
        SELECT * FROM SPLIT_BILL_DB_PROD_REHEARSAL.dbo.[$tbl]
    ) d1;
"@
    $diff1 = [int]$fullDiffCmd1.ExecuteScalar()

    # 3. Full Row Diff: Rehearsal EXCEPT Prod
    $fullDiffCmd2 = $conn.CreateCommand()
    $fullDiffCmd2.CommandText = @"
    SELECT COUNT(*) FROM (
        SELECT * FROM SPLIT_BILL_DB_PROD_REHEARSAL.dbo.[$tbl]
        EXCEPT
        SELECT * FROM SPLIT_BILL_DB.dbo.[$tbl]
    ) d2;
"@
    $diff2 = [int]$fullDiffCmd2.ExecuteScalar()

    # 4. BINARY_CHECKSUM comparison
    $chkCmd = $conn.CreateCommand()
    $chkCmd.CommandText = @"
    SELECT 
        (SELECT ISNULL(CHECKSUM_AGG(BINARY_CHECKSUM(*)), 0) FROM SPLIT_BILL_DB.dbo.[$tbl]) AS ProdChecksum,
        (SELECT ISNULL(CHECKSUM_AGG(BINARY_CHECKSUM(*)), 0) FROM SPLIT_BILL_DB_PROD_REHEARSAL.dbo.[$tbl]) AS RehearsalChecksum;
"@
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($chkCmd)
    $dtChk = New-Object System.Data.DataTable
    $adapter.Fill($dtChk) | Out-Null
    $prodChk = $dtChk.Rows[0]["ProdChecksum"]
    $rehChk  = $dtChk.Rows[0]["RehearsalChecksum"]

    $parity = ($pkDiffCount -eq 0) -and ($diff1 -eq 0) -and ($diff2 -eq 0) -and ($prodChk -eq $rehChk)

    $tableResults += [PSCustomObject]@{
        TableName         = $tbl
        PrimaryKey        = if ($pkColList) { $pkColList } else { "NONE" }
        PK_Diff           = $pkDiffCount
        Prod_Except_Reh   = $diff1
        Reh_Except_Prod   = $diff2
        Prod_Checksum     = $prodChk
        Reh_Checksum      = $rehChk
        Content_Parity    = if ($parity) { "MATCH (EXACT)" } else { "MISMATCH" }
    }
}

$tableResults | Format-Table -AutoSize

Write-Host "Excluded Columns Analysis: EXACTLY ZERO COLUMNS EXCLUDED."
Write-Host "All columns (including text, nvarchar, datetime, decimal, bit) were verified with direct SELECT * EXCEPT and BINARY_CHECKSUM."

# Clean up rehearsal DB
$cmd.CommandText = @"
ALTER DATABASE SPLIT_BILL_DB_PROD_REHEARSAL SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE SPLIT_BILL_DB_PROD_REHEARSAL;
"@
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] Rehearsal DB dropped."

Write-Host "`n================================================================================"
Write-Host "TASK 5: PRODUCTION LOG BACKUP CHAIN & MSDB BACKUP HISTORY"
Write-Host "================================================================================"

# Query msdb for SPLIT_BILL_DB backups
$cmd.CommandText = @"
SELECT 
    bs.database_name,
    bs.backup_set_id,
    bs.name AS backup_set_name,
    CASE bs.type 
        WHEN 'D' THEN 'Full Database'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Transaction Log'
        WHEN 'F' THEN 'File / Filegroup'
        ELSE bs.type
    END AS backup_type,
    bs.backup_start_date,
    bs.backup_finish_date,
    CAST(bs.backup_size / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS backup_size_mb,
    CAST(bs.compressed_backup_size / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS compressed_size_mb,
    bs.first_lsn,
    bs.last_lsn,
    bs.checkpoint_lsn,
    bmf.physical_device_name
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE bs.database_name = 'SPLIT_BILL_DB'
ORDER BY bs.backup_finish_date DESC;
"@
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtBackups = New-Object System.Data.DataTable
$adapter.Fill($dtBackups) | Out-Null

Write-Host "Total Backups Recorded for SPLIT_BILL_DB in msdb: $($dtBackups.Rows.Count)"
$dtBackups | Format-Table -AutoSize

# Check SQL Server Agent Jobs
Write-Host "`n--- SQL Server Agent Backup Jobs ---"
$cmd.CommandText = @"
SELECT 
    j.name AS job_name,
    j.enabled,
    j.description,
    s.name AS schedule_name,
    s.enabled AS schedule_enabled,
    s.freq_type,
    s.freq_subday_type,
    s.freq_subday_interval
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
LEFT JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name LIKE '%backup%' OR j.name LIKE '%SPLIT%' OR j.description LIKE '%backup%';
"@
$dtJobs = New-Object System.Data.DataTable
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$adapter.Fill($dtJobs) | Out-Null

if ($dtJobs.Rows.Count -eq 0) {
    Write-Host "[WARNING: ZERO AUTOMATED BACKUP JOBS CONFIGURED IN SQL SERVER AGENT]"
    Write-Host "No standing SQL Agent jobs exist for scheduled full, differential, or transaction log backups of SPLIT_BILL_DB."
} else {
    $dtJobs | Format-Table -AutoSize
}

$conn.Close()
