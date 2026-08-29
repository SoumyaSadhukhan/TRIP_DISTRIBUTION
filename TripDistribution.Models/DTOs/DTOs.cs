using System;
using System.Collections.Generic;

namespace TripDistribution.Models.DTOs
{
    public class RegisterRequestDto
    {
        public string PhoneNumber { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
        public int DietType { get; set; }
        public string OtpCode { get; set; } = string.Empty;
    }

    public class LoginRequestDto
    {
        public string PhoneNumber { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
    }

    public class AuthResponseDto
    {
        public bool Success { get; set; }
        public string Message { get; set; } = string.Empty;
        public string Token { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public string PhoneNumber { get; set; } = string.Empty;
        public int DietType { get; set; }
        public string DietName { get; set; } = string.Empty;
    }

    public class OtpRequestDto
    {
        public string PhoneNumber { get; set; } = string.Empty;
        public string Purpose { get; set; } = "REGISTER";
    }

    public class OtpResponseDto
    {
        public bool Success { get; set; }
        public string Message { get; set; } = string.Empty;
        public string OtpCode { get; set; } = string.Empty;
    }

    public class VerifyOtpDto
    {
        public string PhoneNumber { get; set; } = string.Empty;
        public string OtpCode { get; set; } = string.Empty;
    }

    public class CreateTripRequestDto
    {
        public string UserId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
    }

    public class AddMemberRequestDto
    {
        public string TripId { get; set; } = string.Empty;
        public string GroupId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string PhoneNumber { get; set; } = string.Empty;
        public int DietType { get; set; }
    }

    public class SyncTripsRequestDto
    {
        public string UserId { get; set; } = string.Empty;
        public List<SyncTripDto> Trips { get; set; } = new();
    }

    public class SyncTripDto
    {
        public string TripId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public List<SyncGroupDto> Groups { get; set; } = new();
        public List<SyncExpenseDto> Expenses { get; set; } = new();
    }

    public class SyncGroupDto
    {
        public string GroupId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public List<SyncPersonDto> Members { get; set; } = new();
    }

    public class SyncPersonDto
    {
        public string PersonId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string PhoneNumber { get; set; } = string.Empty;
        public int DietType { get; set; }
        public string DietName { get; set; } = string.Empty;
        public decimal PaidAmount { get; set; }
        public decimal OwedAmount { get; set; }
        public decimal Balance { get; set; }
    }

    public class SyncExpenseDto
    {
        public string ExpenseId { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public int CategoryIndex { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        public string PaidByPersonId { get; set; } = string.Empty;
        public List<ExpenseSplitDto> Splits { get; set; } = new();
    }

    public class CreateExpenseRequestDto
    {
        public string TripId { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public int CategoryIndex { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        public string PaidByPersonId { get; set; } = string.Empty;
        public List<ExpenseSplitDto> Splits { get; set; } = new();
    }

    public class ExpenseSplitDto
    {
        public string PersonId { get; set; } = string.Empty;
        public decimal Amount { get; set; }
    }

    public class CreateSettlementRequestDto
    {
        public string TripId { get; set; } = string.Empty;
        public string FromPersonId { get; set; } = string.Empty;
        public string ToPersonId { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string CreatedByUserId { get; set; } = string.Empty;
    }

    public class AddFriendRequestDto
    {
        public string UserId { get; set; } = string.Empty;
        public string FriendPhone { get; set; } = string.Empty;
        public string FriendName { get; set; } = string.Empty;
        public int DietType { get; set; }
    }

    public class ApiResponse<T>
    {
        public bool Success { get; set; }
        public string Message { get; set; } = string.Empty;
        public T? Data { get; set; }
    }
}
