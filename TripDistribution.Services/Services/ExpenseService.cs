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
    public interface IExpenseService
    {
        Task<IEnumerable<Expense>> GetExpensesByTripIdAsync(string tripId);
        Task<Expense> CreateExpenseAsync(CreateExpenseRequestDto request);
        Task<IEnumerable<ExpenseSplit>> GetSplitsByExpenseIdAsync(string expenseId);
    }

    public class ExpenseService : IExpenseService
    {
        private readonly ISqlDbConnectionFactory _connectionFactory;
        private readonly IFileLoggerService _logger;

        public ExpenseService(ISqlDbConnectionFactory connectionFactory, IFileLoggerService logger)
        {
            _connectionFactory = connectionFactory;
            _logger = logger;
        }

        public async Task<IEnumerable<Expense>> GetExpensesByTripIdAsync(string tripId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var sql = @"
                    SELECT expense_id as ExpenseId, trip_id as TripId, description as Description, amount as Amount, category_index as CategoryIndex, category_name as CategoryName, paid_by_person_id as PaidByPersonId, created_at as CreatedAt 
                    FROM Expenses 
                    WHERE trip_id = @TripId 
                    ORDER BY created_at DESC";
                return await db.QueryAsync<Expense>(sql, new { TripId = tripId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetExpensesByTripIdAsync for tripId {tripId}", ex, "EXPENSES");
                return new List<Expense>();
            }
        }

        public async Task<Expense> CreateExpenseAsync(CreateExpenseRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var expenseId = Guid.NewGuid().ToString("N");
                var now = DateTime.UtcNow;

                var sqlExpense = @"
                    INSERT INTO Expenses (expense_id, trip_id, description, amount, category_index, category_name, paid_by_person_id, created_at)
                    VALUES (@ExpenseId, @TripId, @Desc, @Amount, @CatIdx, @CatName, @PaidBy, @Now)";

                await db.ExecuteAsync(sqlExpense, new {
                    ExpenseId = expenseId,
                    TripId = request.TripId,
                    Desc = request.Description,
                    Amount = request.Amount,
                    CatIdx = request.CategoryIndex,
                    CatName = request.CategoryName,
                    PaidBy = request.PaidByPersonId,
                    Now = now
                });

                foreach (var split in request.Splits)
                {
                    var splitId = Guid.NewGuid().ToString("N");
                    var sqlSplit = @"
                        INSERT INTO ExpenseSplits (split_id, expense_id, person_id, amount)
                        VALUES (@SplitId, @ExpenseId, @PersonId, @Amount)";

                    await db.ExecuteAsync(sqlSplit, new {
                        SplitId = splitId,
                        ExpenseId = expenseId,
                        PersonId = split.PersonId,
                        Amount = split.Amount
                    });
                }

                _logger.LogInfo($"Expense created: ID={expenseId}, TripId={request.TripId}, Amount={request.Amount}, PaidBy={request.PaidByPersonId}", "EXPENSES_CREATE");

                return new Expense
                {
                    ExpenseId = expenseId,
                    TripId = request.TripId,
                    Description = request.Description,
                    Amount = request.Amount,
                    CategoryIndex = request.CategoryIndex,
                    CategoryName = request.CategoryName,
                    PaidByPersonId = request.PaidByPersonId,
                    CreatedAt = now
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in CreateExpenseAsync for tripId {request.TripId}", ex, "EXPENSES_CREATE");
                throw;
            }
        }

        public async Task<IEnumerable<ExpenseSplit>> GetSplitsByExpenseIdAsync(string expenseId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                return await db.QueryAsync<ExpenseSplit>(
                    "SELECT split_id as SplitId, expense_id as ExpenseId, person_id as PersonId, amount as Amount FROM ExpenseSplits WHERE expense_id = @ExpenseId",
                    new { ExpenseId = expenseId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetSplitsByExpenseIdAsync for expenseId {expenseId}", ex, "EXPENSES");
                return new List<ExpenseSplit>();
            }
        }
    }
}
