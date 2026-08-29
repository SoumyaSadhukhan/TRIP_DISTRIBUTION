using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using TripDistribution.Models.DTOs;
using TripDistribution.Services.Services;

namespace TripDistribution.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class SettlementsController : ControllerBase
    {
        private readonly ISettlementService _settlementService;

        public SettlementsController(ISettlementService settlementService)
        {
            _settlementService = settlementService;
        }

        [HttpGet("trip/{tripId}")]
        public async Task<IActionResult> GetSettlements(string tripId)
        {
            var settlements = await _settlementService.GetSettlementsByTripIdAsync(tripId);
            return Ok(settlements);
        }

        [HttpPost]
        public async Task<IActionResult> CreateSettlement([FromBody] CreateSettlementRequestDto request)
        {
            var settlement = await _settlementService.CreateSettlementAsync(request);
            return Ok(settlement);
        }
    }
}
