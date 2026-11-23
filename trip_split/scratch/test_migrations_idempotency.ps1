$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB_TEST;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

function Execute-SqlFile($filePath, $runLabel) {
    Write-Host "============================================================"
    Write-Host "EXECUTING: $(Split-Path $filePath -Leaf) ($runLabel)"
    Write-Host "============================================================"
    $sql = Get-Content $filePath -Raw
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    
    # Register info message handler to capture SQL PRINT statements
    $handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] {
        param($sender, $event)
        Write-Host $event.Message
    }
    $conn.add_InfoMessage($handler)
    
    try {
        $cmd.ExecuteNonQuery() | Out-Null
        Write-Host "[SUCCESS] $runLabel of $(Split-Path $filePath -Leaf) completed successfully."
    } catch {
        Write-Host "[ERROR] $runLabel failed: $_"
        throw
    } finally {
        $conn.remove_InfoMessage($handler)
    }
}

$m1 = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\migrations\001_composite_foreign_keys.sql"
$m2 = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\migrations\002_soft_delete_support.sql"

# Execution 1
Execute-SqlFile $m1 "RUN 1 (INITIAL)"
Execute-SqlFile $m2 "RUN 1 (INITIAL)"

# Execution 2 (Idempotency test)
Execute-SqlFile $m1 "RUN 2 (IDEMPOTENCY RE-RUN)"
Execute-SqlFile $m2 "RUN 2 (IDEMPOTENCY RE-RUN)"

$conn.Close()
Write-Host "============================================================"
Write-Host "ALL IDEMPOTENCY MIGRATION TESTS PASSED EMPIRICALLY."
Write-Host "============================================================"
