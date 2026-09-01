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
    public interface ISettlementService
    {
        Task<IEnumerable<SettlementTransaction>> GetSettlementsByTripIdAsync(string tripId);
        Task<IEnumerable<SettlementProposalDto>> GetPendingSettlementsAsync(string userId, string? phone);
        Task<SettlementTransaction> CreateSettlementAsync(CreateSettlementRequestDto request);
        Task<ApiResponse<bool>> UpdateSettlementAmountAsync(string settlementId, decimal newAmount, string userId);
        Task<ApiResponse<bool>> AcceptSettlementAsync(string settlementId, string userId);
        Task<ApiResponse<bool>> DeclineSettlementAsync(string settlementId, string? userId);
    }

    public class SettlementService : ISettlementService
    {
        private readonly ISqlDbConnectionFactory _connectionFactory;
        private readonly IFileLoggerService _logger;

        public SettlementService(ISqlDbConnectionFactory connectionFactory, IFileLoggerService logger)
        {
            _connectionFactory = connectionFactory;
            _logger = logger;
        }

        public async Task<IEnumerable<SettlementTransaction>> GetSettlementsByTripIdAsync(string tripId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                return await db.QueryAsync<SettlementTransaction>(
                    "SELECT settlement_id as SettlementId, trip_id as TripId, from_person_id as FromPersonId, to_person_id as ToPersonId, amount as Amount, is_completed as IsCompleted, status as Status, created_by_user_id as CreatedByUserId, settled_at as SettledAt FROM SettlementTransactions WHERE trip_id = @TripId ORDER BY settled_at DESC",
                    new { TripId = tripId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetSettlementsByTripIdAsync for tripId {tripId}", ex, "SETTLEMENTS");
                return new List<SettlementTransaction>();
            }
        }

        public async Task<IEnumerable<SettlementProposalDto>> GetPendingSettlementsAsync(string userId, string? phone)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var cleanPhone = !string.IsNullOrEmpty(phone) ? new string(phone.Where(char.IsDigit).ToArray()) : "";
                if (cleanPhone.Length > 10) cleanPhone = cleanPhone.Substring(cleanPhone.Length - 10);

                var query = @"
                    SELECT 
                        st.settlement_id as SettlementId,
                        st.trip_id as TripId,
                        ISNULL(t.name, 'Trip') as TripName,
                        st.from_person_id as FromPersonId,
                        ISNULL(fp.name, 'Member') as FromPersonName,
                        fp.user_id as FromUserId,
                        fp.phone_number as FromPhone,
                        st.to_person_id as ToPersonId,
                        ISNULL(tp.name, 'Member') as ToPersonName,
                        tp.user_id as ToUserId,
                        tp.phone_number as ToPhone,
                        st.amount as Amount,
                        st.status as Status,
                        st.created_by_user_id as CreatedByUserId,
                        st.settled_at as SettledAt
                    FROM SettlementTransactions st
                    LEFT JOIN Trips t ON st.trip_id = t.trip_id
                    LEFT JOIN Persons fp ON st.from_person_id = fp.person_id
                    LEFT JOIN Persons tp ON st.to_person_id = tp.person_id
                    WHERE st.status = 'PENDING'
                      AND (
                          fp.user_id = @UserId 
                          OR tp.user_id = @UserId
                          OR (@CleanPhone <> '' AND (fp.phone_number LIKE '%' + @CleanPhone + '%' OR tp.phone_number LIKE '%' + @CleanPhone + '%'))
                          OR st.created_by_user_id = @UserId
                      )
                    ORDER BY st.settled_at DESC";

                var rows = await db.QueryAsync<dynamic>(query, new { UserId = userId ?? "", CleanPhone = cleanPhone });

                var result = new List<SettlementProposalDto>();
                foreach (var r in rows)
                {
                    string fromUid = r.FromUserId ?? "";
                    string toUid = r.ToUserId ?? "";
                    string fromPh = r.FromPhone ?? "";
                    string toPh = r.ToPhone ?? "";

                    bool isPayer = (fromUid == userId) || (!string.IsNullOrEmpty(cleanPhone) && fromPh.Contains(cleanPhone));
                    bool isPayee = (toUid == userId) || (!string.IsNullOrEmpty(cleanPhone) && toPh.Contains(cleanPhone));

                    result.Add(new SettlementProposalDto
                    {
                        SettlementId = r.SettlementId,
                        TripId = r.TripId,
                        TripName = r.TripName,
                        FromPersonId = r.FromPersonId,
                        FromPersonName = r.FromPersonName,
                        FromPhone = fromPh,
                        ToPersonId = r.ToPersonId,
                        ToPersonName = r.ToPersonName,
                        ToPhone = toPh,
                        Amount = (decimal)r.Amount,
                        Status = r.Status,
                        CreatedByUserId = r.CreatedByUserId,
                        SettledAt = r.SettledAt != null ? (DateTime)r.SettledAt : DateTime.UtcNow,
                        IsPayer = isPayer,
                        IsPayee = isPayee
                    });
                }

                return result;
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetPendingSettlementsAsync for user {userId}", ex, "SETTLEMENTS");
                return new List<SettlementProposalDto>();
            }
        }

        public async Task<SettlementTransaction> CreateSettlementAsync(CreateSettlementRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var settlementId = Guid.NewGuid().ToString("N");
                var now = DateTime.UtcNow;

                var sql = @"
                    INSERT INTO SettlementTransactions (settlement_id, trip_id, from_person_id, to_person_id, amount, is_completed, status, created_by_user_id, settled_at)
                    VALUES (@SettlementId, @TripId, @From, @To, @Amount, 0, 'PENDING', @CreatedBy, @Now)";

                await db.ExecuteAsync(sql, new {
                    SettlementId = settlementId,
                    TripId = request.TripId,
                    From = request.FromPersonId,
                    To = request.ToPersonId,
                    Amount = request.Amount,
                    CreatedBy = request.CreatedByUserId ?? "",
                    Now = now
                });

                // Lookup persons & trip name
                var persons = (await db.QueryAsync<Person>(
                    "SELECT person_id as PersonId, name as Name, user_id as UserId, phone_number as PhoneNumber FROM Persons WHERE person_id IN (@From, @To)",
                    new { From = request.FromPersonId, To = request.ToPersonId })).ToList();

                var tripName = await db.ExecuteScalarAsync<string>(
                    "SELECT name FROM Trips WHERE trip_id = @TripId",
                    new { TripId = request.TripId }) ?? "Trip";

                var fromP = persons.FirstOrDefault(p => p.PersonId == request.FromPersonId);
                var toP = persons.FirstOrDefault(p => p.PersonId == request.ToPersonId);
                var fromName = fromP?.Name ?? "Member";
                var toName = toP?.Name ?? "Member";

                // Determine target user to notify
                string? targetUserId = (fromP != null && !string.IsNullOrEmpty(fromP.UserId) && fromP.UserId != request.CreatedByUserId)
                    ? fromP.UserId
                    : (toP != null && !string.IsNullOrEmpty(toP.UserId) && toP.UserId != request.CreatedByUserId ? toP.UserId : null);

                if (string.IsNullOrEmpty(targetUserId))
                {
                    var candidatePhone = (fromP != null && fromP.UserId != request.CreatedByUserId && !string.IsNullOrEmpty(fromP.PhoneNumber))
                        ? fromP.PhoneNumber
                        : toP?.PhoneNumber;

                    if (!string.IsNullOrEmpty(candidatePhone))
                    {
                        var cleanPhone = new string(candidatePhone.Where(char.IsDigit).ToArray());
                        if (cleanPhone.Length >= 10)
                        {
                            var last10 = cleanPhone.Substring(cleanPhone.Length - 10);
                            targetUserId = await db.ExecuteScalarAsync<string>(
                                "SELECT TOP 1 user_id FROM Users WHERE phone_number LIKE '%' + @Phone + '%'",
                                new { Phone = last10 });
                        }
                    }
                }

                if (!string.IsNullOrEmpty(targetUserId))
                {
                    var notifId = Guid.NewGuid().ToString("N");
                    var formattedAmt = request.Amount.ToString("N2");
                    bool isCreatorPayer = fromP != null && fromP.UserId == request.CreatedByUserId;

                    var title = isCreatorPayer
                        ? $"💳 Settlement Statement - ₹{formattedAmt}"
                        : $"🔔 Payment Request Statement - ₹{formattedAmt}";

                    var message = isCreatorPayer
                        ? $"{fromName} sent a settlement statement of ₹{formattedAmt} for \"{tripName}\". Tap to view statement, pay, or edit amount."
                        : $"{fromName} sent a payment request statement for ₹{formattedAmt} for \"{tripName}\". Tap to view statement, pay, or edit amount.";

                    await db.ExecuteAsync(@"
                        INSERT INTO Notifications (notification_id, user_id, trip_id, trip_name, settlement_id, title, message, type, amount, is_read, created_at)
                        VALUES (@NotifId, @UserId, @TripId, @TripName, @SettlementId, @Title, @Message, 'SETTLEMENT_PROPOSAL', @Amount, 0, @Now)",
                        new {
                            NotifId = notifId,
                            UserId = targetUserId,
                            TripId = request.TripId,
                            TripName = tripName,
                            SettlementId = settlementId,
                            Title = title,
                            Message = message,
                            Amount = request.Amount,
                            Now = now
                        });
                }

                _logger.LogInfo($"Settlement statement created: ID={settlementId}, TripId={request.TripId}, Amount={request.Amount}", "SETTLEMENTS");

                return new SettlementTransaction
                {
                    SettlementId = settlementId,
                    TripId = request.TripId,
                    FromPersonId = request.FromPersonId,
                    ToPersonId = request.ToPersonId,
                    Amount = request.Amount,
                    IsCompleted = false,
                    Status = "PENDING",
                    CreatedByUserId = request.CreatedByUserId ?? "",
                    SettledAt = now
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in CreateSettlementAsync for tripId {request.TripId}", ex, "SETTLEMENTS");
                throw;
            }
        }

        public async Task<ApiResponse<bool>> UpdateSettlementAmountAsync(string settlementId, decimal newAmount, string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var transaction = await db.QueryFirstOrDefaultAsync<dynamic>(
                    "SELECT st.*, ISNULL(t.name, 'Trip') as trip_name FROM SettlementTransactions st LEFT JOIN Trips t ON st.trip_id = t.trip_id WHERE st.settlement_id = @SettlementId",
                    new { SettlementId = settlementId });

                if (transaction == null)
                {
                    return new ApiResponse<bool> { Success = false, Message = "Settlement transaction not found." };
                }

                var now = DateTime.UtcNow;
                await db.ExecuteAsync(
                    "UPDATE SettlementTransactions SET amount = @Amount, settled_at = @Now WHERE settlement_id = @SettlementId",
                    new { Amount = newAmount, Now = now, SettlementId = settlementId });

                var fromPersonId = (string)transaction.from_person_id;
                var toPersonId = (string)transaction.to_person_id;
                var tripId = (string)transaction.trip_id;
                var tripName = (string)transaction.trip_name;
                var createdByUserId = (string)(transaction.created_by_user_id ?? "");

                var persons = (await db.QueryAsync<Person>(
                    "SELECT person_id as PersonId, name as Name, user_id as UserId, phone_number as PhoneNumber FROM Persons WHERE person_id IN (@From, @To)",
                    new { From = fromPersonId, To = toPersonId })).ToList();

                var fromP = persons.FirstOrDefault(p => p.PersonId == fromPersonId);
                var toP = persons.FirstOrDefault(p => p.PersonId == toPersonId);
                var updaterName = "Member";
                string? targetUserId = null;

                if (!string.IsNullOrEmpty(userId))
                {
                    if (fromP != null && fromP.UserId == userId)
                    {
                        updaterName = fromP.Name;
                        targetUserId = toP?.UserId;
                    }
                    else if (toP != null && toP.UserId == userId)
                    {
                        updaterName = toP.Name;
                        targetUserId = fromP?.UserId;
                    }
                    else
                    {
                        targetUserId = (createdByUserId == userId)
                            ? (toP != null && toP.UserId != userId ? toP.UserId : fromP?.UserId)
                            : createdByUserId;
                    }
                }

                var formattedAmt = newAmount.ToString("N2");

                // Update existing unread notifications
                await db.ExecuteAsync(@"
                    UPDATE Notifications
                    SET amount = @Amount, 
                        title = @Title, 
                        message = @Message
                    WHERE settlement_id = @SettlementId AND is_read = 0",
                    new {
                        Amount = newAmount,
                        Title = $"✏️ Revised Statement - ₹{formattedAmt}",
                        Message = $"{updaterName} updated settlement statement to ₹{formattedAmt} for \"{tripName}\". Tap to view statement & pay/confirm.",
                        SettlementId = settlementId
                    });

                // Insert notification for target user if distinct
                if (!string.IsNullOrEmpty(targetUserId) && targetUserId != userId)
                {
                    var notifId = Guid.NewGuid().ToString("N");
                    await db.ExecuteAsync(@"
                        INSERT INTO Notifications (notification_id, user_id, trip_id, trip_name, settlement_id, title, message, type, amount, is_read, created_at)
                        VALUES (@NotifId, @UserId, @TripId, @TripName, @SettlementId, @Title, @Message, 'SETTLEMENT_PROPOSAL', @Amount, 0, @Now)",
                        new {
                            NotifId = notifId,
                            UserId = targetUserId,
                            TripId = tripId,
                            TripName = tripName,
                            SettlementId = settlementId,
                            Title = $"✏️ Statement Amount Updated: ₹{formattedAmt}",
                            Message = $"{updaterName} changed the settlement statement amount to ₹{formattedAmt}. Tap to view statement & pay.",
                            Amount = newAmount,
                            Now = now
                        });
                }

                _logger.LogInfo($"Settlement amount updated: ID={settlementId} to {newAmount} by user {userId}", "SETTLEMENTS");
                return new ApiResponse<bool> { Success = true, Message = $"Settlement statement amount updated to ₹{formattedAmt}!" };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in UpdateSettlementAmountAsync for settlementId {settlementId}", ex, "SETTLEMENTS");
                return new ApiResponse<bool> { Success = false, Message = ex.Message };
            }
        }

        public async Task<ApiResponse<bool>> AcceptSettlementAsync(string settlementId, string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var now = DateTime.UtcNow;

                var record = await db.QueryFirstOrDefaultAsync<dynamic>(
                    "SELECT st.*, ISNULL(t.name, 'Trip') as trip_name FROM SettlementTransactions st LEFT JOIN Trips t ON st.trip_id = t.trip_id WHERE st.settlement_id = @SettlementId",
                    new { SettlementId = settlementId });

                if (record == null)
                {
                    return new ApiResponse<bool> { Success = false, Message = "Settlement record not found." };
                }

                await db.ExecuteAsync(
                    "UPDATE SettlementTransactions SET status = 'ACCEPTED', is_completed = 1, settled_at = @Now WHERE settlement_id = @SettlementId",
                    new { Now = now, SettlementId = settlementId });

                var tripId = (string)record.trip_id;
                var amount = (decimal)record.amount;
                var fromPersonId = (string)record.from_person_id;
                var toPersonId = (string)record.to_person_id;
                var createdByUserId = (string)(record.created_by_user_id ?? "");

                var persons = (await db.QueryAsync<Person>(
                    "SELECT person_id as PersonId, name as Name, user_id as UserId FROM Persons WHERE person_id IN (@From, @To)",
                    new { From = fromPersonId, To = toPersonId })).ToList();

                var fromP = persons.FirstOrDefault(p => p.PersonId == fromPersonId);
                var toP = persons.FirstOrDefault(p => p.PersonId == toPersonId);
                var fromName = fromP?.Name ?? "Member";
                var toName = toP?.Name ?? "Member";

                // Auto-record settlement payment into Expenses and ExpenseSplits to update balance
                try
                {
                    var expenseId = Guid.NewGuid().ToString("N");
                    var splitId = Guid.NewGuid().ToString("N");
                    var expenseDesc = $"Settlement: {fromName} paid {toName}";

                    await db.ExecuteAsync(@"
                        INSERT INTO Expenses (expense_id, trip_id, description, amount, category_index, category_name, paid_by_person_id, expense_date, created_at)
                        VALUES (@ExpenseId, @TripId, @Description, @Amount, 5, 'Settlement Payment', @PaidBy, @Now, @Now)",
                        new {
                            ExpenseId = expenseId,
                            TripId = tripId,
                            Description = expenseDesc,
                            Amount = amount,
                            PaidBy = fromPersonId,
                            Now = now
                        });

                    await db.ExecuteAsync(@"
                        INSERT INTO ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
                        VALUES (@SplitId, @ExpenseId, @TripId, @PersonId, @Amount, @Now)",
                        new {
                            SplitId = splitId,
                            ExpenseId = expenseId,
                            TripId = tripId,
                            PersonId = toPersonId,
                            Amount = amount,
                            Now = now
                        });
                }
                catch (Exception expEx)
                {
                    _logger.LogWarning($"Auto-recording settlement expense note: {expEx.Message}", "SETTLEMENTS");
                }

                // Mark notifications as read
                await db.ExecuteAsync(@"
                    UPDATE Notifications 
                    SET is_read = 1 
                    WHERE settlement_id = @SettlementId OR (trip_id = @TripId AND type = 'SETTLEMENT_PROPOSAL')",
                    new { SettlementId = settlementId, TripId = tripId });

                // Notify counterparty
                var targetNotifyUserId = (!string.IsNullOrEmpty(createdByUserId) && createdByUserId != userId)
                    ? createdByUserId
                    : (toP != null && toP.UserId != userId ? toP.UserId : (fromP != null && fromP.UserId != userId ? fromP.UserId : null));

                if (!string.IsNullOrEmpty(targetNotifyUserId))
                {
                    var notifId = Guid.NewGuid().ToString("N");
                    var formattedAmt = amount.ToString("N2");
                    await db.ExecuteAsync(@"
                        INSERT INTO Notifications (notification_id, user_id, trip_id, trip_name, settlement_id, title, message, type, amount, is_read, created_at)
                        VALUES (@NotifId, @UserId, @TripId, @TripName, @SettlementId, @Title, @Message, 'SETTLEMENT_ACCEPTED', @Amount, 0, @Now)",
                        new {
                            NotifId = notifId,
                            UserId = targetNotifyUserId,
                            TripId = tripId,
                            TripName = (string)record.trip_name,
                            SettlementId = settlementId,
                            Title = $"✅ Settlement Confirmed - ₹{formattedAmt}",
                            Message = $"Settlement statement of ₹{formattedAmt} between {fromName} and {toName} is confirmed & settled! Balances updated.",
                            Amount = amount,
                            Now = now
                        });
                }

                _logger.LogInfo($"Settlement accepted: ID={settlementId} by user {userId}", "SETTLEMENTS");
                return new ApiResponse<bool> { Success = true, Message = "Settlement payment accepted and recorded!" };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in AcceptSettlementAsync for settlementId {settlementId}", ex, "SETTLEMENTS");
                return new ApiResponse<bool> { Success = false, Message = ex.Message };
            }
        }

        public async Task<ApiResponse<bool>> DeclineSettlementAsync(string settlementId, string? userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var now = DateTime.UtcNow;

                var record = await db.QueryFirstOrDefaultAsync<dynamic>(
                    "SELECT st.*, ISNULL(t.name, 'Trip') as trip_name FROM SettlementTransactions st LEFT JOIN Trips t ON st.trip_id = t.trip_id WHERE st.settlement_id = @SettlementId",
                    new { SettlementId = settlementId });

                if (record == null)
                {
                    return new ApiResponse<bool> { Success = false, Message = "Settlement record not found." };
                }

                await db.ExecuteAsync(
                    "UPDATE SettlementTransactions SET status = 'DECLINED', is_completed = 0 WHERE settlement_id = @SettlementId",
                    new { SettlementId = settlementId });

                var tripId = (string)record.trip_id;
                var amount = (decimal)record.amount;
                var createdByUserId = (string)(record.created_by_user_id ?? "");

                // Mark proposal notifications as read
                await db.ExecuteAsync(@"
                    UPDATE Notifications 
                    SET is_read = 1 
                    WHERE settlement_id = @SettlementId OR (trip_id = @TripId AND type = 'SETTLEMENT_PROPOSAL')",
                    new { SettlementId = settlementId, TripId = tripId });

                // Notify requester
                if (!string.IsNullOrEmpty(createdByUserId) && createdByUserId != userId)
                {
                    var notifId = Guid.NewGuid().ToString("N");
                    var formattedAmt = amount.ToString("N2");
                    await db.ExecuteAsync(@"
                        INSERT INTO Notifications (notification_id, user_id, trip_id, trip_name, settlement_id, title, message, type, amount, is_read, created_at)
                        VALUES (@NotifId, @UserId, @TripId, @TripName, @SettlementId, @Title, @Message, 'SETTLEMENT_DECLINED', @Amount, 0, @Now)",
                        new {
                            NotifId = notifId,
                            UserId = createdByUserId,
                            TripId = tripId,
                            TripName = (string)record.trip_name,
                            SettlementId = settlementId,
                            Title = $"❌ Settlement Declined - ₹{formattedAmt}",
                            Message = $"Settlement request of ₹{formattedAmt} was declined by the member.",
                            Amount = amount,
                            Now = now
                        });
                }

                _logger.LogInfo($"Settlement declined: ID={settlementId} by user {userId}", "SETTLEMENTS");
                return new ApiResponse<bool> { Success = true, Message = "Settlement payment declined." };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in DeclineSettlementAsync for settlementId {settlementId}", ex, "SETTLEMENTS");
                return new ApiResponse<bool> { Success = false, Message = ex.Message };
            }
        }
    }
}
