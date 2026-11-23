SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

USE [SPLIT_BILL_DB_TEST];

PRINT '============================================================================';
PRINT 'CASCADE & NO_ACTION CONSTRAINT VERIFICATION ON SPLIT_BILL_DB_TEST';
PRINT '============================================================================';

-- Setup transient test entities
DECLARE @TestTripId NVARCHAR(200) = 'CASCADE_TEST_TRIP_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @TestUserId NVARCHAR(200) = 'CASCADE_TEST_USER_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @Person1Id NVARCHAR(200) = 'P1_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @Person2Id NVARCHAR(200) = 'P2_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @ExpenseId NVARCHAR(200) = 'E1_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @Split1Id NVARCHAR(200) = 'S1_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @Split2Id NVARCHAR(200) = 'S2_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @SettlementId NVARCHAR(200) = 'ST1_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @TokenId NVARCHAR(200) = 'UT1_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @NotificationId NVARCHAR(200) = 'N1_' + CAST(NEWID() AS NVARCHAR(36));
DECLARE @CollabId NVARCHAR(200) = 'C1_' + CAST(NEWID() AS NVARCHAR(36));

-- Insert test user
INSERT INTO Users (user_id, phone_number, email, username, full_name, is_active)
VALUES (@TestUserId, '+919999099999', 'cascade_tester@test.local', 'cascadetester', 'Cascade Tester', 1);

-- Insert test trip
INSERT INTO Trips (trip_id, user_id, name, created_at)
VALUES (@TestTripId, @TestUserId, 'Cascade Verification Trip', GETDATE());

-- Insert persons in trip
INSERT INTO Persons (person_id, trip_id, name, phone_number, user_id, paid_amount, owed_amount, balance)
VALUES (@Person1Id, @TestTripId, 'Person Alpha', '+919999099991', @TestUserId, 100.00, 50.00, 50.00),
       (@Person2Id, @TestTripId, 'Person Beta', '+919999099992', NULL, 0.00, 50.00, -50.00);

-- Insert expense
INSERT INTO Expenses (expense_id, trip_id, description, amount, paid_by_person_id, expense_date)
VALUES (@ExpenseId, @TestTripId, 'Lunch', 100.00, @Person1Id, GETDATE());

-- Insert splits
INSERT INTO ExpenseSplits (split_id, expense_id, trip_id, person_id, amount)
VALUES (@Split1Id, @ExpenseId, @TestTripId, @Person1Id, 50.00),
       (@Split2Id, @ExpenseId, @TestTripId, @Person2Id, 50.00);

-- Insert settlement
INSERT INTO SettlementTransactions (settlement_id, trip_id, from_person_id, to_person_id, amount, is_completed, status)
VALUES (@SettlementId, @TestTripId, @Person2Id, @Person1Id, 50.00, 1, 'ACCEPTED');

-- Insert user tokens, notifications, collaborators
INSERT INTO UserTokens (token_id, user_id, auth_token, is_active)
VALUES (@TokenId, @TestUserId, 'TEST_ACTIVE_TOKEN', 1);

INSERT INTO Notifications (notification_id, user_id, title, message, type)
VALUES (@NotificationId, @TestUserId, 'Test Notification', 'Hello', 'INFO');

INSERT INTO TripCollaborators (collab_id, trip_id, user_id, role, status)
VALUES (@CollabId, @TestTripId, @TestUserId, 'OWNER', 'ACCEPTED');

PRINT 'Test data inserted successfully.';

PRINT '----------------------------------------------------------------------------';
PRINT 'TEST 1: ATTEMPT TO DELETE PERSON REFERENCED BY AN EXPENSE (EXPECT BLOCKED)';
PRINT '----------------------------------------------------------------------------';
BEGIN TRY
    DELETE FROM Persons WHERE person_id = @Person1Id;
    PRINT 'UNEXPECTED: Delete Person succeeded!';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED BLOCKED: Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE();
END CATCH;

PRINT '----------------------------------------------------------------------------';
PRINT 'TEST 2: ATTEMPT TO DELETE PERSON REFERENCED BY AN EXPENSE SPLIT (EXPECT BLOCKED)';
PRINT '----------------------------------------------------------------------------';
BEGIN TRY
    DELETE FROM Persons WHERE person_id = @Person2Id;
    PRINT 'UNEXPECTED: Delete Person succeeded!';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED BLOCKED: Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' + ERROR_MESSAGE();
END CATCH;

PRINT '----------------------------------------------------------------------------';
PRINT 'TEST 3: DELETE EXPENSE CONTAINING EXPENSE SPLITS (EXPECT CASCADE)';
PRINT '----------------------------------------------------------------------------';
BEGIN TRY
    DELETE FROM Expenses WHERE expense_id = @ExpenseId;
    PRINT 'Expense deleted.';
    DECLARE @RemainingSplits INT;
    SELECT @RemainingSplits = COUNT(*) FROM ExpenseSplits WHERE expense_id = @ExpenseId;
    PRINT 'Remaining splits for deleted expense: ' + CAST(@RemainingSplits AS VARCHAR) + ' (EXPECT: 0)';
END TRY
BEGIN CATCH
    PRINT 'UNEXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH;

PRINT '----------------------------------------------------------------------------';
PRINT 'TEST 4: DELETE TRIP CONTAINING PERSONS, SETTLEMENTS, COLLABORATORS (EXPECT CASCADE)';
PRINT '----------------------------------------------------------------------------';
BEGIN TRY
    DELETE FROM Trips WHERE trip_id = @TestTripId;
    PRINT 'Trip deleted.';
    
    DECLARE @RemPersons INT, @RemSettlements INT, @RemCollabs INT;
    SELECT @RemPersons = COUNT(*) FROM Persons WHERE trip_id = @TestTripId;
    SELECT @RemSettlements = COUNT(*) FROM SettlementTransactions WHERE trip_id = @TestTripId;
    SELECT @RemCollabs = COUNT(*) FROM TripCollaborators WHERE trip_id = @TestTripId;
    
    PRINT 'Remaining Persons: ' + CAST(@RemPersons AS VARCHAR) + ' (EXPECT: 0)';
    PRINT 'Remaining Settlements: ' + CAST(@RemSettlements AS VARCHAR) + ' (EXPECT: 0)';
    PRINT 'Remaining Collaborators: ' + CAST(@RemCollabs AS VARCHAR) + ' (EXPECT: 0)';
END TRY
BEGIN CATCH
    PRINT 'UNEXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH;

PRINT '----------------------------------------------------------------------------';
PRINT 'TEST 5: DELETE USER WITH TOKENS AND NOTIFICATIONS (EXPECT CASCADE)';
PRINT '----------------------------------------------------------------------------';
BEGIN TRY
    DELETE FROM Users WHERE user_id = @TestUserId;
    PRINT 'User deleted.';
    
    DECLARE @RemTokens INT, @RemNotifs INT;
    SELECT @RemTokens = COUNT(*) FROM UserTokens WHERE user_id = @TestUserId;
    SELECT @RemNotifs = COUNT(*) FROM Notifications WHERE user_id = @TestUserId;
    
    PRINT 'Remaining UserTokens: ' + CAST(@RemTokens AS VARCHAR) + ' (EXPECT: 0)';
    PRINT 'Remaining Notifications: ' + CAST(@RemNotifs AS VARCHAR) + ' (EXPECT: 0)';
END TRY
BEGIN CATCH
    PRINT 'UNEXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH;

PRINT '============================================================================';
PRINT 'ALL CASCADE AND REFERENTIAL INTEGRITY TESTS EXECUTED';
PRINT '============================================================================';
