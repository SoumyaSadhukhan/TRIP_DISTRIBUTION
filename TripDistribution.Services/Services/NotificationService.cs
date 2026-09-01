using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Dapper;
using TripDistribution.Models.Entities;
using TripDistribution.Services.Data;

namespace TripDistribution.Services.Services
{
    public interface INotificationService
    {
        Task<IEnumerable<Notification>> GetNotificationsByUserIdAsync(string userId);
        Task<int> GetUnreadCountAsync(string userId);
        Task<bool> MarkReadAsync(string? notificationId, string? userId);
        Task CreateNotificationAsync(Notification notification);
    }

    public class NotificationService : INotificationService
    {
        private readonly ISqlDbConnectionFactory _connectionFactory;
        private readonly IFileLoggerService _logger;

        public NotificationService(ISqlDbConnectionFactory connectionFactory, IFileLoggerService logger)
        {
            _connectionFactory = connectionFactory;
            _logger = logger;
        }

        public async Task<IEnumerable<Notification>> GetNotificationsByUserIdAsync(string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                // Ensure column exists
                try
                {
                    await db.ExecuteAsync(@"
                        IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Notifications') AND name = 'settlement_id')
                        BEGIN
                            ALTER TABLE Notifications ADD settlement_id NVARCHAR(100);
                        END");
                }
                catch { }

                var sql = @"
                    SELECT TOP 50 
                        notification_id as NotificationId, 
                        user_id as UserId, 
                        trip_id as TripId, 
                        trip_name as TripName, 
                        settlement_id as SettlementId, 
                        title as Title, 
                        message as Message, 
                        type as Type, 
                        amount as Amount, 
                        is_read as IsRead, 
                        created_at as CreatedAt
                    FROM Notifications
                    WHERE user_id = @UserId
                    ORDER BY created_at DESC";

                return await db.QueryAsync<Notification>(sql, new { UserId = userId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetNotificationsByUserIdAsync for user {userId}", ex, "NOTIFICATIONS");
                return new List<Notification>();
            }
        }

        public async Task<int> GetUnreadCountAsync(string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                return await db.ExecuteScalarAsync<int>(
                    "SELECT COUNT(*) FROM Notifications WHERE user_id = @UserId AND is_read = 0",
                    new { UserId = userId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetUnreadCountAsync for user {userId}", ex, "NOTIFICATIONS");
                return 0;
            }
        }

        public async Task<bool> MarkReadAsync(string? notificationId, string? userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                if (!string.IsNullOrEmpty(notificationId))
                {
                    await db.ExecuteAsync(
                        "UPDATE Notifications SET is_read = 1 WHERE notification_id = @NotificationId",
                        new { NotificationId = notificationId });
                }
                else if (!string.IsNullOrEmpty(userId))
                {
                    await db.ExecuteAsync(
                        "UPDATE Notifications SET is_read = 1 WHERE user_id = @UserId",
                        new { UserId = userId });
                }
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in MarkReadAsync for notif {notificationId} / user {userId}", ex, "NOTIFICATIONS");
                return false;
            }
        }

        public async Task CreateNotificationAsync(Notification notification)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var sql = @"
                    INSERT INTO Notifications (notification_id, user_id, trip_id, trip_name, settlement_id, title, message, type, amount, is_read, created_at)
                    VALUES (@NotificationId, @UserId, @TripId, @TripName, @SettlementId, @Title, @Message, @Type, @Amount, @IsRead, @CreatedAt)";

                await db.ExecuteAsync(sql, notification);
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in CreateNotificationAsync for user {notification.UserId}", ex, "NOTIFICATIONS");
            }
        }
    }
}
