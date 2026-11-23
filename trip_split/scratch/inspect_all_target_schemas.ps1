[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$conn = New-Object System.Data.SqlClient.SqlConnection("Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB;")
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = @"
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('Persons', 'Expenses', 'Trips', 'ActivityLogs')
ORDER BY TABLE_NAME, ORDINAL_POSITION;
"@
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
$adapter.Fill($dt) | Out-Null
$dt | Format-Table -AutoSize
$conn.Close()
