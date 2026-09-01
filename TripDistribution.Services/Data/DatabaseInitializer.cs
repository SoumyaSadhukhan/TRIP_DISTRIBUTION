using System;
using System.Threading.Tasks;
using Dapper;
using TripDistribution.Services.Data;
using TripDistribution.Services.Services;

namespace TripDistribution.Services.Data
{
    public interface IDatabaseInitializer
    {
        Task InitializeAsync();
    }

    public class DatabaseInitializer : IDatabaseInitializer
    {
        private readonly ISqlDbConnectionFactory _connectionFactory;
        private readonly IFileLoggerService _logger;

        public DatabaseInitializer(ISqlDbConnectionFactory connectionFactory, IFileLoggerService logger)
        {
            _connectionFactory = connectionFactory;
            _logger = logger;
        }

        public async Task InitializeAsync()
        {
            try
            {
                using var db = _connectionFactory.CreateConnection();
                var sql = @"
                    -- Ensure Users table columns
                    IF EXISTS (SELECT * FROM sys.tables WHERE name = 'Users')
                    BEGIN
                        IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Users') AND name = 'is_biometric_enabled')
                            ALTER TABLE Users ADD is_biometric_enabled BIT DEFAULT 0;

                        IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Users') AND name = 'auth_token')
                            ALTER TABLE Users ADD auth_token NVARCHAR(255);

                        IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Users') AND name = 'diet_type')
                            ALTER TABLE Users ADD diet_type INT DEFAULT 0;

                        IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Users') AND name = 'diet_name')
                            ALTER TABLE Users ADD diet_name NVARCHAR(50) DEFAULT 'Vegetarian';

                        IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Users') AND name = 'avatar_color')
                            ALTER TABLE Users ADD avatar_color NVARCHAR(50) DEFAULT '#4F46E5';

                        IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Users') AND name = 'is_active')
                            ALTER TABLE Users ADD is_active BIT DEFAULT 1;

                        IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Users') AND name = 'last_login_at')
                            ALTER TABLE Users ADD last_login_at DATETIME;
                    END;

                    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'SettlementTransactions')
                    BEGIN
                        CREATE TABLE SettlementTransactions (
                            settlement_id NVARCHAR(100),
                            trip_id NVARCHAR(100),
                            from_person_id NVARCHAR(100),
                            to_person_id NVARCHAR(100),
                            amount DECIMAL(18, 2),
                            is_completed BIT DEFAULT 0,
                            status NVARCHAR(50) DEFAULT 'PENDING',
                            created_by_user_id NVARCHAR(100),
                            settled_at DATETIME DEFAULT GETDATE()
                        );
                    END;

                    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Notifications')
                    BEGIN
                        CREATE TABLE Notifications (
                            notification_id NVARCHAR(100),
                            user_id NVARCHAR(100),
                            trip_id NVARCHAR(100),
                            trip_name NVARCHAR(200),
                            settlement_id NVARCHAR(100),
                            title NVARCHAR(200),
                            message NVARCHAR(MAX),
                            type NVARCHAR(50),
                            amount DECIMAL(18, 2) DEFAULT 0.00,
                            is_read BIT DEFAULT 0,
                            created_at DATETIME DEFAULT GETDATE()
                        );
                    END
                    ELSE
                    BEGIN
                        IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Notifications') AND name = 'settlement_id')
                            ALTER TABLE Notifications ADD settlement_id NVARCHAR(100);
                    END;

                    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'FriendConnections')
                    BEGIN
                        CREATE TABLE FriendConnections (
                            connection_id NVARCHAR(100),
                            user_id NVARCHAR(100),
                            friend_user_id NVARCHAR(100),
                            friend_phone NVARCHAR(20),
                            friend_name NVARCHAR(150),
                            diet_type INT DEFAULT 0,
                            diet_name NVARCHAR(50) DEFAULT 'Vegetarian',
                            status NVARCHAR(50) DEFAULT 'ACCEPTED',
                            requester_id NVARCHAR(100),
                            receiver_id NVARCHAR(100),
                            created_at DATETIME DEFAULT GETDATE()
                        );
                    END;

                    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'TripCollaborators')
                    BEGIN
                        CREATE TABLE TripCollaborators (
                            collab_id NVARCHAR(100),
                            trip_id NVARCHAR(100),
                            user_id NVARCHAR(100),
                            person_id NVARCHAR(100),
                            phone_number NVARCHAR(20),
                            role NVARCHAR(50) DEFAULT 'MEMBER',
                            status NVARCHAR(50) DEFAULT 'ACCEPTED',
                            joined_at DATETIME DEFAULT GETDATE()
                        );
                    END;

                    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Persons')
                    BEGIN
                        CREATE TABLE Persons (
                            person_id NVARCHAR(100),
                            group_id NVARCHAR(100),
                            trip_id NVARCHAR(100),
                            user_id NVARCHAR(100),
                            phone_number NVARCHAR(20),
                            name NVARCHAR(150),
                            diet_type INT,
                            diet_name NVARCHAR(50),
                            paid_amount DECIMAL(18, 2) DEFAULT 0.00,
                            owed_amount DECIMAL(18, 2) DEFAULT 0.00,
                            balance DECIMAL(18, 2) DEFAULT 0.00,
                            created_at DATETIME DEFAULT GETDATE()
                        );
                    END;

                    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Groups')
                    BEGIN
                        CREATE TABLE Groups (
                            group_id NVARCHAR(100),
                            trip_id NVARCHAR(100),
                            name NVARCHAR(200),
                            created_at DATETIME DEFAULT GETDATE()
                        );
                    END;";

                await db.ExecuteAsync(sql);
                _logger.LogInfo("Database schema validated and all tables/columns ensured.", "STARTUP");
            }
            catch (Exception ex)
            {
                _logger.LogError("Error initializing database schema", ex, "STARTUP");
            }
        }
    }
}
