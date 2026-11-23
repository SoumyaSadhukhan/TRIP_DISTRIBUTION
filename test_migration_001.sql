SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

USE [SPLIT_BILL_DB_TEST];

PRINT '=== APPLYING COMPOSITE UNIQUE CONSTRAINTS ===';

-- Unique constraint on Users(phone_number)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_Users_Phone' AND object_id = OBJECT_ID('Users'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_Users_Phone ON Users(phone_number);
    PRINT 'Created UQ_Users_Phone.';
END;

-- Unique filtered index on Users(email)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_Users_Email' AND object_id = OBJECT_ID('Users'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_Users_Email ON Users(email) WHERE email IS NOT NULL AND email <> '';
    PRINT 'Created UQ_Users_Email.';
END;

-- Unique index on FriendConnections(user_id, friend_user_id)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_FriendConnections_Pair' AND object_id = OBJECT_ID('FriendConnections'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_FriendConnections_Pair ON FriendConnections(user_id, friend_user_id);
    PRINT 'Created UQ_FriendConnections_Pair.';
END;

-- Composite unique constraint on Persons(person_id, trip_id)
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_Persons_PersonId_TripId')
BEGIN
    ALTER TABLE Persons ADD CONSTRAINT UQ_Persons_PersonId_TripId UNIQUE (person_id, trip_id);
    PRINT 'Created UQ_Persons_PersonId_TripId.';
END;

-- Composite unique constraint on Expenses(expense_id, trip_id)
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_Expenses_ExpenseId_TripId')
BEGIN
    ALTER TABLE Expenses ADD CONSTRAINT UQ_Expenses_ExpenseId_TripId UNIQUE (expense_id, trip_id);
    PRINT 'Created UQ_Expenses_ExpenseId_TripId.';
END;

-- Unique constraint on ExpenseSplits(expense_id, person_id)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_ExpenseSplits_Expense_Person' AND object_id = OBJECT_ID('ExpenseSplits'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_ExpenseSplits_Expense_Person ON ExpenseSplits(expense_id, person_id);
    PRINT 'Created UQ_ExpenseSplits_Expense_Person.';
END;

PRINT '=== APPLYING FOREIGN KEYS ===';

-- 1. Trips -> Persons (CASCADE)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Persons_Trips')
BEGIN
    ALTER TABLE Persons ADD CONSTRAINT FK_Persons_Trips 
    FOREIGN KEY (trip_id) REFERENCES Trips(trip_id) ON DELETE CASCADE;
    PRINT 'Created FK_Persons_Trips (ON DELETE CASCADE).';
END;

-- 2. Trips -> Expenses
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Expenses_Trips')
    BEGIN
        ALTER TABLE Expenses ADD CONSTRAINT FK_Expenses_Trips 
        FOREIGN KEY (trip_id) REFERENCES Trips(trip_id) ON DELETE CASCADE;
        PRINT 'Created FK_Expenses_Trips (ON DELETE CASCADE).';
    END;
END TRY
BEGIN CATCH
    PRINT 'Warning on FK_Expenses_Trips CASCADE: ' + ERROR_MESSAGE();
    ALTER TABLE Expenses ADD CONSTRAINT FK_Expenses_Trips 
    FOREIGN KEY (trip_id) REFERENCES Trips(trip_id) ON DELETE NO ACTION;
    PRINT 'Created FK_Expenses_Trips (ON DELETE NO ACTION fallback).';
END CATCH;

-- 3. Composite FK: Expenses(paid_by_person_id, trip_id) -> Persons(person_id, trip_id)
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Expenses_Persons_Trip')
    BEGIN
        ALTER TABLE Expenses ADD CONSTRAINT FK_Expenses_Persons_Trip 
        FOREIGN KEY (paid_by_person_id, trip_id) REFERENCES Persons(person_id, trip_id) ON DELETE NO ACTION;
        PRINT 'Created FK_Expenses_Persons_Trip (NO ACTION).';
    END;
END TRY
BEGIN CATCH
    PRINT 'Error on FK_Expenses_Persons_Trip: ' + ERROR_MESSAGE();
END CATCH;

-- 4. Composite FK: ExpenseSplits(expense_id, trip_id) -> Expenses(expense_id, trip_id) (CASCADE)
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_ExpenseSplits_Expenses_Trip')
    BEGIN
        ALTER TABLE ExpenseSplits ADD CONSTRAINT FK_ExpenseSplits_Expenses_Trip 
        FOREIGN KEY (expense_id, trip_id) REFERENCES Expenses(expense_id, trip_id) ON DELETE CASCADE;
        PRINT 'Created FK_ExpenseSplits_Expenses_Trip (CASCADE).';
    END;
