using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using TripDistribution.Models.DTOs;
using TripDistribution.Services.Services;

namespace TripDistribution.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class FriendsController : ControllerBase
    {
        private readonly IFriendService _friendService;

        public FriendsController(IFriendService friendService)
        {
            _friendService = friendService;
        }

        [HttpGet("user/{userId}")]
        public async Task<IActionResult> GetFriends(string userId)
        {
            var friends = await _friendService.GetFriendsByUserIdAsync(userId);
            return Ok(friends);
        }

        [HttpPost]
        public async Task<IActionResult> AddFriend([FromBody] AddFriendRequestDto request)
        {
            var friend = await _friendService.AddFriendAsync(request);
            return Ok(friend);
        }
    }
}
