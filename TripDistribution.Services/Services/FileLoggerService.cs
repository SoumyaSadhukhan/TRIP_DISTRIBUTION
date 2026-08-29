using System;
using System.IO;

namespace TripDistribution.Services.Services
{
    public interface IFileLoggerService
    {
        void LogInfo(string message, string? category = null);
        void LogWarning(string message, string? category = null);
        void LogError(string message, Exception? ex = null, string? category = null);
    }

    public class FileLoggerService : IFileLoggerService
    {
        private static readonly object _lock = new object();
        private readonly string _logDirectory;

        public FileLoggerService()
        {
            _logDirectory = Path.Combine(@"C:\My_Project\TRIP_DISTRIBUTION", "logggg");
            if (!Directory.Exists(_logDirectory))
            {
                Directory.CreateDirectory(_logDirectory);
            }
        }

        private void WriteLog(string level, string message, string? category = null, Exception? ex = null)
        {
            try
            {
                var dateStr = DateTime.Now.ToString("yyyy-MM-dd");
                var filePath = Path.Combine(_logDirectory, $"api_logs_{dateStr}.txt");
                var cat = string.IsNullOrWhiteSpace(category) ? "GENERAL" : category.ToUpper();
                var logLine = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] [{level}] [{cat}] {message}";

                if (ex != null)
                {
                    logLine += $"\n  Exception: {ex.Message}\n  StackTrace: {ex.StackTrace}";
                }

                lock (_lock)
                {
                    File.AppendAllText(filePath, logLine + Environment.NewLine);
                }

                var prevColor = Console.ForegroundColor;
                Console.ForegroundColor = level switch
                {
                    "ERROR" => ConsoleColor.Red,
                    "WARN" => ConsoleColor.Yellow,
                    "SYNC" => ConsoleColor.Cyan,
                    _ => ConsoleColor.Gray
                };
                Console.WriteLine(logLine);
                Console.ForegroundColor = prevColor;
            }
            catch
            {
            }
        }

        public void LogInfo(string message, string? category = null)
        {
            WriteLog("INFO", message, category);
        }

        public void LogWarning(string message, string? category = null)
        {
            WriteLog("WARN", message, category);
        }

        public void LogError(string message, Exception? ex = null, string? category = null)
        {
            WriteLog("ERROR", message, category, ex);
        }
    }
}
