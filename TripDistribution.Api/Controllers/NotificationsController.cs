using Microsoft.AspNetCore.Mvc;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace TripDistribution.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class NotificationsController : ControllerBase
    {
        [HttpGet]
        public IActionResult GetNotifications([FromQuery] string? userId)
        {
            return Ok(new { success = true, notifications = new List<object>() });
        }

        [HttpGet("unread-count")]
        public IActionResult GetUnreadCount([FromQuery] string? userId)
        {
            return Ok(new { success = true, count = 0 });
        }

        [HttpPost("mark-read")]
        public IActionResult MarkRead([FromBody] object? body)
        {
            return Ok(new { success = true, message = "Marked as read." });
        }
    }
}
