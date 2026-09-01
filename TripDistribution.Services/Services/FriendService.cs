using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
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
        Task<IEnumerable<dynamic>> SearchUsersAsync(string query, string currentUserId);
        Task<IEnumerable<dynamic>> CheckContactsAsync(List<string> contacts, string currentUserId);
        Task<FriendConnection> AddFriendAsync(AddFriendRequestDto request);
        Task<IEnumerable<dynamic>> GetFriendRequestsAsync(string userId);
        Task<ApiResponse<bool>> AcceptFriendRequestAsync(string connectionId, string userId);
        Task<ApiResponse<bool>> DeclineFriendRequestAsync(string connectionId, string userId);
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
                    @"SELECT 
                        connection_id as ConnectionId, 
                        user_id as UserId, 
                        friend_user_id as FriendUserId,
                        friend_phone as FriendPhone, 
                        friend_name as FriendName, 
                        diet_type as DietType, 
                        diet_name as DietName,
                        status as Status, 
                        requester_id as RequesterId,
                        receiver_id as ReceiverId,
                        created_at as CreatedAt 
                      FROM FriendConnections 
                      WHERE (user_id = @UserId OR friend_user_id = @UserId OR receiver_id = @UserId) AND status = 'ACCEPTED'
                      ORDER BY friend_name",
                    new { UserId = userId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetFriendsByUserIdAsync for userId {userId}", ex, "FRIENDS");
                return new List<FriendConnection>();
            }
        }

        public async Task<IEnumerable<dynamic>> SearchUsersAsync(string query, string currentUserId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var clean = new string((query ?? "").Where(char.IsDigit).ToArray());
                var nameQuery = query ?? "";

                return await db.QueryAsync<dynamic>(
                    @"SELECT TOP 20 
                        user_id as id, 
                        phone_number as phone, 
                        full_name as fullName, 
                        diet_type as dietType, 
                        diet_name as dietName 
                      FROM Users 
                      WHERE user_id <> @CurrentUserId 
                        AND (phone_number LIKE '%' + @Clean + '%' OR full_name LIKE '%' + @NameQuery + '%')",
                    new { CurrentUserId = currentUserId ?? "", Clean = clean, NameQuery = nameQuery });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in SearchUsersAsync for query {query}", ex, "FRIENDS");
                return new List<dynamic>();
            }
        }

        public async Task<IEnumerable<dynamic>> CheckContactsAsync(List<string> contacts, string currentUserId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                if (contacts == null || contacts.Count == 0) return new List<dynamic>();

                var cleanContacts = contacts.Select(c =>
                {
                    var digits = new string(c.Where(char.IsDigit).ToArray());
                    return digits.Length >= 10 ? digits.Substring(digits.Length - 10) : digits;
                }).Where(d => !string.IsNullOrEmpty(d)).Distinct().ToList();

                return await db.QueryAsync<dynamic>(
                    @"SELECT 
                        user_id as id, 
                        phone_number as phone, 
                        full_name as fullName, 
                        diet_type as dietType, 
                        diet_name as dietName 
                      FROM Users 
                      WHERE user_id <> @CurrentUserId",
                    new { CurrentUserId = currentUserId ?? "" });
            }
            catch (Exception ex)
            {
                _logger.LogError("Error in CheckContactsAsync", ex, "FRIENDS");
                return new List<dynamic>();
            }
        }

        public async Task<FriendConnection> AddFriendAsync(AddFriendRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var connId = Guid.NewGuid().ToString("N");
                var now = DateTime.UtcNow;

                var cleanPhone = new string((request.FriendPhone ?? "").Where(char.IsDigit).ToArray());
                if (cleanPhone.Length >= 10) cleanPhone = cleanPhone.Substring(cleanPhone.Length - 10);

                var friendUser = await db.QueryFirstOrDefaultAsync<User>(
                    "SELECT TOP 1 user_id as UserId, phone_number as PhoneNumber, full_name as FullName, diet_type as DietType, diet_name as DietName FROM Users WHERE phone_number LIKE '%' + @Phone + '%'",
                    new { Phone = cleanPhone });

                var friendUserId = friendUser?.UserId ?? "";
                var friendName = !string.IsNullOrEmpty(request.FriendName) ? request.FriendName : (friendUser?.FullName ?? "Friend");
                var dietType = friendUser?.DietType ?? request.DietType;
                var dietName = friendUser?.DietName ?? (dietType == 1 ? "Non-Vegetarian" : "Vegetarian");

                var sql = @"
                    INSERT INTO FriendConnections (connection_id, user_id, friend_user_id, friend_phone, friend_name, diet_type, diet_name, status, requester_id, receiver_id, created_at)
                    VALUES (@ConnId, @UserId, @FriendUserId, @Phone, @Name, @DietType, @DietName, 'ACCEPTED', @UserId, @FriendUserId, @Now)";

                await db.ExecuteAsync(sql, new {
                    ConnId = connId,
                    UserId = request.UserId,
                    FriendUserId = friendUserId,
                    Phone = request.FriendPhone,
                    Name = friendName,
                    DietType = dietType,
                    DietName = dietName,
                    Now = now
                });

                _logger.LogInfo($"Friend added: UserId={request.UserId}, FriendName={friendName}, Phone={request.FriendPhone}", "FRIENDS_ADD");

                return new FriendConnection
                {
                    ConnectionId = connId,
                    UserId = request.UserId,
                    FriendUserId = friendUserId,
                    FriendPhone = request.FriendPhone ?? "",
                    FriendName = friendName,
                    DietType = dietType,
                    DietName = dietName,
                    Status = "ACCEPTED",
                    RequesterId = request.UserId,
                    ReceiverId = friendUserId,
                    CreatedAt = now
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in AddFriendAsync for userId {request.UserId}", ex, "FRIENDS_ADD");
                throw;
            }
        }

        public async Task<IEnumerable<dynamic>> GetFriendRequestsAsync(string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                return await db.QueryAsync<dynamic>(
                    @"SELECT 
                        connection_id as connectionId, 
                        user_id as senderId, 
                        friend_name as senderName, 
                        friend_phone as senderPhone, 
                        status, 
                        created_at as createdAt 
                      FROM FriendConnections 
                      WHERE (friend_user_id = @UserId OR receiver_id = @UserId) AND status = 'PENDING'",
                    new { UserId = userId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetFriendRequestsAsync for userId {userId}", ex, "FRIENDS");
                return new List<dynamic>();
            }
        }

        public async Task<ApiResponse<bool>> AcceptFriendRequestAsync(string connectionId, string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                await db.ExecuteAsync(
                    "UPDATE FriendConnections SET status = 'ACCEPTED' WHERE connection_id = @Id",
                    new { Id = connectionId });
                return new ApiResponse<bool> { Success = true, Message = "Friend request accepted!" };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in AcceptFriendRequestAsync for conn {connectionId}", ex, "FRIENDS");
                return new ApiResponse<bool> { Success = false, Message = ex.Message };
            }
        }

        public async Task<ApiResponse<bool>> DeclineFriendRequestAsync(string connectionId, string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                await db.ExecuteAsync(
                    "UPDATE FriendConnections SET status = 'DECLINED' WHERE connection_id = @Id",
                    new { Id = connectionId });
                return new ApiResponse<bool> { Success = true, Message = "Friend request declined." };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in DeclineFriendRequestAsync for conn {connectionId}", ex, "FRIENDS");
                return new ApiResponse<bool> { Success = false, Message = ex.Message };
            }
        }
    }
}
