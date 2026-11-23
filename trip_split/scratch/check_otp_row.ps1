$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB_TEST;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

$cmd = $conn.CreateCommand()
$cmd.CommandText = @"
SELECT TOP 3 
    otp_id, 
    email, 
    otp_code, 
    SUBSTRING(otp_hash, 1, 24) + '...' AS otp_hash_prefix, 
    purpose, 
    is_verified, 
    failed_attempts, 
    max_attempts, 
    created_at 
FROM OtpVerification 
ORDER BY created_at DESC;
"@

$adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
$adapter.Fill($dt) | Out-Null
$dt | Format-Table -AutoSize

$conn.Close()
