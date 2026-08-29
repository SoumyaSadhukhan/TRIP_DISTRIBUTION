param(
    [string]$BaseUrl = "http://localhost:5246/api",
    [int]$TotalIterations = 200,
    [int]$Concurrency = 20
)

# Compile high-performance native C# load tester directly into memory
$csharpCode = @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

public class LoadTester
{
    private static readonly HttpClient _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };

    public static async Task<LoadResult> RunAsync(string baseUrl, int totalRequests, int concurrency)
    {
        var semaphore = new SemaphoreSlim(concurrency);
        var latencies = new List<double>(totalRequests);
        var lockObj = new object();
        int success = 0;
        int failed = 0;

        var sw = Stopwatch.StartNew();
        var tasks = new List<Task>();

        for (int i = 0; i < totalRequests; i++)
        {
            tasks.Add(Task.Run(async () =>
            {
                await semaphore.WaitAsync();
                var reqSw = Stopwatch.StartNew();
                try
                {
                    var response = await _httpClient.GetAsync(baseUrl + "/health");
                    reqSw.Stop();
                    if (response.IsSuccessStatusCode)
                    {
                        Interlocked.Increment(ref success);
                        lock (lockObj)
                        {
                            latencies.Add(reqSw.Elapsed.TotalMilliseconds);
                        }
                    }
                    else
                    {
                        Interlocked.Increment(ref failed);
                    }
                }
                catch
                {
                    reqSw.Stop();
                    Interlocked.Increment(ref failed);
                }
                finally
                {
                    semaphore.Release();
                }
            }));
        }

        await Task.WhenAll(tasks);
        sw.Stop();

        latencies.Sort();
        double p50 = latencies.Count > 0 ? latencies[(int)(latencies.Count * 0.50)] : 0;
        double p95 = latencies.Count > 0 ? latencies[(int)(latencies.Count * 0.95)] : 0;
        double p99 = latencies.Count > 0 ? latencies[(int)(latencies.Count * 0.99)] : 0;
        double rps = sw.Elapsed.TotalSeconds > 0 ? (success / sw.Elapsed.TotalSeconds) : 0;

        return new LoadResult
        {
            Total = totalRequests,
            Success = success,
            Failed = failed,
            ElapsedSeconds = sw.Elapsed.TotalSeconds,
            Rps = rps,
            P50 = p50,
            P95 = p95,
            P99 = p99
        };
    }
}

public class LoadResult
{
    public int Total { get; set; }
    public int Success { get; set; }
    public int Failed { get; set; }
    public double ElapsedSeconds { get; set; }
    public double Rps { get; set; }
    public double P50 { get; set; }
    public double P95 { get; set; }
    public double P99 { get; set; }
}
"@

Add-Type -TypeDefinition $csharpCode -ReferencedAssemblies "System.Net.Http" -Language CSharp

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  TRIP DISTRIBUTION - HIGH CONCURRENCY LOAD & STRESS TEST   " -ForegroundColor Cyan
Write-Host "  Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "  Concurrency: $Concurrency | Total Iterations: $TotalIterations" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Health check
try {
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [System.TimeSpan]::FromSeconds(5)
    $healthResp = $client.GetAsync("$BaseUrl/health").GetAwaiter().GetResult()
    if ($healthResp.IsSuccessStatusCode) {
        Write-Host "[OK] API Server is ONLINE and HEALTHY (Status: $($healthResp.StatusCode))`n" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] API Server returned status: $($healthResp.StatusCode)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[ERROR] API Server at $BaseUrl is not reachable: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Firing $TotalIterations concurrent requests..." -ForegroundColor Yellow

$result = [LoadTester]::RunAsync($BaseUrl, $TotalIterations, $Concurrency).GetAwaiter().GetResult()

Write-Host "`n--- BENCHMARK RESULTS ---" -ForegroundColor Cyan
Write-Host "Total Requests  : $($result.Total)"
Write-Host "Successful      : $($result.Success)" -ForegroundColor Green
Write-Host "Failed          : $($result.Failed)" -ForegroundColor $(if ($result.Failed -gt 0) { "Red" } else { "Green" })
Write-Host "Total Time      : $([Math]::Round($result.ElapsedSeconds, 2)) seconds"
Write-Host "Throughput (RPS): $([Math]::Round($result.Rps, 2)) req/sec" -ForegroundColor Yellow
Write-Host "Latency (P50)   : $([Math]::Round($result.P50, 2)) ms"
Write-Host "Latency (P95)   : $([Math]::Round($result.P95, 2)) ms"
Write-Host "Latency (P99)   : $([Math]::Round($result.P99, 2)) ms"
Write-Host "============================================================`n" -ForegroundColor Cyan
