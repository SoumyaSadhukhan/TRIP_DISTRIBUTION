namespace TripDistribution.Models.Enums
{
    public enum DietType
    {
        Vegetarian = 0,
        NonVegetarian = 1,
        NonVegAlcoholic = 2
    }

    public enum ConnectionStatus
    {
        Pending,
        Accepted,
        Rejected
    }

    public enum SettlementStatus
    {
        Pending,
        Accepted,
        Declined
    }

    public enum NotificationType
    {
        ExpenseAdded,
        ExpenseUpdated,
        DebtAlert,
        Settlement
    }
}
