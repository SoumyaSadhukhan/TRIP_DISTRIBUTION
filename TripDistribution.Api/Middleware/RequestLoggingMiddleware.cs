using System;
using System.Diagnostics;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using TripDistribution.Services.Services;

namespace TripDistribution.Api.Middleware
{
    public class RequestLoggingMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly IFileLoggerService _logger;

        public RequestLoggingMiddleware(RequestDelegate next, IFileLoggerService logger)
        {
            _next = next;
            _logger = logger;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            var stopwatch = Stopwatch.StartNew();
            var request = context.Request;
            var ip = context.Connection.RemoteIpAddress?.ToString() ?? "Unknown";
            var path = request.Path.Value ?? "";
            var method = request.Method;

            try
            {
                await _next(context);
                stopwatch.Stop();

                var statusCode = context.Response.StatusCode;
                var logMsg = $"HTTP {method} {path} => Status {statusCode} ({stopwatch.ElapsedMilliseconds}ms) from IP {ip}";

                if (statusCode >= 400)
                {
                    _logger.LogWarning(logMsg, "API_REQUEST");
                }
                else
                {
                    _logger.LogInfo(logMsg, "API_REQUEST");
                }
            }
            catch (Exception ex)
            {
                stopwatch.Stop();
                _logger.LogError($"HTTP {method} {path} => UNHANDLED ERROR ({stopwatch.ElapsedMilliseconds}ms) from IP {ip}", ex, "API_ERROR");
                throw;
            }
        }
    }
}
