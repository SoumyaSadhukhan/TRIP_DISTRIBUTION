using System;
using System.Collections.Generic;
using System.Data;
using System.Threading.Tasks;
using Dapper;
using TripDistribution.Models.DTOs;
using TripDistribution.Models.Entities;
using TripDistribution.Services.Data;

namespace TripDistribution.Services.Services
{
    public interface IFriendService
    {
        Task<IEnumerable<FriendConnection>> GetFriendsByUserIdAsync(string userId);
        Task<FriendConnection> AddFriendAsync(AddFriendRequestDto request);
    }

    public class FriendService : IFriendService
    {
        private readonly ISqlDbConnectionFactory _connectionFactory;
        private readonly IFileLoggerService _logger;

        public FriendService(ISqlDbConnectionFactory connectionFactory, IFileLoggerService logger)
        {
            _connectionFactory = connectionFactory;
            _logger = logger;
        }

        public async Task<IEnumerable<FriendConnection>> GetFriendsByUserIdAsync(string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                return await db.QueryAsync<FriendConnection>(
                    "SELECT connection_id as ConnectionId, user_id as UserId, friend_phone as FriendPhone, friend_name as FriendName, diet_type as DietType, status as Status, created_at as CreatedAt FROM FriendConnections WHERE user_id = @UserId ORDER BY friend_name",
                    new { UserId = userId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetFriendsByUserIdAsync for userId {userId}", ex, "FRIENDS");
                return new List<FriendConnection>();
            }
        }

        public async Task<FriendConnection> AddFriendAsync(AddFriendRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var connId = Guid.NewGuid().ToString("N");
                var now = DateTime.UtcNow;

                var sql = @"
                    INSERT INTO FriendConnections (connection_id, user_id, friend_phone, friend_name, diet_type, status, created_at)
                    VALUES (@ConnId, @UserId, @Phone, @Name, @DietType, 'ACCEPTED', @Now)";

                await db.ExecuteAsync(sql, new {
                    ConnId = connId,
                    UserId = request.UserId,
                    Phone = request.FriendPhone,
                    Name = request.FriendName,
                    DietType = request.DietType,
                    Now = now
                });

                _logger.LogInfo($"Friend added: UserId={request.UserId}, FriendName={request.FriendName}, Phone={request.FriendPhone}", "FRIENDS_ADD");

                return new FriendConnection
                {
                    ConnectionId = connId,
                    UserId = request.UserId,
                    FriendPhone = request.FriendPhone,
                    FriendName = request.FriendName,
                    DietType = request.DietType,
                    Status = "ACCEPTED",
                    CreatedAt = now
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in AddFriendAsync for userId {request.UserId}", ex, "FRIENDS_ADD");
                throw;
            }
        }
    }
}
