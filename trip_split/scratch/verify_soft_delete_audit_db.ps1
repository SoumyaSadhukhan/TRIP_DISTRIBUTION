$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB_TEST;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

$cmd = $conn.CreateCommand()
$cmd.CommandText = @"
SELECT 'Trips' AS TableName, trip_id AS Id, name AS Description, is_deleted, deleted_at 
FROM Trips WHERE name = 'Soft Delete Audit Trip'
UNION ALL
SELECT 'Persons', person_id, name, is_deleted, deleted_at 
FROM Persons WHERE name = 'Member 2'
UNION ALL
SELECT 'Expenses', expense_id, description, is_deleted, deleted_at 
FROM Expenses WHERE description IN ('Dinner Expense', 'Taxi Expense');
"@

$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
$adapter.Fill($dt) | Out-Null
$dt | Format-Table -AutoSize

$conn.Close()
