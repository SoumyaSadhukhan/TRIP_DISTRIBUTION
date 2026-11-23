$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB_TEST;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "TASK 6 (PART A): PII AUDIT OF USERS AND PERSONS IN SPLIT_BILL_DB_TEST"
Write-Host "================================================================================"

$userQuery = @"
SELECT 
    user_id, 
    username, 
    phone_number, 
    email, 
    full_name, 
    is_active, 
    created_at 
FROM Users 
ORDER BY created_at ASC;
"@

$cmd = $conn.CreateCommand()
$cmd.CommandText = $userQuery
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtUsers = New-Object System.Data.DataTable
$adapter.Fill($dtUsers) | Out-Null

Write-Host "--- USERS AUDIT (Total Rows: $($dtUsers.Rows.Count)) ---"
$dtUsers | Format-Table -AutoSize

$personQuery = @"
SELECT 
    p.person_id, 
    p.trip_id, 
    t.name AS TripName, 
    p.name AS PersonName, 
    p.phone_number, 
    p.user_id, 
    p.is_deleted 
FROM Persons p
LEFT JOIN Trips t ON p.trip_id = t.trip_id
ORDER BY p.created_at ASC;
"@

$cmd.CommandText = $personQuery
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtPersons = New-Object System.Data.DataTable
$adapter.Fill($dtPersons) | Out-Null

Write-Host "--- PERSONS AUDIT (Total Rows: $($dtPersons.Rows.Count)) ---"
$dtPersons | Format-Table -AutoSize

# Verification of PII leakage
$cmd.CommandText = @"
SELECT 
    (SELECT COUNT(1) FROM Users WHERE phone_number NOT LIKE '+91999900000%' AND phone_number NOT LIKE '980000000%') AS NonSyntheticUsers,
    (SELECT COUNT(1) FROM Users WHERE email NOT LIKE '%@test.local' AND email NOT LIKE '%@example.com' AND email IS NOT NULL AND email <> '') AS NonSyntheticUserEmails,
    (SELECT COUNT(1) FROM Persons WHERE phone_number IS NOT NULL AND phone_number <> '' AND phone_number NOT LIKE '+91999900000%' AND phone_number NOT LIKE '980000000%' AND phone_number NOT LIKE '990000000%') AS NonSyntheticPersonPhones;
"@

$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dtLeakage = New-Object System.Data.DataTable
$adapter.Fill($dtLeakage) | Out-Null
Write-Host "--- PII LEAKAGE VERIFICATION COUNTS ---"
$dtLeakage | Format-Table -AutoSize

$conn.Close()
