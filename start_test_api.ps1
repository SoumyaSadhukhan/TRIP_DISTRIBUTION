$env:ASPNETCORE_ENVIRONMENT = "Testing"
$env:ASPNETCORE_URLS = "http://localhost:5262"
Remove-Item Env:\ConnectionStrings__DefaultConnection -ErrorAction SilentlyContinue

Write-Host "Starting API with ASPNETCORE_ENVIRONMENT=Testing on port 5262..."
& "C:\My_Project\TRIP_DISTRIBUTION_API\TripDistribution.Api\bin\Debug\net9.0\TripDistribution.Api.exe" --contentRoot "C:\My_Project\TRIP_DISTRIBUTION_API\TripDistribution.Api"
