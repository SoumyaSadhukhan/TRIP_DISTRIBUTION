using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using TripDistribution.Models.DTOs;
using TripDistribution.Services.Services;

namespace TripDistribution.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class TripsController : ControllerBase
    {
        private readonly ITripService _tripService;

        public TripsController(ITripService tripService)
        {
            _tripService = tripService;
        }

        [HttpGet("user/{userId}")]
        public async Task<IActionResult> GetUserTrips(string userId)
        {
            var trips = await _tripService.GetTripsByUserIdAsync(userId);
            return Ok(trips);
        }

        [HttpGet("{tripId}")]
        public async Task<IActionResult> GetTripDetails(string tripId)
        {
            var trip = await _tripService.GetTripByIdAsync(tripId);
            if (trip == null) return NotFound();
            
            var groups = await _tripService.GetGroupsByTripIdAsync(tripId);
            var members = await _tripService.GetPersonsByTripIdAsync(tripId);

            return Ok(new { trip, groups, members });
        }

        [HttpPost]
        public async Task<IActionResult> CreateTrip([FromBody] CreateTripRequestDto request)
        {
            var trip = await _tripService.CreateTripAsync(request);
            return Ok(trip);
        }

        [HttpPost("members")]
        public async Task<IActionResult> AddMember([FromBody] AddMemberRequestDto request)
        {
            var person = await _tripService.AddMemberAsync(request);
            return Ok(person);
        }

        [HttpPost("sync")]
        public async Task<IActionResult> SyncTrips([FromBody] SyncTripsRequestDto request)
        {
            var result = await _tripService.SyncTripsAsync(request);
            if (!result.Success) return BadRequest(result);
            return Ok(result);
        }

        [HttpDelete("{tripId}")]
        public async Task<IActionResult> DeleteTrip(string tripId, [FromQuery] string? userId)
        {
            var result = await _tripService.DeleteTripAsync(tripId, userId ?? "");
            if (!result.Success) return BadRequest(result);
            return Ok(result);
        }

        [HttpPost("delete")]
        public async Task<IActionResult> DeleteTripBody([FromBody] DeleteTripDto request)
        {
            var result = await _tripService.DeleteTripAsync(request.TripId, request.UserId);
            if (!result.Success) return BadRequest(result);
            return Ok(result);
        }
    }

    public class DeleteTripDto
    {
        public string TripId { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
    }
}
