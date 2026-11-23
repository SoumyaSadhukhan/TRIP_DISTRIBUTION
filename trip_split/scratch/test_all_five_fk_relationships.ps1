$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB_TEST;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

Write-Host "================================================================================"
Write-Host "TASK 5: RIGOROUS RELATIONAL INTEGRITY VERIFICATION (ALL 5 COMPOSITE FKs)"
Write-Host "================================================================================"

$setupSql = @"
DECLARE @Trip1 NVARCHAR(100) = NEWID();
DECLARE @Trip2 NVARCHAR(100) = NEWID();
DECLARE @Person1A NVARCHAR(100) = NEWID();
DECLARE @Person1B NVARCHAR(100) = NEWID();
DECLARE @Person2A NVARCHAR(100) = NEWID();
DECLARE @Person2B NVARCHAR(100) = NEWID();

INSERT INTO Trips (trip_id, user_id, name) VALUES (@Trip1, 'test-user', 'FK Test Trip 1');
INSERT INTO Trips (trip_id, user_id, name) VALUES (@Trip2, 'test-user', 'FK Test Trip 2');

INSERT INTO Persons (person_id, trip_id, name) VALUES (@Person1A, @Trip1, 'Person 1A');
INSERT INTO Persons (person_id, trip_id, name) VALUES (@Person1B, @Trip1, 'Person 1B');

INSERT INTO Persons (person_id, trip_id, name) VALUES (@Person2A, @Trip2, 'Person 2A');
INSERT INTO Persons (person_id, trip_id, name) VALUES (@Person2B, @Trip2, 'Person 2B');

SELECT @Trip1 AS Trip1, @Trip2 AS Trip2, @Person1A AS P1A, @Person1B AS P1B, @Person2A AS P2A, @Person2B AS P2B;
"@

$cmd = $conn.CreateCommand()
$cmd.CommandText = $setupSql
$reader = $cmd.ExecuteReader()
$reader.Read() | Out-Null
$trip1 = $reader["Trip1"].ToString()
$trip2 = $reader["Trip2"].ToString()
$p1a = $reader["P1A"].ToString()
$p1b = $reader["P1B"].ToString()
$p2a = $reader["P2A"].ToString()
$p2b = $reader["P2B"].ToString()
$reader.Close()

Write-Host "[SETUP COMPLETE]"
Write-Host "Trip 1: $trip1 | Persons: 1A ($p1a), 1B ($p1b)"
Write-Host "Trip 2: $trip2 | Persons: 2A ($p2a), 2B ($p2b)"
Write-Host ""

function Test-Constraint($label, $sql, $expectSuccess, $expectedConstraint) {
    Write-Host "------------------------------------------------------------"
    Write-Host "TEST: $label"
    $tcmd = $conn.CreateCommand()
    $tcmd.CommandText = $sql
    try {
        $tcmd.ExecuteNonQuery() | Out-Null
        if ($expectSuccess) {
            Write-Host "[PASS] Valid operation succeeded as expected."
        } else {
            Write-Host "[FAIL] Expected failure, but statement succeeded!"
            throw "Security violation: $label should have been rejected."
        }
    } catch {
        if (-not $expectSuccess) {
            $err = $_.Exception.Message
            if ($err -match $expectedConstraint) {
                Write-Host "[PASS] Correctly rejected by constraint '$expectedConstraint':"
                Write-Host "       $err"
            } else {
                Write-Host "[FAIL] Rejected by unexpected error: $err"
                throw $_
            }
        } else {
            Write-Host "[FAIL] Valid operation failed: $_"
            throw $_
        }
    }
}

# --- FK 1: Expenses(paid_by_person_id, trip_id) -> Persons(person_id, trip_id) ---
$validExpId = [Guid]::NewGuid().ToString()
Test-Constraint "FK 1 Valid: Expense in Trip 1 paid by Person 1A (Trip 1)" `
    "INSERT INTO Expenses (expense_id, trip_id, description, amount, paid_by_person_id, expense_date) VALUES ('$validExpId', '$trip1', 'Valid Exp 1', 500.00, '$p1a', GETDATE());" `
    $true ""

$invalidExpId = [Guid]::NewGuid().ToString()
Test-Constraint "FK 1 Invalid: Expense in Trip 1 paid by Person 2A (Trip 2)" `
    "INSERT INTO Expenses (expense_id, trip_id, description, amount, paid_by_person_id, expense_date) VALUES ('$invalidExpId', '$trip1', 'Cross Exp', 500.00, '$p2a', GETDATE());" `
    $false "FK_Expenses_Persons_Trip"

