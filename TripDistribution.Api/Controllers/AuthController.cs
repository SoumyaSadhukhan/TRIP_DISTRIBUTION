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

        [HttpPost("verify-token")]
        [HttpPost("validate-token")]
        public async Task<IActionResult> VerifyToken([FromBody] VerifyTokenDto request)
        {
            var result = await _userService.VerifyTokenAsync(request.Token, request.Phone);
            return Ok(result);
        }

        [HttpPost("profile")]
        [HttpPost("update-profile")]
        public async Task<IActionResult> UpdateProfile([FromBody] UpdateProfileDto request)
        {
            var result = await _userService.UpdateProfileAsync(request.UserId, request.FullName, request.DietType);
            if (!result.Success) return BadRequest(result);
            return Ok(result);
        }

        [HttpPost("reset-password")]
        public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordDto request)
        {
            var result = await _userService.ResetPasswordAsync(request.Phone, request.Otp, request.NewPassword);
            if (!result.Success) return BadRequest(result);
            return Ok(result);
        }

        [HttpPost("toggle-biometric")]
        public async Task<IActionResult> ToggleBiometric([FromBody] ToggleBiometricDto request)
        {
            var success = await _userService.ToggleBiometricAsync(request.UserId, request.Enabled);
            return Ok(new { success });
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

    public class VerifyTokenDto
    {
        public string Token { get; set; } = string.Empty;
        public string? Phone { get; set; }
    }

    public class UpdateProfileDto
    {
        public string UserId { get; set; } = string.Empty;
        public string? FullName { get; set; }
        public int? DietType { get; set; }
    }

    public class ResetPasswordDto
    {
        public string Phone { get; set; } = string.Empty;
        public string Otp { get; set; } = string.Empty;
        public string NewPassword { get; set; } = string.Empty;
    }

    public class ToggleBiometricDto
    {
        public string UserId { get; set; } = string.Empty;
        public bool Enabled { get; set; }
    }
}
