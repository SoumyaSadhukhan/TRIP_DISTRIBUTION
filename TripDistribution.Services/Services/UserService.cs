using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
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
        Task<dynamic> VerifyTokenAsync(string token, string? phone);
        Task<ApiResponse<bool>> UpdateProfileAsync(string userId, string? fullName, int? dietType);
        Task<ApiResponse<bool>> ResetPasswordAsync(string phone, string otp, string newPassword);
        Task<bool> ToggleBiometricAsync(string userId, bool enabled);
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
                var existingUser = await db.QueryFirstOrDefaultAsync<User>(
                    "SELECT user_id as UserId, phone_number as PhoneNumber FROM Users WHERE phone_number = @Phone",
                    new { Phone = request.PhoneNumber });

                if (existingUser != null)
                {
                    _logger.LogWarning($"Registration rejected: Phone {request.PhoneNumber} is already registered.", "AUTH_REGISTER");
                    return new AuthResponseDto { Success = false, Message = "Phone number is already registered. Please log in." };
                }

                if (!string.IsNullOrEmpty(request.OtpCode))
                {
                    var otp = await db.QueryFirstOrDefaultAsync<OtpVerification>(
                        "SELECT otp_id as OtpId FROM OtpVerification WHERE phone_number = @Phone AND otp_code = @Code AND is_verified = 0 AND expires_at > GETDATE()",
                        new { Phone = request.PhoneNumber, Code = request.OtpCode });

                    if (otp == null)
                    {
                        _logger.LogWarning($"Invalid or expired OTP for registration: Phone {request.PhoneNumber}", "AUTH_REGISTER");
                        return new AuthResponseDto { Success = false, Message = "Invalid or expired OTP." };
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

                // Refresh auth_token if missing
                var token = user.AuthToken;
                if (string.IsNullOrEmpty(token))
                {
                    token = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");
                    await db.ExecuteAsync("UPDATE Users SET auth_token = @Token, updated_at = GETDATE() WHERE user_id = @UserId",
                        new { Token = token, UserId = user.UserId });
                }

                _logger.LogInfo($"User logged in successfully: ID={user.UserId}, Phone={user.PhoneNumber}, Name={user.FullName}", "AUTH_LOGIN");

                return new AuthResponseDto
                {
                    Success = true,
                    Message = "Login successful",
                    Token = token,
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

        public async Task<dynamic> VerifyTokenAsync(string token, string? phone)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                User? user = null;

                if (!string.IsNullOrEmpty(token))
                {
                    user = await db.QueryFirstOrDefaultAsync<User>(
                        "SELECT user_id as UserId, phone_number as PhoneNumber, full_name as FullName, diet_type as DietType, diet_name as DietName, auth_token as AuthToken, ISNULL(is_biometric_enabled, 0) as IsBiometricEnabled FROM Users WHERE auth_token = @Token",
                        new { Token = token });
                }

                if (user == null && !string.IsNullOrEmpty(phone))
                {
                    user = await db.QueryFirstOrDefaultAsync<User>(
                        "SELECT user_id as UserId, phone_number as PhoneNumber, full_name as FullName, diet_type as DietType, diet_name as DietName, auth_token as AuthToken, ISNULL(is_biometric_enabled, 0) as IsBiometricEnabled FROM Users WHERE phone_number = @Phone",
                        new { Phone = phone });
                }

                if (user != null)
                {
                    return new
                    {
                        valid = true,
                        success = true,
                        user = new
                        {
                            id = user.UserId,
                            phone = user.PhoneNumber,
                            fullName = user.FullName,
                            dietType = user.DietType,
                            dietName = user.DietName,
                            isBiometricEnabled = user.IsBiometricEnabled,
                            token = user.AuthToken ?? token
                        }
                    };
                }

                return new { valid = false, success = false, message = "Token invalid or expired" };
            }
            catch (Exception ex)
            {
                _logger.LogError("Error in VerifyTokenAsync", ex, "AUTH_VERIFY");
                return new { valid = false, success = false, message = ex.Message };
            }
        }

        public async Task<ApiResponse<bool>> UpdateProfileAsync(string userId, string? fullName, int? dietType)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var dietName = dietType switch
                {
                    1 => "Non-Vegetarian",
                    2 => "Non-Veg + Alcoholic",
                    _ => "Vegetarian"
                };

                if (!string.IsNullOrEmpty(fullName) && dietType.HasValue)
                {
                    await db.ExecuteAsync(
                        "UPDATE Users SET full_name = @Name, diet_type = @Diet, diet_name = @DietName, updated_at = GETDATE() WHERE user_id = @UserId",
                        new { Name = fullName, Diet = dietType.Value, DietName = dietName, UserId = userId });
                }
                else if (!string.IsNullOrEmpty(fullName))
                {
                    await db.ExecuteAsync(
                        "UPDATE Users SET full_name = @Name, updated_at = GETDATE() WHERE user_id = @UserId",
                        new { Name = fullName, UserId = userId });
                }
                else if (dietType.HasValue)
                {
                    await db.ExecuteAsync(
                        "UPDATE Users SET diet_type = @Diet, diet_name = @DietName, updated_at = GETDATE() WHERE user_id = @UserId",
                        new { Diet = dietType.Value, DietName = dietName, UserId = userId });
                }

                return new ApiResponse<bool> { Success = true, Message = "Profile updated successfully." };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in UpdateProfileAsync for user {userId}", ex, "USERS");
                return new ApiResponse<bool> { Success = false, Message = ex.Message };
            }
        }

        public async Task<ApiResponse<bool>> ResetPasswordAsync(string phone, string otp, string newPassword)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var otpRecord = await db.QueryFirstOrDefaultAsync<OtpVerification>(
                    "SELECT otp_id as OtpId FROM OtpVerification WHERE phone_number = @Phone AND otp_code = @Code AND is_verified = 0 AND expires_at > GETDATE()",
                    new { Phone = phone, Code = otp });

                if (otpRecord == null)
                {
                    return new ApiResponse<bool> { Success = false, Message = "Invalid or expired OTP." };
                }

                await db.ExecuteAsync("UPDATE OtpVerification SET is_verified = 1 WHERE otp_id = @OtpId", new { OtpId = otpRecord.OtpId });
                await db.ExecuteAsync("UPDATE Users SET password_hash = @Pass, updated_at = GETDATE() WHERE phone_number = @Phone",
                    new { Pass = newPassword, Phone = phone });

                return new ApiResponse<bool> { Success = true, Message = "Password reset successfully!" };
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in ResetPasswordAsync for phone {phone}", ex, "USERS");
                return new ApiResponse<bool> { Success = false, Message = ex.Message };
            }
        }

        public async Task<bool> ToggleBiometricAsync(string userId, bool enabled)
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                try
                {
                    await db.ExecuteAsync("IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Users') AND name = 'is_biometric_enabled') ALTER TABLE Users ADD is_biometric_enabled BIT DEFAULT 0;");
                }
                catch { }

                await db.ExecuteAsync(
                    "UPDATE Users SET is_biometric_enabled = @Enabled, updated_at = GETDATE() WHERE user_id = @UserId",
                    new { Enabled = enabled, UserId = userId });
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error in ToggleBiometricAsync for user {userId}", ex, "USERS");
                return false;
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
