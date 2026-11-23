# Task 4: Complete SHA-256 Implementation Audit & Full Digest Verification (Clean -d)
$Server = "localhost"

Write-Host "================================================================================"
Write-Host "TASK 4: SHA-256 IMPLEMENTATION AUDIT & FULL DIGEST VERIFICATION"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz')"
Write-Host "================================================================================"

$auditSource = @'
SET NOCOUNT ON;
WITH RowData AS (
    SELECT 
        HASHBYTES('SHA2_256', (
            SELECT r.* 
            FOR XML RAW('row'), ELEMENTS XSINIL, BINARY BASE64
        )) AS RowHash
    FROM dbo.[{TABLE_NAME}] AS r
)
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN 'EMPTY_TABLE_E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'
        ELSE CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', 
            STRING_AGG(CAST(CONVERT(VARCHAR(64), RowHash, 2) AS VARCHAR(MAX)), '|') 
            WITHIN GROUP (ORDER BY RowHash)
        ), 2)
    END AS FullTableSha256
FROM RowData;
'@

$tables = @(
    "ActivityLogs",
    "Expenses",
    "ExpenseSplits",
    "FriendConnections",
    "Groups",
    "Notifications",
    "OtpVerification",
    "Persons",
    "SettlementTransactions",
    "TripCollaborators",
    "Trips",
    "Users",
    "UserTokens"
)

$hashReport = @()

foreach ($tbl in $tables) {
    $sqlTbl = $auditSource.Replace("{TABLE_NAME}", $tbl)
    
    $sqlFile = "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\hash_query.sql"
    $sqlTbl | Out-File $sqlFile -Encoding utf8

    # Run on Production SPLIT_BILL_DB
    $prodHash = (sqlcmd -S $Server -E -d "SPLIT_BILL_DB" -i $sqlFile -h -1 -W | Where-Object { $_ -match '^[A-F0-9]{64}$|^EMPTY' }).Trim()

    # Run on Rehearsal SPLIT_BILL_DB_PROD_REHEARSAL
    $rehHash = (sqlcmd -S $Server -E -d "SPLIT_BILL_DB_PROD_REHEARSAL" -i $sqlFile -h -1 -W | Where-Object { $_ -match '^[A-F0-9]{64}$|^EMPTY' }).Trim()

    # Row Count
    $rc = (sqlcmd -S $Server -E -d "SPLIT_BILL_DB" -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.[$tbl];" -h -1 -W).Trim()

    $isMatch = ($prodHash -eq $rehHash)
    
    $hashReport += [PSCustomObject]@{
        TableName           = $tbl
        RowCount            = [int]$rc
        ParityStatus        = if ($isMatch) { "EXACT MATCH (256-bit)" } else { "MISMATCH" }
        Full_SHA256_Digest  = $prodHash
    }
}

Remove-Item "c:\My_Project\TRIP_DISTRIBUTION\trip_split\scratch\hash_query.sql" -Force -ErrorAction SilentlyContinue

Write-Host "`n================================================================================"
Write-Host "TASK 4: TABLE-BY-TABLE FULL SHA-256 PARITY AUDIT RESULTS"
Write-Host "================================================================================"
$hashReport | Format-Table TableName, RowCount, ParityStatus, Full_SHA256_Digest -AutoSize
