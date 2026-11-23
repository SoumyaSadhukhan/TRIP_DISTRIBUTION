$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=master;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

$backupFile = "C:\My_Project\TRIP_DISTRIBUTION\backups\SPLIT_BILL_DB_TEST_Rehearsal.bak"
$cmd = $conn.CreateCommand()
$cmd.CommandText = "RESTORE FILELISTONLY FROM DISK = '$backupFile';"
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
$adapter.Fill($dt) | Out-Null

$dt | Format-Table LogicalName, PhysicalName, Type

$conn.Close()
