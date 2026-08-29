using System;
using System.Data;
using System.Threading.Tasks;
using Dapper;
using TripDistribution.Models.DTOs;
using TripDistribution.Models.Entities;
using TripDistribution.Services.Data;

namespace TripDistribution.Services.Services
{
    public interface IUserService
    {
        Task<AuthResponseDto> RegisterAsync(RegisterRequestDto request);
        Task<AuthResponseDto> LoginAsync(LoginRequestDto request);
        Task<User?> GetUserByIdAsync(string userId);
        Task<User?> GetUserByPhoneAsync(string phoneNumber);
        Task<OtpResponseDto> SendOtpAsync(OtpRequestDto request);
        Task<bool> VerifyOtpAsync(VerifyOtpDto request);
    }

    public class UserService : IUserService
    {
        private readonly ISqlDbConnectionFactory _connectionFactory;
        private readonly IFileLoggerService _logger;

        public UserService(ISqlDbConnectionFactory connectionFactory, IFileLoggerService logger)
        {
            _connectionFactory = connectionFactory;
            _logger = logger;
        }

        public async Task<AuthResponseDto> RegisterAsync(RegisterRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var existing = await db.QueryFirstOrDefaultAsync<User>(
                    "SELECT * FROM Users WHERE phone_number = @Phone", new { Phone = request.PhoneNumber });

                if (existing != null)
                {
                    _logger.LogWarning($"Registration failed: Phone {request.PhoneNumber} already registered.", "AUTH_REGISTER");
                    return new AuthResponseDto { Success = false, Message = "Phone number already registered." };
                }

                // Match and verify OTP code if provided
                if (!string.IsNullOrWhiteSpace(request.OtpCode))
                {
                    var otp = await db.QueryFirstOrDefaultAsync<OtpVerification>(
                        "SELECT otp_id as OtpId, phone_number as PhoneNumber, otp_code as OtpCode, is_verified as IsVerified FROM OtpVerification WHERE phone_number = @Phone AND otp_code = @Code AND expires_at > GETDATE()",
                        new { Phone = request.PhoneNumber, Code = request.OtpCode });

                    if (otp == null)
                    {
                        _logger.LogWarning($"Registration failed: Invalid or expired OTP {request.OtpCode} for phone {request.PhoneNumber}", "AUTH_REGISTER");
                        return new AuthResponseDto { Success = false, Message = "Invalid or expired OTP code." };
                    }

                    await db.ExecuteAsync("UPDATE OtpVerification SET is_verified = 1 WHERE otp_id = @OtpId", new { OtpId = otp.OtpId });
                }

                var userId = Guid.NewGuid().ToString("N");
                var token = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");
                var dietName = request.DietType switch
                {
                    1 => "Non-Vegetarian",
                    2 => "Non-Veg + Alcoholic",
                    _ => "Vegetarian"
                };

                var sql = @"
                    INSERT INTO Users (user_id, phone_number, full_name, password_hash, auth_token, diet_type, diet_name, created_at, updated_at)
                    VALUES (@UserId, @Phone, @Name, @Pass, @Token, @DietType, @DietName, GETDATE(), GETDATE())";

                await db.ExecuteAsync(sql, new {
                    UserId = userId,
                    Phone = request.PhoneNumber,
                    Name = request.FullName,
                    Pass = request.Password,
                    Token = token,
                    DietType = request.DietType,
                    DietName = dietName
                });

                _logger.LogInfo($"User registered successfully: ID={userId}, Phone={request.PhoneNumber}, Name={request.FullName}", "AUTH_REGISTER");

                return new AuthResponseDto
                {
                    Success = true,
                    Message = "Registration successful",
                    Token = token,
                    UserId = userId,
                    FullName = request.FullName,
                    PhoneNumber = request.PhoneNumber,
                    DietType = request.DietType,
                    DietName = dietName
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in RegisterAsync for phone {request.PhoneNumber}", ex, "AUTH_REGISTER");
                return new AuthResponseDto { Success = false, Message = $"Registration error: {ex.Message}" };
            }
        }

