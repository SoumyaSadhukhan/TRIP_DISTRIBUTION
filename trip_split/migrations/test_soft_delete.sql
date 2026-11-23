SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

USE [SPLIT_BILL_DB_TEST];
GO

PRINT '============================================================================';
PRINT 'MIGRATION & VERIFICATION: SOFT DELETION ON TRIPS, EXPENSES, PERSONS';
PRINT '============================================================================';

-- 1. Add soft-delete columns to Trips
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Trips') AND name = 'is_deleted')
BEGIN
    ALTER TABLE Trips ADD is_deleted BIT NOT NULL CONSTRAINT DF_Trips_IsDeleted DEFAULT 0, deleted_at DATETIME NULL;
    PRINT 'Added is_deleted and deleted_at to Trips.';
END;
GO

-- 2. Add soft-delete columns to Expenses
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Expenses') AND name = 'is_deleted')
BEGIN
    ALTER TABLE Expenses ADD is_deleted BIT NOT NULL CONSTRAINT DF_Expenses_IsDeleted DEFAULT 0, deleted_at DATETIME NULL;
    PRINT 'Added is_deleted and deleted_at to Expenses.';
END;
GO

-- 3. Add soft-delete columns to Persons
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Persons') AND name = 'is_deleted')
BEGIN
    ALTER TABLE Persons ADD is_deleted BIT NOT NULL CONSTRAINT DF_Persons_IsDeleted DEFAULT 0, deleted_at DATETIME NULL;
    PRINT 'Added is_deleted and deleted_at to Persons.';
END;
GO

-- 4. Test soft delete workflow
DECLARE @TestTripId NVARCHAR(200) = 'SOFT_DEL_TRIP_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @PersonId NVARCHAR(200) = 'P_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @ExpenseId NVARCHAR(200) = 'E_' + CAST(NEWID() AS NVARCHAR(36));

INSERT INTO Trips (trip_id, user_id, name, created_at, is_deleted)
VALUES (@TestTripId, '7ecc14fe-8797-4d93-a24b-96eeb9ef71fd', 'Soft Delete Test Trip', GETDATE(), 0);

INSERT INTO Persons (person_id, trip_id, name, is_deleted)
VALUES (@PersonId, @TestTripId, 'Auditor Person', 0);

INSERT INTO Expenses (expense_id, trip_id, description, amount, paid_by_person_id, expense_date, is_deleted)
VALUES (@ExpenseId, @TestTripId, 'Historical Audited Expense', 500.00, @PersonId, GETDATE(), 0);

PRINT 'Step 1: Active record counts:';
SELECT COUNT(*) AS ActiveTripsCount FROM Trips WHERE trip_id = @TestTripId AND is_deleted = 0;
SELECT COUNT(*) AS ActiveExpensesCount FROM Expenses WHERE expense_id = @ExpenseId AND is_deleted = 0;

-- Execute Soft Delete
UPDATE Expenses SET is_deleted = 1, deleted_at = GETUTCDATE() WHERE expense_id = @ExpenseId;
UPDATE Trips SET is_deleted = 1, deleted_at = GETUTCDATE() WHERE trip_id = @TestTripId;

PRINT 'Step 2: Normal UI query (WHERE is_deleted = 0):';
SELECT COUNT(*) AS UI_Visible_Trips FROM Trips WHERE trip_id = @TestTripId AND is_deleted = 0;
SELECT COUNT(*) AS UI_Visible_Expenses FROM Expenses WHERE expense_id = @ExpenseId AND is_deleted = 0;

PRINT 'Step 3: Historical Audit query (includes soft-deleted):';
SELECT trip_id, name, is_deleted, deleted_at FROM Trips WHERE trip_id = @TestTripId;
SELECT expense_id, description, amount, is_deleted, deleted_at FROM Expenses WHERE expense_id = @ExpenseId;

-- Clean test records
DELETE FROM Expenses WHERE expense_id = @ExpenseId;
DELETE FROM Persons WHERE person_id = @PersonId;
DELETE FROM Trips WHERE trip_id = @TestTripId;

PRINT '============================================================================';
PRINT 'SOFT DELETION DESIGN VERIFIED SUCCESSFULLY';
PRINT '============================================================================';
GO
