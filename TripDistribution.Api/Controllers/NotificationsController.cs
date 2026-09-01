using Microsoft.AspNetCore.Mvc;
using System.Collections.Generic;
using System.Threading.Tasks;
using TripDistribution.Models.DTOs;
using TripDistribution.Services.Services;

namespace TripDistribution.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class NotificationsController : ControllerBase
    {
        private readonly INotificationService _notificationService;

        public NotificationsController(INotificationService notificationService)
        {
            _notificationService = notificationService;
        }

        [HttpGet]
        public async Task<IActionResult> GetNotifications([FromQuery] string? userId)
        {
            if (string.IsNullOrEmpty(userId))
            {
                return BadRequest(new { success = false, message = "User ID is required." });
            }
            var notifications = await _notificationService.GetNotificationsByUserIdAsync(userId);
            return Ok(new { success = true, notifications });
        }

        [HttpGet("unread-count")]
        public async Task<IActionResult> GetUnreadCount([FromQuery] string? userId)
        {
            if (string.IsNullOrEmpty(userId)) return Ok(new { success = true, count = 0 });
            var count = await _notificationService.GetUnreadCountAsync(userId);
            return Ok(new { success = true, count });
        }

        [HttpPost("mark-read")]
        public async Task<IActionResult> MarkRead([FromBody] MarkNotificationReadDto request)
        {
            var success = await _notificationService.MarkReadAsync(request?.NotificationId, request?.UserId);
            return Ok(new { success, message = success ? "Marked as read." : "Failed to mark as read." });
        }
    }
}
