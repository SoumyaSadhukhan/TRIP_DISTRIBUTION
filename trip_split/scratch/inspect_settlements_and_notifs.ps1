[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "--- SettlementTransactions Columns ---"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SettlementTransactions';"
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
$adapter.Fill($dt) | Out-Null
$dt | Format-Table -AutoSize

Write-Host "`n--- All SettlementTransactions Rows ---"
$cmd.CommandText = "SELECT * FROM dbo.SettlementTransactions;"
$dt2 = New-Object System.Data.DataTable
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$adapter.Fill($dt2) | Out-Null
$dt2 | Format-List

Write-Host "`n--- Full Text of Notifications for Goa / Expenses ---"
$cmd.CommandText = @"
SELECT notification_id, user_id, title, message, type, is_read, created_at
FROM dbo.Notifications
WHERE notification_id IN (
    '8995dd96-2f59-4a48-953e-0ec31492672a',
    '5540042d-8317-47bc-9e92-e6a5c664ccba',
    '8ca7d4ac-a6a6-4fbe-ab3a-812951c9546b',
    '04ab5016-f822-451e-9efe-727c686bcd26'
);
"@
$dtNotifs = New-Object System.Data.DataTable
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$adapter.Fill($dtNotifs) | Out-Null
$dtNotifs | Format-List

$conn.Close()
