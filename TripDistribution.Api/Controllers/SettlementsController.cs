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
            return Ok(new { success = true, settlements });
        }

        [HttpPost]
        public async Task<IActionResult> CreateSettlement([FromBody] CreateSettlementRequestDto request)
        {
            var settlement = await _settlementService.CreateSettlementAsync(request);
            return Ok(new { success = true, settlement });
        }

        [HttpPost("accept")]
        public async Task<IActionResult> AcceptSettlement([FromBody] AcceptSettlementDto request)
        {
            var result = await _settlementService.AcceptSettlementAsync(request.SettlementId, request.UserId);
            if (!result.Success) return BadRequest(result);
            return Ok(result);
        }
    }

    public class AcceptSettlementDto
    {
        public string SettlementId { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
    }
}