        public async Task<AuthResponseDto> LoginAsync(LoginRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var user = await db.QueryFirstOrDefaultAsync<User>(
                    "SELECT user_id as UserId, phone_number as PhoneNumber, full_name as FullName, password_hash as PasswordHash, auth_token as AuthToken, diet_type as DietType, diet_name as DietName FROM Users WHERE phone_number = @Phone",
                    new { Phone = request.PhoneNumber });

                if (user == null || user.PasswordHash != request.Password)
                {
                    _logger.LogWarning($"Login failed for phone {request.PhoneNumber}: Invalid credentials.", "AUTH_LOGIN");
                    return new AuthResponseDto { Success = false, Message = "Invalid phone number or password." };
                }

                _logger.LogInfo($"User logged in successfully: ID={user.UserId}, Phone={user.PhoneNumber}, Name={user.FullName}", "AUTH_LOGIN");

                return new AuthResponseDto
                {
                    Success = true,
                    Message = "Login successful",
                    Token = user.AuthToken,
                    UserId = user.UserId,
                    FullName = user.FullName,
                    PhoneNumber = user.PhoneNumber,
                    DietType = user.DietType,
                    DietName = user.DietName
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in LoginAsync for phone {request.PhoneNumber}", ex, "AUTH_LOGIN");
                return new AuthResponseDto { Success = false, Message = $"Login error: {ex.Message}" };
            }
        }

        public async Task<User?> GetUserByIdAsync(string userId)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                return await db.QueryFirstOrDefaultAsync<User>(
                    "SELECT user_id as UserId, phone_number as PhoneNumber, full_name as FullName, diet_type as DietType, diet_name as DietName FROM Users WHERE user_id = @UserId",
                    new { UserId = userId });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetUserByIdAsync for userId {userId}", ex, "USERS");
                return null;
            }
        }

        public async Task<User?> GetUserByPhoneAsync(string phoneNumber)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                return await db.QueryFirstOrDefaultAsync<User>(
                    "SELECT user_id as UserId, phone_number as PhoneNumber, full_name as FullName, diet_type as DietType, diet_name as DietName FROM Users WHERE phone_number = @Phone",
                    new { Phone = phoneNumber });
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in GetUserByPhoneAsync for phone {phoneNumber}", ex, "USERS");
                return null;
            }
        }

        public async Task<OtpResponseDto> SendOtpAsync(OtpRequestDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var otpId = Guid.NewGuid().ToString("N");
                var otpCode = new Random().Next(100000, 999999).ToString();
                var sql = @"
                    INSERT INTO OtpVerification (otp_id, phone_number, otp_code, purpose, is_verified, expires_at, created_at)
                    VALUES (@OtpId, @Phone, @Code, @Purpose, 0, DATEADD(minute, 10, GETDATE()), GETDATE())";

                await db.ExecuteAsync(sql, new { OtpId = otpId, Phone = request.PhoneNumber, Code = otpCode, Purpose = request.Purpose });

                _logger.LogInfo($"Generated OTP {otpCode} for phone {request.PhoneNumber} (Purpose={request.Purpose})", "AUTH_OTP");

                return new OtpResponseDto
                {
                    Success = true,
                    Message = $"OTP code sent to {request.PhoneNumber}",
                    OtpCode = otpCode
                };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in SendOtpAsync for phone {request.PhoneNumber}", ex, "AUTH_OTP");
                return new OtpResponseDto
                {
                    Success = false,
                    Message = $"Failed to send OTP: {ex.Message}"
                };
            }
        }

        public async Task<bool> VerifyOtpAsync(VerifyOtpDto request)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var otp = await db.QueryFirstOrDefaultAsync<OtpVerification>(
                    "SELECT otp_id as OtpId FROM OtpVerification WHERE phone_number = @Phone AND otp_code = @Code AND is_verified = 0 AND expires_at > GETDATE()",
                    new { Phone = request.PhoneNumber, Code = request.OtpCode });

                if (otp == null)
                {
                    _logger.LogWarning($"OTP verification failed for phone {request.PhoneNumber} with code {request.OtpCode}", "AUTH_OTP");
                    return false;
                }

                await db.ExecuteAsync("UPDATE OtpVerification SET is_verified = 1 WHERE otp_id = @OtpId", new { OtpId = otp.OtpId });
                _logger.LogInfo($"OTP verified successfully for phone {request.PhoneNumber}", "AUTH_OTP");
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in VerifyOtpAsync for phone {request.PhoneNumber}", ex, "AUTH_OTP");
                return false;
            }
        }
    }
}
