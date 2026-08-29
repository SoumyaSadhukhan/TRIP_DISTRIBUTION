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
                    "SELECT settlement_id as SettlementId, trip_id as TripId, from_person_id as FromPersonId, to_person_id as ToPersonId, amount as Amount, status as Status, created_by_user_id as CreatedByUserId, settled_at as SettledAt FROM SettlementTransactions WHERE trip_id = @TripId ORDER BY settled_at DESC",
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
                    INSERT INTO SettlementTransactions (settlement_id, trip_id, from_person_id, to_person_id, amount, is_completed, status, created_by_user_id, settled_at)
                    VALUES (@SettlementId, @TripId, @From, @To, @Amount, 1, 'ACCEPTED', @CreatedBy, @Now)";

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
                    Status = "ACCEPTED",
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
    }
}
