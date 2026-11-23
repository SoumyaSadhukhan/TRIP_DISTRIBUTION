$env:ASPNETCORE_ENVIRONMENT = "Testing"
$env:ConnectionStrings__DefaultConnection = "Data Source=localhost;Initial Catalog=SPLIT_BILL_DB;Integrated Security=True;TrustServerCertificate=True;"

Write-Host "Running API with ASPNETCORE_ENVIRONMENT=Testing and DefaultConnection=SPLIT_BILL_DB (EXPECTED TO FAIL)..."
$proc = Start-Process -FilePath "C:\My_Project\TRIP_DISTRIBUTION_API\TripDistribution.Api\bin\Debug\net9.0\TripDistribution.Api.exe" -ArgumentList "--contentRoot C:\My_Project\TRIP_DISTRIBUTION_API\TripDistribution.Api" -NoNewWindow -Wait -PassThru

Write-Host "Process ExitCode:" $proc.ExitCode
if ($proc.ExitCode -ne 0) {
    Write-Host "SUCCESS: Startup guard terminated process with non-zero exit code!"
} else {
    Write-Host "FAILURE: Process unexpectedly started!"
}
