param(
    [string]$BaseUrl = "http://localhost:5246/api",
    [int]$TotalIterations = 200,
    [int]$Concurrency = 20
)

Add-Type -AssemblyName System.Net.Http

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  TRIP DISTRIBUTION - HIGH CONCURRENCY LOAD & STRESS TEST   " -ForegroundColor Cyan
Write-Host "  Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "  Concurrency: $Concurrency | Total Iterations: $TotalIterations" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Health check
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [System.TimeSpan]::FromSeconds(5)

try {
    $healthResp = $client.GetAsync("$BaseUrl/health").GetAwaiter().GetResult()
    if ($healthResp.IsSuccessStatusCode) {
        Write-Host "[OK] API Server is ONLINE and HEALTHY (Status: $($healthResp.StatusCode))" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] API Server returned status: $($healthResp.StatusCode)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[ERROR] API Server at $BaseUrl is not reachable: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$success = 0
$failed = 0
$latencies = [System.Collections.Generic.List[double]]::new()

Write-Host "Firing $TotalIterations concurrent requests..." -ForegroundColor Yellow

$batches = [Math]::Ceiling($TotalIterations / $Concurrency)

for ($b = 0; $b -lt $batches; $b++) {
    $batchSize = [Math]::Min($Concurrency, ($TotalIterations - ($b * $Concurrency)))
    $tasks = @()

    for ($i = 0; $i -lt $batchSize; $i++) {
        $tasks += [System.Threading.Tasks.Task]::Run([System.Func[double]]{
            $reqSw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $c = New-Object System.Net.Http.HttpClient
                $c.Timeout = [System.TimeSpan]::FromSeconds(5)
                $r = $c.GetAsync("$BaseUrl/health").GetAwaiter().GetResult()
                $reqSw.Stop()
                if ($r.IsSuccessStatusCode) {
                    return $reqSw.Elapsed.TotalMilliseconds
                }
                return -1.0
            } catch {
                return -1.0
            }
        })
    }

    [System.Threading.Tasks.Task]::WaitAll($tasks)

    foreach ($t in $tasks) {
        $val = $t.Result
        if ($val -ge 0) {
            $success++
            $latencies.Add($val)
        } else {
            $failed++
        }
    }
}

$sw.Stop()

$latArray = $latencies.ToArray()
[Array]::Sort($latArray)

$p50 = if ($latArray.Length -gt 0) { $latArray[[Math]::Floor($latArray.Length * 0.5)] } else { 0 }
$p95 = if ($latArray.Length -gt 0) { $latArray[[Math]::Floor($latArray.Length * 0.95)] } else { 0 }
$p99 = if ($latArray.Length -gt 0) { $latArray[[Math]::Floor($latArray.Length * 0.99)] } else { 0 }
$rps = if ($sw.Elapsed.TotalSeconds -gt 0) { [Math]::Round(($success / $sw.Elapsed.TotalSeconds), 2) } else { 0 }

Write-Host "`n--- BENCHMARK RESULTS ---" -ForegroundColor Cyan
Write-Host "Total Requests  : $TotalIterations"
Write-Host "Successful      : $success" -ForegroundColor Green
Write-Host "Failed          : $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "Total Time      : $([Math]::Round($sw.Elapsed.TotalSeconds, 2)) seconds"
Write-Host "Throughput (RPS): $rps req/sec" -ForegroundColor Yellow
Write-Host "Latency (P50)   : $([Math]::Round($p50, 2)) ms"
Write-Host "Latency (P95)   : $([Math]::Round($p95, 2)) ms"
Write-Host "Latency (P99)   : $([Math]::Round($p99, 2)) ms"
Write-Host "============================================================`n" -ForegroundColor Cyan
