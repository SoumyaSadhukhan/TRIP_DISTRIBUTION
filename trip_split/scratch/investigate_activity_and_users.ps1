[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "DEEPER INVESTIGATION OF PRODUCTION ORPHANS & ACTIVITY LOGS"
Write-Host "================================================================================"

function Run-Query($title, $sql) {
    Write-Host "`n>>> $title"
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $dt = New-Object System.Data.DataTable
    $adapter.Fill($dt) | Out-Null
    if ($dt.Rows.Count -eq 0) {
        Write-Host "    [NO RECORDS FOUND]"
    } else {
        $dt | Format-Table -AutoSize
    }
}

# 1. Inspect ActivityLogs column definitions
Run-Query "1. ActivityLogs Columns" @"
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ActivityLogs';
"@

# 2. ActivityLogs content for trip or user Soumya (0d979a07-3c0b-4efc-a6ec-d3199f51335b)
Run-Query "2. All ActivityLogs for Soumya" @"
SELECT * 
FROM dbo.ActivityLogs
WHERE user_id = '0d979a07-3c0b-4efc-a6ec-d3199f51335b'
   OR details LIKE '%8092c57a%'
   OR details LIKE '%goa%'
   OR details LIKE '%cf8806d1%'
   OR details LIKE '%76810b14%';
"@

# 3. Check All Users
Run-Query "3. All Users in Production" @"
SELECT user_id, phone_number, email, username, full_name, created_at
FROM dbo.Users;
"@

# 4. Check All FriendConnections in Production
Run-Query "4. All FriendConnections in Production" @"
SELECT * FROM dbo.FriendConnections;
"@

# 5. Check All TripCollaborators in Production
Run-Query "5. All TripCollaborators in Production" @"
SELECT * FROM dbo.TripCollaborators;
"@

# 6. Check All Groups in Goa trip
Run-Query "6. All Groups in Goa trip" @"
SELECT * FROM dbo.Groups WHERE trip_id = '8092c57a-8638-4dc9-8969-748a9607d834';
"@

# 7. Check Soumya's balance in Goa trip
Run-Query "7. Soumya's Balance in Goa trip" @"
SELECT person_id, name, paid_amount, owed_amount, balance
FROM dbo.Persons
WHERE trip_id = '8092c57a-8638-4dc9-8969-748a9607d834';
"@

$conn.Close()
