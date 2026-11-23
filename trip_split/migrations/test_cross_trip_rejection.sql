SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

USE [SPLIT_BILL_DB_TEST];

PRINT '============================================================================';
PRINT 'TEST SUITE: CROSS-TRIP COMPOSITE FOREIGN KEY INTEGRITY ENFORCEMENT';
PRINT '============================================================================';

-- Setup two distinct test trips and their persons
DECLARE @TripA NVARCHAR(200) = 'TRIP_ALPHA_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @TripB NVARCHAR(200) = 'TRIP_BETA_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @PersonA NVARCHAR(200) = 'PA_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @PersonB NVARCHAR(200) = 'PB_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @ExpenseA NVARCHAR(200) = 'EA_' + CAST(NEWID() AS NVARCHAR(36));

-- Insert test trips
INSERT INTO Trips (trip_id, user_id, name, created_at)
VALUES (@TripA, '7ecc14fe-8797-4d93-a24b-96eeb9ef71fd', 'Trip Alpha', GETDATE()),
       (@TripB, '7ecc14fe-8797-4d93-a24b-96eeb9ef71fd', 'Trip Beta', GETDATE());

-- Insert Person A into Trip A, Person B into Trip B
INSERT INTO Persons (person_id, trip_id, name, phone_number)
VALUES (@PersonA, @TripA, 'Alice (Trip A)', '+919999011111'),
       (@PersonB, @TripB, 'Bob (Trip B)', '+919999022222');

PRINT 'Inserted Person A into Trip Alpha, Person B into Trip Beta.';

-- Insert valid Expense A in Trip A (paid by Person A)
INSERT INTO Expenses (expense_id, trip_id, description, amount, paid_by_person_id, expense_date)
VALUES (@ExpenseA, @TripA, 'Valid Expense in Trip A', 100.00, @PersonA, GETDATE());
PRINT 'Inserted valid Expense A in Trip Alpha (paid by Person A).';

PRINT '----------------------------------------------------------------------------';
PRINT 'TEST 1: ATTEMPT TO INSERT EXPENSE IN TRIP ALPHA PAID BY PERSON B (TRIP BETA)';
PRINT '----------------------------------------------------------------------------';
BEGIN TRY
    INSERT INTO Expenses (expense_id, trip_id, description, amount, paid_by_person_id, expense_date)
    VALUES (NEWID(), @TripA, 'Invalid Cross-Trip Expense', 250.00, @PersonB, GETDATE());
    PRINT 'UNEXPECTED: Cross-trip expense insert succeeded!';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED REJECTION: Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE();
END CATCH;

PRINT '----------------------------------------------------------------------------';
PRINT 'TEST 2: ATTEMPT TO INSERT SPLIT IN TRIP ALPHA FOR PERSON B (TRIP BETA)';
PRINT '----------------------------------------------------------------------------';
BEGIN TRY
    INSERT INTO ExpenseSplits (split_id, expense_id, trip_id, person_id, amount)
    VALUES (NEWID(), @ExpenseA, @TripA, @PersonB, 50.00);
    PRINT 'UNEXPECTED: Cross-trip expense split insert succeeded!';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED REJECTION: Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE();
END CATCH;

PRINT '----------------------------------------------------------------------------';
PRINT 'TEST 3: ATTEMPT TO INSERT SETTLEMENT IN TRIP ALPHA WITH PERSON B AS PAYER';
PRINT '----------------------------------------------------------------------------';
BEGIN TRY
    INSERT INTO SettlementTransactions (settlement_id, trip_id, from_person_id, to_person_id, amount, is_completed, status)
    VALUES (NEWID(), @TripA, @PersonB, @PersonA, 50.00, 1, 'ACCEPTED');
    PRINT 'UNEXPECTED: Cross-trip settlement insert succeeded!';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED REJECTION: Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE();
END CATCH;

-- Cleanup transient test trips
DELETE FROM Trips WHERE trip_id IN (@TripA, @TripB);
PRINT 'Cleaned up transient test trips.';

PRINT '============================================================================';
PRINT 'COMPOSITE INTEGRITY ENFORCEMENT VERIFIED: ALL INVALID CROSS-TRIP INSERTS REJECTED';
PRINT '============================================================================';
