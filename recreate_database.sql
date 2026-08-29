-- ====================================================================
-- SCRIPT 2: DROP AND RECREATE FRESH DATABASE & TABLES
-- Database: SPLIT_BILL_DB
-- ====================================================================
USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = N'SPLIT_BILL_DB')
BEGIN
    ALTER DATABASE SPLIT_BILL_DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SPLIT_BILL_DB;
END
GO

CREATE DATABASE SPLIT_BILL_DB;
GO

USE SPLIT_BILL_DB;
GO

-- 1. Users Table
CREATE TABLE Users (
    user_id NVARCHAR(100) PRIMARY KEY,
    phone_number NVARCHAR(20) NOT NULL UNIQUE,
    full_name NVARCHAR(100) NOT NULL,
    password_hash NVARCHAR(255) NOT NULL,
    auth_token NVARCHAR(255),
    diet_type INT DEFAULT 0, -- 0: Veg, 1: Non-Veg, 2: Non-Veg + Alcoholic
    diet_name NVARCHAR(50) DEFAULT 'Vegetarian',
    created_at DATETIME DEFAULT GETDATE(),
    updated_at DATETIME DEFAULT GETDATE()
);
GO

-- 2. OTP Verification Table
CREATE TABLE OtpVerification (
    otp_id NVARCHAR(100) PRIMARY KEY,
    phone_number NVARCHAR(20) NOT NULL,
    otp_code NVARCHAR(10) NOT NULL,
    purpose NVARCHAR(50) DEFAULT 'REGISTER',
    is_verified BIT DEFAULT 0,
    expires_at DATETIME NOT NULL,
    created_at DATETIME DEFAULT GETDATE()
);
GO

-- 3. Trips Table
CREATE TABLE Trips (
    trip_id NVARCHAR(100) PRIMARY KEY,
    name NVARCHAR(150) NOT NULL,
    description NVARCHAR(500),
    created_by_user_id NVARCHAR(100) NOT NULL FOREIGN KEY REFERENCES Users(user_id),
    created_at DATETIME DEFAULT GETDATE(),
    updated_at DATETIME DEFAULT GETDATE()
);
GO

-- 4. Trip Members Table
CREATE TABLE TripMembers (
    member_id NVARCHAR(100) PRIMARY KEY,
    trip_id NVARCHAR(100) NOT NULL FOREIGN KEY REFERENCES Trips(trip_id) ON DELETE CASCADE,
    group_id NVARCHAR(100),
    name NVARCHAR(100) NOT NULL,
    phone_number NVARCHAR(20),
    diet_type INT DEFAULT 0,
    diet_name NVARCHAR(50) DEFAULT 'Vegetarian',
    created_at DATETIME DEFAULT GETDATE()
);
GO

-- 5. Expenses Table
CREATE TABLE Expenses (
    expense_id NVARCHAR(100) PRIMARY KEY,
    trip_id NVARCHAR(100) NOT NULL FOREIGN KEY REFERENCES Trips(trip_id) ON DELETE CASCADE,
    description NVARCHAR(255) NOT NULL,
    amount DECIMAL(18, 2) NOT NULL,
    category_index INT DEFAULT 0,
    category_name NVARCHAR(50) DEFAULT 'Other',
    paid_by_person_id NVARCHAR(100) NOT NULL,
    created_at DATETIME DEFAULT GETDATE()
);
GO

-- 6. Expense Splits Table
CREATE TABLE ExpenseSplits (
    split_id NVARCHAR(100) PRIMARY KEY,
    expense_id NVARCHAR(100) NOT NULL FOREIGN KEY REFERENCES Expenses(expense_id) ON DELETE CASCADE,
    person_id NVARCHAR(100) NOT NULL,
    amount DECIMAL(18, 2) NOT NULL
);
GO

-- 7. Settlements Table
CREATE TABLE Settlements (
    settlement_id NVARCHAR(100) PRIMARY KEY,
    trip_id NVARCHAR(100) NOT NULL FOREIGN KEY REFERENCES Trips(trip_id) ON DELETE CASCADE,
    from_person_id NVARCHAR(100) NOT NULL,
    to_person_id NVARCHAR(100) NOT NULL,
    amount DECIMAL(18, 2) NOT NULL,
    status NVARCHAR(20) DEFAULT 'COMPLETED',
    created_by_user_id NVARCHAR(100),
    created_at DATETIME DEFAULT GETDATE()
);
GO

-- 8. Friends Table
CREATE TABLE Friends (
    friend_id NVARCHAR(100) PRIMARY KEY,
    user_id NVARCHAR(100) NOT NULL FOREIGN KEY REFERENCES Users(user_id),
    friend_phone NVARCHAR(20) NOT NULL,
    friend_name NVARCHAR(100) NOT NULL,
    diet_type INT DEFAULT 0,
    created_at DATETIME DEFAULT GETDATE()
);
GO

PRINT 'SPLIT_BILL_DB has been completely reset and all tables recreated!';
GO
