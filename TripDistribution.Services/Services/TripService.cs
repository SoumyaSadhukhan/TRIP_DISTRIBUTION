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
    public interface ITripService
    {
        Task<IEnumerable<Trip>> GetTripsByUserIdAsync(string userId);
        Task<Trip?> GetTripByIdAsync(string tripId);
        Task<Trip> CreateTripAsync(CreateTripRequestDto request);
        Task<IEnumerable<Group>> GetGroupsByTripIdAsync(string tripId);
        Task<IEnumerable<Person>> GetPersonsByTripIdAsync(string tripId);
        Task<Person> AddMemberAsync(AddMemberRequestDto request);
        Task<ApiResponse<bool>> DeleteTripAsync(string tripId, string userId);
        Task<ApiResponse<bool>> SyncTripsAsync(SyncTripsRequestDto request);
    }

    public class TripService : ITripService
    {
        private readonly ISqlDbConnectionFactory _connectionFactory;
        private readonly IFileLoggerService _logger;

        public TripService(ISqlDbConnectionFactory connectionFactory, IFileLoggerService logger)
        {
            _connectionFactory = connectionFactory;
            _logger = logger;
        }

        public async Task<IEnumerable<Trip>> GetTripsByUserIdAsync(string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var sql = @"
                    SELECT trip_id as TripId, created_by_user_id as UserId, name as Name, description as Description, created_at as CreatedAt, updated_at as UpdatedAt 
                    FROM Trips 
                    WHERE created_by_user_id = @UserId OR trip_id IN (SELECT trip_id FROM TripCollaborators WHERE user_id = @UserId)
                    ORDER BY created_at DESC";
                var trips = await db.QueryAsync<Trip>(sql, new { UserId = userId });
                _logger.LogInfo($"Fetched trips for userId {userId}", "TRIPS");
                return trips;
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetTripsByUserIdAsync for userId {userId}", ex, "TRIPS");
                return new List<Trip>();
            }
        }

        public async Task<Trip?> GetTripByIdAsync(string tripId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var sql = @"SELECT trip_id as TripId, created_by_user_id as UserId, name as Name, description as Description, created_at as CreatedAt, updated_at as UpdatedAt FROM Trips WHERE trip_id = @TripId";
                return await db.QueryFirstOrDefaultAsync<Trip>(sql, new { TripId = tripId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetTripByIdAsync for tripId {tripId}", ex, "TRIPS");
                return null;
            }
        }

        public async Task<Trip> CreateTripAsync(CreateTripRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var tripId = Guid.NewGuid().ToString("N");
                var now = DateTime.UtcNow;

                var sqlTrip = @"
                    INSERT INTO Trips (trip_id, created_by_user_id, name, description, created_at, updated_at)
                    VALUES (@TripId, @UserId, @Name, @Desc, @Now, @Now)";

                await db.ExecuteAsync(sqlTrip, new { TripId = tripId, UserId = request.UserId, Name = request.Name, Desc = request.Description, Now = now });

                // Create default group
                var groupId = Guid.NewGuid().ToString("N");
                var sqlGroup = "INSERT INTO Groups (group_id, trip_id, name, created_at) VALUES (@GroupId, @TripId, 'Main Group', @Now)";
                await db.ExecuteAsync(sqlGroup, new { GroupId = groupId, TripId = tripId, Now = now });

                _logger.LogInfo($"Trip created: ID={tripId}, Name={request.Name}, CreatedBy={request.UserId}", "TRIPS_CREATE");

                return new Trip
                {
                    TripId = tripId,
                    UserId = request.UserId,
                    Name = request.Name,
                    Description = request.Description,
                    CreatedAt = now,
                    UpdatedAt = now
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in CreateTripAsync for trip {request.Name}", ex, "TRIPS_CREATE");
                throw;
            }
        }

        public async Task<IEnumerable<Group>> GetGroupsByTripIdAsync(string tripId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                return await db.QueryAsync<Group>(
                    "SELECT group_id as GroupId, trip_id as TripId, name as Name, created_at as CreatedAt FROM Groups WHERE trip_id = @TripId",
                    new { TripId = tripId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetGroupsByTripIdAsync for tripId {tripId}", ex, "GROUPS");
                return new List<Group>();
            }
        }

        public async Task<IEnumerable<Person>> GetPersonsByTripIdAsync(string tripId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                return await db.QueryAsync<Person>(
                    "SELECT person_id as PersonId, group_id as GroupId, trip_id as TripId, phone_number as PhoneNumber, name as Name, diet_type as DietType, diet_name as DietName, paid_amount as PaidAmount, owed_amount as OwedAmount, balance as Balance, created_at as CreatedAt FROM Persons WHERE trip_id = @TripId",
                    new { TripId = tripId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetPersonsByTripIdAsync for tripId {tripId}", ex, "PERSONS");
                return new List<Person>();
            }
        }

        public async Task<Person> AddMemberAsync(AddMemberRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var personId = Guid.NewGuid().ToString("N");
                var dietName = request.DietType switch
                {
                    1 => "Non-Vegetarian",
                    2 => "Non-Veg + Alcoholic",
                    _ => "Vegetarian"
                };

                var sql = @"
                    INSERT INTO Persons (person_id, group_id, trip_id, phone_number, name, diet_type, diet_name, paid_amount, owed_amount, balance, created_at)
                    VALUES (@PersonId, @GroupId, @TripId, @Phone, @Name, @DietType, @DietName, 0, 0, 0, GETDATE())";

                await db.ExecuteAsync(sql, new {
                    PersonId = personId,
                    GroupId = request.GroupId,
                    TripId = request.TripId,
                    Phone = request.PhoneNumber,
                    Name = request.Name,
                    DietType = request.DietType,
                    DietName = dietName
                });

                _logger.LogInfo($"Member added to trip {request.TripId}: {request.Name} ({request.PhoneNumber})", "TRIPS_MEMBER");

                return new Person
                {
                    PersonId = personId,
                    GroupId = request.GroupId,
                    TripId = request.TripId,
                    PhoneNumber = request.PhoneNumber,
                    Name = request.Name,
                    DietType = request.DietType,
                    DietName = dietName
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in AddMemberAsync for member {request.Name} in trip {request.TripId}", ex, "TRIPS_MEMBER");
                throw;
            }
        }

        public async Task<ApiResponse<bool>> DeleteTripAsync(string tripId, string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var trip = await db.QueryFirstOrDefaultAsync<Trip>(
                    "SELECT trip_id as TripId, created_by_user_id as UserId FROM Trips WHERE trip_id = @TripId",
                    new { TripId = tripId });

                if (trip == null)
                {
                    return new ApiResponse<bool> { Success = false, Message = "Trip not found." };
                }

                if (!string.IsNullOrEmpty(userId) && trip.UserId != userId)
                {
                    _logger.LogWarning($"Unauthorized delete attempt on trip {tripId} by user {userId}", "TRIPS_DELETE");
                    return new ApiResponse<bool> { Success = false, Message = "Only the trip admin can delete this trip." };
                }

                var memberCount = await db.ExecuteScalarAsync<int>(
                    "SELECT COUNT(1) FROM Persons WHERE trip_id = @TripId",
                    new { TripId = tripId });

                if (memberCount > 0)
                {
                    _logger.LogWarning($"Trip {tripId} deletion blocked: {memberCount} members present.", "TRIPS_DELETE");
                    return new ApiResponse<bool>
                    {
                        Success = false,
                        Message = "Cannot delete trip! Members are currently present in this trip. Admin must remove all members before deleting."
                    };
                }

                var expenseCount = await db.ExecuteScalarAsync<int>(
                    "SELECT COUNT(1) FROM Expenses WHERE trip_id = @TripId",
                    new { TripId = tripId });

                if (expenseCount > 0)
                {
                    _logger.LogWarning($"Trip {tripId} deletion blocked: {expenseCount} expenses present.", "TRIPS_DELETE");
                    return new ApiResponse<bool>
                    {
                        Success = false,
                        Message = "Cannot delete trip! Expenses exist in this trip. Admin must clear all expenses before deleting."
                    };
                }

                await db.ExecuteAsync("DELETE FROM Groups WHERE trip_id = @TripId", new { TripId = tripId });
                await db.ExecuteAsync("DELETE FROM Trips WHERE trip_id = @TripId", new { TripId = tripId });

                _logger.LogInfo($"Trip {tripId} deleted successfully by admin {userId}", "TRIPS_DELETE");

                return new ApiResponse<bool> { Success = true, Message = "Trip deleted successfully." };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in DeleteTripAsync for trip {tripId}", ex, "TRIPS_DELETE");
                return new ApiResponse<bool> { Success = false, Message = $"Failed to delete trip: {ex.Message}" };
            }
        }

        public async Task<ApiResponse<bool>> SyncTripsAsync(SyncTripsRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                int syncedTripsCount = 0;
                int syncedMembersCount = 0;
                int syncedExpensesCount = 0;

                foreach (var trip in request.Trips)
                {
                    var existingTrip = await db.QueryFirstOrDefaultAsync<Trip>(
                        "SELECT trip_id as TripId FROM Trips WHERE trip_id = @TripId", new { TripId = trip.TripId });

                    if (existingTrip == null)
                    {
                        await db.ExecuteAsync(@"
                            INSERT INTO Trips (trip_id, created_by_user_id, name, description, created_at, updated_at)
                            VALUES (@TripId, @UserId, @Name, @Desc, GETDATE(), GETDATE())",
                            new { TripId = trip.TripId, UserId = request.UserId, Name = trip.Name, Desc = trip.Description });
                        syncedTripsCount++;
                    }
                    else
                    {
                        await db.ExecuteAsync(@"
                            UPDATE Trips SET name = @Name, description = @Desc, updated_at = GETDATE()
                            WHERE trip_id = @TripId",
                            new { TripId = trip.TripId, Name = trip.Name, Desc = trip.Description });
                    }

                    foreach (var group in trip.Groups)
                    {
                        var existingGroup = await db.QueryFirstOrDefaultAsync<Group>(
                            "SELECT group_id as GroupId FROM Groups WHERE group_id = @GroupId", new { GroupId = group.GroupId });

                        if (existingGroup == null)
                        {
                            await db.ExecuteAsync(@"
                                INSERT INTO Groups (group_id, trip_id, name, created_at)
                                VALUES (@GroupId, @TripId, @Name, GETDATE())",
                                new { GroupId = group.GroupId, TripId = trip.TripId, Name = group.Name });
                        }

                        foreach (var person in group.Members)
                        {
                            var existingPerson = await db.QueryFirstOrDefaultAsync<Person>(
                                "SELECT person_id as PersonId FROM Persons WHERE person_id = @PersonId", new { PersonId = person.PersonId });

                            if (existingPerson == null)
                            {
                                await db.ExecuteAsync(@"
                                    INSERT INTO Persons (person_id, group_id, trip_id, phone_number, name, diet_type, diet_name, paid_amount, owed_amount, balance, created_at)
                                    VALUES (@PersonId, @GroupId, @TripId, @Phone, @Name, @DietType, @DietName, @Paid, @Owed, @Balance, GETDATE())",
                                    new {
                                        PersonId = person.PersonId,
                                        GroupId = group.GroupId,
                                        TripId = trip.TripId,
                                        Phone = person.PhoneNumber,
                                        Name = person.Name,
                                        DietType = person.DietType,
                                        DietName = person.DietName ?? "Vegetarian",
                                        Paid = person.PaidAmount,
                                        Owed = person.OwedAmount,
                                        Balance = person.Balance
                                    });
                                syncedMembersCount++;
                            }
                        }
                    }

                    foreach (var exp in trip.Expenses)
                    {
                        var existingExp = await db.QueryFirstOrDefaultAsync<Expense>(
                            "SELECT expense_id as ExpenseId FROM Expenses WHERE expense_id = @ExpenseId", new { ExpenseId = exp.ExpenseId });

                        if (existingExp == null)
                        {
                            await db.ExecuteAsync(@"
                                INSERT INTO Expenses (expense_id, trip_id, description, amount, category_index, category_name, paid_by_person_id, created_at)
                                VALUES (@ExpenseId, @TripId, @Desc, @Amount, @CatIdx, @CatName, @PaidBy, GETDATE())",
                                new {
                                    ExpenseId = exp.ExpenseId,
                                    TripId = trip.TripId,
                                    Desc = exp.Description,
                                    Amount = exp.Amount,
                                    CatIdx = exp.CategoryIndex,
                                    CatName = exp.CategoryName ?? "Other",
                                    PaidBy = exp.PaidByPersonId
                                });

                            foreach (var split in exp.Splits)
                            {
                                await db.ExecuteAsync(@"
                                    INSERT INTO ExpenseSplits (split_id, expense_id, person_id, amount)
                                    VALUES (@SplitId, @ExpenseId, @PersonId, @Amount)",
                                    new {
                                        SplitId = Guid.NewGuid().ToString("N"),
                                        ExpenseId = exp.ExpenseId,
                                        PersonId = split.PersonId,
                                        Amount = split.Amount
                                    });
                            }
                            syncedExpensesCount++;
                        }
                    }
                }

                _logger.LogInfo($"Offline Sync completed for userId {request.UserId}: Synced {syncedTripsCount} trips, {syncedMembersCount} members, {syncedExpensesCount} expenses to SQL Server DB.", "TRIPS_SYNC");

                return new ApiResponse<bool> { Success = true, Message = "Offline data synced successfully to SQL Server DB." };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in SyncTripsAsync for userId {request.UserId}", ex, "TRIPS_SYNC");
                return new ApiResponse<bool> { Success = false, Message = $"Sync failed: {ex.Message}" };
            }
        }
    }
}
