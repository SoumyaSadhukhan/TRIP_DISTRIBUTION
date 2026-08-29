using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using TripDistribution.Models.DTOs;
using TripDistribution.Services.Services;

namespace TripDistribution.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ExpensesController : ControllerBase
    {
        private readonly IExpenseService _expenseService;

        public ExpensesController(IExpenseService expenseService)
        {
            _expenseService = expenseService;
        }

        [HttpGet("trip/{tripId}")]
        public async Task<IActionResult> GetTripExpenses(string tripId)
        {
            var expenses = await _expenseService.GetExpensesByTripIdAsync(tripId);
            return Ok(expenses);
        }

        [HttpGet("{expenseId}/splits")]
        public async Task<IActionResult> GetExpenseSplits(string expenseId)
        {
            var splits = await _expenseService.GetSplitsByExpenseIdAsync(expenseId);
            return Ok(splits);
        }

        [HttpPost]
        public async Task<IActionResult> AddExpense([FromBody] CreateExpenseRequestDto request)
        {
            var expense = await _expenseService.CreateExpenseAsync(request);
            return Ok(expense);
        }
    }
}
