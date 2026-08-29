using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using TripDistribution.Models.DTOs;
using TripDistribution.Services.Services;

namespace TripDistribution.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuthController : ControllerBase
    {
        private readonly IUserService _userService;

        public AuthController(IUserService userService)
        {
            _userService = userService;
        }

        [HttpPost("register")]
        public async Task<IActionResult> Register([FromBody] RegisterRequestDto request)
        {
            var result = await _userService.RegisterAsync(request);
            if (!result.Success) return BadRequest(result);
            return Ok(result);
        }

        [HttpPost("login")]
        public async Task<IActionResult> Login([FromBody] LoginRequestDto request)
        {
            var result = await _userService.LoginAsync(request);
            if (!result.Success) return Unauthorized(result);
            return Ok(result);
        }

        [HttpPost("send-otp")]
        public async Task<IActionResult> SendOtp([FromBody] OtpRequestDto request)
        {
            var result = await _userService.SendOtpAsync(request);
            return Ok(result);
        }

        [HttpPost("verify-otp")]
        public async Task<IActionResult> VerifyOtp([FromBody] VerifyOtpDto request)
        {
            var success = await _userService.VerifyOtpAsync(request);
            return Ok(new { success, message = success ? "OTP verified" : "Invalid or expired OTP" });
        }
    }
}
