[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$conn = New-Object System.Data.SqlClient.SqlConnection("Server=localhost;Database=SPLIT_BILL_DB_TEST;Integrated Security=True;TrustServerCertificate=True;")
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT name, OBJECT_NAME(parent_object_id) AS TableName FROM sys.foreign_keys;"
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
$adapter.Fill($dt) | Out-Null
$dt | Format-Table -AutoSize
$conn.Close()
