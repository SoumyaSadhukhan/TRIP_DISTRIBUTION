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
        Task<IEnumerable<dynamic>> GetFriendsByUserIdAsync(string userId);
        Task<IEnumerable<dynamic>> SearchUsersAsync(string query, string currentUserId);
        Task<IEnumerable<dynamic>> CheckContactsAsync(List<string> contacts, string currentUserId);
        Task<ApiResponse<dynamic>> AddFriendAsync(AddFriendRequestDto request);
        Task<IEnumerable<dynamic>> GetFriendRequestsAsync(string userId);
        Task<ApiResponse<bool>> AcceptFriendRequestAsync(string connectionId, string userId);
        Task<ApiResponse<bool>> DeclineFriendRequestAsync(string connectionId, string userId);
        Task<ApiResponse<bool>> DeleteFriendAsync(string connectionId, string userId);
    }

    public class FriendService : IFriendService
    {
        private readonly ISqlDbConnectionFactory _connectionFactory;
        private readonly IFileLoggerService _logger;
        private readonly INotificationService _notificationService;

        public FriendService(
            ISqlDbConnectionFactory connectionFactory, 
            IFileLoggerService logger,
            INotificationService notificationService)
        {
            _connectionFactory = connectionFactory;
            _logger = logger;
            _notificationService = notificationService;
        }

        public async Task<IEnumerable<dynamic>> GetFriendsByUserIdAsync(string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var currentUser = await db.QueryFirstOrDefaultAsync<User>(
                    "SELECT user_id as UserId, phone_number as PhoneNumber FROM Users WHERE user_id = @UserId",
                    new { UserId = userId });

                var cleanUserPhone = "";
                if (currentUser != null && !string.IsNullOrEmpty(currentUser.PhoneNumber))
                {
                    cleanUserPhone = new string(currentUser.PhoneNumber.Where(char.IsDigit).ToArray());
                    if (cleanUserPhone.Length > 10) cleanUserPhone = cleanUserPhone.Substring(cleanUserPhone.Length - 10);
                }

                // Query all mutual accepted friendships and dynamically join live Users data
                var sql = @"
                    SELECT 
                        fc.connection_id as id,
                        fc.connection_id as connectionId,
                        fc.user_id as userId,
                        ISNULL(u.user_id, fc.friend_user_id) as friendUserId,
                        ISNULL(NULLIF(u.full_name, ''), ISNULL(NULLIF(fc.friend_name, ''), 'User')) as friendName,
                        ISNULL(NULLIF(u.phone_number, ''), fc.friend_phone) as friendPhone,
                        ISNULL(u.diet_type, fc.diet_type) as dietType,
                        ISNULL(NULLIF(u.diet_name, ''), ISNULL(NULLIF(fc.diet_name, ''), 'Vegetarian')) as dietName,
                        fc.status as status,
                        fc.created_at as createdAt
                    FROM (
                        SELECT connection_id, user_id, friend_user_id, friend_phone, friend_name, diet_type, diet_name, status, created_at
                        FROM FriendConnections
                        WHERE user_id = @UserId AND status = 'ACCEPTED'
                        UNION
                        SELECT connection_id, friend_user_id as user_id, user_id as friend_user_id, friend_phone, friend_name, diet_type, diet_name, status, created_at
                        FROM FriendConnections
                        WHERE (friend_user_id = @UserId OR (receiver_id = @UserId AND requester_id <> @UserId)) AND status = 'ACCEPTED'
                    ) fc
                    LEFT JOIN Users u ON (
                        (fc.friend_user_id IS NOT NULL AND fc.friend_user_id <> '' AND u.user_id = fc.friend_user_id)
                        OR (fc.friend_phone IS NOT NULL AND fc.friend_phone <> '' AND u.phone_number LIKE '%' + RIGHT(fc.friend_phone, 10) + '%')
                    )
                    WHERE fc.friend_user_id <> @UserId";

                var friends = (await db.QueryAsync<dynamic>(sql, new { UserId = userId })).ToList();

                // Deduplicate friends by phone or friendUserId
                var uniqueFriends = friends
                    .GroupBy(f => (string)(!string.IsNullOrEmpty((string)f.friendUserId) ? f.friendUserId : f.friendPhone))
                    .Select(g => g.First())
                    .ToList();

                _logger.LogInfo($"Fetched {uniqueFriends.Count} unique friends for userId {userId}", "FRIENDS");
                return uniqueFriends;
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetFriendsByUserIdAsync for userId {userId}", ex, "FRIENDS");
                return new List<dynamic>();
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
                        user_id as userId,
                        phone_number as phone, 
                        full_name as fullName, 
                        diet_type as dietType, 
                        diet_name as dietName 
                      FROM Users 
                      WHERE user_id <> @CurrentUserId 
                        AND (
                            (@Clean <> '' AND phone_number LIKE '%' + @Clean + '%')
                            OR (@NameQuery <> '' AND full_name LIKE '%' + @NameQuery + '%')
                        )",
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

                var users = await db.QueryAsync<dynamic>(
                    @"SELECT 
                        user_id as id, 
                        user_id as userId,
                        phone_number as phone, 
                        full_name as fullName, 
                        diet_type as dietType, 
                        diet_name as dietName 
                      FROM Users 
                      WHERE user_id <> @CurrentUserId",
                    new { CurrentUserId = currentUserId ?? "" });

                var matched = users.Where(u =>
                {
                    var uPhone = new string(((string)(u.phone ?? "")).Where(char.IsDigit).ToArray());
                    return cleanContacts.Any(c => uPhone.EndsWith(c));
                }).ToList();

                return matched;
            }
            catch (Exception ex)
            {
                _logger.LogError("Error in CheckContactsAsync", ex, "FRIENDS");
                return new List<dynamic>();
            }
        }

        public async Task<ApiResponse<dynamic>> AddFriendAsync(AddFriendRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();

                // 1. Fetch current requester details
                var requester = await db.QueryFirstOrDefaultAsync<User>(
                    "SELECT user_id as UserId, phone_number as PhoneNumber, full_name as FullName FROM Users WHERE user_id = @UserId",
                    new { UserId = request.UserId });

                var cleanRequesterPhone = "";
                if (requester != null && !string.IsNullOrEmpty(requester.PhoneNumber))
                {
                    cleanRequesterPhone = new string(requester.PhoneNumber.Where(char.IsDigit).ToArray());
                    if (cleanRequesterPhone.Length > 10) cleanRequesterPhone = cleanRequesterPhone.Substring(cleanRequesterPhone.Length - 10);
                }

                var cleanFriendPhone = new string((request.FriendPhone ?? "").Where(char.IsDigit).ToArray());
                if (cleanFriendPhone.Length > 10) cleanFriendPhone = cleanFriendPhone.Substring(cleanFriendPhone.Length - 10);

                // 2. Prevent adding self
                if ((!string.IsNullOrEmpty(cleanRequesterPhone) && !string.IsNullOrEmpty(cleanFriendPhone) && cleanRequesterPhone == cleanFriendPhone)
                    || (!string.IsNullOrEmpty(request.FriendUserId) && request.FriendUserId == request.UserId))
                {
                    _logger.LogWarning($"Rejected self friend request for user {request.UserId}", "FRIENDS_ADD");
                    return new ApiResponse<dynamic> { Success = false, Message = "You cannot add yourself as a friend." };
                }

                // 3. Find if target user is registered
                User? friendUser = null;
                if (!string.IsNullOrEmpty(request.FriendUserId))
                {
                    friendUser = await db.QueryFirstOrDefaultAsync<User>(
                        "SELECT user_id as UserId, phone_number as PhoneNumber, full_name as FullName, diet_type as DietType, diet_name as DietName FROM Users WHERE user_id = @Id",
                        new { Id = request.FriendUserId });
                }

                if (friendUser == null && !string.IsNullOrEmpty(cleanFriendPhone))
                {
                    friendUser = await db.QueryFirstOrDefaultAsync<User>(
                        "SELECT user_id as UserId, phone_number as PhoneNumber, full_name as FullName, diet_type as DietType, diet_name as DietName FROM Users WHERE phone_number LIKE '%' + @Phone + '%'",
                        new { Phone = cleanFriendPhone });
                }

                var friendUserId = friendUser?.UserId ?? (request.FriendUserId ?? "");
                var friendName = friendUser?.FullName ?? (!string.IsNullOrEmpty(request.FriendName) ? request.FriendName : "Friend");
                var dietType = friendUser?.DietType ?? request.DietType;
                var dietName = friendUser?.DietName ?? (dietType == 1 ? "Non-Vegetarian" : "Vegetarian");

                // 4. Check for existing connection or pending request
                var existingConns = (await db.QueryAsync<dynamic>(
                    @"SELECT connection_id as connectionId, status 
                      FROM FriendConnections 
                      WHERE (
                          (user_id = @UserId AND (friend_user_id = @FriendUserId OR (@CleanPhone <> '' AND friend_phone LIKE '%' + @CleanPhone + '%')))
                          OR (friend_user_id = @UserId AND (user_id = @FriendUserId OR (@CleanReqPhone <> '' AND friend_phone LIKE '%' + @CleanReqPhone + '%')))
                          OR (requester_id = @UserId AND receiver_id = @FriendUserId AND @FriendUserId <> '')
                          OR (requester_id = @FriendUserId AND receiver_id = @UserId AND @FriendUserId <> '')
                      )",
                    new {
                        UserId = request.UserId,
                        FriendUserId = friendUserId,
                        CleanPhone = cleanFriendPhone,
                        CleanReqPhone = cleanRequesterPhone
                    })).ToList();

                if (existingConns.Any(c => (string)c.status == "ACCEPTED"))
                {
                    return new ApiResponse<dynamic> { Success = false, Message = "You are already friends with this contact." };
                }

                if (existingConns.Any(c => (string)c.status == "PENDING"))
                {
                    return new ApiResponse<dynamic> { Success = false, Message = "A friend request is already pending between you." };
                }

                // If old declined or canceled rows exist, remove them so fresh request is clean
                if (existingConns.Count > 0)
                {
                    foreach (var old in existingConns)
                    {
                        await db.ExecuteAsync("DELETE FROM FriendConnections WHERE connection_id = @Id", new { Id = (string)old.connectionId });
                    }
                }

                var connId = Guid.NewGuid().ToString("N");
                var now = DateTime.UtcNow;

                var sql = @"
                    INSERT INTO FriendConnections (connection_id, user_id, friend_user_id, friend_phone, friend_name, diet_type, diet_name, status, requester_id, receiver_id, created_at)
                    VALUES (@ConnId, @UserId, @FriendUserId, @Phone, @Name, @DietType, @DietName, 'PENDING', @UserId, @ReceiverId, @Now)";

                await db.ExecuteAsync(sql, new {
                    ConnId = connId,
                    UserId = request.UserId,
                    FriendUserId = friendUserId,
                    Phone = request.FriendPhone ?? cleanFriendPhone,
                    Name = friendName,
                    DietType = dietType,
                    DietName = dietName,
                    ReceiverId = friendUserId,
                    Now = now
                });

                // 5. Send Real-time Notification to Recipient
                if (!string.IsNullOrEmpty(friendUserId))
                {
                    var senderName = requester?.FullName ?? "A user";
                    var senderPhone = requester?.PhoneNumber ?? "";
                    await _notificationService.CreateNotificationAsync(new Notification
                    {
                        NotificationId = Guid.NewGuid().ToString("N"),
                        UserId = friendUserId,
                        Title = "New Friend Request",
                        Message = $"{senderName} ({senderPhone}) sent you a trip friend request.",
                        Type = "FRIEND_REQUEST",
                        IsRead = false,
                        CreatedAt = DateTime.UtcNow
                    });
                }

                _logger.LogInfo($"Friend request sent: From={request.UserId} to {friendName} ({cleanFriendPhone})", "FRIENDS_ADD");

                return new ApiResponse<dynamic>
                {
                    Success = true,
                    Message = "Friend request sent successfully!",
                    Data = new
                    {
                        id = connId,
                        connectionId = connId,
                        friendName = friendName,
                        friendPhone = request.FriendPhone,
                        friendUserId = friendUserId,
                        dietType = dietType,
                        dietName = dietName,
                        status = "PENDING"
                    }
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in AddFriendAsync for userId {request.UserId}", ex, "FRIENDS_ADD");
                return new ApiResponse<dynamic> { Success = false, Message = $"Failed to send friend request: {ex.Message}" };
            }
        }

        public async Task<IEnumerable<dynamic>> GetFriendRequestsAsync(string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var currentUser = await db.QueryFirstOrDefaultAsync<User>(
                    "SELECT user_id as UserId, phone_number as PhoneNumber FROM Users WHERE user_id = @UserId",
                    new { UserId = userId });

                var cleanPhone = "";
                if (currentUser != null && !string.IsNullOrEmpty(currentUser.PhoneNumber))
                {
                    cleanPhone = new string(currentUser.PhoneNumber.Where(char.IsDigit).ToArray());
                    if (cleanPhone.Length > 10) cleanPhone = cleanPhone.Substring(cleanPhone.Length - 10);
                }

                // Query pending requests where current user is the receiver, dynamically joining live requester profile
                var sql = @"
                    SELECT 
                        fc.connection_id as id,
                        fc.connection_id as connectionId, 
                        fc.requester_id as requesterId, 
                        ISNULL(NULLIF(u.full_name, ''), ISNULL(NULLIF(fc.friend_name, ''), 'A member')) as requesterName, 
                        ISNULL(NULLIF(u.phone_number, ''), fc.friend_phone) as requesterPhone, 
                        ISNULL(u.diet_type, fc.diet_type) as dietType,
                        ISNULL(NULLIF(u.diet_name, ''), ISNULL(NULLIF(fc.diet_name, ''), 'Vegetarian')) as dietName,
                        fc.status, 
                        fc.created_at as createdAt 
                    FROM FriendConnections fc
                    LEFT JOIN Users u ON (fc.requester_id = u.user_id)
                    WHERE (fc.receiver_id = @UserId OR (fc.friend_user_id = @UserId AND fc.requester_id <> @UserId) OR (@CleanPhone <> '' AND fc.friend_phone LIKE '%' + @CleanPhone + '%' AND fc.requester_id <> @UserId))
                      AND fc.status = 'PENDING'";

                return await db.QueryAsync<dynamic>(sql, new { UserId = userId, CleanPhone = cleanPhone });
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
                var conn = await db.QueryFirstOrDefaultAsync<dynamic>(
                    "SELECT connection_id, requester_id, receiver_id, friend_user_id, user_id FROM FriendConnections WHERE connection_id = @Id",
                    new { Id = connectionId });

                if (conn == null)
                {
                    return new ApiResponse<bool> { Success = false, Message = "Friend request not found." };
                }

                await db.ExecuteAsync(
                    "UPDATE FriendConnections SET status = 'ACCEPTED' WHERE connection_id = @Id",
                    new { Id = connectionId });

                // Fetch accepting user details for notification
                var acceptingUser = await db.QueryFirstOrDefaultAsync<User>(
                    "SELECT user_id as UserId, full_name as FullName, phone_number as PhoneNumber FROM Users WHERE user_id = @UserId",
                    new { UserId = userId });

                string requesterId = conn.requester_id ?? conn.user_id;
                if (!string.IsNullOrEmpty(requesterId) && requesterId != userId)
                {
                    var name = acceptingUser?.FullName ?? "Your friend";
                    await _notificationService.CreateNotificationAsync(new Notification
                    {
                        NotificationId = Guid.NewGuid().ToString("N"),
                        UserId = requesterId,
                        Title = "Friend Request Accepted",
                        Message = $"{name} accepted your friend request! You can now add each other to trips.",
                        Type = "FRIEND_ACCEPTED",
                        IsRead = false,
                        CreatedAt = DateTime.UtcNow
                    });
                }

                _logger.LogInfo($"Friend request {connectionId} accepted by {userId}", "FRIENDS_ACCEPT");
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
                    "DELETE FROM FriendConnections WHERE connection_id = @Id",
                    new { Id = connectionId });

                _logger.LogInfo($"Friend request {connectionId} declined/removed by {userId}", "FRIENDS_DECLINE");
                return new ApiResponse<bool> { Success = true, Message = "Friend request declined." };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in DeclineFriendRequestAsync for conn {connectionId}", ex, "FRIENDS");
                return new ApiResponse<bool> { Success = false, Message = ex.Message };
            }
        }

        public async Task<ApiResponse<bool>> DeleteFriendAsync(string connectionId, string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var conn = await db.QueryFirstOrDefaultAsync<dynamic>(
                    @"SELECT connection_id, user_id, friend_user_id, friend_phone, requester_id, receiver_id 
                      FROM FriendConnections 
                      WHERE connection_id = @Id OR user_id = @Id OR friend_user_id = @Id",
                    new { Id = connectionId });

                if (conn != null)
                {
                    string u1 = conn.user_id ?? conn.requester_id ?? userId;
                    string u2 = conn.friend_user_id ?? conn.receiver_id ?? connectionId;
                    string phone = conn.friend_phone ?? "";
                    var cleanPhone = new string(phone.Where(char.IsDigit).ToArray());
                    if (cleanPhone.Length > 10) cleanPhone = cleanPhone.Substring(cleanPhone.Length - 10);

                    await db.ExecuteAsync(@"
                        DELETE FROM FriendConnections 
                        WHERE connection_id = @ConnId
                           OR (user_id = @U1 AND (friend_user_id = @U2 OR (@CleanPhone <> '' AND friend_phone LIKE '%' + @CleanPhone + '%')))
                           OR (user_id = @U2 AND (friend_user_id = @U1 OR (@CleanPhone <> '' AND friend_phone LIKE '%' + @CleanPhone + '%')))
                           OR (requester_id = @U1 AND receiver_id = @U2)
                           OR (requester_id = @U2 AND receiver_id = @U1)",
                        new { ConnId = (string)conn.connection_id, U1 = u1, U2 = u2, CleanPhone = cleanPhone });
                }
                else
                {
                    await db.ExecuteAsync(@"
                        DELETE FROM FriendConnections 
                        WHERE connection_id = @Id 
                           OR (user_id = @UserId AND friend_user_id = @Id)
                           OR (friend_user_id = @UserId AND user_id = @Id)",
                        new { Id = connectionId, UserId = userId });
                }

                _logger.LogInfo($"Deleted friend connection {connectionId} for user {userId}", "FRIENDS_DELETE");
                return new ApiResponse<bool> { Success = true, Message = "Friend removed successfully." };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in DeleteFriendAsync for conn {connectionId}", ex, "FRIENDS");
                return new ApiResponse<bool> { Success = false, Message = ex.Message };
            }
        }
    }
}
