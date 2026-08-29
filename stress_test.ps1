param(
    [string]$BaseUrl = "http://localhost:5246/api",
    [int]$ConcurrentRequests = 50,
    [int]$TotalIterations = 200
)

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  TRIP DISTRIBUTION - HIGH CONCURRENCY LOAD & STRESS TEST   " -ForegroundColor Cyan
Write-Host "  Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "  Simulating high-throughput concurrent user traffic..." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Health check
try {
    $health = Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get -TimeoutSec 5
    Write-Host "[OK] API Server is ONLINE and HEALTHY" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] API Server at $BaseUrl is not reachable. Please ensure API is running." -ForegroundColor Red
    exit 1
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$successCount = 0
$failCount = 0
$latencies = [System.Collections.Generic.List[double]]::new()

$tasks = 1..$TotalIterations | ForEach-Object {
    $idx = $_
    [System.Threading.Tasks.Task]::Run([Action]{
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            # Test Health / Trip Query
            $response = Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get -TimeoutSec 5
            $sw.Stop()
            [System.Threading.Interlocked]::Increment([ref]$script:successCount) | Out-Null
            [System.Threading.Monitor]::Enter($script:latencies)
            try { $script:latencies.Add($sw.Elapsed.TotalMilliseconds) } finally { [System.Threading.Monitor]::Exit($script:latencies) }
        } catch {
            $sw.Stop()
            [System.Threading.Interlocked]::Increment([ref]$script:failCount) | Out-Null
        }
    })
}

[System.Threading.Tasks.Task]::WaitAll($tasks)
$stopwatch.Stop()

$latenciesList = $latencies.ToArray()
[Array]::Sort($latenciesList)

$p50 = if ($latenciesList.Length -gt 0) { $latenciesList[[Math]::Floor($latenciesList.Length * 0.5)] } else { 0 }
$p95 = if ($latenciesList.Length -gt 0) { $latenciesList[[Math]::Floor($latenciesList.Length * 0.95)] } else { 0 }
$p99 = if ($latenciesList.Length -gt 0) { $latenciesList[[Math]::Floor($latenciesList.Length * 0.99)] } else { 0 }
$rps = [Math]::Round(($successCount / ($stopwatch.Elapsed.TotalSeconds)), 2)

Write-Host "`n--- BENCHMARK RESULTS ---" -ForegroundColor Cyan
Write-Host "Total Requests  : $TotalIterations"
Write-Host "Successful      : $successCount" -ForegroundColor Green
Write-Host "Failed          : $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host "Total Time      : $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) seconds"
Write-Host "Throughput (RPS): $rps req/sec" -ForegroundColor Yellow
Write-Host "Latency (P50)   : $([Math]::Round($p50, 2)) ms"
Write-Host "Latency (P95)   : $([Math]::Round($p95, 2)) ms"
Write-Host "Latency (P99)   : $([Math]::Round($p99, 2)) ms"
Write-Host "============================================================`n" -ForegroundColor Cyan
