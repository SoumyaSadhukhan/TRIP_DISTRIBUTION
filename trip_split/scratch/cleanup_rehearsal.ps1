[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null
$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=master;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

$cmd = $conn.CreateCommand()
$cleanupSql = @"
USE master;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SPLIT_BILL_DB_REHEARSAL')
BEGIN
    ALTER DATABASE SPLIT_BILL_DB_REHEARSAL SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SPLIT_BILL_DB_REHEARSAL;
END
"@
$cmd.CommandText = $cleanupSql
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "[SUCCESS] SPLIT_BILL_DB_REHEARSAL cleanly dropped."
$conn.Close()
