using System;

namespace TripDistribution.Models.Entities
{
    public class User
    {
        public string UserId { get; set; } = string.Empty;
        public string PhoneNumber { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public string PasswordHash { get; set; } = string.Empty;
        public string AuthToken { get; set; } = string.Empty;
        public DateTime? TokenExpiry { get; set; }
        public int DietType { get; set; }
        public string DietName { get; set; } = "Vegetarian";
        public string AvatarColor { get; set; } = "#4F46E5";
        public bool IsBiometricEnabled { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
        public DateTime? LastLoginAt { get; set; }
    }

    public class UserToken
    {
        public string TokenId { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string PhoneNumber { get; set; } = string.Empty;
        public string AuthToken { get; set; } = string.Empty;
        public string DeviceInfo { get; set; } = string.Empty;
        public bool IsActive { get; set; } = true;
        public DateTime ExpiresAt { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime LastUsedAt { get; set; } = DateTime.UtcNow;
    }

    public class OtpVerification
    {
        public string OtpId { get; set; } = string.Empty;
        public string PhoneNumber { get; set; } = string.Empty;
        public string OtpCode { get; set; } = string.Empty;
        public string Purpose { get; set; } = string.Empty;
        public bool IsVerified { get; set; }
        public DateTime ExpiresAt { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class Trip
    {
        public string TripId { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }

    public class Group
    {
        public string GroupId { get; set; } = string.Empty;
        public string TripId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class Person
    {
        public string PersonId { get; set; } = string.Empty;
        public string GroupId { get; set; } = string.Empty;
        public string TripId { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string PhoneNumber { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public int DietType { get; set; }
        public string DietName { get; set; } = string.Empty;
        public decimal PaidAmount { get; set; }
        public decimal OwedAmount { get; set; }
        public decimal Balance { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class Expense
    {
        public string ExpenseId { get; set; } = string.Empty;
        public string TripId { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public int CategoryIndex { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        public string PaidByPersonId { get; set; } = string.Empty;
        public DateTime ExpenseDate { get; set; } = DateTime.UtcNow;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class ExpenseSplit
    {
        public string SplitId { get; set; } = string.Empty;
        public string ExpenseId { get; set; } = string.Empty;
        public string TripId { get; set; } = string.Empty;
        public string PersonId { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class SettlementTransaction
    {
        public string SettlementId { get; set; } = string.Empty;
        public string TripId { get; set; } = string.Empty;
        public string FromPersonId { get; set; } = string.Empty;
        public string ToPersonId { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public bool IsCompleted { get; set; }
        public string Status { get; set; } = "ACCEPTED";
        public string CreatedByUserId { get; set; } = string.Empty;
        public DateTime SettledAt { get; set; } = DateTime.UtcNow;
    }

    public class FriendConnection
    {
        public string ConnectionId { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string FriendUserId { get; set; } = string.Empty;
        public string FriendPhone { get; set; } = string.Empty;
        public string FriendName { get; set; } = string.Empty;
        public int DietType { get; set; }
        public string DietName { get; set; } = "Vegetarian";
        public string Status { get; set; } = "ACCEPTED";
        public string RequesterId { get; set; } = string.Empty;
        public string ReceiverId { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class Notification
    {
        public string NotificationId { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string TripId { get; set; } = string.Empty;
        public string TripName { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public bool IsRead { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }
}
