$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB_TEST;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

$cmd = $conn.CreateCommand()
$cmd.CommandText = @"
SELECT person_id, trip_id, name, phone_number 
FROM Persons 
WHERE phone_number IS NOT NULL AND phone_number <> '' 
  AND phone_number NOT LIKE '+91999900000%' 
  AND phone_number NOT LIKE '980000000%' 
  AND phone_number NOT LIKE '990000000%';
"@

$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
$adapter.Fill($dt) | Out-Null
$dt | Format-Table -AutoSize

$conn.Close()
