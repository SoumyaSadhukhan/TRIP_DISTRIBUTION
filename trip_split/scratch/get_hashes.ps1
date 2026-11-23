Get-ChildItem -Path "c:\My_Project\TRIP_DISTRIBUTION\trip_split\migrations" -Filter "*.sql" | ForEach-Object {
    [PSCustomObject]@{
        Script = $_.Name
        LengthBytes = $_.Length
        SHA256 = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
    }
} | Format-List