# --- FK 2: ExpenseSplits(expense_id, trip_id) -> Expenses(expense_id, trip_id) ---
$validSplit1Id = [Guid]::NewGuid().ToString()
Test-Constraint "FK 2 Valid: Split in Trip 1 referencing Expense 1 (Trip 1)" `
    "INSERT INTO ExpenseSplits (split_id, expense_id, person_id, trip_id, amount) VALUES ('$validSplit1Id', '$validExpId', '$p1a', '$trip1', 250.00);" `
    $true ""

$invalidSplitCrossExpId = [Guid]::NewGuid().ToString()
Test-Constraint "FK 2 Invalid: Split in Trip 2 referencing Expense 1 (Trip 1)" `
    "INSERT INTO ExpenseSplits (split_id, expense_id, person_id, trip_id, amount) VALUES ('$invalidSplitCrossExpId', '$validExpId', '$p2a', '$trip2', 250.00);" `
    $false "FK_ExpenseSplits_Expenses_Trip"

# --- FK 3: ExpenseSplits(person_id, trip_id) -> Persons(person_id, trip_id) ---
$validSplit2Id = [Guid]::NewGuid().ToString()
Test-Constraint "FK 3 Valid: Split in Trip 1 assigned to Person 1B (Trip 1)" `
    "INSERT INTO ExpenseSplits (split_id, expense_id, person_id, trip_id, amount) VALUES ('$validSplit2Id', '$validExpId', '$p1b', '$trip1', 250.00);" `
    $true ""

$invalidSplitCrossPersonId = [Guid]::NewGuid().ToString()
Test-Constraint "FK 3 Invalid: Split in Trip 1 assigned to Person 2B (Trip 2)" `
    "INSERT INTO ExpenseSplits (split_id, expense_id, person_id, trip_id, amount) VALUES ('$invalidSplitCrossPersonId', '$validExpId', '$p2b', '$trip1', 250.00);" `
    $false "FK_ExpenseSplits_Persons_Trip"

# --- FK 4: SettlementTransactions(from_person_id, trip_id) -> Persons(person_id, trip_id) ---
$validSettleId = [Guid]::NewGuid().ToString()
Test-Constraint "FK 4 Valid: Settlement in Trip 1 from Person 1A to Person 1B" `
    "INSERT INTO SettlementTransactions (settlement_id, trip_id, from_person_id, to_person_id, amount, settled_at) VALUES ('$validSettleId', '$trip1', '$p1a', '$p1b', 100.00, GETDATE());" `
    $true ""

$invalidSettleFromId = [Guid]::NewGuid().ToString()
Test-Constraint "FK 4 Invalid: Settlement in Trip 1 from Person 2A (Trip 2) to Person 1B (Trip 1)" `
    "INSERT INTO SettlementTransactions (settlement_id, trip_id, from_person_id, to_person_id, amount, settled_at) VALUES ('$invalidSettleFromId', '$trip1', '$p2a', '$p1b', 100.00, GETDATE());" `
    $false "FK_Settlements_Persons_From_Trip"

# --- FK 5: SettlementTransactions(to_person_id, trip_id) -> Persons(person_id, trip_id) ---
$invalidSettleToId = [Guid]::NewGuid().ToString()
Test-Constraint "FK 5 Invalid: Settlement in Trip 1 from Person 1A (Trip 1) to Person 2B (Trip 2)" `
    "INSERT INTO SettlementTransactions (settlement_id, trip_id, from_person_id, to_person_id, amount, settled_at) VALUES ('$invalidSettleToId', '$trip1', '$p1a', '$p2b', 100.00, GETDATE());" `
    $false "FK_Settlements_Persons_To_Trip"

# Cleanup
$cleanupSql = @"
DELETE FROM SettlementTransactions WHERE trip_id IN ('$trip1', '$trip2');
DELETE FROM ExpenseSplits WHERE trip_id IN ('$trip1', '$trip2');
DELETE FROM Expenses WHERE trip_id IN ('$trip1', '$trip2');
DELETE FROM Persons WHERE trip_id IN ('$trip1', '$trip2');
DELETE FROM Trips WHERE trip_id IN ('$trip1', '$trip2');
"@
$cmd.CommandText = $cleanupSql
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "------------------------------------------------------------"
Write-Host "[CLEANUP COMPLETE] All test records removed."

$conn.Close()
Write-Host "================================================================================"
Write-Host "ALL 5 COMPOSITE FOREIGN KEY INTEGRITY TESTS PASSED EMPIRICALLY."
Write-Host "================================================================================"
