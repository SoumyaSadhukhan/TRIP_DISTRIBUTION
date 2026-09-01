using Microsoft.AspNetCore.Mvc;
using System.Collections.Generic;
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

        [HttpGet]
        public async Task<IActionResult> GetFriendsQuery([FromQuery] string? userId)
        {
            if (string.IsNullOrEmpty(userId)) return Ok(new { success = true, friends = new object[] { } });
            var friends = await _friendService.GetFriendsByUserIdAsync(userId);
            return Ok(new { success = true, friends });
        }

        [HttpGet("user/{userId}")]
        public async Task<IActionResult> GetFriends(string userId)
        {
            var friends = await _friendService.GetFriendsByUserIdAsync(userId);
            return Ok(new { success = true, friends });
        }

        [HttpPost("search")]
        public async Task<IActionResult> SearchUsers([FromBody] SearchFriendDto request)
        {
            var users = await _friendService.SearchUsersAsync(request.Phone ?? request.Query ?? "", request.UserId ?? "");
            return Ok(new { success = true, users });
        }

        [HttpPost("check-contacts")]
        public async Task<IActionResult> CheckContacts([FromBody] CheckContactsDto request)
        {
            var registeredUsers = await _friendService.CheckContactsAsync(request.Contacts ?? new List<string>(), request.UserId ?? "");
            return Ok(new { success = true, registeredUsers });
        }

        [HttpPost]
        [HttpPost("add")]
        public async Task<IActionResult> AddFriend([FromBody] AddFriendRequestDto request)
        {
            var result = await _friendService.AddFriendAsync(request);
            if (!result.Success) return BadRequest(result);
            return Ok(new { success = true, message = result.Message, friend = result.Data });
        }

        [HttpGet("requests")]
        public async Task<IActionResult> GetFriendRequests([FromQuery] string? userId)
        {
            if (string.IsNullOrEmpty(userId)) return Ok(new { success = true, requests = new object[] { } });
            var requests = await _friendService.GetFriendRequestsAsync(userId);
            return Ok(new { success = true, requests });
        }

        [HttpPost("accept")]
        public async Task<IActionResult> AcceptFriendRequest([FromBody] FriendActionDto request)
        {
            var result = await _friendService.AcceptFriendRequestAsync(request.ConnectionId, request.UserId);
            if (!result.Success) return BadRequest(result);
            return Ok(result);
        }

        [HttpPost("decline")]
        public async Task<IActionResult> DeclineFriendRequest([FromBody] FriendActionDto request)
        {
            var result = await _friendService.DeclineFriendRequestAsync(request.ConnectionId, request.UserId);
            if (!result.Success) return BadRequest(result);
            return Ok(result);
        }

        [HttpDelete("{connectionId}")]
        [HttpDelete]
        public async Task<IActionResult> DeleteFriend(string? connectionId, [FromQuery] string? userId)
        {
            var connId = connectionId ?? HttpContext.Request.Query["connectionId"].ToString();
            var usrId = userId ?? HttpContext.Request.Query["userId"].ToString();
            var result = await _friendService.DeleteFriendAsync(connId, usrId);
            if (!result.Success) return BadRequest(result);
            return Ok(result);
        }
    }

    public class SearchFriendDto
    {
        public string? Phone { get; set; }
        public string? Query { get; set; }
        public string? UserId { get; set; }
    }

    public class CheckContactsDto
    {
        public List<string>? Contacts { get; set; }
        public string? UserId { get; set; }
    }

    public class FriendActionDto
    {
        public string ConnectionId { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
    }
}