END TRY
BEGIN CATCH
    PRINT 'Error on FK_ExpenseSplits_Expenses_Trip: ' + ERROR_MESSAGE();
END CATCH;

-- 5. Composite FK: ExpenseSplits(person_id, trip_id) -> Persons(person_id, trip_id) (NO ACTION)
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_ExpenseSplits_Persons_Trip')
    BEGIN
        ALTER TABLE ExpenseSplits ADD CONSTRAINT FK_ExpenseSplits_Persons_Trip 
        FOREIGN KEY (person_id, trip_id) REFERENCES Persons(person_id, trip_id) ON DELETE NO ACTION;
        PRINT 'Created FK_ExpenseSplits_Persons_Trip (NO ACTION).';
    END;
END TRY
BEGIN CATCH
    PRINT 'Error on FK_ExpenseSplits_Persons_Trip: ' + ERROR_MESSAGE();
END CATCH;

-- 6. SettlementTransactions foreign keys
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Settlements_Trips')
    BEGIN
        ALTER TABLE SettlementTransactions ADD CONSTRAINT FK_Settlements_Trips 
        FOREIGN KEY (trip_id) REFERENCES Trips(trip_id) ON DELETE CASCADE;
        PRINT 'Created FK_Settlements_Trips (CASCADE).';
    END;
    
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Settlements_Persons_From_Trip')
    BEGIN
        ALTER TABLE SettlementTransactions ADD CONSTRAINT FK_Settlements_Persons_From_Trip 
        FOREIGN KEY (from_person_id, trip_id) REFERENCES Persons(person_id, trip_id) ON DELETE NO ACTION;
        PRINT 'Created FK_Settlements_Persons_From_Trip (NO ACTION).';
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Settlements_Persons_To_Trip')
    BEGIN
        ALTER TABLE SettlementTransactions ADD CONSTRAINT FK_Settlements_Persons_To_Trip 
        FOREIGN KEY (to_person_id, trip_id) REFERENCES Persons(person_id, trip_id) ON DELETE NO ACTION;
        PRINT 'Created FK_Settlements_Persons_To_Trip (NO ACTION).';
    END;
END TRY
BEGIN CATCH
    PRINT 'Error on SettlementTransactions FKs: ' + ERROR_MESSAGE();
END CATCH;

-- 7. TripCollaborators -> Trips (CASCADE)
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TripCollaborators_Trips')
    BEGIN
        ALTER TABLE TripCollaborators ADD CONSTRAINT FK_TripCollaborators_Trips 
        FOREIGN KEY (trip_id) REFERENCES Trips(trip_id) ON DELETE CASCADE;
        PRINT 'Created FK_TripCollaborators_Trips (CASCADE).';
    END;
END TRY
BEGIN CATCH
    PRINT 'Error on FK_TripCollaborators_Trips: ' + ERROR_MESSAGE();
END CATCH;

-- 8. Users foreign keys
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_UserTokens_Users')
    BEGIN
        ALTER TABLE UserTokens ADD CONSTRAINT FK_UserTokens_Users 
        FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE;
        PRINT 'Created FK_UserTokens_Users (CASCADE).';
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Notifications_Users')
    BEGIN
        ALTER TABLE Notifications ADD CONSTRAINT FK_Notifications_Users 
        FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE;
        PRINT 'Created FK_Notifications_Users (CASCADE).';
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_FriendConnections_Users')
    BEGIN
        ALTER TABLE FriendConnections ADD CONSTRAINT FK_FriendConnections_Users 
        FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE;
        PRINT 'Created FK_FriendConnections_Users (CASCADE).';
    END;
    
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_FriendConnections_Friend_Users')
    BEGIN
        ALTER TABLE FriendConnections ADD CONSTRAINT FK_FriendConnections_Friend_Users 
        FOREIGN KEY (friend_user_id) REFERENCES Users(user_id) ON DELETE NO ACTION;
        PRINT 'Created FK_FriendConnections_Friend_Users (NO ACTION).';
    END;
END TRY
BEGIN CATCH
    PRINT 'Error on Users FKs: ' + ERROR_MESSAGE();
END CATCH;

PRINT '=== MIGRATION VERIFICATION ===';
SELECT 
    fk.name AS ForeignKey,
    tp.name AS ParentTable,
    tr.name AS ReferencedTable,
    fk.delete_referential_action_desc AS OnDelete
FROM sys.foreign_keys fk
JOIN sys.tables tp ON fk.parent_object_id = tp.object_id
JOIN sys.tables tr ON fk.referenced_object_id = tr.object_id
ORDER BY tp.name, fk.name;
