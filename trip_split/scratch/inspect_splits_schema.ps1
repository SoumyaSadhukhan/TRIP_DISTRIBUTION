[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$conn = New-Object System.Data.SqlClient.SqlConnection("Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB;")
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ExpenseSplits' ORDER BY ORDINAL_POSITION;"
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
$adapter.Fill($dt) | Out-Null
$dt | Format-Table -AutoSize

Write-Host "`n--- Sample Rows from ExpenseSplits ---"
$cmd.CommandText = "SELECT TOP 3 * FROM dbo.ExpenseSplits;"
$adapter2 = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt2 = New-Object System.Data.DataTable
$adapter2.Fill($dt2) | Out-Null
$dt2 | Format-List

$conn.Close()
