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
    public interface ISettlementService
    {
        Task<IEnumerable<SettlementTransaction>> GetSettlementsByTripIdAsync(string tripId);
        Task<SettlementTransaction> CreateSettlementAsync(CreateSettlementRequestDto request);
        Task<ApiResponse<bool>> AcceptSettlementAsync(string settlementId, string userId);
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
                    "SELECT settlement_id as SettlementId, trip_id as TripId, from_person_id as FromPersonId, to_person_id as ToPersonId, amount as Amount, status as Status, created_by_user_id as CreatedByUserId, created_at as SettledAt FROM Settlements WHERE trip_id = @TripId ORDER BY created_at DESC",
                    new { TripId = tripId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetSettlementsByTripIdAsync for tripId {tripId}", ex, "SETTLEMENTS");
                return new List<SettlementTransaction>();
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
                    INSERT INTO Settlements (settlement_id, trip_id, from_person_id, to_person_id, amount, status, created_by_user_id, created_at)
                    VALUES (@SettlementId, @TripId, @From, @To, @Amount, 'COMPLETED', @CreatedBy, @Now)";

                await db.ExecuteAsync(sql, new {
                    SettlementId = settlementId,
                    TripId = request.TripId,
                    From = request.FromPersonId,
                    To = request.ToPersonId,
                    Amount = request.Amount,
                    CreatedBy = request.CreatedByUserId,
                    Now = now
                });

                _logger.LogInfo($"Settlement recorded: ID={settlementId}, TripId={request.TripId}, Amount={request.Amount}, From={request.FromPersonId} To={request.ToPersonId}", "SETTLEMENTS");

                return new SettlementTransaction
                {
                    SettlementId = settlementId,
                    TripId = request.TripId,
                    FromPersonId = request.FromPersonId,
                    ToPersonId = request.ToPersonId,
                    Amount = request.Amount,
                    IsCompleted = true,
                    Status = "COMPLETED",
                    CreatedByUserId = request.CreatedByUserId,
                    SettledAt = now
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in CreateSettlementAsync for tripId {request.TripId}", ex, "SETTLEMENTS");
                throw;
            }
        }

        public async Task<ApiResponse<bool>> AcceptSettlementAsync(string settlementId, string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var rows = await db.ExecuteAsync(
                    "UPDATE Settlements SET status = 'COMPLETED' WHERE settlement_id = @SettlementId",
                    new { SettlementId = settlementId });

                if (rows > 0)
                {
                    _logger.LogInfo($"Settlement accepted: ID={settlementId} by user {userId}", "SETTLEMENTS");
                    return new ApiResponse<bool> { Success = true, Message = "Settlement accepted and completed." };
                }
                return new ApiResponse<bool> { Success = false, Message = "Settlement record not found." };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in AcceptSettlementAsync for settlementId {settlementId}", ex, "SETTLEMENTS");
                return new ApiResponse<bool> { Success = false, Message = ex.Message };
            }
        }
    }
}
