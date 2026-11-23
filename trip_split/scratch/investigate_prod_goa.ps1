[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "TASK 1: PRODUCTION GOA TRIP INVESTIGATION (SPLIT_BILL_DB - READ ONLY)"
Write-Host "================================================================================"

$tripId = "8092c57a-8638-4dc9-8969-748a9607d834"

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

# 1. Trip details
Run-Query "1. TRIP RECORD" @"
SELECT trip_id, user_id, name, description, currency_code, created_at, updated_at
FROM dbo.Trips
WHERE trip_id = '$tripId';
"@

# 2. Persons in this trip
Run-Query "2. PERSONS IN GOA TRIP" @"
SELECT person_id, group_id, trip_id, user_id, phone_number, name, diet_type, diet_name, paid_amount, owed_amount, balance, created_at
FROM dbo.Persons
WHERE trip_id = '$tripId'
ORDER BY created_at ASC;
"@

# 3. Expenses in this trip
Run-Query "3. EXPENSES IN GOA TRIP" @"
SELECT expense_id, trip_id, description, amount, currency_code, category_index, category_name, paid_by_person_id, split_type, expense_date, created_at
FROM dbo.Expenses
WHERE trip_id = '$tripId'
ORDER BY created_at ASC;
"@

# 4. ExpenseSplits for these expenses
Run-Query "4. EXPENSE SPLITS IN GOA TRIP" @"
SELECT es.split_id, es.expense_id, es.trip_id, es.person_id, p.name AS PersonName, es.amount, es.created_at
FROM dbo.ExpenseSplits es
LEFT JOIN dbo.Persons p ON es.person_id = p.person_id
WHERE es.trip_id = '$tripId'
ORDER BY es.expense_id, es.created_at;
"@

# 5. Settlements in this trip
Run-Query "5. SETTLEMENTS IN GOA TRIP" @"
SELECT settlement_id, trip_id, from_person_id, to_person_id, amount, is_completed, status, created_by_user_id, settled_at
FROM dbo.SettlementTransactions
WHERE trip_id = '$tripId';
"@

# 6. Collaborators for this trip
Run-Query "6. TRIP COLLABORATORS FOR GOA TRIP" @"
SELECT collab_id, trip_id, user_id, person_id, phone_number, role, status, joined_at
FROM dbo.TripCollaborators
WHERE trip_id = '$tripId';
"@

# 7. Activity logs for this trip
Run-Query "7. ACTIVITY LOGS FOR GOA TRIP" @"
SELECT log_id, user_id, trip_id, action, details, created_at
FROM dbo.ActivityLogs
WHERE trip_id = '$tripId'
ORDER BY created_at ASC;
"@

# 8. Check where the orphan payer person IDs exist in ALL tables across the database
Run-Query "8. INVESTIGATE ORPHAN PAYER IDs ACROSS ENTIRE SPLIT_BILL_DB" @"
DECLARE @orphan1 NVARCHAR(50) = 'cf8806d1-a3f4-4aa1-bf3';
DECLARE @orphan2 NVARCHAR(50) = '76810b14-585c-438e-a3e';

SELECT 'Persons' AS TableFound, person_id AS Id, trip_id, name, phone_number, user_id
FROM dbo.Persons
WHERE person_id LIKE @orphan1 + '%' OR person_id LIKE @orphan2 + '%'
UNION ALL
SELECT 'Users' AS TableFound, user_id AS Id, 'N/A' AS trip_id, username AS name, phone_number, user_id
FROM dbo.Users
WHERE user_id LIKE @orphan1 + '%' OR user_id LIKE @orphan2 + '%'
UNION ALL
SELECT 'TripCollaborators' AS TableFound, collab_id AS Id, trip_id, role AS name, phone_number, user_id
FROM dbo.TripCollaborators
WHERE person_id LIKE @orphan1 + '%' OR person_id LIKE @orphan2 + '%' 
   OR user_id LIKE @orphan1 + '%' OR user_id LIKE @orphan2 + '%';
"@

# 9. Check all Expenses with their paid_by_person_id exact values
Run-Query "9. EXACT PAID_BY_PERSON_ID VALUES IN GOA EXPENSES" @"
SELECT expense_id, description, amount, paid_by_person_id, LEN(paid_by_person_id) AS PayerIdLength
FROM dbo.Expenses
WHERE trip_id = '$tripId';
"@

# 10. Check if any persons were ever in this trip or deleted
Run-Query "10. ALL PERSONS EVER CREATED IN SPLIT_BILL_DB" @"
SELECT p.person_id, p.trip_id, t.name AS TripName, p.name AS PersonName, p.user_id, p.phone_number
FROM dbo.Persons p
LEFT JOIN dbo.Trips t ON p.trip_id = t.trip_id
ORDER BY p.created_at;
"@

$conn.Close()
