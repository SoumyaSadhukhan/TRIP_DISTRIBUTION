-- ====================================================================
-- SCRIPT: HIGH-PERFORMANCE INDEXES FOR 1 MILLION+ USERS
-- Target Database: SPLIT_BILL_DB
-- ====================================================================
USE SPLIT_BILL_DB;
GO

-- 1. Users Indexes
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_Users_Phone')
    CREATE NONCLUSTERED INDEX IX_Users_Phone ON Users(phone_number) INCLUDE (user_id, full_name, password_hash, auth_token, diet_type);
GO

-- 2. Trips Indexes
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_Trips_CreatedBy')
    CREATE NONCLUSTERED INDEX IX_Trips_CreatedBy ON Trips(created_by_user_id) INCLUDE (trip_id, name, created_at);
GO

-- 3. Trip Members Indexes
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_TripMembers_TripId')
    CREATE NONCLUSTERED INDEX IX_TripMembers_TripId ON TripMembers(trip_id) INCLUDE (member_id, group_id, name, phone_number, diet_type);
GO

IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_TripMembers_Phone')
    CREATE NONCLUSTERED INDEX IX_TripMembers_Phone ON TripMembers(phone_number) INCLUDE (trip_id, member_id, name);
GO

-- 4. Expenses Indexes
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_Expenses_TripId')
    CREATE NONCLUSTERED INDEX IX_Expenses_TripId ON Expenses(trip_id) INCLUDE (expense_id, amount, paid_by_person_id, created_at);
GO

-- 5. Expense Splits Indexes
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_ExpenseSplits_ExpenseId')
    CREATE NONCLUSTERED INDEX IX_ExpenseSplits_ExpenseId ON ExpenseSplits(expense_id) INCLUDE (split_id, person_id, amount);
GO

IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_ExpenseSplits_PersonId')
    CREATE NONCLUSTERED INDEX IX_ExpenseSplits_PersonId ON ExpenseSplits(person_id) INCLUDE (expense_id, amount);
GO

-- 6. Settlements Indexes
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_Settlements_TripId')
    CREATE NONCLUSTERED INDEX IX_Settlements_TripId ON Settlements(trip_id) INCLUDE (settlement_id, from_person_id, to_person_id, amount, status, created_at);
GO

-- 7. Friends Indexes
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_Friends_UserId')
    CREATE NONCLUSTERED INDEX IX_Friends_UserId ON Friends(user_id) INCLUDE (friend_id, friend_phone, friend_name, diet_type);
GO

-- 8. OTP Verification Indexes
IF NOT EXISTS (SELECT name FROM sys.indexes WHERE name = N'IX_Otp_Phone_Code')
    CREATE NONCLUSTERED INDEX IX_Otp_Phone_Code ON OtpVerification(phone_number, otp_code) INCLUDE (otp_id, is_verified, expires_at);
GO

PRINT 'High-performance indexes for 1 Million+ users applied successfully!';
GO
