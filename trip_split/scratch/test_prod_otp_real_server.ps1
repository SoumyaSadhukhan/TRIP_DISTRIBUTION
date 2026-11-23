# ============================================================================
# Task 3: Real Server-Side Production Mode OTP Suppression & Hash Verification
# Runs API with ProductionMode=true on port 5264 against SPLIT_BILL_DB_TEST
# Proves that production suppression guard works live over HTTP
# ============================================================================

[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null

Write-Host "================================================================================"
Write-Host "TASK 3: REAL PRODUCTION MODE OTP SUPPRESSION & HASH VERIFICATION"
Write-Host "================================================================================"

$port = 5264
$apiUrl = "http://localhost:$port"
$logFile = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\prod_api_run.log"
$errFile = "C:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\prod_api_err.log"
if (Test-Path $logFile) { Remove-Item $logFile -Force }
if (Test-Path $errFile) { Remove-Item $errFile -Force }

$env:ASPNETCORE_ENVIRONMENT = "Testing"
$env:ASPNETCORE_URLS = $apiUrl
$env:ProductionMode = "true"                     # Triggers isServerProduction in AuthController
$env:Environment = "PRODUCTION"                  # Triggers isServerProduction in AuthController & AuthDataService
$env:AuthSettings__ExposeOtpInResponse = "true"  # Intentional client/config misconfiguration attempt
$env:AuthSettings__BypassOtpInDebug = "true"     # Intentional bypass attempt
$env:ConnectionStrings__DefaultConnection = "Server=localhost;Database=SPLIT_BILL_DB_TEST;Integrated Security=True;TrustServerCertificate=True;"

Write-Host "Starting API process with ProductionMode=true and Environment=PRODUCTION on port $port..."
$proc = Start-Process -FilePath "C:\My_Project\TRIP_DISTRIBUTION_API\TripDistribution.Api\bin\Debug\net9.0\TripDistribution.Api.exe" `
    -ArgumentList "--contentRoot C:\My_Project\TRIP_DISTRIBUTION_API\TripDistribution.Api" `
    -PassThru `
    -RedirectStandardOutput $logFile `
    -RedirectStandardError $errFile

# Wait up to 10s for API to start listening
$started = $false
for ($i = 0; $i -lt 25; $i++) {
    Start-Sleep -Milliseconds 400
    if (Test-Path $logFile) {
        $content = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
        if ($content -and $content -match "Now listening on") {
            $started = $true
            break
        }
    }
}

Write-Host "API startup status: $(if ($started) { 'LISTENING ON PORT ' + $port } else { 'WAIT TIMEOUT' })"
if (Test-Path $logFile) {
    Get-Content $logFile | Select-Object -First 10 | Write-Host
}
if (Test-Path $errFile) {
    $errs = Get-Content $errFile -Raw
    if ($errs) { Write-Host "STDERR: $errs" }
}

try {
    # Fire send-otp request
    $targetEmail = "prod_guard_$(Get-Random)@equitrip-audit.com"
    $body = @{
        email = $targetEmail
        purpose = "REGISTER"
        username = "ProductionAuditUser"
    } | ConvertTo-Json

    Write-Host "`nSending POST /api/Auth/send-otp with misconfigured expose settings..."
    $response = Invoke-RestMethod -Uri "$apiUrl/api/Auth/send-otp" -Method Post -ContentType "application/json" -Body $body

    Write-Host "`nHTTP Response Received:"
    $responseJson = $response | ConvertTo-Json -Depth 5
    Write-Host $responseJson

    $exposedOtp = $response.data.otpCode
    Write-Host "`n--- Verification Assertions ---"
    Write-Host "1. Was OTP exposed in response? $(if ($exposedOtp) { "FAILED: $exposedOtp" } else { "PASS: OTP is NULL (Server production guard enforced)" })"

    # Query SPLIT_BILL_DB_TEST OtpVerification row
    $conn = New-Object System.Data.SqlClient.SqlConnection("Server=localhost;Database=SPLIT_BILL_DB_TEST;Integrated Security=True;TrustServerCertificate=True;")
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT TOP 1 otp_id, email, otp_code, otp_hash, purpose, failed_attempts, max_attempts, is_verified FROM dbo.OtpVerification WHERE email = '$targetEmail' ORDER BY created_at DESC;"
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $dt = New-Object System.Data.DataTable
    $adapter.Fill($dt) | Out-Null
    $conn.Close()

    Write-Host "`nDatabase Row in dbo.OtpVerification:"
    $dt | Format-List

    $storedCode = $dt.Rows[0]["otp_code"].ToString()
    $storedHash = $dt.Rows[0]["otp_hash"].ToString()

    Write-Host "2. Plaintext otp_code in DB: '$storedCode' $(if ($storedCode -eq 'REDACTED') { '(PASS: REDACTED)' } else { '(FAIL)' })"
    Write-Host "3. HMAC-SHA256 hash length: $($storedHash.Length) chars $(if ($storedHash.Length -eq 64) { '(PASS: 256-bit Hex)' } else { '(FAIL)' })"
}
finally {
    Write-Host "`nStopping Production Test API process (PID $($proc.Id))..."
    if (!$proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    # Reset env vars
    $env:ProductionMode = $null
    $env:Environment = $null
    $env:ASPNETCORE_ENVIRONMENT = "Testing"
    $env:ASPNETCORE_URLS = "http://localhost:5262"
    Write-Host "[SUCCESS] Process terminated."
}
