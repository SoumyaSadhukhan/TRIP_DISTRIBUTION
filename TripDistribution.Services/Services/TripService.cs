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
    public interface ITripService
    {
        Task<IEnumerable<dynamic>> GetTripsByUserIdAsync(string userId, string? phone = null);
        Task<Trip?> GetTripByIdAsync(string tripId);
        Task<Trip> CreateTripAsync(CreateTripRequestDto request);
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

        public async Task<IEnumerable<dynamic>> GetTripsByUserIdAsync(string userId, string? phone = null)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var cleanPhone = !string.IsNullOrEmpty(phone) ? new string(phone.Where(char.IsDigit).ToArray()) : "";
                if (cleanPhone.Length > 10) cleanPhone = cleanPhone.Substring(cleanPhone.Length - 10);

                var sqlTrips = @"
                    SELECT DISTINCT
                        t.trip_id as id,
                        t.name as name,
                        t.description as description,
                        t.created_by_user_id as createdByUserId,
                        t.created_at as createdAt,
                        t.updated_at as updatedAt
                    FROM Trips t
                    LEFT JOIN TripMembers tm ON t.trip_id = tm.trip_id
                    LEFT JOIN Persons p ON t.trip_id = p.trip_id
                    WHERE t.created_by_user_id = @UserId
                       OR (@CleanPhone <> '' AND (tm.phone_number LIKE '%' + @CleanPhone + '%' OR p.phone_number LIKE '%' + @CleanPhone + '%'))
                       OR p.user_id = @UserId
                    ORDER BY t.created_at DESC";

                var trips = (await db.QueryAsync<dynamic>(sqlTrips, new { UserId = userId ?? "", CleanPhone = cleanPhone })).ToList();

                var result = new List<dynamic>();

                foreach (var t in trips)
                {
                    string tripId = t.id;

                    // 1. Fetch Groups
                    var groups = (await db.QueryAsync<dynamic>(
                        "SELECT group_id as id, name as name FROM Groups WHERE trip_id = @TripId ORDER BY created_at",
                        new { TripId = tripId })).ToList();

                    // 2. Fetch Members (from TripMembers & Persons)
                    var members = (await db.QueryAsync<dynamic>(
                        @"SELECT 
                            ISNULL(member_id, person_id) as id, 
                            group_id as groupId, 
                            name as name, 
                            phone_number as phone, 
                            user_id as userId, 
                            diet_type as dietType, 
                            diet_name as dietName,
                            paid_amount as paidAmount,
                            owed_amount as owedAmount,
                            balance as balance
                          FROM (
                              SELECT member_id, group_id, name, phone_number, NULL as user_id, diet_type, diet_name, 0.0 as paid_amount, 0.0 as owed_amount, 0.0 as balance, trip_id FROM TripMembers
                              UNION ALL
                              SELECT person_id as member_id, group_id, name, phone_number, user_id, diet_type, diet_name, paid_amount, owed_amount, balance, trip_id FROM Persons
                          ) combined
                          WHERE trip_id = @TripId",
                        new { TripId = tripId })).ToList();

                    // Deduplicate members by id
                    var distinctMembers = members.GroupBy(m => (string)m.id).Select(g => g.First()).ToList();

                    var structuredGroups = new List<dynamic>();
                    var groupedMemberGroupIds = distinctMembers.Select(m => (string)(m.groupId ?? "")).Distinct().ToList();

                    // Include all explicit groups
                    foreach (var g in groups)
                    {
                        string gId = g.id;
                        var gMembers = distinctMembers.Where(m => (string)(m.groupId ?? "") == gId).Select(m => new
                        {
                            id = m.id,
                            name = m.name,
                            dietType = m.dietType != null ? (int)m.dietType : 0,
                            dietName = m.dietName ?? "Vegetarian",
                            phone = m.phone,
                            userId = m.userId,
                            paidAmount = m.paidAmount != null ? (decimal)m.paidAmount : 0m,
                            owedAmount = m.owedAmount != null ? (decimal)m.owedAmount : 0m,
                            balance = m.balance != null ? (decimal)m.balance : 0m,
                        }).ToList();

                        structuredGroups.Add(new
                        {
                            id = g.id,
                            name = g.name,
                            members = gMembers
                        });
                    }

                    // Also include groups from members that weren't in Groups table
                    foreach (var gId in groupedMemberGroupIds)
                    {
                        if (!string.IsNullOrEmpty(gId) && !structuredGroups.Any(sg => (string)sg.id == gId))
                        {
                            var gMembers = distinctMembers.Where(m => (string)(m.groupId ?? "") == gId).Select(m => new
                            {
                                id = m.id,
                                name = m.name,
                                dietType = m.dietType != null ? (int)m.dietType : 0,
                                dietName = m.dietName ?? "Vegetarian",
                                phone = m.phone,
                                userId = m.userId,
                                paidAmount = m.paidAmount != null ? (decimal)m.paidAmount : 0m,
                                owedAmount = m.owedAmount != null ? (decimal)m.owedAmount : 0m,
                                balance = m.balance != null ? (decimal)m.balance : 0m,
                            }).ToList();

                            structuredGroups.Add(new
                            {
                                id = gId,
                                name = "Group",
                                members = gMembers
                            });
                        }
                    }

                    // 3. Fetch Expenses & Splits
                    var expenses = (await db.QueryAsync<dynamic>(
                        @"SELECT 
                            expense_id as id, 
                            description as description, 
                            amount as amount, 
                            category_index as categoryIndex, 
                            category_name as categoryName, 
                            paid_by_person_id as paidById, 
                            created_at as createdAt 
                          FROM Expenses 
                          WHERE trip_id = @TripId 
                          ORDER BY created_at",
                        new { TripId = tripId })).ToList();

                    var structuredExpenses = new List<dynamic>();
                    foreach (var exp in expenses)
                    {
                        string expId = exp.id;
                        var splits = (await db.QueryAsync<dynamic>(
                            "SELECT person_id as personId, amount as amount FROM ExpenseSplits WHERE expense_id = @ExpId",
                            new { ExpId = expId })).ToList();

                        var splitMap = new Dictionary<string, double>();
                        var splitAmongIds = new List<string>();
                        foreach (var s in splits)
                        {
                            string pid = s.personId;
                            double amt = (double)(decimal)s.amount;
                            splitMap[pid] = amt;
                            splitAmongIds.Add(pid);
                        }

                        structuredExpenses.Add(new
                        {
                            id = exp.id,
                            description = exp.description,
                            amount = (double)(decimal)exp.amount,
                            categoryIndex = exp.categoryIndex != null ? (int)exp.categoryIndex : 0,
                            categoryName = exp.categoryName ?? "Other",
                            paidById = exp.paidById,
                            createdAt = exp.createdAt != null ? ((DateTime)exp.createdAt).ToString("o") : DateTime.UtcNow.ToString("o"),
                            splitAmongIds = splitAmongIds,
                            customSplits = splitMap
                        });
                    }

                    result.Add(new
                    {
                        id = t.id,
                        name = t.name,
                        description = t.description,
                        createdByUserId = t.createdByUserId,
                        createdAt = t.createdAt != null ? ((DateTime)t.createdAt).ToString("o") : DateTime.UtcNow.ToString("o"),
                        groups = structuredGroups,
                        expenses = structuredExpenses
                    });
                }

                _logger.LogInfo($"Fetched {result.Count} complete trips for userId {userId}", "TRIPS");
                return result;
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetTripsByUserIdAsync for userId {userId}", ex, "TRIPS");
                return new List<dynamic>();
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

        public async Task<IEnumerable<Person>> GetPersonsByTripIdAsync(string tripId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                return await db.QueryAsync<Person>(
                    "SELECT member_id as PersonId, group_id as GroupId, trip_id as TripId, name as Name, phone_number as PhoneNumber, diet_type as DietType, diet_name as DietName, created_at as CreatedAt FROM TripMembers WHERE trip_id = @TripId",
                    new { TripId = tripId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetPersonsByTripIdAsync for tripId {tripId}", ex, "TRIPS");
                return new List<Person>();
            }
        }

        public async Task<Person> AddMemberAsync(AddMemberRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var memberId = Guid.NewGuid().ToString("N");
                var dietName = request.DietType switch
                {
                    1 => "Non-Vegetarian",
                    2 => "Non-Veg + Alcoholic",
                    _ => "Vegetarian"
                };

                var sql = @"
                    INSERT INTO TripMembers (member_id, trip_id, group_id, name, phone_number, diet_type, diet_name, created_at)
                    VALUES (@MemberId, @TripId, @GroupId, @Name, @Phone, @DietType, @DietName, GETDATE())";

                await db.ExecuteAsync(sql, new {
                    MemberId = memberId,
                    TripId = request.TripId,
                    GroupId = request.GroupId,
                    Name = request.Name,
                    Phone = request.PhoneNumber,
                    DietType = request.DietType,
                    DietName = dietName
                });

                _logger.LogInfo($"Member added to trip {request.TripId}: Name={request.Name}, Group={request.GroupId}", "TRIPS_MEMBER");

                return new Person
                {
                    PersonId = memberId,
                    TripId = request.TripId,
                    GroupId = request.GroupId,
                    Name = request.Name,
                    PhoneNumber = request.PhoneNumber,
                    DietType = request.DietType,
                    DietName = dietName
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in AddMemberAsync for trip {request.TripId}", ex, "TRIPS_MEMBER");
                throw;
            }
        }

        public async Task<ApiResponse<bool>> DeleteTripAsync(string tripId, string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
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
                int syncedGroupsCount = 0;
                int syncedMembersCount = 0;
                int syncedExpensesCount = 0;

                foreach (var trip in request.Trips)
                {
                    // 1. Upsert Trip
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

                    // 2. Upsert Groups into Groups Table
                    foreach (var group in trip.Groups)
                    {
                        var existingGroup = await db.QueryFirstOrDefaultAsync<dynamic>(
                            "SELECT group_id FROM Groups WHERE group_id = @GroupId",
                            new { GroupId = group.GroupId });

                        if (existingGroup == null)
                        {
                            await db.ExecuteAsync(@"
                                INSERT INTO Groups (group_id, trip_id, name, created_at)
                                VALUES (@GroupId, @TripId, @Name, GETDATE())",
                                new { GroupId = group.GroupId, TripId = trip.TripId, Name = group.Name });
                            syncedGroupsCount++;
                        }
                        else
                        {
                            await db.ExecuteAsync(@"
                                UPDATE Groups SET name = @Name WHERE group_id = @GroupId",
                                new { GroupId = group.GroupId, Name = group.Name });
                        }

                        // Upsert Members
                        foreach (var person in group.Members)
                        {
                            var existingMember = await db.QueryFirstOrDefaultAsync<Person>(
                                "SELECT member_id as PersonId FROM TripMembers WHERE member_id = @MemberId",
                                new { MemberId = person.PersonId });

                            if (existingMember == null)
                            {
                                await db.ExecuteAsync(@"
                                    INSERT INTO TripMembers (member_id, trip_id, group_id, name, phone_number, diet_type, diet_name, created_at)
                                    VALUES (@MemberId, @TripId, @GroupId, @Name, @Phone, @DietType, @DietName, GETDATE())",
                                    new {
                                        MemberId = person.PersonId,
                                        TripId = trip.TripId,
                                        GroupId = group.GroupId,
                                        Name = person.Name,
                                        Phone = person.PhoneNumber,
                                        DietType = person.DietType,
                                        DietName = person.DietName ?? "Vegetarian"
                                    });

                                await db.ExecuteAsync(@"
                                    IF NOT EXISTS (SELECT 1 FROM Persons WHERE person_id = @PersonId)
                                    INSERT INTO Persons (person_id, trip_id, group_id, name, phone_number, diet_type, diet_name, paid_amount, owed_amount, balance, created_at)
                                    VALUES (@PersonId, @TripId, @GroupId, @Name, @Phone, @DietType, @DietName, @Paid, @Owed, @Bal, GETDATE())",
                                    new {
                                        PersonId = person.PersonId,
                                        TripId = trip.TripId,
                                        GroupId = group.GroupId,
                                        Name = person.Name,
                                        Phone = person.PhoneNumber,
                                        DietType = person.DietType,
                                        DietName = person.DietName ?? "Vegetarian",
                                        Paid = person.PaidAmount,
                                        Owed = person.OwedAmount,
                                        Bal = person.Balance
                                    });

                                syncedMembersCount++;
                            }
                            else
                            {
                                await db.ExecuteAsync(@"
                                    UPDATE TripMembers 
                                    SET name = @Name, phone_number = @Phone, diet_type = @DietType, diet_name = @DietName, group_id = @GroupId
                                    WHERE member_id = @MemberId",
                                    new {
                                        MemberId = person.PersonId,
                                        Name = person.Name,
                                        Phone = person.PhoneNumber,
                                        DietType = person.DietType,
                                        DietName = person.DietName ?? "Vegetarian",
                                        GroupId = group.GroupId
                                    });

                                await db.ExecuteAsync(@"
                                    UPDATE Persons
                                    SET name = @Name, phone_number = @Phone, diet_type = @DietType, diet_name = @DietName, group_id = @GroupId,
                                        paid_amount = @Paid, owed_amount = @Owed, balance = @Bal
                                    WHERE person_id = @PersonId",
                                    new {
                                        PersonId = person.PersonId,
                                        Name = person.Name,
                                        Phone = person.PhoneNumber,
                                        DietType = person.DietType,
                                        DietName = person.DietName ?? "Vegetarian",
                                        GroupId = group.GroupId,
                                        Paid = person.PaidAmount,
                                        Owed = person.OwedAmount,
                                        Bal = person.Balance
                                    });
                            }
                        }
                    }

                    // 3. Upsert Expenses and Splits
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

                _logger.LogInfo($"Offline Sync completed for userId {request.UserId}: Synced {syncedTripsCount} trips, {syncedGroupsCount} groups, {syncedMembersCount} members, {syncedExpensesCount} expenses to SQL Server DB.", "TRIPS_SYNC");

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
