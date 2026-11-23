# ============================================================================
# Task 1 & 2 Investigation Script
# 1. Exact direct COUNT(*) on all tables in SPLIT_BILL_DB with automatic sum.
# 2. Complete inspection of ActivityLogs, Notifications, SettlementTransactions
#    for Goa trip '8092c57a-8638-4dc9-8969-748a9607d834'.
# ============================================================================

[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "TASK 1: RE-RUN DIRECT COUNT(*) ON ALL 13 PRODUCTION TABLES"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;"
$reader = $cmd.ExecuteReader()
$tables = @()
while ($reader.Read()) {
    $tables += $reader.GetString(0)
}
$reader.Close()

$totalRows = 0
$results = @()
foreach ($t in $tables) {
    $cCmd = $conn.CreateCommand()
    $cCmd.CommandText = "SELECT COUNT(*) FROM dbo.[$t];"
    $count = [int]$cCmd.ExecuteScalar()
    $totalRows += $count
    $results += [PSCustomObject]@{
        TableName = $t
        RowCount = $count
    }
}
$results | Format-Table -AutoSize
Write-Host "AUTOMATICALLY CALCULATED TOTAL ROWS ACROSS ALL $($tables.Count) TABLES: $totalRows"

Write-Host "`n================================================================================"
Write-Host "TASK 2: COMPLETE AUDIT LOGS & EVIDENCE FOR GOA TRIP"
Write-Host "Trip ID: 8092c57a-8638-4dc9-8969-748a9607d834"
Write-Host "================================================================================"

# 1. ActivityLogs complete columns & rows
Write-Host "`n--- 1. All ActivityLogs for Goa Trip (All Columns) ---"
$cmd.CommandText = @"
SELECT log_id, user_id, trip_id, action_type, details, created_at
FROM dbo.ActivityLogs
WHERE trip_id = '8092c57a-8638-4dc9-8969-748a9607d834'
ORDER BY created_at ASC;
"@
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtLogs = New-Object System.Data.DataTable
$adapter.Fill($dtLogs) | Out-Null
$dtLogs | Format-List

# 2. ActivityLogs schema: all columns in table
Write-Host "`n--- 2. ActivityLogs Table Schema ---"
$cmd.CommandText = @"
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ActivityLogs'
ORDER BY ORDINAL_POSITION;
"@
$dtSchema = New-Object System.Data.DataTable
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$adapter.Fill($dtSchema) | Out-Null
$dtSchema | Format-Table -AutoSize

# 3. Check Notifications for Goa Trip or related users
Write-Host "`n--- 3. Notifications related to Goa Trip or Users (Soumya, Dipa, Manik, etc.) ---"
$cmd.CommandText = @"
SELECT notification_id, user_id, title, message, type, is_read, created_at
FROM dbo.Notifications
WHERE message LIKE '%goa%' OR message LIKE '%Car%' OR message LIKE '%food%' OR message LIKE '%room%'
   OR user_id IN ('0d979a07-3c0b-4efc-a6ec-d3199f51335b', '4f16ae4b-63e0-453a-9e35-27e6a754981a')
ORDER BY created_at ASC;
"@
$dtNotifs = New-Object System.Data.DataTable
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$adapter.Fill($dtNotifs) | Out-Null
$dtNotifs | Format-Table -AutoSize

# 4. Check SettlementTransactions for Goa Trip
Write-Host "`n--- 4. SettlementTransactions for Goa Trip ---"
$cmd.CommandText = @"
SELECT settlement_id, trip_id, from_person_id, to_person_id, amount, currency_code, status, payment_method, notes, settled_at, created_at
FROM dbo.SettlementTransactions
WHERE trip_id = '8092c57a-8638-4dc9-8969-748a9607d834';
"@
$dtSettlements = New-Object System.Data.DataTable
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$adapter.Fill($dtSettlements) | Out-Null
if ($dtSettlements.Rows.Count -eq 0) {
    Write-Host "[ZERO SETTLEMENTS FOUND FOR GOA TRIP]"
} else {
    $dtSettlements | Format-Table -AutoSize
}

# 5. Check all SettlementTransactions across entire production database
Write-Host "`n--- 5. All SettlementTransactions in Entire Production Database ---"
$cmd.CommandText = @"
SELECT settlement_id, trip_id, from_person_id, to_person_id, amount, currency_code, status, payment_method, notes, settled_at, created_at
FROM dbo.SettlementTransactions;
"@
$dtAllSettlements = New-Object System.Data.DataTable
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$adapter.Fill($dtAllSettlements) | Out-Null
$dtAllSettlements | Format-Table -AutoSize

$conn.Close()
