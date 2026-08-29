-- ====================================================================
-- SCRIPT 1: CLEAR ALL DATA FROM ALL TABLES (RETAIN TABLE SCHEMAS)
-- Database: SPLIT_BILL_DB
-- ====================================================================
USE SPLIT_BILL_DB;
GO

-- Disable foreign key constraints temporarily
EXEC sp_MSforeachtable "ALTER TABLE ? NOCHECK CONSTRAINT ALL";
GO

-- Delete all rows from each table
DELETE FROM Settlements;
DELETE FROM ExpenseSplits;
DELETE FROM Expenses;
DELETE FROM TripMembers;
DELETE FROM Trips;
DELETE FROM Friends;
DELETE FROM OtpVerification;
DELETE FROM Users;
GO

-- Re-enable foreign key constraints
EXEC sp_MSforeachtable "ALTER TABLE ? WITH CHECK CHECK CONSTRAINT ALL";
GO

PRINT 'All data in SPLIT_BILL_DB has been successfully cleared!';
GO
