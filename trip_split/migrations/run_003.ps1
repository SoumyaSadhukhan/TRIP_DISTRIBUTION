$connString = "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB_TEST;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

$ddl = @"
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'otp_hash')
BEGIN
    ALTER TABLE dbo.OtpVerification ADD otp_hash NVARCHAR(128) NULL;
    PRINT 'Added otp_hash column to OtpVerification.';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'failed_attempts')
BEGIN
    ALTER TABLE dbo.OtpVerification ADD failed_attempts INT NOT NULL DEFAULT 0;
    PRINT 'Added failed_attempts column to OtpVerification.';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'max_attempts')
BEGIN
    ALTER TABLE dbo.OtpVerification ADD max_attempts INT NOT NULL DEFAULT 5;
    PRINT 'Added max_attempts column to OtpVerification.';
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'lockout_until')
BEGIN
    ALTER TABLE dbo.OtpVerification ADD lockout_until DATETIME NULL;
    PRINT 'Added lockout_until column to OtpVerification.';
END
"@

$cmd = $conn.CreateCommand()
$cmd.CommandText = $ddl
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "DDL executed."

$dml = @"
UPDATE dbo.OtpVerification
SET otp_hash = CONVERT(NVARCHAR(128), HASHBYTES('SHA2_256', otp_code), 2)
WHERE otp_hash IS NULL AND otp_code IS NOT NULL;
"@

$cmd.CommandText = $dml
$cmd.ExecuteNonQuery() | Out-Null
Write-Host "DML executed."

$conn.Close()
