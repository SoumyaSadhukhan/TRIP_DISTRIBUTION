try {
    $conn = New-Object System.Data.SqlClient.SqlConnection("Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=SPLIT_BILL_DB_TEST;")
    $conn.Open()
    Write-Host "Success!"
    $conn.Close()
} catch {
    Write-Host "Caught exception: $($_.Exception.ToString())"
    if ($_.Exception.InnerException) {
        Write-Host "Inner exception: $($_.Exception.InnerException.ToString())"
    }
}
